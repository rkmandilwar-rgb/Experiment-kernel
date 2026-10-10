#!/bin/bash
# SPDX-License-Identifier: GPL-2.0-only
#
# merge-defconfig.sh - merge a vendor defconfig with kernel/configs/miatoll
#                      config fragments to produce the final .config used
#                      by the build.
#
# Usage:
#   ARCH=arm64 scripts/merge-defconfig.sh \
#       arch/arm64/configs/vendor/xiaomi/miatoll_defconfig
#
# The result is written to .config (or $KCONFIG_CONFIG if set).
# For each symbol that appears in BOTH the defconfig AND one of the
# fragments, the fragment wins.  Symbols that only appear in one file
# or the other are kept as-is.
#
# The script deliberately does NOT use scripts/kconfig/merge_config.sh
# from mainline because that script does not understand how to "replace"
# a value already set in the base; it only appends to the end of an
# already-loaded config, and for tristate symbols its '=y' vs '#is not
# set' resolution can silently flip things the defconfig already locked
# down.

set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SRC"

base="${1:?Usage: $0 <defconfig>}"
[ -f "$base" ] || { echo "FATAL: $base not found" >&2; exit 1; }

frags=(
    kernel/configs/miatoll/ebpf.config
    kernel/configs/miatoll/ntfs.config
    kernel/configs/miatoll/erofs.config
    kernel/configs/miatoll/bbr.config
    kernel/configs/miatoll/droidspaces.config
    kernel/configs/miatoll/nethunter.config
)

out="${KCONFIG_CONFIG:-.config}"

echo "merge-defconfig.sh"
echo "  base  : $base"
echo "  frags : ${frags[*]}"
echo "  out   : $out"

# 1)  Copy the vendor defconfig verbatim as the starting .config.
cp "$base" "$out"

# 2)  For every CONFIG_FOO=<value> line in each fragment, overwrite
#     the same symbol in $out.  If the symbol was not in $base at all,
#     it is appended.  If a fragment says "# CONFIG_FOO is not set",
#     it replaces a CONFIG_FOO=y or CONFIG_FOO=m in $out.
for f in "${frags[@]}"; do
    [ -f "$f" ] || { echo "SKIP $f (not found)"; continue; }
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            '#'*' is not set')
                # "not-set" directive: # CONFIG_FOO is not set
                sym=$(echo "$line" | sed 's/^[[:space:]]*# CONFIG_\(.*\) is not set.*/\1/')
                sed -i "s|^CONFIG_${sym}=.*|# CONFIG_${sym} is not set|" "$out"
                if ! grep -q "CONFIG_${sym}" "$out"; then
                    echo "$line" >> "$out"
                fi
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
                ;;
            '#'*|[[:space:]]*)  ;;
        esac
    done <"$f"
done

echo "merge-defconfig.sh: done ($out)"