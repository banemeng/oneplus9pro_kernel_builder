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

# 7. Add kernel 5.4 compatibility for copy_to_kernel_nofault
cat << 'UACC_EOF' >> kernel/include/linux/uaccess.h

#ifndef copy_to_kernel_nofault
#define copy_to_kernel_nofault probe_kernel_write
#endif
#ifndef copy_from_kernel_nofault
#define copy_from_kernel_nofault probe_kernel_read
#endif
UACC_EOF

# 8. Fix KernelSU SukiSU-Ultra internal 5.4 compatibility
if [ -d kernel/drivers/kernelsu ]; then
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/<linux\/pgtable.h>/<asm\/pgtable.h>/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_to_kernel_nofault/probe_kernel_write/g' {} + 2>/dev/null || true
    find kernel/drivers/kernelsu/ -type f -exec sed -i 's/copy_from_kernel_nofault/probe_kernel_read/g' {} + 2>/dev/null || true

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
fi

echo "=== All Patches applied successfully ==="
