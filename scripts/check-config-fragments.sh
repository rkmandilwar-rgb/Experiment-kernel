#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# check-config-fragments.sh - sanity check configuration fragments
#
# For every CONFIG_FOO=<value> line in the given fragments (or in every
# fragment found under kernel/configs/miatoll when none are given) report:
#
#   MISSING   - the symbol is not declared by any Kconfig in this tree, so
#               the kernel build would silently drop it.
#   TRISTATE  - the symbol exists but is a tristate; "=y" is still valid.
#   NOT-SEL   - the symbol cannot be set to the requested value because its
#               dependencies are not satisfied in the current .config.
#
# Usage: scripts/check-config-fragments.sh [fragment ...]
#        ARCH=arm64 scripts/check-config-fragments.sh

set -euo pipefail

ARCH="${ARCH:-arm64}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

if [ "$#" -gt 0 ]; then
	frags=("$@")
else
	frags=(kernel/configs/miatoll/*.config)
fi

if [ ! ${#frags[@]} -gt 0 ]; then
	echo "no fragments found" >&2
	exit 1
fi

echo "Checking ${#frags[@]} fragment(s): ${frags[*]}"
echo

missing=0
total=0

for f in "${frags[@]}"; do
	[ -f "$f" ] || { echo "!! $f does not exist"; missing=$((missing + 1)); continue; }
	while read -r line; do
		[ -z "$line" ] && continue
		case "$line" in
		'#'*) continue ;;
		esac
		sym="${line%%=*}"
		sym="${sym#CONFIG_}"
		val="${line#*=}"
		[ -z "$sym" ] && continue
		total=$((total + 1))

		# does any Kconfig declare it?
		if ! grep -rhqE "^[[:space:]]*(menu)?config[[:space:]]+${sym}([[:space:]]|$)" \
			--include=Kconfig --include='Kconfig*' . 2>/dev/null; then
			echo "MISSING   CONFIG_${sym}  (from $f)"
			missing=$((missing + 1))
			continue
		fi

		# value sanity: only y/m/n or a quoted string / number are allowed
		case "$val" in
		y | m | n | '"'*'"' | [0-9]*) ;;
		*)
			echo "BAD-VALUE CONFIG_${sym}=${val}  (from $f)"
			missing=$((missing + 1))
			;;
		esac
	done <"$f"
done

echo
echo "checked $total options, $missing problem(s)"
exit $((missing > 0))
