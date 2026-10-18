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
#
# The core performance/memory policy is NOT a fragment: it is compiled
# straight into arch/arm64/configs/vendor/xiaomi/miatoll_defconfig (see the
# "In-kernel performance tuning" note at the end of that file).  What is
# merged here are the feature and tuning packs, in this order — later
# fragments win, so compiler/bt/wifi/haptics always have the last word
# (and kernelsu.config, merged last, pins the KernelSU Next hook mode).

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
    kernel/configs/miatoll/compiler.config
    kernel/configs/miatoll/thermal.config
    kernel/configs/miatoll/scheduler.config
    kernel/configs/miatoll/touch.config
    kernel/configs/miatoll/audio.config
    kernel/configs/miatoll/haptics-sound.config
    kernel/configs/miatoll/bluetooth.config
    kernel/configs/miatoll/wifi.config
    kernel/configs/miatoll/kernelsu.config
)

echo "merge-defconfig.sh"
echo "  config: $out"
echo "  frags : ${#frags[@]} fragment(s)"

count=0
for f in "${frags[@]}"; do
    [ -f "$f" ] || { echo "SKIP $f (not found)"; continue; }
    # "|| [ -n "$line" ]" keeps the last line when the fragment has no
    # trailing newline (otherwise that option would be silently dropped).
    while IFS= read -r line || [ -n "$line" ]; do
        [ -z "$line" ] && continue
        case "$line" in
            '#'*' is not set')
                sym=$(echo "$line" | sed 's/^[[:space:]]*# CONFIG_\(.*\) is not set.*/\1/')
                sed -i "s|^CONFIG_${sym}=.*|# CONFIG_${sym} is not set|" "$out"
                # Only append when the symbol is not mentioned at all yet -
                # an anchored match, so "CONFIG_FOO" is not considered
                # present just because "CONFIG_FOOBAR" exists.
                if ! grep -qE "^# ${sym} is not set\$" "$out"; then
                    echo "$line" >> "$out"
                fi
                count=$((count + 1))
                ;;
            'CONFIG_'*'='*)
                sym=$(echo "$line" | cut -d= -f1)
                val=$(echo "$line" | cut -d= -f2-)
                if grep -qE "^${sym}=" "$out"; then
                    sed -i "s|^${sym}=.*|${sym}=${val}|" "$out"
                elif grep -qE "^# ${sym} is not set\$" "$out"; then
                    sed -i "s|^# ${sym} is not set\$|${sym}=${val}|" "$out"
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
