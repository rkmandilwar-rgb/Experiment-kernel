// SPDX-License-Identifier: GPL-2.0-only
/*
 * Copyright (C) 2026 \xx
 *
 * This file is a downstream extension and NOT affiliated, endorsed by,
 * or maintained by the official KernelSU developers.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 2 as
 * published by the Free Software Foundation.
 *
 */

// sys_newfstat rp
// upstream: https://github.com/tiann/KernelSU/commit/df640917d11dd0eff1b34ea53ec3c0dc49667002

static int sys_newfstat_handler_pre(struct kretprobe_instance *p, struct pt_regs *regs)
{
	struct pt_regs *real_regs = PT_REAL_REGS(regs);

	// grab ptr on entry
	uintptr_t *arg = (uintptr_t *)p->data;
	arg[0] = (uintptr_t)PT_REGS_SYSCALL_PARM1(real_regs); 
	arg[1] = (uintptr_t)PT_REGS_PARM2(real_regs); 

	return 0;
}

static int sys_newfstat_handler_post(struct kretprobe_instance *p, struct pt_regs *regs)
{
	uintptr_t *arg = (uintptr_t *)p->data;
	unsigned int fd = (unsigned int)arg[0];
	struct stat __user *statbuf = (struct stat __user *)arg[1];

	ksu_handle_newfstat_ret(&fd, &statbuf);

	return 0;
}

static struct kretprobe sys_newfstat_rp = {
	.kp.symbol_name = SYS_NEWFSTAT_SYMBOL,
	.entry_handler = sys_newfstat_handler_pre,
	.handler = sys_newfstat_handler_post,
	.data_size = sizeof(uintptr_t) * 2, // int + ptr, should fit
};

#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
static int sys_fstat64_handler_pre(struct kretprobe_instance *p, struct pt_regs *regs)
{
	struct pt_regs *real_regs = PT_REAL_REGS(regs);

	// grab ptr on entry
	uintptr_t *arg = (uintptr_t *)p->data;
	arg[0] = (uintptr_t)PT_REGS_SYSCALL_PARM1(real_regs); 
	arg[1] = (uintptr_t)PT_REGS_PARM2(real_regs); 

	return 0;
}

static int sys_fstat64_handler_post(struct kretprobe_instance *p, struct pt_regs *regs)
{
	uintptr_t *arg = (uintptr_t *)p->data;
	unsigned long fd = (unsigned long)arg[0];
	struct stat64 __user *statbuf = (struct stat64 __user *)arg[1];

	ksu_handle_fstat64_ret(&fd, &statbuf);

	return 0;
}

static struct kretprobe sys_fstat64_rp = {
	.kp.symbol_name = SYS_FSTAT64_SYMBOL,
	.entry_handler = sys_fstat64_handler_pre,
	.handler = sys_fstat64_handler_post,
	.data_size = sizeof(uintptr_t) * 2, // long + ptr, should fit
};
#endif

// sys_reboot
static int sys_reboot_handler_pre(struct kprobe *p, struct pt_regs *regs)
{
	struct pt_regs *real_regs = PT_REAL_REGS(regs);
	int *magic1 = (int *)&PT_REGS_SYSCALL_PARM1(real_regs); // ptr so we can mutate this
	int magic2 = (int)PT_REGS_PARM2(real_regs);
	int cmd = (int)PT_REGS_PARM3(real_regs);
	void __user **arg = (void __user **)&PT_REGS_SYSCALL_PARM4(real_regs);

	if (*magic1 != KSU_INSTALL_MAGIC1)
		return 0;

	// HACK: flip preempt status inside kp
	// checking not really needed but its cool
	bool got_flipped = false;
	if (likely(!preemptible())) {
		preempt_enable();
		got_flipped = true;
	}

	ksu_handle_sys_reboot(*magic1, magic2, cmd, arg);

	if (got_flipped)
		preempt_disable();

	// to prevent double hooking
	*magic1 = 0;

	return 0;
}

static struct kprobe sys_reboot_kp = {
	.symbol_name = REBOOT_SYMBOL,
	.pre_handler = sys_reboot_handler_pre,
};

// sys_prctl — SUSFS binary uses prctl(KERNEL_SU_OPTION, CMD, data, NULL, &error)
#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs.h>
#include <linux/susfs_def.h>

#ifndef PRCTL_SYMBOL
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 19, 0)
#define PRCTL_SYMBOL "__arm64_sys_prctl"
#else
#define PRCTL_SYMBOL "sys_prctl"
#endif
#endif

static int sys_prctl_handler_pre(struct kprobe *p, struct pt_regs *regs)
{
	struct pt_regs *real_regs = PT_REAL_REGS(regs);
	int option = (int)PT_REGS_SYSCALL_PARM1(real_regs);
	unsigned long arg2 = (unsigned long)PT_REGS_PARM2(real_regs);
	unsigned long arg3 = (unsigned long)PT_REGS_PARM3(real_regs);
	unsigned long arg5 = (unsigned long)PT_REGS_PARM5(real_regs);
	int error = 0;

	if (option != KSU_INSTALL_MAGIC1)
		return 0;

	if (current_uid().val != 0)
		return 0;

	// arg3 = data pointer, arg5 = &error (where to write result)
	// We wrap arg3 into a local variable so SUSFS funcs can deref it
	// as void **user_info (where *user_info = arg3)
	void __user *data_ptr = (void __user *)arg3;
	void __user **wrapped = &data_ptr;

	bool got_flipped = false;
	if (likely(!preemptible())) {
		preempt_enable();
		got_flipped = true;
	}

	// SUSFS info commands — handle inline like upstream
	if (arg2 == CMD_SUSFS_SHOW_VERSION) {
		int len_of_susfs_version = strlen(SUSFS_VERSION);
		if (!access_ok(VERIFY_WRITE, (void __user *)arg3, len_of_susfs_version + 1)) {
			pr_err("susfs: CMD_SUSFS_SHOW_VERSION -> arg3 not accessible\n");
			goto out;
		}
		error = copy_to_user((void __user *)arg3, SUSFS_VERSION, len_of_susfs_version + 1);
		if (arg5)
			copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}

	if (arg2 == CMD_SUSFS_SHOW_VARIANT) {
		int len = strlen(SUSFS_VARIANT);
		if (!access_ok(VERIFY_WRITE, (void __user *)arg3, len + 1)) {
			pr_err("susfs: CMD_SUSFS_SHOW_VARIANT -> arg3 not accessible\n");
			goto out;
		}
		error = copy_to_user((void __user *)arg3, SUSFS_VARIANT, len + 1);
		if (arg5)
			copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}

	// Commands that use SUSFS wrapper functions (void **user_info)
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
	if (arg2 == CMD_SUSFS_ADD_SUS_PATH) {
		susfs_add_sus_path(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
	if (arg2 == CMD_SUSFS_ADD_SUS_PATH_LOOP) {
		susfs_add_sus_path_loop(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
	if (arg2 == CMD_SUSFS_HIDE_SUS_MNTS_FOR_NON_SU_PROCS) {
		susfs_set_hide_sus_mnts_for_non_su_procs(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
	if (arg2 == CMD_SUSFS_ADD_SUS_KSTAT) {
		susfs_add_sus_kstat(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
	if (arg2 == CMD_SUSFS_UPDATE_SUS_KSTAT) {
		susfs_update_sus_kstat(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
	if (arg2 == CMD_SUSFS_ADD_SUS_KSTAT_STATICALLY) {
		susfs_add_sus_kstat(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
	if (arg2 == CMD_SUSFS_ADD_TRY_UMOUNT) {
		susfs_add_try_umount(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	if (arg2 == CMD_SUSFS_SET_UNAME) {
		susfs_set_uname(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
	if (arg2 == CMD_SUSFS_ENABLE_LOG) {
		susfs_enable_log(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (arg2 == CMD_SUSFS_SET_CMDLINE_OR_BOOTCONFIG) {
		susfs_set_cmdline_or_bootconfig(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
	if (arg2 == CMD_SUSFS_ADD_OPEN_REDIRECT) {
		susfs_add_open_redirect(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
	if (arg2 == CMD_SUSFS_ADD_SUS_MAP) {
		susfs_add_sus_map(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
#endif
	if (arg2 == CMD_SUSFS_ENABLE_AVC_LOG_SPOOFING) {
		susfs_set_avc_log_spoofing(wrapped);
		if (arg5) copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}
	if (arg2 == CMD_SUSFS_SHOW_ENABLED_FEATURES) {
		unsigned long features = 0;
		int bit = 0;
#ifdef CONFIG_KSU_SUSFS_SUS_PATH
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_MOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_SUS_KSU_DEFAULT_MOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_SUS_BIND_MOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_KSTAT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_OVERLAYFS
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_TRY_UMOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_AUTO_ADD_TRY_UMOUNT_FOR_BIND_MOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_ENABLE_LOG
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_OPEN_REDIRECT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_SU
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_HAS_MAGIC_MOUNT
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_MEMFD
		features |= (1 << bit);
#endif
		bit++;
#ifdef CONFIG_KSU_SUSFS_SUS_MAP
		features |= (1 << bit);
#endif
		if (arg3)
			copy_to_user((void __user *)arg3, &features, sizeof(features));
		if (arg5)
			copy_to_user((void __user *)arg5, &error, sizeof(error));
		goto out;
	}

out:
	if (got_flipped)
		preempt_disable();
	return 0;
}

static struct kprobe sys_prctl_kp = {
	.symbol_name = PRCTL_SYMBOL,
	.pre_handler = sys_prctl_handler_pre,
};
#endif /* CONFIG_KSU_SUSFS */

static int unregister_kprobe_function(void *data)
{
	set_user_nice(current, 19); // low prio

loop_start:

	msleep(1000);

	if (*(volatile bool *)&ksu_vfs_read_hook)
		goto loop_start;

	pr_info("kp_ksud: unregistering kprobes...\n");

	unregister_kretprobe(&sys_newfstat_rp);
	pr_info("kp_ksud: unregister sys_newfstat_rp!\n");

#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
	unregister_kretprobe(&sys_fstat64_rp);
	pr_info("kp_ksud: unregister sys_fstat64_rp!\n");
#endif

	return 0;
}

static __init int kp_ksud_init()
{
	int ret = register_kprobe(&sys_reboot_kp); // dont unreg this one
	pr_info("kp_ksud: sys_reboot_kp: %d\n", ret);

#ifdef CONFIG_KSU_SUSFS
	int ret_prctl = register_kprobe(&sys_prctl_kp);
	pr_info("kp_ksud: sys_prctl_kp (SUSFS): %d\n", ret_prctl);
#endif

	int ret2 = register_kretprobe(&sys_newfstat_rp);
	pr_info("kp_ksud: sys_newfstat_rp: %d\n", ret2);

#if defined(__ARCH_WANT_STAT64) || defined(__ARCH_WANT_COMPAT_STAT64)
	int ret3 = register_kretprobe(&sys_fstat64_rp);
	pr_info("kp_ksud: sys_fstat64_rp: %d\n", ret3);
#endif

	kthread_run(unregister_kprobe_function, NULL, "kp_unreg");
	return 0;
}
