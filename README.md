# MiscShellFiles

A personal collection of shell scripts and config files for Linux system management, media handling, and Zsh customization. Primarily built around **openSUSE** with Docker/Portainer, but most scripts are portable to any systemd-based Linux distro.

---

## Files at a Glance

| File | Description |
|---|---|
| `.zshrc` | Full Zsh config — amber-hued prompt, aliases, and utility functions |
| `music_meta_fix.sh` | Batch fix music metadata and embed cover art for MP3/FLAC libraries |
| `install_update_portainer.sh` | Install or update Portainer CE in Docker |
| `backup_portainer.sh` | Rsync-based backup with 7-day retention for home and `/opt` |
| `update_opensuse.sh` | One-liner system update for openSUSE (zypper + flatpak) |
| `convert_bashrc_2_zsh.sh` | Migrate aliases, exports, and functions from `.bashrc` to `.zshrc` |

---

## `.zshrc`

A full Zsh configuration with an amber/dark color palette themed for the Kitty terminal. Features a context-aware two-line prompt, a suite of custom aliases and functions, and sensible history and completion settings.

**Prompt behavior** — the prompt color shifts based on context:
- 🔴 Red — running as root
- 🔵 Blue — inside a Git repo
- 🟢 Green — inside a Python project (detects `setup.py`, `requirements.txt`, `.venv`, `pyproject.toml`)
- 🟡 Amber — default

**Aliases**

| Alias | Expands to |
|---|---|
| `ls`, `ll` | `ls --color=auto -Flartchs` |
| `la` | `ls --color=auto -a` |
| `lla` | `ls --color=auto -la` |
| `cp` | `rsync -vpartlXEHhP --ignore-existing` |
| `update` | `sudo zypper ref -f; sudo zypper dup; flatpak update` |
| `grep` | `grep --color=auto -i -n -I` |
| `sls` | `screen -list` |
| `swp` | `screen -wipe` |

**Custom Functions**

| Function | Description |
|---|---|
| `vmv <src> <dest>` | Verbose move via rsync with progress |
| `vcp <src> <dest>` | Verbose copy via rsync with progress |
| `unpack <file\|dir>` | Intelligently extract `.tar.gz`, `.zip`, `.rar`, `.7z`, and more; recursively unpacks nested archives |
| `moveav [-R] [dir]` | Sort media files into `images/`, `videos/`, `audio/` subdirectories; `-R` recurses |
| `shredfile <file>` | Securely shred a single file (with confirmation prompt and SSD warning) |
| `shredfolder <dir>` | Securely shred all files in a directory, then remove it |
| `sss <name>` | Start a new named `screen` session |
| `srs <name>` | Reattach to an existing `screen` session |
| `sks <name>` | Kill a named `screen` session from outside |
| `cfhelp` | Print a cheat-sheet of all custom aliases and functions |

Run `cfhelp` after sourcing `.zshrc` to see a quick reference of everything above.

---

## `music_meta_fix.sh`

**v1.4** — Recursively scans a music directory and performs two passes on every album folder containing MP3 or FLAC files:

1. **Metadata fix** — normalizes artist, album, and title tags to Title Case, infers disc number from folder names, and prompts interactively for any missing fields.
2. **Cover art fix** — detects missing, mixed, low-resolution (< 500 px), or WebP-encoded art; upgrades it by checking local image files first, then querying the iTunes Search API and MusicBrainz/Cover Art Archive as fallbacks.

**Dependencies:** `ffmpeg`, `ffprobe`, `id3v2`, `metaflac`, `curl`, `jq`, `sed`

```bash
# Interactive mode (prompts for missing info and art selection)
bash music_meta_fix.sh /path/to/music

# Unattended mode (skips prompts; logs problem folders to skipped_albums.txt)
bash music_meta_fix.sh /path/to/music --no-prompt
```

Albums that could not be fully resolved are logged to `skipped_albums.txt` in the working directory for manual follow-up.

> **Note:** The Title Case fixer has a known limitation — it will mangle intentional all-caps names (e.g. `AC/DC → Ac/Dc`) and lowercase stylizations (e.g. `deadmau5 → Deadmau5`). An exceptions list can be added to `fix_casing()` if needed.

---

## `install_update_portainer.sh`

Idempotent script to install or update **Portainer CE** (`portainer/portainer-ce:lts`) in Docker. On each run it:

1. Checks for an existing Portainer container.
2. Pulls the latest image and compares image IDs.
3. If up to date — exits cleanly with no changes.
4. If outdated — stops and removes the old container, then starts a fresh one.
5. If not installed — performs a clean install.
6. Prunes dangling images afterward.

**Requires:** root / sudo, Docker

```bash
sudo bash install_update_portainer.sh
```

Portainer is exposed on ports `8000` (tunnel) and `9443` (HTTPS UI), with data persisted to `/opt/portainer`.

---

## `backup_portainer.sh`

Rsync-based daily backup script for `/home/tyler` and `/opt`. Creates a date-stamped directory under `/mnt/media/backups/` and enforces a **7-day retention policy** by pruning older backup directories automatically.

**Requires:** root / sudo, `rsync`

```bash
sudo bash backup_portainer.sh
```

To change the backup sources or destination, edit the `SOURCES` array and `BACKUP_ROOT` variable at the top of the script.

---

## `update_opensuse.sh`

A minimal wrapper to fully update an openSUSE system in one command:

```bash
bash update_opensuse.sh
```

Runs `zypper ref -f` (force-refresh repos), `zypper dup` (distribution upgrade), and `flatpak update` in sequence.

---

## `convert_bashrc_2_zsh.sh`

Extracts aliases, `export` statements, and shell functions from an existing `.bashrc` and appends them to `.zshrc` inside a clearly marked migration block. Safe to re-run — it checks for the marker and exits early if the migration has already been applied.

```bash
# Preview what would be added (no files modified)
bash convert_bashrc_2_zsh.sh --dry-run

# Run the migration with default paths (~/.bashrc → ~/.zshrc)
bash convert_bashrc_2_zsh.sh

# Specify custom paths
bash convert_bashrc_2_zsh.sh --bashrc /path/to/.bashrc --zshrc /path/to/.zshrc
```

A timestamped backup of `.zshrc` is created before any changes are written. To redo the migration, remove the block between the `# >>> bashrc migration <<<` and `# <<< bashrc migration >>>` markers and re-run.

---

## License

See [LICENSE](LICENSE).
