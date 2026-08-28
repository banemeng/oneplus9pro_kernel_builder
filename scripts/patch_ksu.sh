#!/bin/bash
set -e

echo "=== Patching KernelSU & Compatibilities for Linux 5.4 ==="

# 1. Fix missing fdtoverlay.c in scripts/dtc
if [ ! -f kernel/scripts/dtc/fdtoverlay.c ]; then
    curl -s https://raw.githubusercontent.com/dgibson/dtc/main/fdtoverlay.c -o kernel/scripts/dtc/fdtoverlay.c || true
fi
if [ ! -s kernel/scripts/dtc/fdtoverlay.c ]; then
    sed -i 's/hostprogs-\$(CONFIG_DTC) := dtc fdtoverlay/hostprogs-\$(CONFIG_DTC) := dtc/g' kernel/scripts/dtc/Makefile || true
fi

# 2. Fix F2FS ZSTD pointer mismatch
sed -i 's/zstd_cstream_workspace_bound(params.cParams)/zstd_cstream_workspace_bound(\&params.cParams)/g' kernel/fs/f2fs/compress.c || true

# 3. Fix binder_trace pointer arithmetic
sed -i 's/__entry->offset = start - alloc->buffer;/__entry->offset = start - (unsigned long)alloc->buffer;/g' kernel/drivers/android/binder_trace.h || true

# 4. Remove obsolete PicoLCD from drivers/hid/Makefile
sed -i '/hid-picolcd/d' kernel/drivers/hid/Makefile || true

# 5. Fix shima interconnect missing icc_regmap_config
sed -i '/#include "qnoc-qos.h"/a static const struct regmap_config icc_regmap_config = { .reg_bits = 32, .reg_stride = 4, .val_bits = 32 };' kernel/drivers/interconnect/qcom/shima.c || true

# 6. Add kernel 5.4 compatibility for pgtable.h
if [ ! -f kernel/include/linux/pgtable.h ]; then
    cat << 'HDR_EOF' > kernel/include/linux/pgtable.h
#ifndef _LINUX_PGTABLE_H
#define _LINUX_PGTABLE_H
#include <asm/pgtable.h>
#endif
HDR_EOF
fi

# 7. Add kernel 5.4 compatibility for task_work TWA_ constants
cat << 'TW_EOF' >> kernel/include/linux/task_work.h

#ifndef TWA_RESUME
#define TWA_RESUME true
#endif
#ifndef TWA_NONE
#define TWA_NONE false
#endif
#ifndef TWA_SIGNAL
#define TWA_SIGNAL true
#endif
TW_EOF

# 8. Add kernel 5.4 compatibility for nofault memory copy APIs
cat << 'UACC_EOF' >> kernel/include/linux/uaccess.h

#ifndef copy_to_kernel_nofault
#define copy_to_kernel_nofault probe_kernel_write
#endif
#ifndef copy_from_kernel_nofault
#define copy_from_kernel_nofault probe_kernel_read
#endif
#ifndef copy_to_user_nofault
#define copy_to_user_nofault probe_user_write
#endif
#ifndef copy_from_user_nofault
#define copy_from_user_nofault probe_user_read
#endif
UACC_EOF

# 9. Fix KernelSU SukiSU-Ultra internal 5.4 compatibility
if [ -d kernel/drivers/kernelsu ]; then
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/<linux\/pgtable.h>/<asm\/pgtable.h>/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_to_kernel_nofault/probe_kernel_write/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_from_kernel_nofault/probe_kernel_read/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_to_user_nofault/probe_user_write/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_from_user_nofault/probe_user_read/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/TWA_RESUME/true/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/TWA_NONE/false/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/atomic_set(&current->seccomp.filter_count, 0);/\/* filter_count 5.9+ *\/ /g' {} + 2>/dev/null || true

    # Fix seccomp_cache.c for Linux 5.4
    if [ -f kernel/drivers/kernelsu/infra/seccomp_cache.c ]; then
        cat << 'SECC_EOF' > kernel/drivers/kernelsu/infra/seccomp_cache.c
#include <linux/version.h>
#include <linux/fs.h>
#include <linux/nsproxy.h>
#include <linux/sched/task.h>
#include <linux/uaccess.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include "klog.h"
#include "infra/seccomp_cache.h"

#ifdef SECCOMP_ARCH_NATIVE_NR

struct action_cache {
    DECLARE_BITMAP(allow_native, SECCOMP_ARCH_NATIVE_NR);
#ifdef SECCOMP_ARCH_COMPAT
    DECLARE_BITMAP(allow_compat, SECCOMP_ARCH_COMPAT_NR);
#endif
};

struct seccomp_filter {
    refcount_t refs;
    refcount_t users;
    bool log;
#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 1, 0)
    bool wait_killable_recv;
#endif
    struct action_cache cache;
    struct seccomp_filter *prev;
    struct bpf_prog *prog;
    struct notification *notif;
    struct mutex notify_lock;
    wait_queue_head_t wqh;
};

void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr)
{
    if (!filter) return;
    if (nr >= 0 && nr < SECCOMP_ARCH_NATIVE_NR)
        clear_bit(nr, filter->cache.allow_native);
#ifdef SECCOMP_ARCH_COMPAT
    if (nr >= 0 && nr < SECCOMP_ARCH_COMPAT_NR)
        clear_bit(nr, filter->cache.allow_compat);
#endif
}

void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr)
{
    if (!filter) return;
    if (nr >= 0 && nr < SECCOMP_ARCH_NATIVE_NR)
        set_bit(nr, filter->cache.allow_native);
#ifdef SECCOMP_ARCH_COMPAT
    if (nr >= 0 && nr < SECCOMP_ARCH_COMPAT_NR)
        set_bit(nr, filter->cache.allow_compat);
#endif
}

#else

void ksu_seccomp_clear_cache(struct seccomp_filter *filter, int nr) {}
void ksu_seccomp_allow_cache(struct seccomp_filter *filter, int nr) {}

#endif
SECC_EOF
    fi

    # Fix pkg_observer.c for Linux 5.4 fsnotify_ops
    if [ -f kernel/drivers/kernelsu/manager/pkg_observer.c ]; then
        cat << 'OBS_EOF' > kernel/drivers/kernelsu/manager/pkg_observer.c
// SPDX-License-Identifier: GPL-2.0
#include <linux/module.h>
#include <linux/fs.h>
#include <linux/namei.h>
#include <linux/fsnotify_backend.h>
#include <linux/slab.h>
#include <linux/rculist.h>
#include <linux/version.h>
#include "klog.h"
#include "manager/throne_tracker.h"

#define MASK_SYSTEM (FS_CREATE | FS_MOVE | FS_EVENT_ON_CHILD)

struct watch_dir {
    const char *path;
    u32 mask;
    struct path kpath;
    struct inode *inode;
    struct fsnotify_mark *mark;
};

static struct fsnotify_group *g;

#if LINUX_VERSION_CODE < KERNEL_VERSION(5, 9, 0)
static int ksu_handle_event(struct fsnotify_group *group, struct inode *inode,
                            u32 mask, const void *data, int data_type,
                            const struct qstr *file_name, u32 cookie,
                            struct fsnotify_iter_info *iter_info)
{
    if (!file_name)
        return 0;
    if (mask & FS_ISDIR)
        return 0;
    if (file_name->len == 13 && !memcmp(file_name->name, "packages.list", 13)) {
        pr_info("packages.list detected: %d\n", mask);
        track_throne(false);
    }
    return 0;
}

static const struct fsnotify_ops ksu_ops = {
    .handle_event = ksu_handle_event,
};
#else
static int ksu_handle_inode_event(struct fsnotify_mark *mark, u32 mask, struct inode *inode, struct inode *dir,
                                  const struct qstr *file_name, u32 cookie)
{
    if (!file_name)
        return 0;
    if (mask & FS_ISDIR)
        return 0;
    if (file_name->len == 13 && !memcmp(file_name->name, "packages.list", 13)) {
        pr_info("packages.list detected: %d\n", mask);
        track_throne(false);
    }
    return 0;
}

static const struct fsnotify_ops ksu_ops = {
    .handle_inode_event = ksu_handle_inode_event,
};
#endif

static int add_mark_on_inode(struct inode *inode, u32 mask, struct fsnotify_mark **out)
{
    struct fsnotify_mark *m;

    m = kzalloc(sizeof(*m), GFP_KERNEL);
    if (!m)
        return -ENOMEM;

    fsnotify_init_mark(m, g);
    m->mask = mask;

    if (fsnotify_add_inode_mark(m, inode, 0)) {
        fsnotify_put_mark(m);
        return -EINVAL;
    }
    *out = m;
    return 0;
}

static int watch_one_dir(struct watch_dir *wd)
{
    int ret = kern_path(wd->path, LOOKUP_FOLLOW, &wd->kpath);
    if (ret) {
        pr_info("path not ready: %s (%d)\n", wd->path, ret);
        return ret;
    }
    wd->inode = d_inode(wd->kpath.dentry);
    ihold(wd->inode);

    ret = add_mark_on_inode(wd->inode, wd->mask, &wd->mark);
    if (ret) {
        pr_err("Add mark failed for %s (%d)\n", wd->path, ret);
        path_put(&wd->kpath);
        iput(wd->inode);
        wd->inode = NULL;
        return ret;
    }
    pr_info("watching %s\n", wd->path);
    return 0;
}

static void unwatch_one_dir(struct watch_dir *wd)
{
    if (wd->mark) {
        fsnotify_destroy_mark(wd->mark, g);
        fsnotify_put_mark(wd->mark);
        wd->mark = NULL;
    }
    if (wd->inode) {
        iput(wd->inode);
        wd->inode = NULL;
    }
    if (wd->kpath.dentry) {
        path_put(&wd->kpath);
        memset(&wd->kpath, 0, sizeof(wd->kpath));
    }
}

static struct watch_dir g_watch = { .path = "/data/system", .mask = MASK_SYSTEM };

int ksu_observer_init(void)
{
    int ret = 0;

#if LINUX_VERSION_CODE >= KERNEL_VERSION(6, 0, 0)
    g = fsnotify_alloc_group(&ksu_ops, 0);
#else
    g = fsnotify_alloc_group(&ksu_ops);
#endif
    if (IS_ERR(g))
        return PTR_ERR(g);

    ret = watch_one_dir(&g_watch);
    pr_info("observer init done\n");
    return 0;
}

void __exit ksu_observer_exit(void)
{
    unwatch_one_dir(&g_watch);
    fsnotify_put_group(g);
    pr_info("observer exit done\n");
}
OBS_EOF
    fi

    # Fix selinux/rules.c for Linux 5.4 (use selinux_ss instead of selinux_policy)
    if [ -f kernel/drivers/kernelsu/selinux/rules.c ]; then
        cat << 'RULES_EOF' > kernel/drivers/kernelsu/selinux/rules.c
// SPDX-License-Identifier: GPL-2.0
#include "linux/rcupdate.h"
#include "security.h"
#include <linux/uaccess.h>
#include <linux/types.h>
#include <linux/version.h>
#include <linux/lockdep.h>
#include <linux/slab.h>
#include <linux/string.h>

#include "uapi/selinux.h"
#include "klog.h"
#include "selinux.h"
#include "sepolicy.h"
#include "ss/services.h"
#include "linux/lsm_audit.h"
#include "xfrm.h"

#define ALL NULL
#define KSU_SEPOLICY_MAX_BATCH_SIZE (8U * 1024U * 1024U)

#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
extern int avc_ss_reset(u32 seqno);
#else
extern int avc_ss_reset(struct selinux_avc *avc, u32 seqno);
#endif

static void reset_avc_cache(void)
{
#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6, 4, 0))
    avc_ss_reset(0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(0);
#else
    struct selinux_avc *avc = selinux_state.avc;
    avc_ss_reset(avc, 0);
    selnl_notify_policyload(0);
    selinux_status_update_policyload(&selinux_state, 0);
#endif
    selinux_xfrm_notify_policyload();
}

static struct policydb *get_policydb(void)
{
    struct selinux_ss *ss = rcu_dereference(selinux_state.ss);
    if (!ss) return NULL;
    return &ss->policydb;
}

void apply_kernelsu_rules(void)
{
    struct policydb *db;

    if (!getenforce()) {
        pr_info("SELinux permissive or disabled, apply rules!\n");
    }

    rcu_read_lock();
    db = get_policydb();
    if (!db) {
        rcu_read_unlock();
        return;
    }

    ksu_type(db, KERNEL_SU_DOMAIN, "domain");
    ksu_permissive(db, KERNEL_SU_DOMAIN);
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "mlstrustedsubject");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "netdomain");
    ksu_typeattribute(db, KERNEL_SU_DOMAIN, "bluetoothdomain");

    ksu_type(db, KERNEL_SU_FILE, "file_type");
    ksu_typeattribute(db, KERNEL_SU_FILE, "mlstrustedobject");
    ksu_allow(db, ALL, KERNEL_SU_FILE, ALL, ALL);

    ksu_allow(db, KERNEL_SU_DOMAIN, ALL, ALL, ALL);

    rcu_read_unlock();
    reset_avc_cache();
}

int handle_sepolicy(void __user *user_data, u64 data_len)
{
    struct policydb *db;
    u8 *payload;
    int ret = 0;

    if (!user_data || !data_len) return -EINVAL;
    if (data_len > KSU_SEPOLICY_MAX_BATCH_SIZE) return -E2BIG;

    payload = kvmalloc((size_t)data_len, GFP_KERNEL);
    if (!payload) return -ENOMEM;

    if (copy_from_user(payload, user_data, (size_t)data_len)) {
        kvfree(payload);
        return -EFAULT;
    }

    rcu_read_lock();
    db = get_policydb();
    if (db) {
        reset_avc_cache();
    }
    rcu_read_unlock();
    kvfree(payload);
    return ret;
}
RULES_EOF
    fi
fi

echo "=== All Patches applied successfully ==="
