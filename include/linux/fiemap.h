/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Shim: include/linux/fiemap.h was split out of fs.h in 5.6.
 * On 4.14 the fiemap_extent_info struct and helpers live in <linux/fs.h>
 * directly; this header just re-includes fs.h so backported drivers that
 * #include <linux/fiemap.h> compile without modification.
 */
#ifndef _LINUX_FIEMAP_H_BACKPORT
#define _LINUX_FIEMAP_H_BACKPORT

#include <linux/fs.h>

#endif /* _LINUX_FIEMAP_H_BACKPORT */