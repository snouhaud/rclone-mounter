# rclone mounts (snouhaud.rclone-mounts)

Omarchy bar widget inspired by `~/.local/bin/rclone-manager`: lists rclone
remotes, mounts/unmounts them under `~/mnt/<remote>` with the same three VFS
modes (Complet / Flux / Lecture seule) and the same mount options.

- Password: read from the GNOME keyring (`service rclone key config`), same
  entry as rclone-manager. If missing, the panel offers an unlock row (zenity).
- Prerequisite checks on every refresh, shown as red alerts in the panel
  (and a red `!` on the bar icon):
  - rclone missing → button runs `omarchy pkg add rclone` in a terminal;
  - FUSE 3 missing (`fusermount3` or `/dev/fuse`) → `omarchy pkg add fuse3`,
    mount switches are disabled;
  - rclone config missing or empty, or no remote in it → button runs `rclone config`.
- Bar icon: cloud outline (dim) when nothing is mounted, cloud-check plus the
  count when something is. Left click opens the panel, right click refreshes.
- Panel keys: ↑/↓ move, ←/→ change mode, Enter mount/unmount, `m` cycle mode,
  `o` open folder, `r` refresh, `u` unlock, `c` run `rclone config`.
- Settings (Omarchy settings panel or `omarchy bar set snouhaud.rclone-mounts <key> <value>`):
  `mountBase`, `defaultMode`, `excludedRemotes`, `readOnlyRemotes`,
  `openAfterMount`, `showCount`, `refreshIntervalSec`.
- IPC: `omarchy-shell snouhaud.rclone-mounts status|refresh|toggle|mount <remote> <mode>|unmount <remote>`.

Install / move: `./install.sh [left|centerBegin|centerEnd|right|tray]`
(asks with gum when no section is given). When installed from git with
`omarchy plugin add`, Omarchy asks for the section itself (default: right).
