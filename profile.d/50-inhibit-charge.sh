# shellcheck shell=sh
# Show inhibit-charge battery state at the top of every new interactive
# shell. Disabled by default; enable with:
#   inhibit-charge motd on
#
# Sourced by /etc/profile (for login shells) and by /etc/bash.bashrc (for
# interactive non-login shells, on Debian/Ubuntu). The early guards
# below make sure we only print once per shell, only in interactive
# shells, and only when the user has explicitly enabled the greeting.
#
# This file is intentionally NOT executable: profile.d snippets are
# sourced, not exec'd. The toggle is a flag file, not a chmod.

# Run only in interactive shells.
case $- in
    *i*) ;;
    *)   return 0 ;;
esac

# Run only when the user has enabled the greeting.
[ -f /var/lib/inhibit-charge/motd-enabled ] || return 0

# Don't run twice in nested shells (e.g. opening tmux from an already-greeted shell).
[ -n "${INHIBIT_CHARGE_GREETED:-}" ] && return 0
INHIBIT_CHARGE_GREETED=1
export INHIBIT_CHARGE_GREETED

# Render via the CLI. The motd-render subcommand is read-only on sysfs
# and the state dir, takes a few milliseconds, and is safe in any
# interactive shell. Suppress all errors so a broken render never breaks
# the user's shell.
if command -v inhibit-charge >/dev/null 2>&1; then
    inhibit-charge motd-render 2>/dev/null
fi
