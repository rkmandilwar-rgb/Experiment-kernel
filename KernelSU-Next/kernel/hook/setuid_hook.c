#include <linux/compiler.h>
#include <linux/version.h>
#if LINUX_VERSION_CODE >= KERNEL_VERSION(4, 11, 0)
#include <linux/sched/signal.h>
#endif
#include <linux/slab.h>
#include <linux/task_work.h>
#include <linux/thread_info.h>
#include <linux/seccomp.h>
#include <linux/printk.h>
#include <linux/sched.h>
#include <linux/string.h>
#include <linux/types.h>
#include <linux/uaccess.h>
#include <linux/uidgid.h>

#include "policy/app_profile.h"
#include "policy/allowlist.h"
#include "policy/app_profile.h"
#include "hook/setuid_hook.h"
#include "klog.h" // IWYU pragma: keep
#include "manager/manager_identity.h"
#include "infra/seccomp_cache.h"
#include "supercall/supercall.h"
#include "hook/hook_manager.h"
#include "feature/kernel_umount.h"
#include "compat/kernel_compat.h"
#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs.h>
#include <linux/susfs_def.h>
#include <linux/workqueue.h>
#include "selinux/selinux.h"

extern u32 susfs_zygote_sid;
extern bool susfs_is_sid_equal(const struct cred *cred, u32 sid2);
extern struct work_struct susfs_extra_works;

static inline void ksu_handle_extra_susfs_work(void)
{
    if (work_pending(&susfs_extra_works))
        return;
    schedule_work(&susfs_extra_works);
}

/*
 * The SUSFS branch has to perform the same per-process set-up as the plain
 * branch below: without the tracepoint flag (and the seccomp relaxation on
 * 5.10+) a manager or an allowlisted app spawned by zygote would keep
 * without a working supercall channel.
 */
static void ksu_prepare_traced_process(void)
{
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
    if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter)
        ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);
#else
    disable_seccomp();
#endif

#ifdef KSU_KPROBES_HOOK
    ksu_set_task_tracepoint_flag(current);
#endif
}

/*
 * SUSFS-aware spawn policy (v2.3.0): zygote is the only uid-0 spawner we
 * care about. Apps that must not see su/mounts get marked no_su+umounted
 * and their mounts are torn down before returning to userspace.
 */
static int susfs_handle_zygote_spawn(uid_t old_uid, uid_t ruid)
{
    if (is_isolated_process(ruid)) {
        susfs_set_current_proc_no_su();
        susfs_set_current_proc_umounted();
        goto do_umount;
    }

    // manager app: give it the supercall fd and let seccomp through
    if (unlikely(is_uid_manager(ruid))) {
        ksu_prepare_traced_process();
        pr_info("install fd for manager: %d\n", ruid);
        ksu_install_fd();
        return 0;
    }

    if (likely(is_appuid(ruid) && ksu_uid_should_umount(ruid))) {
        susfs_set_current_proc_no_su();
        susfs_set_current_proc_umounted();
        goto do_umount;
    }

    if (ksu_is_allow_uid_for_current(ruid)) {
        ksu_prepare_traced_process();
        return 0;
    }

    // spawned app keeps its mounts but must never see su
#ifdef KSU_KPROBES_HOOK
    ksu_clear_task_tracepoint_flag_if_needed(current);
#endif
    susfs_set_current_proc_no_su();
    return 0;

do_umount:
    ksu_handle_umount(old_uid, ruid);
    ksu_handle_extra_susfs_work();
    return 0;
}
#endif // CONFIG_KSU_SUSFS

int ksu_handle_setresuid(uid_t old_uid, uid_t new_uid)
{
#ifdef CONFIG_KSU_SUSFS
    // only the uid-0 spawner (zygote) is interesting here
    if (current_uid().val != 0)
        return 0;

    if (susfs_is_sid_equal(current_cred(), susfs_zygote_sid))
        return susfs_handle_zygote_spawn(old_uid, new_uid);

    return 0;
#else
    // we rely on the fact that zygote always call setresuid(3) with same uids

    pr_info("handle_setresuid from %d to %d\n", old_uid, new_uid);

    if (unlikely(is_uid_manager(new_uid))) {

#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter) {
            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);
        }
#else
		disable_seccomp();
#endif

#ifdef KSU_KPROBES_HOOK
        ksu_set_task_tracepoint_flag(current);
#endif

        pr_info("install fd for manager: %d\n", new_uid);
        ksu_install_fd();
        return 0;
    }

    if (ksu_is_allow_uid_for_current(new_uid)) {
#if LINUX_VERSION_CODE >= KERNEL_VERSION(5, 10, 0)
        if (current->seccomp.mode == SECCOMP_MODE_FILTER && current->seccomp.filter) {
            ksu_seccomp_allow_cache(current->seccomp.filter, __NR_reboot);
        }
#else
		disable_seccomp();
#endif

#ifdef KSU_KPROBES_HOOK
		ksu_set_task_tracepoint_flag(current);
#endif
	} else {
#ifdef KSU_KPROBES_HOOK
		ksu_clear_task_tracepoint_flag_if_needed(current);
#endif
    }

    // Handle kernel umount
    ksu_handle_umount(old_uid, new_uid);

    return 0;
#endif // CONFIG_KSU_SUSFS
}

void __init ksu_setuid_hook_init(void)
{
	ksu_kernel_umount_init();
}

void __exit ksu_setuid_hook_exit(void)
{
	pr_info("ksu_core_exit\n");
	ksu_kernel_umount_exit();
}