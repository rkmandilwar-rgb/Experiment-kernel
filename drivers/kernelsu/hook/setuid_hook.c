#ifdef CONFIG_KSU_SUSFS
#include <linux/susfs_def.h>
extern u32 susfs_zygote_sid;
extern bool susfs_is_sid_equal(const struct cred *cred, u32 sid2);
extern void susfs_try_umount(uid_t uid);
extern void susfs_set_current_proc_umounted(void);
#endif

static __always_inline void ksu_handle_setresuid_cred(struct cred *new, const struct cred *old)
{
	if (!new || !old)
		return;

	uid_t new_uid = ksu_get_uid_t(new->uid);
	uid_t old_uid = ksu_get_uid_t(old->uid);

	// old process is not root, ignore it.
	if (unlikely(!!old_uid))
		return;

	if (IS_ENABLED(CONFIG_KSU_DEBUG))
		pr_info("handle_setresuid from %d to %d\n", old_uid, new_uid);

#ifdef CONFIG_KSU_SUSFS
	// SUSFS: check if current process is zygote domain
	if (susfs_zygote_sid && !susfs_is_sid_equal(current_cred(), susfs_zygote_sid)) {
		// not zygote, skip
	}
#endif

	// we dont have those new fancy things upstream has
	// lets just do the original thing where we disable seccomp
	if (unlikely(is_uid_manager(new_uid)))
		goto install_ksu_fd;

	if (ksu_is_allow_uid_for_current(new_uid))
		goto kill_seccomp;

	// Handle kernel umount
	ksu_handle_umount(new, old);

#ifdef CONFIG_KSU_SUSFS
	// SUSFS: try_umount for non-root processes
	susfs_try_umount(new_uid);
	// SUSFS: mark current process as umounted
	susfs_set_current_proc_umounted();
#endif
	return;

install_ksu_fd:
	pr_info("install fd for manager: %d\n", new_uid);
	ksu_install_fd();

kill_seccomp:
	disable_seccomp();
	set_thread_flag(TIF_KSU_MANAGED); // sucompat fast-path
	return;
}
