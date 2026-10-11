#!/system/bin/sh
# Stormbreaker — balanced performance tuning for 4 GB RAM
# Runs once at boot via init.d / Magisk post-fs-data

# ── VM: lower swappiness so apps stay in RAM longer ──
echo 60 > /proc/sys/vm/swappiness

# ── VM: reduce dirty page ratio for smoother writes ──
echo 20 > /proc/sys/vm/dirty_ratio
echo 5  > /proc/sys/vm/dirty_background_ratio
echo 3000 > /proc/sys/vm/dirty_expire_centisecs
echo 500  > /proc/sys/vm/dirty_writeback_centisecs

# ── VM: keep more free RAM as emergency reserve ──
echo 20480 > /proc/sys/vm/extra_free_kbytes

# ── VM: faster reclaim of file-backed pages ──
echo 50 > /proc/sys/vm/vfs_cache_pressure

# ── VM: compaction proactiveness for THP ──
echo 20 > /proc/sys/vm/compaction_proactiveness

# ── ZRAM: LZ4 compression, 50% of RAM as swap ──
for z in /dev/block/zram0 /dev/zram0; do
  if [ -e "$z" ]; then
    echo 4 > /sys/block/zram0/max_comp_streams 2>/dev/null
    echo lz4 > /sys/block/zram0/comp_algorithm 2>/dev/null
  fi
done

# ── KSM: scan every 200 ms, max 2 pages per scan ──
echo 200 > /sys/kernel/mm/ksm/sleep_millisecs 2>/dev/null
echo 2   > /sys/kernel/mm/ksm/pages_to_scan 2>/dev/null
echo 1   > /sys/kernel/mm/ksm/run 2>/dev/null

# ── BFQ: lower read-ahead for faster random I/O ──
echo 128 > /sys/block/sda/queue/read_ahead_kb 2>/dev/null

# ── Network: buffer tuning for BBR ──
echo 4096 87380 6291456 > /proc/sys/net/ipv4/tcp_rmem
echo 4096 65536 6291456 > /proc/sys/net/ipv4/tcp_wmem
echo 262144            > /proc/sys/net/core/wmem_max
echo 262144            > /proc/sys/net/core/rmem_max
echo 1                 > /proc/sys/net/ipv4/tcp_ecn
echo 1                 > /proc/sys/net/ipv4/tcp_sack
echo 1                 > /proc/sys/net/ipv4/tcp_dsack
echo 1                 > /proc/sys/net/ipv4/tcp_timestamps

# ── Scheduler: upmigrate/downmigrate thresholds for EAS ──
# Keeps small tasks on little cores longer → saves battery
for cpu_dir in /proc/sys/kernel/sched_*; do
  echo 85 > /proc/sys/kernel/sched_upmigrate 2>/dev/null
  echo 65 > /proc/sys/kernel/sched_downmigrate 2>/dev/null
done

# ── Scheduler: reduce sched latency for UI responsiveness ──
echo 10000000  > /proc/sys/kernel/sched_latency_ns 2>/dev/null
echo 4000000   > /proc/sys/kernel/sched_min_granularity_ns 2>/dev/null
echo 2000000   > /proc/sys/kernel/sched_wakeup_granularity_ns 2>/dev/null

# ── Input boost: short burst to mid freq on touch ──
# (Qualcomm WALT specific paths)
echo 0:1401600 4:1401600 7:1401600 > /sys/module/cpu_boost/parameters/input_boost_freq 2>/dev/null
echo 40 > /sys/module/cpu_boost/parameters/input_boost_ms 2>/dev/null

# ── Core control: keep 2 big cores online minimum ──
echo 1 > /sys/devices/system/cpu/cpu4/core_ctl/enabled 2>/dev/null
echo 1 > /sys/devices/system/cpu/cpu7/core_ctl/enabled 2>/dev/null

# ── GPU: set governor to msm-adreno-tz ──
echo msm-adreno-tz > /sys/class/kgsl/kgsl-3d0/devfreq/governor 2>/dev/null

# ── I/O: set BFQ scheduler ──
echo bfq > /sys/block/sda/queue/scheduler 2>/dev/null

# Done
exit 0