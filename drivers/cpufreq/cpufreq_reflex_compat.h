/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Reflex CPUFreq governor: the only kernel-version differences.
 * cpufreq_reflex.c is byte-identical across versions; this file is not.
 *
 * Linux 4.14 (qcom WALT tree): no Energy Model (governor falls back to the
 * cube law), no cpufreq_driver_adjust_perf() (the freq path is used), and
 * arch_scale_cpu_capacity() takes (sd, cpu).
 */
#ifndef _CPUFREQ_REFLEX_COMPAT_H
#define _CPUFREQ_REFLEX_COMPAT_H

/* 4.14: arch_scale_cpu_capacity(struct sched_domain *sd, int cpu) */
#undef arch_scale_cpu_capacity
#define arch_scale_cpu_capacity(cpu) topology_get_cpu_scale(NULL, (cpu))

/*
 * 4.14 has no <linux/sched/util.h> helpers.  Keep exactly one DVFS
 * headroom: map_util_perf() boosts the utilization, map_util_freq() is a
 * plain linear map (as in 6.x, where rfx_floor_util() is its exact
 * inverse).  For the same underlying utilization this yields the same
 * frequency request as this tree's schedutil: (ref + ref/4) * util / max.
 */
static inline unsigned long map_util_perf(unsigned long util)
{
	return min(util + (util >> 2), (unsigned long)SCHED_CAPACITY_SCALE);
}

static inline unsigned long map_util_freq(unsigned long util,
					  unsigned long freq,
					  unsigned long max)
{
	if (!max)
		return 0;
	return (unsigned long)div64_u64((u64)util * freq, max);
}

/*
 * 4.14 has no cpufreq_driver_adjust_perf(): route the perf path through
 * the frequency path.  Reflex only selects rfx_update_single_perf() when
 * cpufreq_driver_has_adjust_perf() is true, so this is a safety net for
 * the one direct call site.
 */
static inline unsigned int rfx_adjust_perf(struct cpufreq_policy *policy,
					   unsigned long min_perf,
					   unsigned long target_perf,
					   unsigned long max_perf,
					   unsigned long capacity)
{
	unsigned int freq;

	freq = map_util_freq(target_perf, policy->cpuinfo.max_freq, capacity);

	if (policy->fast_switch_enabled)
		return cpufreq_driver_fast_switch(policy, freq);

	return __cpufreq_driver_target(policy, freq, CPUFREQ_RELATION_L);
}

/* 4.14 has neither of these driver flags. */
#define cpufreq_driver_test_flags(flags)	(false)
#define cpufreq_driver_has_adjust_perf()	(false)

#endif /* _CPUFREQ_REFLEX_COMPAT_H */
