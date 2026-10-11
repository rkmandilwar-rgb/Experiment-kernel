/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Shim: include/linux/fiemap.h was split out of fs.h in 5.6.
 * On 4.14 the fiemap_extent_info struct and helpers live in <linux/fs.h>
 * directly; the uapi header has fiemap_extent / fiemap and FIEMAP_* macros.
 * This header re-exports the uapi definitions so backported drivers that
 * #include <linux/fiemap.h> compile without modification.
 */
#ifndef _LINUX_FIEMAP_H_BACKPORT
#define _LINUX_FIEMAP_H_BACKPORT

#include <uapi/linux/fiemap.h>

#endif /* _LINUX_FIEMAP_H_BACKPORT */