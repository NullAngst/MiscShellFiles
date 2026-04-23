#!/usr/bin/env bash
# convert_bashrc_2_zsh.sh — Migrate aliases, functions, and exports from .bashrc to .zshrc

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────

BASHRC="${BASHRC_PATH:-$HOME/.bashrc}"
ZSHRC="${ZSHRC_PATH:-$HOME/.zshrc}"
MARKER="# >>> bashrc migration <<<"
DRY_RUN=false

# ── Argument parsing ─────────────────────────────────────────────────────────

usage() {
    echo "Usage: $0 [--dry-run] [--bashrc PATH] [--zshrc PATH]"
    echo ""
    echo "  --dry-run        Print what would be added without modifying .zshrc"
    echo "  --bashrc PATH    Source file (default: ~/.bashrc)"
    echo "  --zshrc  PATH    Target file (default: ~/.zshrc)"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)  DRY_RUN=true ;;
        --bashrc)   BASHRC="$2"; shift ;;
        --zshrc)    ZSHRC="$2";  shift ;;
        -h|--help)  usage ;;
        *) echo "Unknown option: $1"; usage ;;
    esac
    shift
done

# ── Validation ───────────────────────────────────────────────────────────────

if [[ ! -f "$BASHRC" ]]; then
    echo "Error: $BASHRC not found." >&2
    exit 1
fi

# ── Idempotency check ────────────────────────────────────────────────────────

if [[ -f "$ZSHRC" ]] && grep -qF "$MARKER" "$ZSHRC"; then
    echo "Warning: migration marker already present in $ZSHRC."
    echo "Remove the block between '$MARKER' markers and re-run to refresh."
    exit 0
fi

# ── Extraction logic ─────────────────────────────────────────────────────────

extract_aliases() {
    # Match lines starting with optional whitespace then 'alias '
    grep -E $'^[ \t]*alias ' "$BASHRC" || true
}

extract_exports() {
    # Match export lines that set a value (skip bare 'export VAR' re-exports)
    grep -E $'^[ \t]*export [A-Za-z_][A-Za-z0-9_]*=' "$BASHRC" || true
}

extract_functions() {
    # Handles both styles:
    #   foo() {         (POSIX style)
    #   function foo {  (ksh/bash style, with or without parens)
    awk '
    # Match either declaration style
    /^[[:space:]]*(function[[:space:]]+[a-zA-Z0-9_:-]+([[:space:]]*\(\))?|[a-zA-Z0-9_:-]+[[:space:]]*\(\))[[:space:]]*\{/ {
        in_func = 1
        brace_count = 0
    }
    in_func {
        print $0
        # Count braces on a clean copy of the line to avoid double-counting
        line = $0
        open = split(line, a, "{") - 1
        close = split(line, b, "}") - 1
        brace_count += open - close
        if (brace_count <= 0 && in_func) {
            in_func = 0
            print ""
        }
    }
    ' "$BASHRC"
}

# ── Assemble the block ────────────────────────────────────────────────────────

ALIASES=$(extract_aliases)
EXPORTS=$(extract_exports)
FUNCTIONS=$(extract_functions)

BLOCK=""
BLOCK+=$'\n'"$MARKER"$'\n'
BLOCK+="# Ported from $BASHRC on $(date '+%Y-%m-%d %H:%M:%S')"$'\n'

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

BLOCK+=$'\n'"# <<< bashrc migration >>>"$'\n'

# ── Output ───────────────────────────────────────────────────────────────────

if $DRY_RUN; then
    echo "=== DRY RUN — nothing will be written to $ZSHRC ==="
    echo "$BLOCK"
    exit 0
fi

# Backup before modifying
if [[ -f "$ZSHRC" ]]; then
    BACKUP="${ZSHRC}.bak.$(date '+%Y%m%d%H%M%S')"
    cp "$ZSHRC" "$BACKUP"
    echo "Backup created: $BACKUP"
fi

echo "$BLOCK" >> "$ZSHRC"

echo "Migration complete."
[[ -n "$ALIASES"   ]] && echo "  ✓ Aliases:   $(echo "$ALIASES"   | grep -c 'alias')"
[[ -n "$EXPORTS"   ]] && echo "  ✓ Exports:   $(echo "$EXPORTS"   | wc -l | tr -d ' ')"
[[ -n "$FUNCTIONS" ]] && echo "  ✓ Functions: $(echo "$FUNCTIONS" | grep -cE '^\s*(function\s+[a-zA-Z]|[a-zA-Z].+\(\))' || true)"
echo ""
echo "Run 'source $ZSHRC' to apply changes."
