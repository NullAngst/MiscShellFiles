#!/usr/bin/env bash
# convert_zshrc_2_bash.sh — Migrate aliases, functions, and exports from .zshrc to .bashrc
#
# What is ported:       aliases, export VAR=value, named functions
# What is translated:   typeset → declare (inside functions)
# What is warned about: setopt/unsetopt, autoload, zsh anonymous functions () { }
# What is skipped:      zsh-only plugin/framework lines (oh-my-zsh, zinit, antigen, etc.)

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

ZSHRC="${ZSHRC_PATH:-$HOME/.zshrc}"
BASHRC="${BASHRC_PATH:-$HOME/.bashrc}"
MARKER="# >>> zshrc migration <<<"
DRY_RUN=false

# ── Argument parsing ─────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 [--dry-run] [--zshrc PATH] [--bashrc PATH]"
    echo ""
    echo "  --dry-run        Print what would be added without modifying .bashrc"
    echo "  --zshrc  PATH    Source file (default: ~/.zshrc)"
    echo "  --bashrc PATH    Target file (default: ~/.bashrc)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --zshrc)    ZSHRC="$2";  shift ;;
        --bashrc)   BASHRC="$2"; shift ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

# ── Validation ───────────────────────────────────────────────────────────────

if [[ ! -f "$ZSHRC" ]]; then
    echo "Error: $ZSHRC not found." >&2
    exit 1
fi

# ── Idempotency check ────────────────────────────────────────────────────────

if [[ -f "$BASHRC" ]] && grep -qF "$MARKER" "$BASHRC"; then
    echo "Warning: migration marker already present in $BASHRC."
    echo "Remove the block between '$MARKER' markers and re-run to refresh."
    exit 0
fi

# ── Extraction logic ─────────────────────────────────────────────────────────

extract_aliases() {
    grep -E $'^[ \t]*alias ' "$ZSHRC" || true
}

extract_exports() {
    # Skip bare re-exports (export VAR with no value assignment)
    grep -E $'^[ \t]*export [A-Za-z_][A-Za-z0-9_]*=' "$ZSHRC" || true
}

extract_functions() {
    awk '
    # Skip zsh anonymous functions: lines that are just "() {" with no name
    /^[[:space:]]*\(\)[[:space:]]*\{/ { next }

    # Match named function declarations (both styles)
    /^[[:space:]]*(function[[:space:]]+[a-zA-Z0-9_:-]+([[:space:]]*\(\))?|[a-zA-Z0-9_:-]+[[:space:]]*\(\))[[:space:]]*\{/ {
        in_func = 1
        brace_count = 0
    }
    in_func {
        line = $0
        # Translate zsh typeset to bash declare
        gsub(/\btypeset\b/, "declare", line)
        print line
        open  = split(line, a, "{") - 1
        close = split(line, b, "}") - 1
        brace_count += open - close
        if (brace_count <= 0 && in_func) {
            in_func = 0
            print ""
        }
    }
    ' "$ZSHRC"
}

collect_warnings() {
    local warnings=()

    # setopt / unsetopt — zsh shell option builtins, no bash equivalent
    local setopts
    setopts=$(grep -nE $'^[ \t]*(setopt|unsetopt)' "$ZSHRC" || true)
    if [[ -n "$setopts" ]]; then
        warnings+=("  setopt/unsetopt (no bash equivalent):")
        while IFS= read -r line; do
            warnings+=("    $line")
        done <<< "$setopts"
    fi

    # autoload — zsh lazy-loading builtin, not available in bash
    local autoloads
    autoloads=$(grep -nE $'^[ \t]*autoload' "$ZSHRC" || true)
    if [[ -n "$autoloads" ]]; then
        warnings+=("  autoload (not available in bash):")
        while IFS= read -r line; do
            warnings+=("    $line")
        done <<< "$autoloads"
    fi

    # zsh plugin/framework lines
    local plugins
    plugins=$(grep -nE $'^[ \t]*(source.*oh-my-zsh|zinit|antigen|zplug|antibody|zi )' "$ZSHRC" || true)
    if [[ -n "$plugins" ]]; then
        warnings+=("  zsh plugin/framework calls (skipped entirely):")
        while IFS= read -r line; do
            warnings+=("    $line")
        done <<< "$plugins"
    fi

    # Anonymous functions
    local anon
    anon=$(grep -nE $'^[ \t]*\(\)[[:space:]]*\{' "$ZSHRC" || true)
    if [[ -n "$anon" ]]; then
        warnings+=("  anonymous functions (skipped, bash has no equivalent):")
        while IFS= read -r line; do
            warnings+=("    $line")
        done <<< "$anon"
    fi

    printf '%s\n' "${warnings[@]}"
}

# ── Assemble the block ────────────────────────────────────────────────────────

ALIASES=$(extract_aliases)
EXPORTS=$(extract_exports)
FUNCTIONS=$(extract_functions)
WARNINGS=$(collect_warnings)

BLOCK=""
BLOCK+=$'\n'"$MARKER"$'\n'
BLOCK+="# Ported from $ZSHRC on $(date '+%Y-%m-%d %H:%M:%S')"$'\n'

if [[ -n "$ALIASES" ]]; then
    BLOCK+=$'\n# -- Aliases --\n'
    BLOCK+="$ALIASES"$'\n'
fi

if [[ -n "$EXPORTS" ]]; then
    BLOCK+=$'\n# -- Exports --\n'
    BLOCK+="$EXPORTS"$'\n'
fi

if [[ -n "$FUNCTIONS" ]]; then
    BLOCK+=$'\n# -- Functions --\n'
    BLOCK+="$FUNCTIONS"
fi

BLOCK+=$'\n'"# <<< zshrc migration >>>"$'\n'

# ── Output ───────────────────────────────────────────────────────────────────

if $DRY_RUN; then
    echo "=== DRY RUN — nothing will be written to $BASHRC ==="
    echo "$BLOCK"
    if [[ -n "$WARNINGS" ]]; then
        echo ""
        echo "=== WARNINGS — zsh-only constructs that were skipped/need manual review ==="
        echo "$WARNINGS"
    fi
    exit 0
fi

# Backup before modifying
if [[ -f "$BASHRC" ]]; then
    BACKUP="${BASHRC}.bak.$(date '+%Y%m%d%H%M%S')"
    cp "$BASHRC" "$BACKUP"
    echo "Backup created: $BACKUP"
fi

echo "$BLOCK" >> "$BASHRC"

echo "Migration complete."
[[ -n "$ALIASES"   ]] && echo "  ✓ Aliases:   $(echo "$ALIASES"   | grep -c 'alias')"
[[ -n "$EXPORTS"   ]] && echo "  ✓ Exports:   $(echo "$EXPORTS"   | wc -l | tr -d ' ')"
[[ -n "$FUNCTIONS" ]] && echo "  ✓ Functions: $(echo "$FUNCTIONS" | grep -cE '^\s*(function\s+[a-zA-Z]|[a-zA-Z].+\(\))' || true)"

if [[ -n "$WARNINGS" ]]; then
    echo ""
    echo "⚠ Some zsh-only constructs were skipped and need manual review:"
    echo "$WARNINGS"
fi

echo ""
echo "Run 'source $BASHRC' to apply changes."
