# ~/.zshrc
#
# Amber-Hued Zsh Configuration
# Based on the provided Kitty terminal theme.

# ------------------------------------------------------------------------------
# --- Color Palette
# ------------------------------------------------------------------------------

# Load the 'colors' module to use color names in prompts
autoload -U colors && colors

# Define color variables using hex codes
# %F{...} sets the foreground color.
# We wrap it in a variable for easier use.
PROMPT_FG_AMBER='%F{#ffa71a}'
PROMPT_FG_RED='%F{#D75F5F}'
PROMPT_FG_GREEN='%F{#AFB16A}'
PROMPT_FG_BLUE='%F{#7DA3CC}'
PROMPT_FG_WHITE='%F{#E8D4A9}'
PROMPT_FG_GRAY='%F{#7A705F}'
PROMPT_FG_BLACK='%F{#0c0702}'
PROMPT_FG_NONE='%f' # Resets to default foreground color

# ------------------------------------------------------------------------------
# --- Aliases
# ------------------------------------------------------------------------------

alias ls='ls --color=auto -Flartchs'
alias ll='ls -Flartchs'
alias la='ls -a'
alias lla='ls -la'
alias cp='rsync -vpartlXEHhP --ignore-existing'
alias update='sudo bash /home/tyler/bin/system-update.sh'
alias ripcd='bash /home/tyler/bin/ripcd.sh'
alias grep='grep --color=auto -i -n -I'

# ------------------------------------------------------------------------------
# --- Custom Functions (vmv vcp unpack sss moveav ffile)
# ------------------------------------------------------------------------------

# Verbose file move
vmv() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: vmv <source> [source...] <destination>"
        return 1
    fi

    local args=("$@")
    local dest="${args[-1]}"
    local sources=("${args[@]:0:$#-1}")

    rsync -vpartlXEHhP --info=progress2 --remove-source-files "${sources[@]}" "$dest"
    local status=$?

    if [ $status -eq 0 ]; then
        for src in "${sources[@]}"; do
            if [ -d "$src" ]; then
                # Delete deepest empty dirs first, working up to (and including)
                # the source dir itself if it ended up empty.
                find "$src" -type d -empty -delete 2>/dev/null
            fi
        done
    fi

    return $status
}

# Verbose file copy
vcp() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: vcp <source> [source...] <destination>"
        return 1
    fi
    rsync -vpartlXEHhP --info=progress2 --ignore-existing "$@"
}


# can extract common compression types intelligently and handles split archives
unpack() {
    if [ "$#" -eq 0 ]; then
        echo "Usage: unpack <archive_file_or_directory> [additional_files...]"
        return 1
    fi

    for target in "$@"; do
        # Handle directories recursively
        if [ -d "$target" ]; then
            find "$target" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
                local lower_file=$(echo "$file" | tr '[:upper:]' '[:lower:]')
                case "$lower_file" in
                    *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.tar|*.zip|*.rar|*.7z|*.001)
                        unpack "$file"
                        ;;
                esac
            done
            continue
        fi

        if [ ! -f "$target" ]; then
            echo "Error: '$target' is not a valid file or directory."
            continue
        fi

        local file="$target"
        local dir=$(dirname "$file")
        local base=$(basename "$file")
        
        # Strip common and multi-volume suffixes for the output folder name
        local folder_name=$(echo "$base" | sed -E 's/\.(tar\.gz|tar\.bz2|tar\.xz|tgz|tbz2|zip|rar|7z|tar|part[0-9]+\.rar|[0-9]{3})$//I')
        local folder="$dir/$folder_name"
        local lower_base=$(echo "$base" | tr '[:upper:]' '[:lower:]')

        # Skip secondary archive volumes to prevent redundant extraction errors
        if [[ "$lower_base" =~ \.(r[0-9]{2,}|z[0-9]{2,}|[0-9]{3})$ && ! "$lower_base" =~ \.(r00|r01|z01|001)$ ]]; then
             continue
        fi
        if [[ "$lower_base" =~ \.part[0-9]+\.rar$ && ! "$lower_base" =~ \.part0*1\.rar$ ]]; then
             continue
        fi

        mkdir -p "$folder"
        local extracted=0

        # Execute extraction against the primary file
        case "$lower_base" in
            *.tar.bz2|*.tbz2) tar -xvjf "$file" -C "$folder" && extracted=1 ;;
            *.tar.gz|*.tgz)   tar -xvzf "$file" -C "$folder" && extracted=1 ;;
            *.tar.xz)         tar -xvJf "$file" -C "$folder" && extracted=1 ;;
            *.tar)            tar -xvf "$file" -C "$folder" && extracted=1 ;;
            *.zip|*.zip.001)  unzip "$file" -d "$folder" && extracted=1 ;;
            *.rar|*.part*.rar) unrar x "$file" "$folder/" && extracted=1 ;;
            *.7z|*.7z.001)    7z x "$file" -o"$folder" && extracted=1 ;;
            *)
                echo "Error: Unsupported archive format for '$file'."
                rmdir "$folder" 2>/dev/null
                continue
                ;;
        esac

        if [ "$extracted" -eq 1 ]; then
            echo "Successfully unpacked into '$folder/'."
            
            # Identify split formats and scrub all related volume files
            if [[ "$lower_base" =~ \.part[0-9]+\.rar$ ]]; then
                local clean_base=$(echo "$file" | sed -E 's/\.part[0-9]+\.rar$//I')
                rm -f "$clean_base".part*.rar(N)
            elif [[ "$lower_base" =~ \.rar$ ]]; then
                local clean_base="${file%.rar}"
                rm -f "$file" "$clean_base".r[0-9][0-9](N) "$clean_base".s[0-9][0-9](N)
            elif [[ "$lower_base" =~ \.zip$ || "$lower_base" =~ \.zip\.001$ ]]; then
                local clean_base=$(echo "$file" | sed -E 's/\.zip(\.001)?$//I')
                rm -f "$clean_base".zip "$clean_base".z[0-9][0-9](N)
            elif [[ "$lower_base" =~ \.7z\.001$ ]]; then
                local clean_base="${file%.001}"
                rm -f "$clean_base".[0-9][0-9][0-9](N)
            else
                # Clean standard single-file archives
                rm -f "$file"
            fi
            # Recursively scan the newly created folder
            unpack "$folder"
        else
            echo "Extraction failed for '$file'. Original files were not deleted."
            rmdir "$folder" 2>/dev/null
        fi
    done
}

# Start a new named screen session
sss() {
    if [ -z "$1" ]; then
        echo "Usage: sss <session_name>"
        return 1
    fi
    screen -S "$1"
}

# Reattach to an existing screen session
srs() {
    if [ -z "$1" ]; then
        echo "Usage: srs <session_name>"
        return 1
    fi
    # The -d -r combination detaches the session if it is open in another terminal, then reattaches it here
    screen -d -r "$1"
}

# List all active screen sessions
alias sls='screen -list'

# Wipe dead screen sessions
alias swp='screen -wipe'

# Kill a specific screen session from the outside
sks() {
    if [ -z "$1" ]; then
        echo "Usage: sks <session_name>"
        return 1
    fi
    screen -X -S "$1" quit
}

# Easily move and sort folders of media
moveav() {
    local recursive=0
    local target_dir="."

    while [[ "$#" -gt 0 ]]; do
        case "$1" in
            -R) recursive=1 ;;
            -*) echo "Error: Invalid option '$1'" >&2; return 1 ;;
            *) target_dir="$1" ;;
        esac
        shift
    done

    if [[ ! -d "$target_dir" ]]; then
        echo "Error: Directory '$target_dir' does not exist." >&2
        return 1
    fi

    target_dir=$(cd "$target_dir" && pwd)

    _process_category() {
        local dir="$1"
        local category="$2"
        shift 2
        
        # $@ passes the remaining arguments (the -iname flags) to the find command
        find "$dir" -maxdepth 1 -type f \( "$@" \) -print0 | while IFS= read -r -d $'\0' file; do
            local dest_dir="$dir/$category"
            local filename=$(basename "$file")
            
            if [[ ! -d "$dest_dir" ]]; then
                mkdir -p "$dest_dir"
            fi
            
            mv "$file" "$dest_dir/"
            
            # Verbose output
            echo "Moved: $filename"
            echo "From:  $file"
            echo "To:    $dest_dir/$filename"
            echo ""
        done
    }

    _sort_media() {
        local dir="$1"
        
        _process_category "$dir" "images" -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.webp" -o -iname "*.bmp" -o -iname "*.tiff" -o -iname "*.svg"
        
        _process_category "$dir" "videos" -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.avi" -o -iname "*.mov" -o -iname "*.wmv" -o -iname "*.flv" -o -iname "*.webm" -o -iname "*.m4v"
        
        _process_category "$dir" "audio" -iname "*.mp3" -o -iname "*.wav" -o -iname "*.flac" -o -iname "*.m4a" -o -iname "*.ogg" -o -iname "*.aac" -o -iname "*.wma"
    }

    if (( recursive )); then
        find "$target_dir" -type d \( -name "images" -o -name "videos" -o -name "audio" \) -prune -o -type d -print0 | while IFS= read -r -d $'\0' d; do
            _sort_media "$d"
        done
    else
        _sort_media "$target_dir"
    fi

    unset -f _process_category
    unset -f _sort_media
}

# shred a file with proper args
shredfile() {
    if [ -z "$1" ]; then
        echo "Usage: shredfile <filepath>"
        return 1
    fi

    local target="$1"

    if [ ! -f "$target" ]; then
        echo "Error: '$target' not found or is not a regular file."
        return 1
    fi

    printf 'confirm you want to shred file "%s" and understand that shred does not properly work if ran on an ssd (y/n): ' "$target"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            # -v: verbose, -z: add final zero overwrite, -u: remove file after shredding
            shred -vzu "$target"
            echo "File shredded."
            ;;
        *)
            echo "Aborted."
            ;;
    esac
}

# shred a folder with proper args
shredfolder() {
    if [ -z "$1" ]; then
        echo "Usage: shredfolder <folderpath>"
        return 1
    fi

    local target="$1"

    if [ ! -d "$target" ]; then
        echo "Error: '$target' not found or is not a directory."
        return 1
    fi

    printf 'confirm you want to shred folder "%s" and understand that shred does not properly work if ran on an ssd (y/n): ' "$target"
    read -r response

    case "$response" in
        [yY][eE][sS]|[yY])
            # Find and shred all files inside the directory
            find "$target" -type f -exec shred -vzu {} +
            # Remove the now-empty directory structure
            rm -rf "$target"
            echo "Folder shredded."
            ;;
        *)
            echo "Aborted."
            ;;
    esac
}

# Forensic File Analysis
# Pulls every available piece of metadata and content hinting from a file
# to help identify what it is, who/what made it, and when.
ffile() {
    if [ -z "$1" ]; then
        echo "Usage: ffile <filepath>"
        return 1
    fi

    local target="$1"
    local sep="================================================================================"

    if [ ! -e "$target" ]; then
        echo "Error: '$target' does not exist."
        return 1
    fi

    # Helper: print a section header
    _ff_header() { echo; echo "$sep"; echo "  $1"; echo "$sep"; }

    # Resolve symlinks and get the real path
    local realpath_val
    realpath_val=$(realpath "$target" 2>/dev/null || readlink -f "$target" 2>/dev/null || echo "$target")

    _ff_header "IDENTITY"
    echo "  Provided path : $target"
    echo "  Resolved path : $realpath_val"
    if [ -L "$target" ]; then
        echo "  Symlink target: $(readlink "$target")"
    fi

    # --- stat: all timestamps, permissions, inode, device ---
    _ff_header "STAT (timestamps, permissions, inode)"
    stat "$target"

    # --- file type detection ---
    _ff_header "FILE TYPE DETECTION"
    echo "[file command]"
    file "$target"
    echo
    echo "[file --mime]"
    file --mime "$target"

    # --- checksums ---
    _ff_header "CHECKSUMS"
    md5sum    "$target" 2>/dev/null && \
    sha1sum   "$target" 2>/dev/null && \
    sha256sum "$target" 2>/dev/null && \
    sha512sum "$target" 2>/dev/null
    if command -v b2sum &>/dev/null; then
        b2sum "$target" 2>/dev/null
    fi

    # --- size / line / word counts ---
    _ff_header "SIZE / COUNTS"
    wc "$target" 2>/dev/null
    du -sh "$target" 2>/dev/null

    # --- file system attributes ---
    _ff_header "FILESYSTEM ATTRIBUTES (lsattr)"
    lsattr "$target" 2>/dev/null || echo "  lsattr unavailable or not applicable."

    # --- extended attributes ---
    _ff_header "EXTENDED ATTRIBUTES (getfattr)"
    if command -v getfattr &>/dev/null; then
        getfattr -d "$target" 2>/dev/null || echo "  No extended attributes found."
    else
        echo "  getfattr not installed."
    fi

    # --- ACLs ---
    _ff_header "ACCESS CONTROL LIST (getfacl)"
    if command -v getfacl &>/dev/null; then
        getfacl "$target" 2>/dev/null
    else
        echo "  getfacl not installed."
    fi

    # --- open file handles ---
    _ff_header "OPEN FILE HANDLES (lsof)"
    if command -v lsof &>/dev/null; then
        lsof "$realpath_val" 2>/dev/null || echo "  File is not currently open by any process."
    else
        echo "  lsof not installed."
    fi

    # --- package ownership ---
    _ff_header "PACKAGE OWNERSHIP"
    if command -v rpm &>/dev/null; then
        rpm -qf "$realpath_val" 2>/dev/null || echo "  Not owned by any RPM package."
    fi
    if command -v dpkg &>/dev/null; then
        dpkg -S "$realpath_val" 2>/dev/null || echo "  Not owned by any dpkg package."
    fi
    if command -v pacman &>/dev/null; then
        pacman -Qo "$realpath_val" 2>/dev/null || echo "  Not owned by any pacman package."
    fi

    # --- hex header (first 256 bytes) ---
    _ff_header "HEX HEADER (first 256 bytes)"
    if command -v xxd &>/dev/null; then
        xxd "$target" 2>/dev/null | head -n 16
    elif command -v hexdump &>/dev/null; then
        hexdump -C "$target" 2>/dev/null | head -n 16
    else
        od -A x -t x1z "$target" 2>/dev/null | head -n 16
    fi

    # --- hex tail (last 256 bytes) ---
    _ff_header "HEX TAIL (last 256 bytes)"
    if command -v xxd &>/dev/null; then
        xxd "$target" 2>/dev/null | tail -n 16
    elif command -v hexdump &>/dev/null; then
        hexdump -C "$target" 2>/dev/null | tail -n 16
    else
        od -A x -t x1z "$target" 2>/dev/null | tail -n 16
    fi

    # --- printable strings ---
    _ff_header "PRINTABLE STRINGS (min length 6, first 80 results)"
    if command -v strings &>/dev/null; then
        strings -n 6 "$target" 2>/dev/null | head -n 80
    else
        echo "  strings not installed."
    fi

    # --- head / tail of raw text ---
    _ff_header "HEAD (first 20 lines of raw content)"
    head -n 20 "$target" 2>/dev/null || echo "  Could not read as text."

    _ff_header "TAIL (last 20 lines of raw content)"
    tail -n 20 "$target" 2>/dev/null || echo "  Could not read as text."

    # --- exiftool metadata (gold for images, PDFs, office docs) ---
    _ff_header "EXIFTOOL METADATA"
    if command -v exiftool &>/dev/null; then
        exiftool "$target" 2>/dev/null
    else
        echo "  exiftool not installed. Install it for deep metadata on images, PDFs, etc."
        echo "  (sudo zypper install perl-Image-ExifTool  OR  sudo apt install libimage-exiftool-perl)"
    fi

    # --- binwalk: embedded files / firmware signatures ---
    _ff_header "BINWALK (embedded file signatures)"
    if command -v binwalk &>/dev/null; then
        binwalk "$target" 2>/dev/null
    else
        echo "  binwalk not installed."
    fi

    # --- entropy hint via ent or python fallback ---
    _ff_header "ENTROPY ESTIMATE"
    if command -v ent &>/dev/null; then
        ent "$target" 2>/dev/null
    elif command -v python3 &>/dev/null; then
        python3 - "$target" << 'PYEOF'
import sys, math, collections
try:
    data = open(sys.argv[1], 'rb').read()
    if not data:
        print("  File is empty.")
        sys.exit(0)
    counts = collections.Counter(data)
    total  = len(data)
    entropy = -sum((c/total) * math.log2(c/total) for c in counts.values())
    print(f"  Byte entropy : {entropy:.4f} bits/byte  (max 8.0)")
    print(f"  Total bytes  : {total}")
    print(f"  Unique bytes : {len(counts)}")
    if entropy > 7.5:
        print("  Interpretation: very high entropy -- likely compressed, encrypted, or packed.")
    elif entropy > 6.0:
        print("  Interpretation: moderate-high entropy -- possibly compressed or binary data.")
    elif entropy < 1.0:
        print("  Interpretation: very low entropy -- highly repetitive or near-empty file.")
    else:
        print("  Interpretation: entropy consistent with normal text or structured binary.")
except Exception as e:
    print(f"  Entropy calculation failed: {e}")
PYEOF
    else
        echo "  Neither 'ent' nor python3 available for entropy calculation."
    fi

    _ff_header "DONE"
    echo "  Target: $target"
    echo

    unset -f _ff_header
}

cfhelp() {
    cat << 'EOF'

========================================
             CUSTOM ALIASES
========================================
ls      : Colorized, verbose list (ls --color=auto -Flartchs)
ll      : Verbose list (ls -Flartchs)
la      : List all (ls -a)
lla     : List all verbose (ls -la)
cp      : Robust copy via rsync (--ignore-existing)
update  : System update (zypper ref, zypper dup, flatpak update)
ripcd   : Run ripcd.sh script
grep    : Colorized, case-insensitive, line numbers, ignore binary
sls     : List all active screen sessions
swp     : Wipe dead screen sessions

========================================
            CUSTOM FUNCTIONS
========================================
vmv        : Verbose file move using rsync (cleans empty source dirs after transfer)
vcp        : Verbose file copy using rsync
unpack     : Intelligently extract common compression types
sss        : Start a new named screen session (Usage: sss <session_name>)
srs        : Reattach to an existing screen session (Usage: srs <session_name>)
sks        : Kill a specific screen session from the outside (Usage: sks <session_name>)
moveav     : Move and sort folders of media into images/, videos/, and audio/
shredfile  : Runs shred against a file with proper arguments
shredfolder: Runs shred against a folder with proper arguments
ffile      : Forensic file analysis -- stat, hashes, hex, strings, entropy, metadata

EOF
}

# ------------------------------------------------------------------------------
# --- Zsh Configuration
# ------------------------------------------------------------------------------

# Set the default editor for command-line editing
export EDITOR='nano'

# --- History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt APPEND_HISTORY        # Append history to the history file
setopt SHARE_HISTORY         # Share history between all sessions
setopt HIST_IGNORE_DUPS      # Don't record duplicate commands
setopt HIST_IGNORE_ALL_DUPS  # Delete old duplicate entries from history
setopt HIST_FIND_NO_DUPS     # Don't show duplicates when searching
setopt HIST_REDUCE_BLANKS    # Remove superfluous blanks

# --- Completion
# Initialize the Zsh completion system
autoload -U compinit && compinit
# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
# Group completions by type
zstyle ':completion:*:descriptions' group-name ''

# --- Keybindings
bindkey -e # Use Emacs keybindings

# ------------------------------------------------------------------------------
# --- Version Control System (Git) Integration
# ------------------------------------------------------------------------------
# This enables Zsh to get information from Git repositories.

autoload -Uz vcs_info
# Format for the git info (branch name)
# %b = branch, %r = repository root, %s = vcs name (git)
zstyle ':vcs_info:git:*' formats " on ${PROMPT_FG_WHITE}%b${PROMPT_FG_NONE}"
zstyle ':vcs_info:*' enable git # Enable for git

# ------------------------------------------------------------------------------
# --- FANCY PROMPT
# ------------------------------------------------------------------------------
# This section defines the appearance of your command prompt.

# precmd() is a special function that runs just before the prompt is drawn.
# We use it to check the context (user, git, python) and set the color.
precmd() {
  # First, run vcs_info to get git info and store it in the $vcs_info_msg array
  vcs_info

  # --- Detect Context and Set Color ---
  # Check if the user is root.
  if [[ $EUID -eq 0 ]]; then
    PROMPT_CONTEXT_COLOR=$PROMPT_FG_RED
  # Check if we are inside a Git working tree.
  elif git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    PROMPT_CONTEXT_COLOR=$PROMPT_FG_BLUE
  # Check for common Python project files.
  elif [[ -f "setup.py" || -f "requirements.txt" || -d ".venv" || -f "pyproject.toml" ]]; then
    PROMPT_CONTEXT_COLOR=$PROMPT_FG_GREEN
  # If none of the above, use the default amber color.
  else
    PROMPT_CONTEXT_COLOR=$PROMPT_FG_AMBER
  fi
}

# --- Prompt Structure ---
# This sets the main prompt (PS1). It's a two-line prompt for clarity.
#
# Line 1: [user]@[hostname] in [current_directory] [git_branch]
# Line 2: ❯
#
# Breakdown:
# %n -> username
# %m -> hostname
# %~ -> current directory, with '~' for home
# ${vcs_info_msg[0]} -> The formatted git info from our zstyle above
# %(?.<ok_char>.<err_char>) -> Shows a different character if the last command failed.

setopt PROMPT_SUBST

PROMPT='
${PROMPT_FG_WHITE}%n${PROMPT_FG_GRAY}@%m ${PROMPT_FG_NONE}in ${PROMPT_CONTEXT_COLOR}%B%~%b${vcs_info_msg[0]}
${PROMPT_CONTEXT_COLOR}❯ ${PROMPT_FG_NONE}'
