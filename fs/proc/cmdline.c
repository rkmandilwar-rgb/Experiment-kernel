// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/string.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <asm/setup.h>

#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
#include <linux/susfs_def.h>
/* returns 0 when a fake cmdline was emitted */
extern int susfs_spoof_cmdline_or_bootconfig(struct seq_file *m);
#endif

#if defined(CONFIG_PROC_CMDLINE_APPEND_ANDROID_FORCE_NORMAL_BOOT) || \
    defined(CONFIG_INITRAMFS_IGNORE_SKIP_FLAG)
/*
 * Bootloaders of this generation pass "skip_initramfs" for every normal boot,
 * including the ones where userspace has to run two-stage init out of the
 * ramdisk.  Android 10+ decides between normal boot and recovery from
 * androidboot.force_normal_boot, which such bootloaders never send, and the
 * string Magisk and friends look for is "want_initramfs".
 *
 * Keep the real cmdline untouched (early_param has already run) and only fix
 * up the copy that userspace reads back through /proc/cmdline.
 */
#define INITRAMFS_STR_FIND	"skip_initramf"
#define INITRAMFS_STR_REPLACE	"want_initramf"
#define INITRAMFS_STR_LEN	(sizeof(INITRAMFS_STR_FIND) - 1)
#define FORCE_NORMAL_BOOT_STR	" androidboot.force_normal_boot=1"

static char proc_command_line[COMMAND_LINE_SIZE];

static void __init proc_command_line_init(void)
{
	size_t len;

	len = strlcpy(proc_command_line, saved_command_line,
		      sizeof(proc_command_line));
	if (len >= sizeof(proc_command_line))
		len = sizeof(proc_command_line) - 1;

#ifdef CONFIG_INITRAMFS_IGNORE_SKIP_FLAG
	{
		char *p = strstr(proc_command_line, INITRAMFS_STR_FIND);

		if (p)
			memcpy(p, INITRAMFS_STR_REPLACE, INITRAMFS_STR_LEN);
	}
#endif

#ifdef CONFIG_PROC_CMDLINE_APPEND_ANDROID_FORCE_NORMAL_BOOT
	if (strstr(saved_command_line, INITRAMFS_STR_FIND) &&
	    len + sizeof(FORCE_NORMAL_BOOT_STR) <= sizeof(proc_command_line))
		memcpy(proc_command_line + len, FORCE_NORMAL_BOOT_STR,
		       sizeof(FORCE_NORMAL_BOOT_STR));
#endif
}
#endif /* CONFIG_PROC_CMDLINE_APPEND_ANDROID_FORCE_NORMAL_BOOT ||
	  CONFIG_INITRAMFS_IGNORE_SKIP_FLAG */

static int cmdline_proc_show(struct seq_file *m, void *v)
{
#ifdef CONFIG_KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG
	if (!susfs_spoof_cmdline_or_bootconfig(m)) {
		seq_putc(m, '\n');
		return 0;
	}
#endif
#if defined(CONFIG_PROC_CMDLINE_APPEND_ANDROID_FORCE_NORMAL_BOOT) || \
    defined(CONFIG_INITRAMFS_IGNORE_SKIP_FLAG)
	seq_printf(m, "%s\n", proc_command_line);
#else
	seq_printf(m, "%s\n", saved_command_line);
#endif
	return 0;
}

static int cmdline_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, cmdline_proc_show, NULL);
}

static const struct file_operations cmdline_proc_fops = {
	.open		= cmdline_proc_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init proc_cmdline_init(void)
{
#if defined(CONFIG_PROC_CMDLINE_APPEND_ANDROID_FORCE_NORMAL_BOOT) || \
    defined(CONFIG_INITRAMFS_IGNORE_SKIP_FLAG)
	proc_command_line_init();
#endif
	proc_create("cmdline", 0, NULL, &cmdline_proc_fops);
	return 0;
}
fs_initcall(proc_cmdline_init);
