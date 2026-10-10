# steam-library.nix notes

Creates a `steam-library` group and a shared directory at `/var/lib/steam-library` (mode 2775, owned by root:steam-library). Both `siigna` and `deck` users are added to the group, allowing cross-user Steam library sharing between desktop and gaming sessions.
