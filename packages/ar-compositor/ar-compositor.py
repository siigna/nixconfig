#!/usr/bin/env python3
"""AR Compositor: GTK window with live preview and Record button."""

import gi
gi.require_version('Gtk', '3.0')
gi.require_version('Gst', '1.0')
from gi.repository import Gtk, Gst, GLib, Gio

import sys, os, signal, datetime, struct, binascii

XREAL_VENDOR_ID   = 0x3318
XREAL_PRODUCT_IDS = {0x0435, 0x0436, 0x0437, 0x0438}

DISPLAY_DEST    = "org.gnome.Mutter.DisplayConfig"
SCREENCAST_DEST = "org.gnome.Mutter.ScreenCast"
CAM_W, CAM_H    = 2048, 1512
SCREEN_ALPHA    = 0.75
RECORDINGS_DIR  = os.path.expanduser("~/Videos")

_ENC_ELEMENTS = [
    ('videoconvert', 'recconvert'),
    ('vah264enc',    'recenc'),
    ('h264parse',    'recparse'),
    ('_mux_',        'recmux'),
    ('filesink',     'recfsink'),
]

FORMATS = {
    'MKV': ('matroskamux', '.mkv'),
    'MP4': ('mp4mux',      '.mp4'),
}


# ── XReal camera enable ────────────────────────────────────────────────────────

def _xreal_hid_message(command, payload=b''):
    """Build a 1024-byte framed HID message for the XReal One protocol.

    Wire layout (repr C packed):
      [0]    magic      u8  = 0xFD
      [1..4] checksum   u32 (LE) = adler32 of bytes [5..(5+length)]
      [5..6] length     u16 (LE) = 17 + len(payload)
      [7..10] request_id u32 (LE) = 0
      [11..14] timestamp u32 (LE) = 0
      [15..16] command  [u8;2]
      [17..21] unknown  [u8;5] = 0
      [22..]   payload
    """
    length = 17 + len(payload)
    # The checksummed region starts at offset 5 (the length field itself)
    checksummed_region = (
        struct.pack('<H', length)      # length     (2)
        + struct.pack('<I', 0)         # request_id (4)
        + struct.pack('<I', 0)         # timestamp  (4)
        + bytes(command)               # command    (2)
        + bytes(5)                     # unknown    (5)
        + payload
    )
    checksum = binascii.crc32(checksummed_region) & 0xFFFFFFFF
    return bytes([0xFD]) + struct.pack('<I', checksum) + checksummed_region


def find_xreal_video_device():
    """Return the first /dev/videoN that belongs to an XReal One USB device, or None."""
    v4l_base = '/sys/class/video4linux'
    if not os.path.isdir(v4l_base):
        return None
    for node in sorted(os.listdir(v4l_base)):
        dev_link = os.path.join(v4l_base, node, 'device')
        if not os.path.exists(dev_link):
            continue
        path = os.path.realpath(dev_link)
        # Walk up sysfs ancestors looking for idVendor
        d = path
        for _ in range(10):
            d = os.path.dirname(d)
            vendor_file = os.path.join(d, 'idVendor')
            if os.path.isfile(vendor_file):
                try:
                    vendor = int(open(vendor_file).read().strip(), 16)
                    if vendor == XREAL_VENDOR_ID:
                        return f'/dev/{node}'
                except ValueError:
                    pass
                break  # found idVendor but wrong vendor — stop climbing
    return None


def enable_camera():
    """Send the SetUsbConfigAll command to enable the UVC camera on XReal One."""
    # Find the first hidraw node for an XReal One device via sysfs
    hidraw_path = None
    hid_base = '/sys/bus/hid/devices'
    for entry in sorted(os.listdir(hid_base)):
        # Entry format: BBBB:VVVV:PPPP.NNNN
        parts = entry.split(':')
        if len(parts) < 3:
            continue
        try:
            vid = int(parts[1], 16)
            pid = int(parts[2].split('.')[0], 16)
        except ValueError:
            continue
        if vid != XREAL_VENDOR_ID or pid not in XREAL_PRODUCT_IDS:
            continue
        # Find the hidraw child (lives in a hidraw/ subdirectory)
        hidraw_dir = os.path.join(hid_base, entry, 'hidraw')
        if os.path.isdir(hidraw_dir):
            for child in os.listdir(hidraw_dir):
                if child.startswith('hidraw'):
                    hidraw_path = f'/dev/{child}'
                    break
        if hidraw_path:
            break
    if hidraw_path is None:
        raise RuntimeError("XReal One device not found")
    if hidraw_path is None:
        raise RuntimeError("XReal One device not found")

    # Use raw hidraw to avoid Python hid's report-descriptor size cap on reads
    import fcntl
    # uvc0=1 (bits 12-13) | enable=1 (bits 16-17) → 0x00011000 LE
    payload = struct.pack('<I', (1 << 12) | (1 << 16))
    buf = _xreal_hid_message([0xD3, 0x00], payload)
    import select
    fd = os.open(hidraw_path, os.O_RDWR | os.O_NONBLOCK)
    try:
        written = os.write(fd, buf)
        print(f"enable_camera: wrote {written} bytes to {hidraw_path}", file=sys.stderr)
        ready, _, _ = select.select([fd], [], [], 3.0)
        if not ready:
            raise RuntimeError("No response from device (timeout)")
        resp = os.read(fd, 1024)
        status = resp[22] if len(resp) > 22 else -1
        print(f"enable_camera: response ({len(resp)}b) status={status}", file=sys.stderr)
        if status != 0:
            raise RuntimeError(f"Device returned error status {status}")
    finally:
        os.close(fd)


# ── D-Bus helpers ──────────────────────────────────────────────────────────────

def dbus_call(conn, dest, path, iface, method, params=None):
    return conn.call_sync(
        dest, path, iface, method, params,
        None, Gio.DBusCallFlags.NONE, -1, None,
    ).unpack()


def get_displays(conn):
    state = dbus_call(conn, DISPLAY_DEST, "/org/gnome/Mutter/DisplayConfig",
                      DISPLAY_DEST, "GetCurrentState")
    return [(c, product) for m in state[2] for c, vendor, product, serial in m[5]]


def get_logical_size(conn, connector):
    state = dbus_call(conn, DISPLAY_DEST, "/org/gnome/Mutter/DisplayConfig",
                      DISPLAY_DEST, "GetCurrentState")
    scale = 1.0
    for lm in state[2]:
        for out in lm[5]:
            if out[0] == connector:
                scale = lm[2]
    for mon in state[1]:
        if mon[0][0] != connector:
            continue
        for mode in mon[1]:
            props = mode[6] if len(mode) > 6 else {}
            if props.get('is-current'):
                return int(mode[1] / scale), int(mode[2] / scale)
    return 1920, 1080


def start_screencast(conn, connector):
    (session_path,) = dbus_call(
        conn, SCREENCAST_DEST, "/org/gnome/Mutter/ScreenCast",
        SCREENCAST_DEST, "CreateSession", GLib.Variant("(a{sv})", ({},)))
    (stream_path,) = dbus_call(
        conn, SCREENCAST_DEST, session_path,
        "org.gnome.Mutter.ScreenCast.Session", "RecordMonitor",
        GLib.Variant("(sa{sv})", (connector, {})))
    return session_path, stream_path


# ── Setup window ───────────────────────────────────────────────────────────────

class SetupWindow(Gtk.ApplicationWindow):
    def __init__(self, app, conn):
        super().__init__(application=app, title="AR Compositor")
        self.conn = conn

        hbar = Gtk.HeaderBar(show_close_button=True, title="AR Compositor")
        self.set_titlebar(hbar)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_margin_top(24)
        outer.set_margin_bottom(24)
        outer.set_margin_start(24)
        outer.set_margin_end(24)

        lbl = Gtk.Label(label="Select display to capture:")
        lbl.set_halign(Gtk.Align.START)
        outer.pack_start(lbl, False, False, 0)

        sw = Gtk.ScrolledWindow()
        sw.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        sw.set_min_content_height(80)

        self.display_list = Gtk.ListBox()
        self.display_list.set_selection_mode(Gtk.SelectionMode.SINGLE)
        sw.add(self.display_list)
        outer.pack_start(sw, True, True, 0)

        try:
            self.displays = get_displays(conn)
        except Exception as e:
            self.displays = []
            print(f"Failed to list displays: {e}", file=sys.stderr)

        for connector, product in self.displays:
            row = Gtk.ListBoxRow()
            box = Gtk.Box(spacing=8)
            box.set_margin_top(8)
            box.set_margin_bottom(8)
            box.set_margin_start(8)
            box.set_margin_end(8)
            box.pack_start(Gtk.Label(label=connector), False, False, 0)
            box.pack_start(Gtk.Label(label=f"— {product}"), False, False, 0)
            row.add(box)
            self.display_list.add(row)

        if self.displays:
            self.display_list.select_row(self.display_list.get_row_at_index(0))

        self.start_btn = Gtk.Button(label="▶  Start")
        self.start_btn.get_style_context().add_class("suggested-action")
        self.start_btn.connect("clicked", self._on_start)
        self.start_btn.set_sensitive(bool(self.displays))
        outer.pack_start(self.start_btn, False, False, 0)

        self.add(outer)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.show_all()

    def _on_start(self, *_):
        row = self.display_list.get_selected_row()
        idx = row.get_index() if row else 0
        self._connector, _ = self.displays[idx]

        self.start_btn.set_sensitive(False)

        self._cam_dev = find_xreal_video_device()
        if self._cam_dev is None:
            self.start_btn.set_label("Enabling camera…")
            try:
                enable_camera()
            except Exception as e:
                print(f"Failed to enable camera: {e}", file=sys.stderr)
                self._error_dialog("Could not enable camera",
                                   f"Make sure your glasses are plugged in.\n\n{e}")
                self.start_btn.set_label("▶  Start")
                self.start_btn.set_sensitive(True)
                return
            # Device re-enumerates after enable — poll for the XReal video device (up to 10s)
            self._camera_wait_ticks = 0
            GLib.timeout_add(500, self._wait_for_camera)
            return

        self.start_btn.set_label("Starting…")
        self._do_start_screencast()

    def _wait_for_camera(self):
        self._camera_wait_ticks += 1
        self._cam_dev = find_xreal_video_device()
        if self._cam_dev is not None:
            self.start_btn.set_label("Starting…")
            self._do_start_screencast()
            return False  # stop polling
        if self._camera_wait_ticks >= 20:  # 10 seconds
            self._error_dialog("Camera not found",
                               "Camera was enabled but no XReal video device appeared.\n"
                               "Try unplugging and replugging the glasses.")
            self.start_btn.set_label("▶  Start")
            self.start_btn.set_sensitive(True)
            return False
        return True  # keep polling

    def _do_start_screencast(self):
        try:
            self._out_w, self._out_h = get_logical_size(self.conn, self._connector)
            self._session_path, stream_path = start_screencast(self.conn, self._connector)
        except Exception as e:
            print(f"Failed to start screencast: {e}", file=sys.stderr)
            self.start_btn.set_label("▶  Start")
            self.start_btn.set_sensitive(True)
            return

        self.conn.signal_subscribe(
            SCREENCAST_DEST, "org.gnome.Mutter.ScreenCast.Stream",
            "PipeWireStreamAdded", stream_path,
            None, Gio.DBusSignalFlags.NONE, self._on_pipewire_node, None)

        dbus_call(self.conn, SCREENCAST_DEST, self._session_path,
                  "org.gnome.Mutter.ScreenCast.Session", "Start")

        GLib.timeout_add_seconds(10, self._on_pipewire_timeout)

    def _on_pipewire_node(self, conn, sender, path, iface, sig, params, data):
        screen_node = params.unpack()[0]
        GLib.idle_add(self._launch_compositor, screen_node)

    def _on_pipewire_timeout(self):
        if self.get_visible():
            print("Timed out waiting for PipeWire node.", file=sys.stderr)
            self.start_btn.set_label("▶  Start")
            self.start_btn.set_sensitive(True)
        return False

    def _launch_compositor(self, screen_node):
        try:
            win = ARCompositorWindow(
                self.get_application(), self.conn,
                self._session_path, screen_node,
                self._out_w, self._out_h,
                self._cam_dev,
            )
            win.present()
            self.destroy()
        except Exception:
            import traceback
            traceback.print_exc()
            self.start_btn.set_label("▶  Start")
            self.start_btn.set_sensitive(True)
        return False

    def _error_dialog(self, title, message):
        dlg = Gtk.MessageDialog(
            transient_for=self,
            message_type=Gtk.MessageType.ERROR,
            buttons=Gtk.ButtonsType.OK,
            text=title,
        )
        dlg.format_secondary_text(message)
        dlg.run()
        dlg.destroy()


# ── Compositor window ──────────────────────────────────────────────────────────

class ARCompositorWindow(Gtk.ApplicationWindow):
    def __init__(self, app, conn, session_path, screen_node, out_w, out_h, cam_dev):
        super().__init__(application=app, title="AR Compositor")
        self.conn         = conn
        self.session_path = session_path
        self.screen_node  = screen_node
        self.out_w, self.out_h = out_w, out_h
        self.cam_dev      = cam_dev

        self._recording = False
        self._stopping  = False
        self.rec_path   = None
        self._rec_start = None
        self._timer_id  = None

        ow, oh = out_w, out_h
        self.ovl_w = ow // 3
        self.ovl_h = oh // 3
        self.ovl_x = (ow - self.ovl_w) // 2
        self.ovl_y = (oh - self.ovl_h) // 2
        self._target_w = min(ow, 1280)
        self._target_h = self._target_w * oh // ow

        self._build_ui()

    def _build_ui(self):
        hbar = Gtk.HeaderBar(show_close_button=True, title="AR Compositor")

        self.rec_btn = Gtk.Button(label="⏺  Record")
        self.rec_btn.get_style_context().add_class("suggested-action")
        self.rec_btn.connect("clicked", self._on_record)
        hbar.pack_start(self.rec_btn)

        self.fmt_combo = Gtk.ComboBoxText()
        for fmt in FORMATS:
            self.fmt_combo.append_text(fmt)
        self.fmt_combo.set_active(0)
        hbar.pack_start(self.fmt_combo)

        self.elapsed = Gtk.Label(label="")
        self.elapsed.set_width_chars(8)
        hbar.pack_start(self.elapsed)

        self.status = Gtk.Label(label="")
        hbar.pack_start(self.status)

        self.set_titlebar(hbar)

        main_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL)

        self.video_box = Gtk.Box()
        self.video_box.set_size_request(self._target_w, self._target_h)
        main_box.pack_start(self.video_box, True, True, 0)

        main_box.pack_start(self._build_controls(), False, False, 0)
        self.add(main_box)

        # Set size before show_all so Mutter places this fresh window correctly
        self.set_default_size(self._target_w + 220, self._target_h)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.show_all()

        self._build_pipeline()

    def _build_controls(self):
        ow, oh = self.out_w, self.out_h
        panel = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        panel.set_margin_top(16)
        panel.set_margin_bottom(16)
        panel.set_margin_start(12)
        panel.set_margin_end(12)
        panel.set_size_request(200, -1)

        # ── Size slider ────────────────────────────────────────────────────────
        size_label = Gtk.Label(label="Overlay size")
        size_label.set_halign(Gtk.Align.START)
        panel.pack_start(size_label, False, False, 0)

        init_pct = round(self.ovl_w / ow * 100)
        self._size_adj = Gtk.Adjustment(value=init_pct, lower=5, upper=100,
                                        step_increment=1, page_increment=5)
        size_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL,
                               adjustment=self._size_adj)
        size_scale.set_digits(0)
        size_scale.set_draw_value(True)
        size_scale.set_value_pos(Gtk.PositionType.RIGHT)
        size_scale.connect("value-changed", self._on_size_changed)
        panel.pack_start(size_scale, False, False, 0)

        # ── X position slider ──────────────────────────────────────────────────
        x_label = Gtk.Label(label="X position")
        x_label.set_halign(Gtk.Align.START)
        panel.pack_start(x_label, False, False, 0)

        self._x_adj = Gtk.Adjustment(value=self.ovl_x, lower=0, upper=ow,
                                     step_increment=1, page_increment=10)
        x_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL,
                            adjustment=self._x_adj)
        x_scale.set_digits(0)
        x_scale.set_draw_value(True)
        x_scale.set_value_pos(Gtk.PositionType.RIGHT)
        x_scale.connect("value-changed", self._on_pos_changed)
        panel.pack_start(x_scale, False, False, 0)

        # ── Y position slider ──────────────────────────────────────────────────
        y_label = Gtk.Label(label="Y position")
        y_label.set_halign(Gtk.Align.START)
        panel.pack_start(y_label, False, False, 0)

        self._y_adj = Gtk.Adjustment(value=self.ovl_y, lower=0, upper=oh,
                                     step_increment=1, page_increment=10)
        y_scale = Gtk.Scale(orientation=Gtk.Orientation.HORIZONTAL,
                            adjustment=self._y_adj)
        y_scale.set_digits(0)
        y_scale.set_draw_value(True)
        y_scale.set_value_pos(Gtk.PositionType.RIGHT)
        y_scale.connect("value-changed", self._on_pos_changed)
        panel.pack_start(y_scale, False, False, 0)

        # ── Re-center button ───────────────────────────────────────────────────
        recenter_btn = Gtk.Button(label="⊹  Re-center")
        recenter_btn.connect("clicked", self._on_recenter)
        panel.pack_start(recenter_btn, False, False, 8)

        return panel

    def _on_recenter(self, _btn):
        ow, oh = self.out_w, self.out_h
        cx = (ow - self.ovl_w) // 2
        cy = (oh - self.ovl_h) // 2
        self._x_adj.set_value(cx)
        self._y_adj.set_value(cy)
        self.ovl_x, self.ovl_y = cx, cy
        self._update_overlay_pad()

    def _on_size_changed(self, scale):
        ow, oh = self.out_w, self.out_h
        pct = scale.get_value() / 100.0
        self.ovl_w = max(1, round(ow * pct))
        self.ovl_h = max(1, round(oh * pct))
        self._update_overlay_pad()

    def _on_pos_changed(self, _scale):
        self.ovl_x = round(self._x_adj.get_value())
        self.ovl_y = round(self._y_adj.get_value())
        self._update_overlay_pad()

    def _update_overlay_pad(self):
        if not hasattr(self, 'pipeline'):
            return
        comp = self.pipeline.get_by_name('comp')
        if comp is None:
            return
        pad = comp.get_static_pad('sink_1')
        pad.set_property('xpos',   self.ovl_x)
        pad.set_property('ypos',   self.ovl_y)
        pad.set_property('width',  self.ovl_w)
        pad.set_property('height', self.ovl_h)

    def _build_pipeline(self):
        ow, oh   = self.out_w, self.out_h
        ovw, ovh = self.ovl_w, self.ovl_h
        ovx, ovy = self.ovl_x, self.ovl_y

        pipe = f"""
            glvideomixer name=comp
                sink_0::zorder=0 sink_0::width={ow} sink_0::height={oh}
                sink_1::zorder=1
                    sink_1::alpha={SCREEN_ALPHA}
                    sink_1::xpos={ovx} sink_1::ypos={ovy}
                    sink_1::width={ovw} sink_1::height={ovh}
            ! video/x-raw(memory:GLMemory),width={ow},height={oh}
            ! gldownload
            ! tee name=t

            t.
            ! queue max-size-buffers=2 leaky=downstream
            ! gtkwaylandsink name=vsink sync=false

            t.
            ! queue max-size-buffers=30 leaky=upstream name=recqueue
            ! fakesink sync=false name=recfake

            v4l2src device={self.cam_dev}
            ! video/x-h265,width={CAM_W},height={CAM_H},framerate=30/1
            ! vah265dec ! vapostproc
            ! video/x-raw,format=NV12,width={CAM_W},height={CAM_H}
            ! videocrop top=216 bottom=216 left=64 right=64
            ! glupload
            ! queue max-size-buffers=2 leaky=downstream
            ! comp.sink_0

            pipewiresrc path={self.screen_node} do-timestamp=true
            ! videoconvert ! video/x-raw,format=BGRx
            ! glupload
            ! queue max-size-buffers=2 leaky=downstream
            ! comp.sink_1
        """
        self.pipeline = Gst.parse_launch(pipe)

        vsink = self.pipeline.get_by_name('vsink')
        video_widget = vsink.get_property('widget')
        self.video_box.pack_start(video_widget, True, True, 0)
        video_widget.show()

        bus = self.pipeline.get_bus()
        bus.add_signal_watch()
        bus.connect('message', self._on_bus)

        self.pipeline.set_state(Gst.State.PLAYING)

    # ── Recording ──────────────────────────────────────────────────────────────

    def _tick_timer(self):
        elapsed = datetime.datetime.now() - self._rec_start
        h, rem  = divmod(int(elapsed.total_seconds()), 3600)
        m, s    = divmod(rem, 60)
        self.elapsed.set_label(f"{h}:{m:02d}:{s:02d}")
        return True

    def _on_record(self, _btn):
        if not self._recording and not self._stopping:
            self._start_recording()
        elif self._recording and not self._stopping:
            self._stop_recording()

    # -- Start --

    def _start_recording(self):
        os.makedirs(RECORDINGS_DIR, exist_ok=True)
        ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
        self.rec_path = os.path.join(RECORDINGS_DIR, f"ar-{ts}.mkv")

        self.elapsed.set_label("")
        recqueue = self.pipeline.get_by_name('recqueue')
        self._start_block_id = recqueue.get_static_pad('src').add_probe(
            Gst.PadProbeType.BLOCK_DOWNSTREAM,
            lambda pad, info: Gst.PadProbeReturn.OK)
        GLib.idle_add(self._do_start_main)

    def _do_start_main(self):
        recqueue = self.pipeline.get_by_name('recqueue')
        recfake  = self.pipeline.get_by_name('recfake')
        src_pad  = recqueue.get_static_pad('src')

        recqueue.unlink(recfake)
        recfake.set_state(Gst.State.NULL)
        self.pipeline.remove(recfake)

        fmt_name = self.fmt_combo.get_active_text()
        mux_factory, ext = FORMATS[fmt_name]
        base = self.rec_path.rsplit('.', 1)[0]
        self.rec_path = base + ext

        elems = []
        for factory, name in _ENC_ELEMENTS:
            actual_factory = mux_factory if factory == '_mux_' else factory
            el = Gst.ElementFactory.make(actual_factory, name)
            self.pipeline.add(el)
            elems.append(el)
        elems[-1].set_property('location', self.rec_path)
        elems[-1].set_property('sync', False)
        for i in range(len(elems) - 1):
            elems[i].link(elems[i + 1])
        src_pad.link(elems[0].get_static_pad('sink'))
        for el in elems:
            el.sync_state_with_parent()

        src_pad.remove_probe(self._start_block_id)

        self._recording = True
        self._rec_start = datetime.datetime.now()
        self._timer_id  = GLib.timeout_add(1000, self._tick_timer)
        self.fmt_combo.set_sensitive(False)
        self.rec_btn.set_label("⏹  Stop")
        self.rec_btn.get_style_context().remove_class("suggested-action")
        self.rec_btn.get_style_context().add_class("destructive-action")
        self.status.set_markup(
            f'<span foreground="#e01b24">● {os.path.basename(self.rec_path)}</span>')
        return False

    # -- Stop --

    def _stop_recording(self):
        self._stopping = True
        self.rec_btn.set_sensitive(False)
        self.status.set_label("Finalizing…")

        recqueue = self.pipeline.get_by_name('recqueue')
        self._stop_block_id = recqueue.get_static_pad('src').add_probe(
            Gst.PadProbeType.BLOCK_DOWNSTREAM,
            lambda pad, info: Gst.PadProbeReturn.OK)
        GLib.idle_add(self._do_inject_eos_main)

    def _do_inject_eos_main(self):
        fsink = self.pipeline.get_by_name('recfsink')
        fsink.get_static_pad('sink').add_probe(
            Gst.PadProbeType.EVENT_DOWNSTREAM, self._on_rec_eos_probe)

        recconvert = self.pipeline.get_by_name('recconvert')
        recconvert.get_static_pad('sink').send_event(Gst.Event.new_eos())
        return False

    def _on_rec_eos_probe(self, pad, info):
        if info.get_event().type == Gst.EventType.EOS:
            GLib.idle_add(self._do_teardown_main)
            return Gst.PadProbeReturn.REMOVE
        return Gst.PadProbeReturn.OK

    def _do_teardown_main(self):
        recqueue   = self.pipeline.get_by_name('recqueue')
        recconvert = self.pipeline.get_by_name('recconvert')
        src_pad    = recqueue.get_static_pad('src')

        if recqueue and recconvert:
            recqueue.unlink(recconvert)

        for _, name in reversed(_ENC_ELEMENTS):
            el = self.pipeline.get_by_name(name)
            if el:
                el.set_state(Gst.State.NULL)
                self.pipeline.remove(el)

        fake = Gst.ElementFactory.make('fakesink', 'recfake')
        fake.set_property('sync', False)
        self.pipeline.add(fake)
        src_pad.link(fake.get_static_pad('sink'))
        fake.sync_state_with_parent()

        src_pad.remove_probe(self._stop_block_id)

        if self._timer_id:
            GLib.source_remove(self._timer_id)
            self._timer_id = None
        self._recording = False
        self._stopping  = False
        self.fmt_combo.set_sensitive(True)
        self.rec_btn.set_label("⏺  Record")
        self.rec_btn.get_style_context().remove_class("destructive-action")
        self.rec_btn.get_style_context().add_class("suggested-action")
        self.rec_btn.set_sensitive(True)
        self.status.set_label(f"Saved: {os.path.basename(self.rec_path)}")
        return False

    # ── Bus / window ───────────────────────────────────────────────────────────

    def _on_bus(self, _bus, msg):
        if msg.type == Gst.MessageType.ERROR:
            err, dbg = msg.parse_error()
            print(f"Pipeline error: {err}\n{dbg}", file=sys.stderr)
            dlg = Gtk.MessageDialog(
                transient_for=self,
                message_type=Gtk.MessageType.ERROR,
                buttons=Gtk.ButtonsType.OK,
                text="Pipeline error",
            )
            dlg.format_secondary_text(str(err))
            dlg.run()
            dlg.destroy()
            self.get_application().quit()

    def _stop_session(self):
        if self.session_path:
            try:
                dbus_call(self.conn, SCREENCAST_DEST, self.session_path,
                          "org.gnome.Mutter.ScreenCast.Session", "Stop")
            except Exception:
                pass
            self.session_path = None

    def do_delete_event(self, _ev):
        if self._recording and not self._stopping:
            self._stop_recording()
        if hasattr(self, 'pipeline'):
            self.pipeline.set_state(Gst.State.NULL)
        self._stop_session()
        return False


# ── App / entry point ──────────────────────────────────────────────────────────

class ARApp(Gtk.Application):
    def __init__(self, conn):
        super().__init__(application_id="com.siigna.ar-compositor")
        self.conn = conn

    def do_activate(self):
        win = SetupWindow(self, self.conn)
        win.present()


def main():
    Gst.init(None)
    conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)

    signal.signal(signal.SIGINT, lambda *_: app.quit())

    app = ARApp(conn)
    sys.exit(app.run(None))


if __name__ == "__main__":
    main()
