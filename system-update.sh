#!/usr/bin/env bash
# =============================================================================
# system-update.sh
# Generic Linux system updater for RMM deployment
# Detects and runs updates for all present package managers + Flatpak/Snap
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Config
# -----------------------------------------------------------------------------
LOG_FILE="/var/log/rmm-system-update.log"
TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
ERRORS=0

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
log() {
    echo "[${TIMESTAMP}] $*" | tee -a "$LOG_FILE"
}

log_section() {
    log ""
    log "============================================"
    log " $*"
    log "============================================"
}

run_cmd() {
    log "Running: $*"
    if ! "$@" >> "$LOG_FILE" 2>&1; then
        log "ERROR: Command failed: $*"
        (( ERRORS++ )) || true
    fi
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root." >&2
        exit 1
    fi
}

has_cmd() {
    command -v "$1" &>/dev/null
}

# -----------------------------------------------------------------------------
# Package manager update functions
# -----------------------------------------------------------------------------

update_apt() {
    log_section "APT (Debian/Ubuntu/Mint)"
    run_cmd apt update -q
    run_cmd apt dist-upgrade -y -q
    run_cmd apt autoremove -y -q
    run_cmd apt autoclean -q
}

update_dnf() {
    log_section "DNF (Fedora/RHEL 8+/AlmaLinux/Rocky)"
    run_cmd dnf upgrade --refresh -y
    run_cmd dnf autoremove -y
}

update_yum() {
    log_section "YUM (CentOS/RHEL 7)"
    run_cmd yum update -y
    run_cmd yum autoremove -y
}

zypper_autoremove() {
    local pkgs
    mapfile -t pkgs < <(
        zypper packages --unneeded \
        | grep "^i" \
        | cut -d"|" -f3 \
        | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
    )

    if [[ ${#pkgs[@]} -eq 0 ]]; then
        log "No unneeded packages found. Nothing to do."
        return 0
    fi

    log "Removing ${#pkgs[@]} unneeded package(s): ${pkgs[*]}"
    run_cmd zypper remove --clean-deps -- "${pkgs[@]}"
}

update_zypper() {
    log_section "Zypper (openSUSE/SLES)"
    run_cmd zypper ref -f
    run_cmd zypper dup -y --no-recommends
    zypper_autoremove
}

update_pacman() {
    log_section "Pacman (Arch/Manjaro)"
    run_cmd pacman -Syu --noconfirm
    # Remove orphaned packages
    ORPHANS=$(pacman -Qdtq 2>/dev/null || true)
    if [[ -n "$ORPHANS" ]]; then
        log "Removing orphaned packages..."
        echo "$ORPHANS" | xargs -r pacman -Rns --noconfirm >> "$LOG_FILE" 2>&1 || true
    fi
}

update_aur() {
    # AUR helpers must not run as root; find the invoking user or first human user
    local AUR_USER
    AUR_USER=$(logname 2>/dev/null || getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')

    if [[ -z "$AUR_USER" ]]; then
        log "WARNING: Could not determine unprivileged user for AUR helper. Skipping AUR update."
        return
    fi

    if has_cmd yay; then
        log_section "AUR via yay (user: ${AUR_USER})"
        run_cmd sudo -u "$AUR_USER" yay -Syu --noconfirm --aur
    elif has_cmd paru; then
        log_section "AUR via paru (user: ${AUR_USER})"
        run_cmd sudo -u "$AUR_USER" paru -Syu --noconfirm --aur
    fi
}

update_apk() {
    log_section "APK (Alpine)"
    run_cmd apk update
    run_cmd apk upgrade
}

update_xbps() {
    log_section "XBPS (Void Linux)"
    run_cmd xbps-install -Syu
}

update_emerge() {
    log_section "Portage/Emerge (Gentoo)"
    run_cmd emerge --sync
    run_cmd emerge -uDU --keep-going --with-bdeps=y @world
    run_cmd emerge --depclean
    run_cmd revdep-rebuild || true
}

update_nix() {
    log_section "Nix"
    if has_cmd nixos-rebuild; then
        run_cmd nix-channel --update
        run_cmd nixos-rebuild switch
    else
        # Standalone nix install (non-NixOS)
        local NIX_USER
        NIX_USER=$(logname 2>/dev/null || getent passwd | awk -F: '$3>=1000 && $3<65534 {print $1; exit}')
        if [[ -n "$NIX_USER" ]]; then
            run_cmd sudo -u "$NIX_USER" nix-channel --update
            run_cmd sudo -u "$NIX_USER" nix-env -u '*'
        fi
    fi
}

update_snap() {
    log_section "Snap"
    run_cmd snap refresh
}

update_flatpak() {
    log_section "Flatpak"
    # Update system-wide installs (as root)
    run_cmd flatpak update --system -y --noninteractive
    # Also update any user installs for all human users
    while IFS=: read -r username _ uid _ _ homedir shell; do
        [[ "$uid" -lt 1000 || "$uid" -ge 65534 ]] && continue
        [[ "$shell" == */nologin || "$shell" == */false ]] && continue
        if sudo -u "$username" flatpak list --user &>/dev/null 2>&1; then
            log "Updating Flatpak user installs for: ${username}"
            run_cmd sudo -u "$username" flatpak update --user -y --noninteractive
        fi
    done < /etc/passwd
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
require_root

log_section "System Update Started: ${TIMESTAMP}"
log "Hostname: $(hostname)"
log "OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || uname -s)"
log "Kernel: $(uname -r)"

# Native package managers (only one should normally be present, but we check all)
has_cmd apt      && update_apt
has_cmd dnf      && update_dnf
has_cmd yum      && ! has_cmd dnf && update_yum   # skip yum if dnf is present
has_cmd zypper   && update_zypper
has_cmd pacman   && update_pacman
has_cmd pacman   && update_aur    # attempt AUR after pacman
has_cmd apk      && update_apk
has_cmd xbps-install && update_xbps
has_cmd emerge   && update_emerge
has_cmd nix-env  && update_nix

# Universal package systems
has_cmd snap     && update_snap
has_cmd flatpak  && update_flatpak

# -----------------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------------
log_section "Update Complete"
if [[ $ERRORS -gt 0 ]]; then
    log "Finished with ${ERRORS} error(s). Review ${LOG_FILE} for details."
    exit 1
else
    log "All updates completed successfully."
    exit 0
fi
