// SPDX-License-Identifier: GPL-2.0
#include <linux/types.h>
#include <linux/fs.h>
#include <linux/sched.h>
#include <linux/security.h>
#include <linux/string.h>
#include <linux/cred.h>
#include <linux/version.h>

#include "objsec.h"
#include "security.h"
#include "klog.h"
#include "selinux.h"
#include "ksu.h"

static u32 susfs_zygote_sid = 0;
static u32 susfs_ksu_sid = 0;
static u32 susfs_init_sid = 0;

static inline u32 get_current_sid(void) {
    struct task_security_struct *tsec;
    const struct cred *cred = current_cred();
    if (!cred) return 0;
    tsec = selinux_cred(cred);
    if (!tsec) return 0;
    return tsec->sid;
}

static inline void set_susfs_sid(const char *secctx_name, u32 *out_sid) {
    u32 sid = 0;
    if (!*out_sid) {
        if (!security_secctx_to_secid(secctx_name, strlen(secctx_name), &sid)) {
            *out_sid = sid;
        }
    }
}

u32 susfs_get_sid_from_name(const char *secctx_name) {
    u32 sid = 0;
    if (!security_secctx_to_secid(secctx_name, strlen(secctx_name), &sid)) {
        return sid;
    }
    return 0;
}

u32 susfs_get_current_sid(void) {
    return get_current_sid();
}

void susfs_set_zygote_sid(void) {
    set_susfs_sid("u:r:zygote:s0", &susfs_zygote_sid);
}

bool susfs_is_current_zygote_domain(void) {
    return unlikely(get_current_sid() == susfs_zygote_sid && susfs_zygote_sid != 0);
}

void susfs_set_ksu_sid(void) {
    set_susfs_sid("u:r:su:s0", &susfs_ksu_sid);
}

bool susfs_is_current_ksu_domain(void) {
    return unlikely(get_current_sid() == susfs_ksu_sid && susfs_ksu_sid != 0);
}

void susfs_set_init_sid(void) {
    set_susfs_sid("u:r:init:s0", &susfs_init_sid);
}

bool susfs_is_current_init_domain(void) {
    return unlikely(get_current_sid() == susfs_init_sid && susfs_init_sid != 0);
}

/* Manual Hooks required by kernel 5.4 SUSFS patch */
int ksu_handle_execveat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) { return 0; }
int ksu_handle_execveat_sucompat(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) { return 0; }
int ksu_handle_faccessat(int *dfd, const char __user **filename_user, int *mode, int *flags) { return 0; }
int ksu_handle_stat(int *dfd, const char __user **filename_user, int *flags) { return 0; }
int ksu_handle_sys_read(unsigned int fd, char __user **buf, size_t *count) { return 0; }
int ksu_vfs_read_hook(struct file *file, char __user **buf, size_t *count, loff_t **pos) { return 0; }
int ksu_execveat_hook(int *fd, struct filename **filename_ptr, void *argv, void *envp, int *flags) { return 0; }
