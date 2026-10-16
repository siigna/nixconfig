{ ... }:
{
  # 10-foot streaming apps for a TV box: Plex HTPC plus Chrome kiosk launchers for YouTube's TV
  # UI, Netflix and Prime Video. Each launcher also gets a .desktop entry so Steam's "Add a
  # Non-Steam Game" lists it; adding them to the Steam library is a one-time manual step.
  flake.modules.nixos.tv-apps =
    { pkgs, lib, ... }:
    let
      # youtube.com/tv only serves the TV (TVHTML5 / leanback) client to TV user agents; a desktop
      # Chrome UA gets the regular site, which a remote can't drive.
      googleTvUserAgent = "Mozilla/5.0 (X11; Linux i686) AppleWebKit/534.24 (KHTML, like Gecko) Chrome/11.0.696.77 Large Screen Safari/534.24 GoogleTV/092754";

      # Launcher + .desktop entry. Steam starts non-Steam games with LD_PRELOAD set to its overlay
      # (gameoverlayrenderer.so), which segfaults Chromium-based apps during init: the launch just
      # spins on the Steam logo. Clearing it loses only the in-app overlay; the Steam button and
      # quick access menu come from gamescope and still work.
      mkTvApp =
        {
          name,
          desktopName,
          icon,
          command,
        }:
        pkgs.symlinkJoin {
          inherit name;
          paths = [
            (pkgs.writeShellScriptBin name ''
              unset LD_PRELOAD
              exec ${command} "$@"
            '')
            (pkgs.makeDesktopItem {
              inherit name desktopName icon;
              exec = name;
              categories = [
                "AudioVideo"
                "Video"
              ];
            })
          ];
        };

      # Netflix/Prime web UIs are built for a mouse; plain arrow keys just scroll the page. Chromium's
      # spatial navigation moves focus between links/tiles in the arrow's direction and Enter (remote
      # OK) activates, which is what TV browsers do. YouTube's TV client handles arrows itself.
      spatialNavigation = "--enable-spatial-navigation";

      # One Chrome profile per app, so logins persist and two apps can run without fighting over
      # a profile lock.
      mkKioskApp =
        {
          name,
          desktopName,
          url,
          userAgent ? null,
          extraFlags ? [ ],
        }:
        mkTvApp {
          inherit name desktopName;
          icon = "google-chrome";
          command = lib.concatStringsSep " " (
            [
              (lib.getExe' pkgs.google-chrome "google-chrome-stable")
              ''--user-data-dir="$HOME/.local/share/tv-apps/${name}"''
              "--kiosk --start-fullscreen"
              # Netflix's browse page otherwise shows a desktop scrollbar on the TV; scrolling still works.
              "--hide-scrollbars"
              "--no-first-run --no-default-browser-check"
              "--noerrdialogs --disable-session-crashed-bubble"
              "--autoplay-policy=no-user-gesture-required"
            ]
            ++ lib.optional (userAgent != null) "--user-agent=${lib.escapeShellArg userAgent}"
            ++ extraFlags
            ++ [ (lib.escapeShellArg url) ]
          );
        };
    in
    {
      environment.systemPackages = [
        # Plex HTPC embeds Chromium (Qt WebEngine) too; add "Plex (TV)" to Steam, not "Plex HTPC".
        (mkTvApp {
          name = "tv-plex";
          desktopName = "Plex (TV)";
          icon = "plex-htpc";
          command = lib.getExe pkgs.plex-htpc;
        })
        (mkKioskApp {
          name = "tv-youtube";
          desktopName = "YouTube (TV)";
          url = "https://www.youtube.com/tv";
          userAgent = googleTvUserAgent;
        })
        # Linux Chrome only gets Widevine L3: Netflix tops out around 720p, Prime Video similar,
        # no HDR. The TV's own apps do 4K HDR; these exist for convenience.
        (mkKioskApp {
          name = "tv-netflix";
          desktopName = "Netflix";
          url = "https://www.netflix.com/browse";
          extraFlags = [ spatialNavigation ];
        })
        (mkKioskApp {
          name = "tv-prime";
          desktopName = "Prime Video";
          url = "https://www.primevideo.com";
          extraFlags = [ spatialNavigation ];
        })
      ];
    };
}
