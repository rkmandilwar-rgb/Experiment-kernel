#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# check-config-fragments.sh - verify that the fragments in
# kernel/configs/miatoll actually take effect.
#
# This is the guard against "silent no-op" config lines: a fragment can ask
# for CONFIG_FOO=y while Kconfig quietly drops it because a dependency is
# unmet (different symbol name, unmet "depends on", select-only symbol, ...).
# The kernel then builds fine and simply lacks the feature.
#
# Two checks per fragment line, against a generated .config:
#
#   NOT-SET  a line says "=y"/"=m" but the generated .config does not have
#            that value  -> the feature is missing (hard failure)
#   OVERRID  a line says "# CONFIG_FOO is not set" but the generated .config
#            has FOO=y/m       -> something else selects it (hard failure)
#   MISSING  the symbol is not declared by any Kconfig in this tree
#            -> typo, or the option does not exist in this kernel (failure)
#
# Usage:
#   scripts/check-config-fragments.sh [config]        # default: out/.config
#   scripts/check-config-fragments.sh out/.config
#
# Without a generated config it still performs the MISSING symbol check.

set -euo pipefail

ARCH="${ARCH:-arm64}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

config="${1:-}"
if [ -z "$config" ] && [ -f out/.config ]; then
	config="out/.config"
fi

frags=(kernel/configs/miatoll/*.config)
[ ${#frags[@]} -gt 0 ] || { echo "no fragments found" >&2; exit 1; }

if [ -n "$config" ]; then
	[ -f "$config" ] || { echo "FATAL: $config does not exist" >&2; exit 1; }
	echo "Checking ${#frags[@]} fragment(s) against $config"
else
	echo "Checking ${#frags[@]} fragment(s) - no generated config, symbol existence only"
fi
echo

missing=0
problems=0
checked=0

# Look up the effective value of a symbol in the generated config.
effective() {
	local sym="$1" line
	line=$(grep -m1 -E "^${sym}=|^# ${sym} is not set$" "$config" 2>/dev/null || true)
	if [ -z "$line" ]; then
		echo "ABSENT"
	elif [ "$line" = "# ${sym} is not set" ]; then
		echo "n"
	else
		echo "${line#*=}"
	fi
}

symbol_declared() {
	local sym="$1"
	grep -rhqE "^[[:space:]]*(menu)?config[[:space:]]+${sym}([[:space:]]|$)" \
		--include=Kconfig --include='Kconfig*' . 2>/dev/null
}

for f in "${frags[@]}"; do
	while IFS= read -r line || [ -n "$line" ]; do
		[ -z "$line" ] && continue
		case "$line" in
			'CONFIG_'*'='*)
				sym="${line%%=*}"
				val="${line#*=}"
				;;
			'# CONFIG_'*' is not set')
				sym="${line#\# }"
				sym="${sym%% is not set*}"
				val="n"
				;;
			*) continue ;;
		esac
		checked=$((checked + 1))

		# 1. does any Kconfig declare it?
		if ! symbol_declared "${sym#CONFIG_}"; then
			echo "MISSING   ${sym}  (from $f; not declared by any Kconfig)"
			missing=$((missing + 1))
			continue
		fi

		[ -n "$config" ] || continue

		# 2. is the requested value what the generated config has?
		cur=$(effective "$sym")
		if [ "$val" = "n" ]; then
			case "$cur" in
				y|m)
					echo "OVERRID   ${sym}  (from $f: fragment asks for 'not set', config has '=$cur')"
					problems=$((problems + 1))
					;;
			esac
		else
			if [ "$cur" != "$val" ]; then
				echo "NOT-SET   ${sym}=${val}  (from $f: effective value is '$cur')"
				problems=$((problems + 1))
			fi
		fi
	done <"$f"
done

echo
echo "checked $checked options, $missing missing symbol(s), $problems ineffective option(s)"
[ $((missing + problems)) -eq 0 ]
