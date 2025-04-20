#
# Makefile for the output source package
#

RHEL_VER := $(shell echo `grep '^ID_LIKE'  /etc/os-release |grep -qi 'fedora' && grep '^VERSION_ID' /etc/os-release | awk -F'[.=\"]' '{printf("%02d%02d", $$3, $$4)}'`)
ifdef RHEL_VER
EXTRA_CFLAGS += -DRHEL8
ifeq ($(shell test $(RHEL_VER) -ge 0905; echo $$?),0)
EXTRA_CFLAGS += -DRHEL95
endif
endif

CONFIG_MOD += CONFIG_MT76_SDIO=m
CONFIG_MOD += CONFIG_MT792x_USB=m
CONFIG_MOD += CONFIG_MT7921U=m
CONFIG_MOD += CONFIG_MT7921S=m

CONFIG_MOD += CONFIG_MT7603E=m
CONFIG_MOD += CONFIG_MT7915E=m
CONFIG_MOD += CONFIG_MT7925U=m

ifeq ($(KERNELRELEASE),)

MAKEFLAGS += --no-print-directory
SHELL := /bin/bash
BACKPORT_DIR := $(shell pwd)

KMODDIR ?= updates
ifneq ($(origin KLIB), undefined)
KMODPATH_ARG := "INSTALL_MOD_PATH=$(KLIB)"
DEPMOD_BASE := $(KLIB)
DEPMOD_BASE_OPT := -b $(KLIB)
else
KLIB := /lib/modules/$(shell uname -r)/
KMODPATH_ARG :=
DEPMOD_BASE :=
DEPMOD_BASE_OPT :=
endif
KLIB_BUILD ?= $(KLIB)/build/
KERNEL_CONFIG := $(KLIB_BUILD)/.config
KERNEL_MAKEFILE := $(KLIB_BUILD)/Makefile
CONFIG_MD5 := $(shell md5sum $(KERNEL_CONFIG) 2>/dev/null | sed 's/\s.*//')
DEPMOD_VERSION ?=

MODDESTDIR := $(KLIB)/kernel/drivers/net
#Handle the compression option for modules in 3.18+
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.gz)")
COMPRESS_EXEC := gzip -f
endif
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.xz)")
COMPRESS_EXEC := xz -f -C crc32
endif
ifneq ("","$(wildcard $(MODDESTDIR)/*.ko.zst)")
COMPRESS_EXEC := zstd -f -q --rm
endif


export KLIB KLIB_BUILD BACKPORT_DIR KMODDIR KMODPATH_ARG

# disable built-in rules for this file
.SUFFIXES:

.PHONY: default
default:
	$(MAKE) -C $(KLIB_BUILD) M=$(BACKPORT_DIR) ccflags-y="$(EXTRA_CFLAGS)" $(CONFIG_MOD)
	
.PHONY: clean
clean:
	$(MAKE) -C $(KLIB_BUILD) M=$(BACKPORT_DIR) clean

.PHONY: modules_install
modules_install: default
	@$(MAKE) -C $(KLIB_BUILD) M=$(BACKPORT_DIR)			\
		INSTALL_MOD_DIR=$(KMODDIR) $(KMODPATH_ARG)		\
		modules_install
	
.PHONY: install
install: default
	@test -d "${KLIB_BUILD}/certs" && 				\
		openssl req -new -x509 -newkey rsa:2048 		\
		-keyout ${KLIB_BUILD}/certs/signing_key.pem 		\
		-outform DER -out ${KLIB_BUILD}/certs/signing_key.x509	\
		-nodes -days 36500 -subj "/CN=Custom MOK/"
	@$(MAKE) -C $(KLIB_BUILD) M=$(BACKPORT_DIR)			\
		INSTALL_MOD_DIR=$(KMODDIR) $(KMODPATH_ARG)		\
		modules_install
	@test -n "$(COMPRESS_EXEC)" && find $(KLIB)/$(KMODDIR) -type f -name "*.ko" -exec $(COMPRESS_EXEC) {} +
	@./scripts/check_depmod.sh
	@/sbin/depmod -a $(DEPMOD_BASE_OPT) $(DEPMOD_VERSION)
	@./scripts/fw_install.sh $(DEPMOD_BASE)

.PHONY: uninstall
uninstall:
	@./scripts/uninstall.sh
	@/sbin/depmod -a
		
else
include $(BACKPORT_DIR)/Makefile.kernel
endif
