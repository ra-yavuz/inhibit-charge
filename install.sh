#!/usr/bin/env bash
# Install inhibit-charge from this source tree.
#
# Use this if you want to install without adding the apt repository to
# your system. For most users the apt repo is easier (apt upgrade works);
# see README.md for the apt instructions.
#
# Run with sudo from the repo root:
#   sudo bash install.sh
#
# Subcommands:
#   install     (default)   install or upgrade in place
#   uninstall               remove files but keep state
#   purge                   remove files AND wipe state and group
#   verify                  print install state, service status, journal
#
# This script is idempotent: re-running 'install' is safe.
#
# DISCLAIMER: This software writes to your laptop's battery management
# interface. It is provided AS IS, WITHOUT WARRANTY OF ANY KIND. The
# author is not liable for any damage to battery, hardware, or data.
# By installing or running this software you accept full responsibility.
# See README.md for the full disclaimer.

set -euo pipefail

PREFIX=${PREFIX:-/usr}
STATE_DIR=/var/lib/inhibit-charge
GROUP=inhibit-charge
SERVICE=inhibit-charged.service
UNIT_DIR=/lib/systemd/system

ROOT=$(cd "$(dirname "$0")" && pwd)

log()  { printf '[install.sh] %s\n' "$*"; }
fail() { printf '[install.sh] ERROR: %s\n' "$*" >&2; exit 1; }

require_root() {
    [ "$(id -u)" -eq 0 ] || fail "must be run as root (use: sudo bash $0)"
}

# Sanity: are we in a real source checkout?
require_source_tree() {
    for f in bin/inhibit-charge lib/inhibit-charge/inhibit-charged systemd/inhibit-charged.service; do
        [ -f "$ROOT/$f" ] || fail "expected file '$f' is missing - run from the repo root"
    done
}

ensure_group() {
    if ! getent group "$GROUP" >/dev/null; then
        log "creating system group: $GROUP"
        addgroup --system "$GROUP" 2>/dev/null || groupadd --system "$GROUP"
    fi
}

ensure_state_dir() {
    install -d -o root -g "$GROUP" -m 0775 "$STATE_DIR"
    [ -e "$STATE_DIR/mode" ]   || echo home > "$STATE_DIR/mode"
    [ -e "$STATE_DIR/target" ] || echo 60   > "$STATE_DIR/target"
    chown root:"$GROUP" "$STATE_DIR/mode" "$STATE_DIR/target"
    chmod 0664 "$STATE_DIR/mode" "$STATE_DIR/target"
}

install_files() {
    install -d "$PREFIX/bin" "$PREFIX/lib/inhibit-charge" "$UNIT_DIR" "$PREFIX/share/doc/inhibit-charge"
    install -m 0755 "$ROOT/bin/inhibit-charge"                     "$PREFIX/bin/inhibit-charge"
    install -m 0755 "$ROOT/lib/inhibit-charge/inhibit-charged"     "$PREFIX/lib/inhibit-charge/inhibit-charged"
    install -m 0644 "$ROOT/systemd/inhibit-charged.service"        "$UNIT_DIR/$SERVICE"
    if [ -f "$ROOT/README.md" ]; then install -m 0644 "$ROOT/README.md" "$PREFIX/share/doc/inhibit-charge/README.md"; fi
    if [ -f "$ROOT/LICENSE"   ]; then install -m 0644 "$ROOT/LICENSE"   "$PREFIX/share/doc/inhibit-charge/copyright"; fi
}

remove_files() {
    rm -f "$PREFIX/bin/inhibit-charge"
    rm -f "$PREFIX/lib/inhibit-charge/inhibit-charged"
    rmdir --ignore-fail-on-non-empty "$PREFIX/lib/inhibit-charge" 2>/dev/null || true
    rm -f "$UNIT_DIR/$SERVICE"
    rm -f "$PREFIX/share/doc/inhibit-charge/README.md"
    rm -f "$PREFIX/share/doc/inhibit-charge/copyright"
    rmdir --ignore-fail-on-non-empty "$PREFIX/share/doc/inhibit-charge" 2>/dev/null || true
}

# Kill any inhibit-charged or older "power-daemon" processes that aren't
# managed by systemd anymore. Belt-and-suspenders against orphaned bash
# loops that systemctl stop won't reach.
kill_orphan_daemons() {
    for pat in 'lib/inhibit-charge/inhibit-charged' 'power-management/bin/power-daemon'; do
        # shellcheck disable=SC2009
        pids=$(pgrep -f "$pat" 2>/dev/null || true)
        [ -z "$pids" ] && continue
        log "killing orphan process(es) matching '$pat': $pids"
        # shellcheck disable=SC2086
        kill $pids 2>/dev/null || true
        sleep 1
        # shellcheck disable=SC2086
        kill -9 $pids 2>/dev/null || true
    done
}

systemd_enable_start() {
    [ -d /run/systemd/system ] || { log "systemd not active, skipping enable+start"; return; }
    systemctl daemon-reload || true
    systemctl enable "$SERVICE" 2>/dev/null || true
    if systemctl is-active --quiet "$SERVICE"; then
        log "service running, restarting to pick up new files"
        systemctl restart "$SERVICE" || true
    else
        log "starting $SERVICE"
        systemctl start "$SERVICE" || true
    fi
}

systemd_stop_disable() {
    [ -d /run/systemd/system ] || return
    systemctl stop    "$SERVICE" 2>/dev/null || true
    systemctl disable "$SERVICE" 2>/dev/null || true
    systemctl daemon-reload || true
}

add_invoking_user_to_group() {
    local target_user=${SUDO_USER:-}
    [ -n "$target_user" ] || return 0
    [ "$target_user" = "root" ] && return 0
    if id -nG "$target_user" 2>/dev/null | grep -qw "$GROUP"; then
        log "$target_user is already in the $GROUP group"
    else
        log "adding $target_user to the $GROUP group"
        usermod -aG "$GROUP" "$target_user"
        # Defer the user-facing "you need a fresh shell" notice to the
        # very end of the install run, so it isn't scrolled off-screen
        # by the verify block. cmd_install reads this flag.
        FRESH_SHELL_NEEDED=1
        FRESH_SHELL_USER=$target_user
    fi
}

print_post_install_notice() {
    [ "${FRESH_SHELL_NEEDED:-0}" = "1" ] || return 0
    cat <<EOF

============================================================================
  ACTION NEEDED before you can use the 'inhibit-charge' command as $FRESH_SHELL_USER
============================================================================

  Linux freezes a user's group list at login, so a new terminal tab or
  window in the SAME login session inherits the old group list and
  will NOT pick up the new 'inhibit-charge' group. You need a fresh
  shell session. Pick one:

      newgrp $GROUP    (works in this terminal, no logout needed)
      log out of your desktop / SSH session and log back in
      reboot

  After that, try:    inhibit-charge status

============================================================================
EOF
}

verify() {
    echo
    echo "===== inhibit-charge install state ====="
    for p in "$PREFIX/bin/inhibit-charge" "$PREFIX/lib/inhibit-charge/inhibit-charged" "$UNIT_DIR/$SERVICE"; do
        if [ -e "$p" ]; then
            printf "  present  %s\n" "$p"
        else
            printf "  MISSING  %s\n" "$p"
        fi
    done
    echo
    echo "===== state ====="
    if [ -d "$STATE_DIR" ]; then
        ls -la "$STATE_DIR"
        echo "  mode:   $(cat "$STATE_DIR/mode" 2>/dev/null || echo '?')"
        echo "  target: $(cat "$STATE_DIR/target" 2>/dev/null || echo '?')"
    else
        echo "  (state dir not present)"
    fi
    echo
    echo "===== service ====="
    systemctl status "$SERVICE" --no-pager -l 2>&1 | head -10 || true
    echo
    echo "===== recent journal ====="
    journalctl -u "$SERVICE" -n 15 --no-pager 2>&1 | tail -15 || true
    echo
    echo "===== sysfs snapshot ====="
    if command -v inhibit-charge >/dev/null 2>&1; then
        inhibit-charge status 2>&1 || true
    else
        echo "  (inhibit-charge not in PATH)"
    fi
}

cmd_install() {
    require_root
    require_source_tree
    log "installing inhibit-charge from $ROOT"
    kill_orphan_daemons
    ensure_group
    ensure_state_dir
    install_files
    add_invoking_user_to_group
    systemd_enable_start
    sleep 1
    verify
    log "install complete"
    print_post_install_notice
}

cmd_uninstall() {
    require_root
    log "uninstalling inhibit-charge (state preserved)"
    systemd_stop_disable
    remove_files
    kill_orphan_daemons
    log "uninstall complete (run '$0 purge' to also wipe state and group)"
}

cmd_purge() {
    require_root
    log "purging inhibit-charge"
    systemd_stop_disable
    remove_files
    kill_orphan_daemons
    rm -rf "$STATE_DIR"
    if getent group "$GROUP" >/dev/null; then
        log "removing group: $GROUP"
        delgroup --system "$GROUP" 2>/dev/null || groupdel "$GROUP" 2>/dev/null || true
    fi
    log "purge complete"
}

sub=${1:-install}
case "$sub" in
    install)   cmd_install ;;
    uninstall) cmd_uninstall ;;
    purge)     cmd_purge ;;
    verify)    verify ;;
    -h|--help|help)
        cat <<EOF
Usage: sudo bash $0 [install|uninstall|purge|verify]

  install    (default)  install or upgrade from this source tree
  uninstall             remove files but keep state in $STATE_DIR
  purge                 remove files AND wipe state and the $GROUP group
  verify                print install state and service status

Most users should prefer the apt repository (see README.md) so that
'apt upgrade' picks up future versions automatically. Use this script
when you need to install without adding a third-party apt source.
EOF
        ;;
    *)
        fail "unknown subcommand: $sub (try '$0 help')"
        ;;
esac
