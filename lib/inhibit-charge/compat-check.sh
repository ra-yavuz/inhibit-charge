#!/usr/bin/env bash
# compat-check.sh: shared hardware/kernel compatibility check for
# inhibit-charge. Source this file and call `check_compat` to get a 0/1
# answer plus stderr explaining what is missing on a failure.
#
# Used by:
#   - scripts/get.sh   (refuses install on incompatible hardware)
#   - debian/postinst  (warns but does not fail)
#   - lib/inhibit-charge/inhibit-charged (final runtime gate)
#
# We intentionally avoid `set -e` here so callers control failure mode.

# Minimum kernel version that exposes charge_behaviour. Older kernels do
# not have the sysfs interface even on supported hardware.
COMPAT_MIN_KERNEL_MAJOR=5
COMPAT_MIN_KERNEL_MINOR=17

# Print a wrapped notice to stderr. Avoid em dashes per project style.
_compat_say() { printf 'inhibit-charge compat: %s\n' "$*" >&2; }

# Return 0 if running kernel >= MIN, 1 otherwise.
_compat_kernel_ok() {
    local rel major minor
    rel=$(uname -r 2>/dev/null || echo "0.0")
    major=${rel%%.*}
    minor=${rel#*.}
    minor=${minor%%.*}
    case "$major$minor" in
        ''|*[!0-9]*)
            _compat_say "could not parse kernel version from 'uname -r' ($rel); proceeding"
            return 0
            ;;
    esac
    if [ "$major" -gt "$COMPAT_MIN_KERNEL_MAJOR" ]; then return 0; fi
    if [ "$major" -eq "$COMPAT_MIN_KERNEL_MAJOR" ] && [ "$minor" -ge "$COMPAT_MIN_KERNEL_MINOR" ]; then
        return 0
    fi
    _compat_say "kernel $rel is older than ${COMPAT_MIN_KERNEL_MAJOR}.${COMPAT_MIN_KERNEL_MINOR}; charge_behaviour sysfs is not available"
    return 1
}

# Find the first battery sysfs directory. Echos the path on success.
_compat_find_battery() {
    local d type
    for d in /sys/class/power_supply/*; do
        [ -r "$d/type" ] || continue
        type=$(cat "$d/type" 2>/dev/null || echo "")
        if [ "$type" = "Battery" ]; then
            echo "$d"
            return 0
        fi
    done
    return 1
}

# check_compat: 0 if this host can run inhibit-charge, 1 otherwise.
# Prints a human-readable explanation to stderr on failure.
check_compat() {
    local bat behaviour
    if ! _compat_kernel_ok; then
        return 1
    fi

    bat=$(_compat_find_battery) || {
        _compat_say "no battery found under /sys/class/power_supply (desktop or VM?)"
        return 1
    }

    if [ ! -r "$bat/charge_behaviour" ]; then
        _compat_say "$bat/charge_behaviour not present; this hardware/driver does not expose the inhibit-charge interface"
        _compat_say "supported drivers: thinkpad_acpi, cros_ec, framework_laptop, system76_acpi, asus_wmi"
        _compat_say "if you only need start/end thresholds, use TLP instead"
        return 1
    fi

    behaviour=$(cat "$bat/charge_behaviour" 2>/dev/null || echo "")
    if ! printf '%s' "$behaviour" | grep -q 'inhibit-charge'; then
        _compat_say "$bat/charge_behaviour does not list 'inhibit-charge' (got: $behaviour)"
        _compat_say "your driver supports charge_behaviour but not the specific mode this tool needs"
        return 1
    fi

    return 0
}
