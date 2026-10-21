// SPDX-License-Identifier: GPL-2.0
#include <linux/fs.h>
#include <linux/init.h>
#include <linux/kernel.h>
#include <linux/proc_fs.h>
#include <linux/seq_file.h>
#include <linux/utsname.h>
#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
#include <linux/susfs_def.h>
extern void susfs_spoof_uname(struct new_utsname *tmp);
#endif

static int version_proc_show(struct seq_file *m, void *v)
{
	struct new_utsname tmp;

	down_read(&uts_sem);
	memcpy(&tmp, utsname(), sizeof(tmp));
	up_read(&uts_sem);

#ifdef CONFIG_KSU_SUSFS_SPOOF_UNAME
	/*
	 * /proc/version publishes the same release/version strings as
	 * uname(2), through a path the syscall hook cannot see.  Apply the
	 * substitution to a local copy so both views agree.
	 */
	susfs_spoof_uname(&tmp);
#endif

	seq_printf(m, linux_proc_banner,
		tmp.sysname,
		tmp.release,
		tmp.version);
	return 0;
}

static int version_proc_open(struct inode *inode, struct file *file)
{
	return single_open(file, version_proc_show, NULL);
}

static const struct file_operations version_proc_fops = {
	.open		= version_proc_open,
	.read		= seq_read,
	.llseek		= seq_lseek,
	.release	= single_release,
};

static int __init proc_version_init(void)
{
	proc_create("version", 0, NULL, &version_proc_fops);
	return 0;
}
fs_initcall(proc_version_init);
