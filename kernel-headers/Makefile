# SPDX-FileCopyrightText: The LineageOS Project
# SPDX-License-Identifier: GPL-2.0-only
#
# Installed kernel UAPI headers (see README.md). LineageOS generates its kernel
# headers with "make headers_install" in TARGET_KERNEL_SOURCE; this copies them.

VERSION = 6
PATCHLEVEL = 12

headers_install:
	@mkdir -p $(O)/usr/include
	@tar -C $(CURDIR) -c --exclude=./Makefile . | tar -C $(O)/usr/include -x

all:
	@true
