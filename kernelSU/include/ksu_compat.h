/* SPDX-License-Identifier: GPL-2.0-only */
/*
 * Compatibility shims so KernelSU-Next compiles on the non-GKI 4.14 tree
 * (miatoll). Every shim is only active below the kernel version that
 * introduced the newer API, so newer kernels keep using the native symbol.
 */
#ifndef __KSU_COMPAT_H
#define __KSU_COMPAT_H

#include <linux/version.h>
#include <linux/uaccess.h>
#include <linux/sched.h>

/*
 * task_work_add(): 4.14 takes a bool "notify" flag, where true means what
 * TWA_RESUME means on 5.11+ (run the work on return to user space).
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 11, 0)
#define TWA_RESUME true
#endif

/*
 * copy_{from,to}_user_nofault(): added in 5.8. Same contract: 0 on success,
 * -EFAULT on a fault, and no sleeping (page faults are disabled).
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 8, 0)
static inline long ksu_copy_from_user_nofault(void *dst,
                                              const void __user *src,
                                              size_t size)
{
    unsigned long left;

    pagefault_disable();
    left = __copy_from_user_inatomic(dst, src, size);
    pagefault_enable();
    return left ? -EFAULT : 0;
}

static inline long ksu_copy_to_user_nofault(void __user *dst, const void *src,
                                            size_t size)
{
    unsigned long left;

    pagefault_disable();
    left = __copy_to_user_inatomic(dst, src, size);
    pagefault_enable();
    return left ? -EFAULT : 0;
}

#define copy_from_user_nofault ksu_copy_from_user_nofault
#define copy_to_user_nofault ksu_copy_to_user_nofault
#endif

/*
 * ksys_unshare(): not present in this 4.14 tree (verified), the syscall
 * implementation is sys_unshare() there.
 */
#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 0, 0)
#define ksys_unshare(flags) sys_unshare(flags)
#endif

#endif /* __KSU_COMPAT_H */
