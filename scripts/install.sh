#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nikitid
# Modified: Add support for ImmortalWrt / iStoreOS
set -eu
die() {
	printf 'ERROR: %s\n' "$*" >&2
	exit 1
}
[ -r /etc/openwrt_release ] || die 'This installer must run on OpenWrt‑based firmware'
. /etc/openwrt_release

# Allow OpenWrt / ImmortalWrt / iStoreOS
case "${DISTRIB_ID:-unknown}" in
OpenWrt|ImmortalWrt|iStoreOS)
    echo "✅ Detected firmware: ${DISTRIB_ID} ${DISTRIB_RELEASE:-}"
;;
*)
    die "Unsupported firmware vendor: ${DISTRIB_ID:-unknown}; require OpenWrt / ImmortalWrt / iStoreOS"
;;
esac

# Auto‑detect package manager(opkg/apk), no longer rely on release version string
package_manager=""
if command -v opkg >/dev/null 2>&1; then
    package_manager="opkg"
elif command -v apk >/dev/null 2>&1; then
    package_manager="apk"
else
    die "neither opkg nor apk found, cannot continue"
fi

command -v "$package_manager" >/dev/null 2>&1 ||
	die "required package manager is missing: $package_manager"

[ "$#" -eq 1 ] || die "Usage: $0 /tmp/luci-app-ikev2-manager_*.ipk|*.apk"
package="$1"
[ -s "$package" ] || die "Package not found: $package"

case "$package_manager:$package" in
	opkg:*.ipk | apk:*.apk) ;;
	opkg:*) die 'opkg environment requires an .ipk package' ;;
	apk:*) die 'apk environment requires an .apk package' ;;
esac

pkg_update() {
	case "$package_manager" in
		opkg) run_bounded 45 opkg update ;;
		apk) run_bounded 45 apk update ;;
		*) return 1 ;;
	esac
}

run_bounded() {
	seconds="$1"
	shift
	command_pid=''
	watchdog_pid=''
	sleeper_pid=''
	rc=0
	"$@" &
	command_pid=$!
	(
		trap '[ -z "$sleeper_pid" ] || kill "$sleeper_pid" 2>/dev/null; exit 0' TERM INT
		sleep "$seconds" &
		sleeper_pid=$!
		wait "$sleeper_pid" 2>/dev/null || exit 0
		kill_tree "$command_pid" TERM
		sleep 1
		kill -0 "$command_pid" 2>/dev/null && kill_tree "$command_pid" KILL
	) >/dev/null 2>&1 &
	watchdog_pid=$!
	wait "$command_pid" 2>/dev/null || rc=$?
	kill "$watchdog_pid" 2>/dev/null || :
	wait "$watchdog_pid" 2>/dev/null || :
	return "$rc"
}

kill_tree() {
	local target signal child
	target="$1"
	signal="${2:-TERM}"
	case "$target" in '' | *[!0-9]*) return 0 ;; esac
	if [ -r "/proc/$target/task/$target/children" ]; then
		for child in $(cat "/proc/$target/task/$target/children" 2>/dev/null); do
			kill_tree "$child" "$signal"
		done
	fi
	kill "-$signal" "$target" 2>/dev/null || :
}

pkg_install_plan() {
	case "$package_manager" in
		opkg) opkg install --noaction "$1" ;;
		apk) apk add --simulate "$1" ;;
		*) return 1 ;;
	esac
}

pkg_install() {
	case "$package_manager" in
		opkg) opkg install "$1" ;;
		apk) apk add "$1" ;;
		*) return 1 ;;
	esac
}

backup="/tmp/ikev2-manager-install-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
sysupgrade -b "$backup"
printf 'Configuration backup: %s\n' "$backup"

pkg_update
if ! pkg_install_plan "$package"; then
	die 'Package preflight failed; no packages were changed'
fi
pkg_install "$package" || die "Package installation failed; restore configuration from $backup if needed"

/usr/libexec/ikev2-manager-system _install-deps-run

cat <<'EOF'
Installation complete. No VPN tunnel, PBR policy or firewall rule was enabled.
Open LuCI -> Services -> IKEv2 Manager -> Overview.
EOF
