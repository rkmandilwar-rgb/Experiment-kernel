# Makefile for NoMount
#
# Upstream derives NOMOUNT_COMMIT_COUNT from `git rev-list --count HEAD`
# inside a standalone clone of maxsteeel/nomount. This tree vendors the
# source inside the kernel repo, where that command would report the
# kernel's own commit count, so the version stays at NOMOUNT_BASE_VERSION
# (the #ifdef in nomount.h handles the missing define).

obj-$(CONFIG_NOMOUNT) += nomount.o
ccflags-y += -std=gnu11 -Wno-declaration-after-statement -O3
