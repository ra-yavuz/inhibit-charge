#!/usr/bin/env bash
# One-shot installer that adds the ra-yavuz apt repository, then installs
# inhibit-charge from it. Idempotent: re-running it is safe.
#
# Run with sudo. The recommended invocation is:
#
#   curl -fsSL https://raw.githubusercontent.com/ra-yavuz/inhibit-charge/main/scripts/get.sh \
#     | sudo bash
#
# Or, if you want to read it first (recommended for any 'curl | bash'):
#
#   curl -fsSL https://raw.githubusercontent.com/ra-yavuz/inhibit-charge/main/scripts/get.sh -o get.sh
#   less get.sh
#   sudo bash get.sh
#
# After install, run 'sudo inhibit-charge motd' to enable the optional
# login-greeting line, and 'inhibit-charge status' to inspect state.
#
# DISCLAIMER: This software writes to your laptop's battery management
# interface. It is provided AS IS, WITHOUT WARRANTY OF ANY KIND. The
# author is not liable for damage caused by events outside their
# control (supply-chain compromise, downstream modifications, etc).

set -euo pipefail

REPO_HOST=ra-yavuz.github.io/apt
KEY_URL="https://${REPO_HOST}/pubkey.gpg"
KEYRING=/etc/apt/keyrings/ra-yavuz.gpg
SOURCES_LIST=/etc/apt/sources.list.d/ra-yavuz.list
SOURCE_LINE="deb [arch=amd64,arm64 signed-by=${KEYRING}] https://${REPO_HOST} stable main"
PKG=inhibit-charge

log()  { printf '[get.sh] %s\n' "$*"; }
fail() { printf '[get.sh] ERROR: %s\n' "$*" >&2; exit 1; }

[ "$(id -u)" -eq 0 ] || fail "must be run as root: sudo bash $0 (or pipe through 'sudo bash')"

# Sanity-check the host has a Debian-derived apt + curl available.
command -v apt-get >/dev/null 2>&1 || fail "apt-get not found; this script targets Debian/Ubuntu and derivatives."
command -v curl >/dev/null 2>&1 || {
    log "curl not found; installing it"
    DEBIAN_FRONTEND=noninteractive apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y curl
}
command -v gpg >/dev/null 2>&1 || {
    log "gnupg not found; installing it"
    DEBIAN_FRONTEND=noninteractive apt-get install -y gnupg
}

# 1. Trust the signing key. We always (re)write the keyring file so a
# rotated key picks up on re-runs without manual cleanup.
log "fetching signing key from $KEY_URL"
install -m 0755 -d /etc/apt/keyrings
TMP_KEY=$(mktemp)
trap 'rm -f "$TMP_KEY"' EXIT
curl -fsSL "$KEY_URL" -o "$TMP_KEY"
# Validate the file is a real PGP keyring before installing it.
if ! gpg --no-default-keyring --keyring "$TMP_KEY" --list-keys >/dev/null 2>&1; then
    fail "fetched file is not a valid GPG keyring; aborting."
fi
install -m 0644 "$TMP_KEY" "$KEYRING"
log "installed keyring at $KEYRING"

# 2. Add the apt source. Re-run is safe; we replace the file.
log "adding apt source at $SOURCES_LIST"
echo "$SOURCE_LINE" > "$SOURCES_LIST"
chmod 0644 "$SOURCES_LIST"

# 3. Update and install. --only-upgrade is wrong if the package is not
# present yet, so we just use 'install'; apt is a no-op when already at
# the latest version.
log "running apt update"
DEBIAN_FRONTEND=noninteractive apt-get update
log "installing $PKG"
DEBIAN_FRONTEND=noninteractive apt-get install -y "$PKG"

# 4. Add the invoking user (if any) to the inhibit-charge group so the
# CLI works without sudo. Note that the .deb postinst already does this
# for the user named 'root' in some configurations; here we add the real
# invoking user (SUDO_USER) when present.
TARGET_USER=${SUDO_USER:-}
if [ -n "$TARGET_USER" ] && [ "$TARGET_USER" != "root" ]; then
    if id -nG "$TARGET_USER" 2>/dev/null | grep -qw inhibit-charge; then
        log "$TARGET_USER is already in the inhibit-charge group"
    else
        log "adding $TARGET_USER to the inhibit-charge group"
        usermod -aG inhibit-charge "$TARGET_USER"
        FRESH_SHELL_NEEDED=1
    fi
fi

# 5. Friendly summary at the very end so it does not scroll off-screen.
echo
echo "================================================================"
echo "  inhibit-charge installed. Quick reference:"
echo "================================================================"
echo
echo "  inhibit-charge status            (current battery state, no sudo)"
echo "  inhibit-charge home [TARGET]     (park at TARGET%, default 60)"
echo "  inhibit-charge travel            (charge fully to 100%)"
echo "  sudo inhibit-charge motd         (toggle login-greeting line)"
echo
echo "  Future upgrades: sudo apt upgrade"
echo "  Full removal:    sudo apt purge inhibit-charge"
echo

if [ "${FRESH_SHELL_NEEDED:-0}" = "1" ]; then
    cat <<EOF
================================================================
  ACTION NEEDED before you can use 'inhibit-charge' as $TARGET_USER
================================================================

  Linux freezes a user's group list at login, so a new terminal tab
  in the SAME login session inherits the old group list and will NOT
  pick up the new 'inhibit-charge' group. You need a fresh shell
  session. Pick one:

      newgrp inhibit-charge   (works in this terminal, no logout needed)
      log out of your desktop / SSH session and log back in
      reboot

  After that, try:    inhibit-charge status

EOF
fi
