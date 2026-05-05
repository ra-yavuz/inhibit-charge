#!/usr/bin/env bash
# Build a .deb without debhelper. Used for environments where the full
# Debian build tooling is not available; produces an equivalent binary
# package layout under dist/.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
VERSION=$(sed -nE '1 s/^[^(]*\(([^)]+)\).*/\1/p' "$ROOT/debian/changelog")
[ -n "$VERSION" ] || { echo "could not parse version from debian/changelog" >&2; exit 1; }

PKG_DIR="$ROOT/dist/inhibit-charge_${VERSION}_all"
DEB_OUT="$ROOT/dist/inhibit-charge_${VERSION}_all.deb"

rm -rf "$PKG_DIR" "$DEB_OUT"
mkdir -p "$PKG_DIR/DEBIAN" \
         "$PKG_DIR/usr/bin" \
         "$PKG_DIR/usr/lib/inhibit-charge" \
         "$PKG_DIR/usr/share/doc/inhibit-charge" \
         "$PKG_DIR/lib/systemd/system" \
         "$PKG_DIR/etc/profile.d"

install -m 0755 "$ROOT/bin/inhibit-charge"                       "$PKG_DIR/usr/bin/inhibit-charge"
install -m 0755 "$ROOT/lib/inhibit-charge/inhibit-charged"       "$PKG_DIR/usr/lib/inhibit-charge/inhibit-charged"
install -m 0644 "$ROOT/systemd/inhibit-charged.service"          "$PKG_DIR/lib/systemd/system/inhibit-charged.service"
# Greeting snippet sourced by every interactive shell. The script
# short-circuits unless /var/lib/inhibit-charge/motd-enabled exists,
# so the default install is silent. Toggle with 'inhibit-charge motd'.
install -m 0644 "$ROOT/profile.d/50-inhibit-charge.sh"           "$PKG_DIR/etc/profile.d/50-inhibit-charge.sh"
install -m 0644 "$ROOT/README.md"                                "$PKG_DIR/usr/share/doc/inhibit-charge/README.md"
install -m 0644 "$ROOT/LICENSE"                                  "$PKG_DIR/usr/share/doc/inhibit-charge/copyright"
install -m 0755 "$ROOT/debian/postinst"                          "$PKG_DIR/DEBIAN/postinst"
install -m 0755 "$ROOT/debian/postrm"                            "$PKG_DIR/DEBIAN/postrm"

cat > "$PKG_DIR/DEBIAN/control" <<EOF
Package: inhibit-charge
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: all
Depends: bash (>= 4.0), systemd, udev, coreutils
Maintainer: Ramazan Yavuz <yavuzramazan1994@gmail.com>
Homepage: https://github.com/ra-yavuz/inhibit-charge
Description: park laptop battery at a target charge level
 inhibit-charge holds your laptop battery at a target percentage when on AC,
 using the kernel's charge_behaviour=inhibit-charge mode. Unlike threshold-only
 tools (TLP, GNOME, KDE), the battery does not trickle-cycle: it sits idle
 while AC powers the system, eliminating wear from repeated mini-cycles.
 .
 Two modes are exposed via the inhibit-charge command: home parks the battery
 at a target percentage on AC; travel charges fully to 100%.
 .
 Requires kernel >= 5.17 and hardware that exposes inhibit-charge in
 /sys/class/power_supply/BAT*/charge_behaviour. Tier-1 supported: ThinkPads
 (thinkpad_acpi), Chromebooks (cros_ec). The daemon refuses to start on
 unsupported hardware with a clear error.
 .
 DISCLAIMER: provided AS IS, no warranty. The author is not liable for any
 damage to battery, hardware, or data. By installing you accept full
 responsibility. See /usr/share/doc/inhibit-charge/README.md for full text.
EOF

: > "$PKG_DIR/DEBIAN/conffiles"

dpkg-deb --build --root-owner-group "$PKG_DIR" "$DEB_OUT"
echo
echo "Built: $DEB_OUT"
ls -la "$DEB_OUT"
