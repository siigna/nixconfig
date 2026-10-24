"""Steam Machine light bar daemon (leds-valve sysfs).

Modes: meter (CPU + GPU + network bar graph), build (breathe while Nix builds run),
fixed (static effect/colour), off. The configured mode comes from the JSON
file given as argv[1]; /run/lightbar/mode overrides it at runtime.
"""

import glob
import grp
import json
import math
import os
import pwd
import signal
import sys
import time

CFG = json.load(open(sys.argv[1]))
NUM_LEDS = 17
LEDS = ["/sys/class/leds/valve-leds[%d]" % i for i in range(NUM_LEDS)]
STRIP = LEDS[0]  # strip-wide attributes are mirrored on every index
OVERRIDE = "/run/lightbar/mode"
MODES = ("meter", "build", "fixed", "off")


def write(path, value):
    with open(path, "w") as f:
        f.write(str(value))


def read(path):
    with open(path) as f:
        return f.read().strip()


class Strip:
    def __init__(self):
        self.rgb = {}

    def effect(self, name):
        write(STRIP + "/effect", name)
        self.rgb.clear()  # firmware effects repaint the strip

    def strip_attr(self, attr, value):
        write(STRIP + "/" + attr, value)

    def led(self, i, rgb):
        value = "%d %d %d" % tuple(max(0, min(255, int(c))) for c in rgb)
        if self.rgb.get(i) != value:
            write(LEDS[i] + "/multi_intensity", value)
            self.rgb[i] = value

    def all(self, rgb):
        for i in range(NUM_LEDS):
            self.led(i, rgb)

    def full_brightness(self):
        for path in LEDS:
            write(path + "/brightness", 255)


def apply_fixed(strip, fixed):
    strip.strip_attr("brightness_scale", fixed["brightness"])
    strip.strip_attr("delay", fixed["delay"])
    strip.effect(fixed["effect"])
    strip.full_brightness()
    strip.all(fixed["color"])


def cpu_times():
    fields = [int(x) for x in read("/proc/stat").splitlines()[0].split()[1:]]
    idle = fields[3] + fields[4]  # idle + iowait
    return sum(fields), idle


def net_bytes(iface):
    base = "/sys/class/net/%s/statistics/" % iface
    try:
        return int(read(base + "rx_bytes")) + int(read(base + "tx_bytes"))
    except OSError:
        return None


def gpu_busy_path():
    """amdgpu's busy percentage for the first GPU exposing one, or None."""
    paths = sorted(glob.glob("/sys/class/drm/card[0-9]*/device/gpu_busy_percent"))
    return paths[0] if paths else None


def gpu_busy(path):
    if path is None:
        return 0.0
    try:
        return max(0, min(100, int(read(path)))) / 100.0
    except (OSError, ValueError):  # EPERM/EBUSY while runtime-suspended or resetting
        return 0.0


def mix(a, b, t):
    return tuple(a[k] + (b[k] - a[k]) * t for k in range(3))


def cpu_colour(pos):
    """Green at the bottom of the bar, yellow mid-way, red at the top."""
    green, yellow, red = (0, 255, 0), (255, 200, 0), (255, 0, 0)
    if pos < 0.5:
        return mix(green, yellow, pos * 2)
    return mix(yellow, red, (pos - 0.5) * 2)


def draw_bar(strip, leds, level, colour_at):
    """Light len(leds) * level LEDs; the boundary LED is partially lit."""
    n = len(leds)
    lit = level * n
    for k, i in enumerate(leds):
        fill = max(0.0, min(1.0, lit - k))
        colour = colour_at(k / max(1, n - 1))
        strip.led(i, tuple(c * fill for c in colour))


class Meter:
    def __init__(self, cfg):
        self.cfg = cfg
        self.prev_cpu = cpu_times()
        self.prev_net = net_bytes(cfg["netInterface"])
        self.prev_t = time.monotonic()
        self.gpu_path = gpu_busy_path() if cfg["gpuLeds"] else None
        self.cpu = 0.0
        self.gpu = 0.0
        self.net = 0.0

    def tick(self, strip):
        cfg = self.cfg
        now = time.monotonic()
        dt = max(1e-3, now - self.prev_t)
        total, idle = cpu_times()
        d_total = total - self.prev_cpu[0]
        d_idle = idle - self.prev_cpu[1]
        busy = 1.0 - d_idle / d_total if d_total > 0 else 0.0
        nb = net_bytes(cfg["netInterface"])
        rate = 0.0
        if nb is not None and self.prev_net is not None:
            rate = max(0, nb - self.prev_net) / dt
        self.prev_cpu, self.prev_net, self.prev_t = (total, idle), nb, now

        # Log scale from 10 KB/s to netMaxBytesPerSec, so light traffic shows.
        floor = 10_000.0
        top = float(cfg["netMaxBytesPerSec"])
        net_level = 0.0
        if rate > floor:
            net_level = min(1.0, math.log(rate / floor) / math.log(top / floor))

        a = cfg["smoothing"]
        self.cpu += (busy - self.cpu) * a
        self.gpu += (gpu_busy(self.gpu_path) - self.gpu) * a
        self.net += (net_level - self.net) * a
        draw_bar(strip, cfg["cpuLeds"], self.cpu, cpu_colour)
        gpu_rgb = tuple(cfg["gpuColor"])
        draw_bar(strip, cfg["gpuLeds"], self.gpu, lambda _pos: gpu_rgb)
        net_rgb = tuple(cfg["netColor"])
        draw_bar(strip, cfg["netLeds"], self.net, lambda _pos: net_rgb)


def build_uids():
    try:
        members = grp.getgrnam("nixbld").gr_mem
    except KeyError:
        return set()
    uids = set()
    for name in members:
        try:
            uids.add(pwd.getpwnam(name).pw_uid)
        except KeyError:
            pass
    return uids


def building(uids):
    for pid in os.listdir("/proc"):
        if pid.isdigit():
            try:
                if os.stat("/proc/" + pid).st_uid in uids:
                    return True
            except OSError:
                pass
    return False


def current_mode():
    try:
        mode = read(OVERRIDE)
        if mode in MODES:
            return mode
    except OSError:
        pass
    return CFG["mode"]


def main():
    if not os.path.isdir(STRIP):
        print("no %s; not a Steam Machine light bar" % STRIP, file=sys.stderr)
        return 0

    strip = Strip()
    restore = CFG["restore"]

    def stop(_signum, _frame):
        apply_fixed(strip, restore)
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    mode = None
    meter = None
    uids = build_uids()
    was_building = None
    while True:
        new_mode = current_mode()
        if new_mode != mode:
            mode = new_mode
            print("mode: %s" % mode, flush=True)
            was_building = None
            if mode == "meter":
                strip.effect("manual")
                strip.strip_attr("brightness_scale", CFG["meter"]["brightness"])
                strip.full_brightness()
                strip.all((0, 0, 0))
                meter = Meter(CFG["meter"])
            elif mode == "fixed":
                apply_fixed(strip, CFG["fixed"])
            elif mode == "off":
                strip.effect("off")

        if mode == "meter":
            meter.tick(strip)
            time.sleep(CFG["meter"]["intervalMs"] / 1000.0)
        elif mode == "build":
            busy = building(uids)
            if busy != was_building:
                was_building = busy
                look = dict(CFG["fixed"])
                if busy:
                    look.update(effect="breath", color=CFG["build"]["color"])
                apply_fixed(strip, look)
                print("build: %s" % ("building" if busy else "idle"), flush=True)
            time.sleep(1.0)
        else:
            time.sleep(1.0)


if __name__ == "__main__":
    sys.exit(main())
