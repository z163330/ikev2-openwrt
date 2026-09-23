#!/bin/sh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Nikitid
# Modified: Support OpenWrt / ImmortalWrt / iStoreOS
set -eu
[ -n "${IPKG_INSTROOT:-}" ] && exit 0
fail() {
	printf 'IKEv2 Manager for OpenWrt: %s\n' "$*" >&2
	exit 1
}
[ -r /etc/openwrt_release ] || fail 'OpenWrt‑based firmware is required'
. /etc/openwrt_release

# ========= 修改：支持 OpenWrt / ImmortalWrt / iStoreOS =========
case "${DISTRIB_ID:-unknown}" in
OpenWrt|ImmortalWrt|iStoreOS)
    echo "✅ Detected firmware: ${DISTRIB_ID} ${DISTRIB_RELEASE:-}"
;;
*)
    fail "Unsupported firmware vendor: ${DISTRIB_ID:-unknown}; require OpenWrt / ImmortalWrt / iStoreOS"
;;
esac

# ========= 修改：自动探测包管理器，不再依赖版本号字符串 =========
package_manager=""
if command -v opkg >/dev/null 2>&1; then
    package_manager="opkg"
elif command -v apk >/dev/null 2>&1; then
    package_manager="apk"
else
    fail "neither opkg nor apk found, cannot continue"
fi

for command in "$package_manager" uci ubus fw4; do
	command -v "$command" >/dev/null 2>&1 ||
		fail "required base command is missing: $command"
done

feed_file_matches() {
	pattern="$1"
	shift
	for file in "$@"; do
		[ -r "$file" ] || continue
		grep -qE "$pattern" "$file" && return 0
	done
	return 1
}

# ========= 注释原版官方OpenWrt源校验，第三方分支不适用 =========
#case "$package_manager:${DISTRIB_RELEASE:-}" in
#	opkg:24.10.*)
#		feed_file_matches 'downloads\.openwrt\.org/releases/24\.10\.' \
#			/etc/opkg/distfeeds.conf ||
#			fail 'official OpenWrt 24.10 release package feeds are required'
#		;;
#	apk:25.12.*)
#		feed_file_matches \
#			'downloads\.openwrt\.org/releases/(25\.12\.|packages‑25\.12)' \
#			/etc/apk/repositories /etc/apk/repositories.d/* ||
#			fail 'official OpenWrt 25.12 release package feeds are required'
#		;;
#	*)
#		fail "unsupported package manager $package_manager for OpenWrt ${DISTRIB_RELEASE:-unknown}"
#		;;
#esac

free_kib=""
# 优先读取overlay
if mountpoint -q /overlay; then
    free_kib="$(df -Pk /overlay 2>/dev/null | awk 'NR == 2 { print $4 }')"
fi
# overlay不存在或者拿不到数值，读根分区 /
if [ -z "${free_kib}" ]; then
    free_kib="$(df -Pk / 2>/dev/null | awk 'NR == 2 { print $4 }')"
fi
# 只保留数字，非数字置0
case "${free_kib:-0}" in
    ''|*[!0-9]*) free_kib=0 ;;
esac
[ "$free_kib" -ge 1024 ] ||
	fail "insufficient persistent storage to install the bootstrap package (${free_kib} KiB free)"
exit 0
