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
alias ll='ls --color=auto -Flartchs'  # FIX: was bare 'ls', now inherits color flags
alias la='ls --color=auto -a'         # FIX: was bare 'ls', now colorized
alias lla='ls --color=auto -la'       # FIX: was bare 'ls', now colorized
alias cp='rsync -vpartlXEHhP --ignore-existing'
alias update='sudo zypper ref -f; sudo zypper dup; flatpak update'
alias ripcd='bash /home/tyler/bin/ripcd.sh'
alias grep='grep --color=auto -i -n -I'

# ------------------------------------------------------------------------------
# --- Custom Functions (vmv vcp unpack sss moveav shredfile shredfolder)
# ------------------------------------------------------------------------------

# Verbose file move
vmv() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: vmv <source> <destination>"
        return 1
    fi
    rsync -vpartlXEHhP --info=progress2 --remove-source-files "$@"
}

# Verbose file copy
vcp() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: vcp <source> <destination>"
        return 1
    fi
    rsync -vpartlXEHhP --info=progress2 --ignore-existing "$@"
}


# can extract common compression types intelligently
unpack() {
    if [ -z "$1" ]; then
        echo "Usage: unpack <archive_file_or_directory>"
        return 1
    fi

    local target="$1"

    if [ -d "$target" ]; then
        find "$target" -maxdepth 1 -type f -print0 | while IFS= read -r -d '' file; do
            local lower_file=$(echo "$file" | tr '[:upper:]' '[:lower:]')
            case "$lower_file" in
                *.tar.gz|*.tgz|*.tar.bz2|*.tbz2|*.tar.xz|*.tar|*.zip|*.rar|*.7z)
                    unpack "$file"
                    ;;
            esac
        done
        return 0
    fi

    if [ ! -f "$target" ]; then
        echo "Error: '$target' is not a valid file or directory."
        return 1
    fi

    local file="$target"
    local dir=$(dirname "$file")
    local base=$(basename "$file")
    local folder_name=$(echo "$base" | sed -E 's/\.(tar\.gz|tar\.bz2|tar\.xz|tgz|tbz2|zip|rar|7z|tar)$//I')
    local folder="$dir/$folder_name"
    
    mkdir -p "$folder"

    local lower_base=$(echo "$base" | tr '[:upper:]' '[:lower:]')
    case "$lower_base" in
        *.tar.bz2|*.tbz2) tar -xvjf "$file" -C "$folder" ;;
        *.tar.gz|*.tgz)   tar -xvzf "$file" -C "$folder" ;;
        *.tar.xz)         tar -xvJf "$file" -C "$folder" ;;
        *.tar)            tar -xvf "$file" -C "$folder" ;;
        *.zip)            unzip "$file" -d "$folder" ;;
        *.rar)            unrar x "$file" "$folder/" ;;
        *.7z)             7z x "$file" -o"$folder" ;;
        *)
            echo "Error: Unsupported archive format for '$file'."
            rmdir "$folder" 2>/dev/null
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        rm "$file"
        echo "Successfully unpacked into '$folder/' and deleted '$file'."
        
        unpack "$folder"
    else
        echo "Extraction failed for '$file'. The original file was not deleted."
        return 1
    fi
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

cfhelp() {
    cat << 'EOF'

========================================
             CUSTOM ALIASES
========================================
ls      : Colorized, verbose list (ls --color=auto -Flartchs)
ll      : Verbose list (ls --color=auto -Flartchs)
la      : List all (ls --color=auto -a)
lla     : List all verbose (ls --color=auto -la)
cp      : Robust copy via rsync (--ignore-existing)
update  : System update (zypper ref, zypper dup, flatpak update)
ripcd   : Run ripcd.sh script
grep    : Colorized, case-insensitive, line numbers, ignore binary
sls     : List all active screen sessions
swp     : Wipe dead screen sessions

========================================
            CUSTOM FUNCTIONS
========================================
vmv       : Verbose file move using rsync
vcp       : Verbose file copy using rsync
unpack    : Intelligently extract common compression types
sss       : Start a new named screen session (Usage: sss <session_name>)
srs       : Reattach to an existing screen session (Usage: srs <session_name>)
sks       : Kill a specific screen session from the outside (Usage: sks <session_name>)
moveav    : Move and sort folders of media into images/, videos/, and audio/
shredfile   : Runs shred against a file with proper arguments
shredfolder : Runs shred against a folder with proper arguments  # FIX: was 'shredolder'

EOF
}

# ------------------------------------------------------------------------------
# --- Zsh Configuration
# ------------------------------------------------------------------------------

# Set the default editor for command-line editing
export EDITOR='nano'

# --- History
HISTFILE=~/.zsh_history
HISTSIZE=50000
SAVEHIST=50000
setopt APPEND_HISTORY        # Append history to the history file
setopt SHARE_HISTORY         # Share history between all sessions
setopt HIST_IGNORE_DUPS      # Don't record duplicate commands
setopt HIST_IGNORE_ALL_DUPS  # Delete old duplicate entries from history
setopt HIST_FIND_NO_DUPS     # Don't show duplicates when searching
setopt HIST_REDUCE_BLANKS    # Remove superfluous blanks
setopt HIST_VERIFY           # ADDED: show history expansion before executing (e.g. !!)

# --- Completion
# Cache compinit for faster shell startup (only regenerate once per day)
autoload -U compinit
if [[ -n ~/.zcompdump(#qN.mh+24) ]]; then
    compinit
else
    compinit -C
fi

# Case-insensitive completion
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
# Arrow-key navigable completion menu  # ADDED
zstyle ':completion:*' menu select
# Group completions by type with a header label  # FIX: was missing 'format', so grouping had no effect
zstyle ':completion:*:descriptions' format '%B%d%b'
zstyle ':completion:*' group-name ''

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

setopt PROMPT_SUBST

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
#
PROMPT='
${PROMPT_FG_WHITE}%n${PROMPT_FG_GRAY}@%m ${PROMPT_FG_NONE}in ${PROMPT_CONTEXT_COLOR}%B%~%b${vcs_info_msg[0]}
${PROMPT_CONTEXT_COLOR}❯ ${PROMPT_FG_NONE}'
