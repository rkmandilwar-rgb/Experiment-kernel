#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# merge-defconfig.sh — merge vendor defconfig with kernel/configs/miatoll
# config fragments.
#
# Usage:
#   scripts/merge-defconfig.sh                           # uses .config
#   scripts/merge-defconfig.sh out/.config               # uses out/.config
#
# Assumes a base .config already exists (from `make defconfig` or similar).
# For every CONFIG_FOO=<value> line in each fragment, the fragment value
# overwrites whatever was in the base .config.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

out="${1:-.config}"
[ -f "$out" ] || { echo "FATAL: $out does not exist. Run defconfig first." >&2; exit 1; }

frags=(
    kernel/configs/miatoll/ebpf.config
    kernel/configs/miatoll/ntfs.config
    kernel/configs/miatoll/erofs.config
    kernel/configs/miatoll/bbr.config
    kernel/configs/miatoll/droidspaces.config
    kernel/configs/miatoll/nethunter.config
    # 4 GB stability/tuning policy — merged LAST so it is the final word
    # on memory/tuning symbols even if a feature fragment drifts.
    kernel/configs/miatoll/tuning.config
)

echo "merge-defconfig.sh"
echo "  config: $out"
echo "  frags : ${#frags[@]} fragment(s)"

count=0
for f in "${frags[@]}"; do
    [ -f "$f" ] || { echo "SKIP $f (not found)"; continue; }
    # "|| [ -n \"$line\" ]" keeps the last line when the fragment has no
    # trailing newline (otherwise that option would be silently dropped).
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            '#'*' is not set')
                sym=$(echo "$line" | sed 's/^[[:space:]]*# CONFIG_\(.*\) is not set.*/\1/')
                sed -i "s|^CONFIG_${sym}=.*|# CONFIG_${sym} is not set|" "$out"
                if ! grep -q "CONFIG_${sym}" "$out"; then
                    echo "$line" >> "$out"
                fi
                count=$((count + 1))
                ;;
            'CONFIG_'*'='*)
                sym=$(echo "$line" | cut -d= -f1)
                val=$(echo "$line" | cut -d= -f2-)
                if grep -q "^${sym}=" "$out"; then
                    sed -i "s|^${sym}=.*|${sym}=${val}|" "$out"
                elif grep -q "# ${sym} is not set" "$out"; then
                    sed -i "s|# ${sym} is not set|${sym}=${val}|" "$out"
                else
                    echo "$line" >> "$out"
                fi
                count=$((count + 1))
                ;;
            '#'*|[[:space:]]*) ;;
        esac
    done <"$f"
done

echo "  applied $count option overrides"
echo "merge-defconfig.sh: done ($out)"