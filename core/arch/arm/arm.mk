# Setup compiler for the core module
ifeq ($(CFG_ARM64_core),y)
arch-bits-core := 64
else
arch-bits-core := 32
endif
CROSS_COMPILE_core := $(CROSS_COMPILE$(arch-bits-core))
COMPILER_core := $(COMPILER)
include mk/$(COMPILER_core).mk

# Defines the cc-option macro using the compiler set for the core module
include mk/cc-option.mk

# Size of emulated TrustZone protected SRAM, 448 kB.
# Only applicable when paging is enabled.
CFG_CORE_TZSRAM_EMUL_SIZE ?= 458752

ifneq ($(CFG_LPAE_ADDR_SPACE_SIZE),)
$(warning Error: CFG_LPAE_ADDR_SPACE_SIZE is not supported any longer)
$(error Error: Please use CFG_LPAE_ADDR_SPACE_BITS instead)
endif

CFG_LPAE_ADDR_SPACE_BITS ?= 32
ifeq ($(CFG_ARM32_core),y)
$(call force,CFG_LPAE_ADDR_SPACE_BITS,32)
endif

CFG_MMAP_REGIONS ?= 13
CFG_RESERVED_VASPACE_SIZE ?= (1024 * 1024 * 10)
CFG_NEX_DYN_VASPACE_SIZE ?= (1024 * 1024)
CFG_TEE_DYN_VASPACE_SIZE ?= (1024 * 1024)

ifeq ($(CFG_ARM64_core),y)
ifeq ($(CFG_ARM32_core),y)
$(error CFG_ARM64_core and CFG_ARM32_core cannot be both 'y')
endif
CFG_KERN_LINKER_FORMAT ?= elf64-littleaarch64
CFG_KERN_LINKER_ARCH ?= aarch64
# TCR_EL1.IPS needs to be initialized according to the largest physical
# address that we need to map.
# Physical address size
# 32 bits, 4GB.
# 36 bits, 64GB.
# (etc.)
CFG_CORE_ARM64_PA_BITS ?= 32
$(call force,CFG_WITH_LPAE,y)
else
$(call force,CFG_ARM32_core,y)
CFG_KERN_LINKER_FORMAT ?= elf32-littlearm
CFG_KERN_LINKER_ARCH ?= arm
endif

ifeq ($(CFG_TA_FLOAT_SUPPORT),y)
# Use hard-float for floating point support in user TAs instead of
# soft-float
CFG_WITH_VFP ?= y
ifeq ($(CFG_ARM64_core),y)
# AArch64 has no fallback to soft-float
$(call force,CFG_WITH_VFP,y)
endif
ifeq ($(CFG_WITH_VFP),y)
arm64-platform-hard-float-enabled := y
ifneq ($(CFG_TA_ARM32_NO_HARD_FLOAT_SUPPORT),y)
arm32-platform-hard-float-enabled := y
endif
endif
endif

# Adds protection against CVE-2017-5715 also know as Spectre
# (https://spectreattack.com)
# See also https://developer.arm.com/-/media/Files/pdf/Cache_Speculation_Side-channels.pdf
# Variant 2
CFG_CORE_WORKAROUND_SPECTRE_BP ?= y
# Same as CFG_CORE_WORKAROUND_SPECTRE_BP but targeting exceptions from
# secure EL0 instead of non-secure world, including mitigation for
# CVE-2022-23960.
CFG_CORE_WORKAROUND_SPECTRE_BP_SEC ?= $(CFG_CORE_WORKAROUND_SPECTRE_BP)

# Adds protection against a tool like Cachegrab
# (https://github.com/nccgroup/cachegrab), which uses non-secure interrupts
# to prime and later analyze the L1D, L1I and BTB caches to gain
# information from secure world execution.
CFG_CORE_WORKAROUND_NSITR_CACHE_PRIME ?= y
ifeq ($(CFG_CORE_WORKAROUND_NSITR_CACHE_PRIME),y)
$(call force,CFG_CORE_WORKAROUND_SPECTRE_BP,y,Required by CFG_CORE_WORKAROUND_NSITR_CACHE_PRIME)
endif

# Adds workarounds against if ARM core is configured with Non-maskable FIQ
# (NMFI) support. This is indicated by SCTLR.NMFI being true. NMFI cannot be
# disabled by software and as it affects atomic context end result will be
# prohibiting FIQ signal usage in OP-TEE and applying some tweaks to make sure
# FIQ is enabled in critical places.
CFG_CORE_WORKAROUND_ARM_NMFI ?= n

CFG_CORE_RWDATA_NOEXEC ?= y
CFG_CORE_RODATA_NOEXEC ?= n
ifeq ($(CFG_CORE_RODATA_NOEXEC),y)
$(call force,CFG_CORE_RWDATA_NOEXEC,y)
endif
# 'y' to set the Alignment Check Enable bit in SCTLR/SCTLR_EL1, 'n' to clear it
CFG_SCTLR_ALIGNMENT_CHECK ?= n

ifeq ($(CFG_CORE_LARGE_PHYS_ADDR),y)
$(call force,CFG_WITH_LPAE,y)
endif

# SPMC configuration "S-EL1 SPMC" where SPM Core is implemented at S-EL1,
# that is, OP-TEE.
ifeq ($(CFG_CORE_SEL1_SPMC),y)
$(call force,CFG_CORE_FFA,y)
$(call force,CFG_CORE_SEL2_SPMC,n)
$(call force,CFG_CORE_EL3_SPMC,n)
endif
# SPMC configuration "S-EL2 SPMC" where SPM Core is implemented at S-EL2,
# that is, the hypervisor sandboxing OP-TEE
ifeq ($(CFG_CORE_SEL2_SPMC),y)
$(call force,CFG_CORE_FFA,y)
$(call force,CFG_CORE_SEL1_SPMC,n)
$(call force,CFG_CORE_EL3_SPMC,n)
CFG_CORE_HAFNIUM_INTC ?= y
# Enable support in OP-TEE to relocate itself to allow it to run from a
# physical address that differs from the link address
CFG_CORE_PHYS_RELOCATABLE ?= y
endif
# SPMC configuration "EL3 SPMC" where SPM Core is implemented at EL3, that
# is, in TF-A
ifeq ($(CFG_CORE_EL3_SPMC),y)
$(call force,CFG_CORE_FFA,y)
$(call force,CFG_CORE_SEL2_SPMC,n)
$(call force,CFG_CORE_SEL1_SPMC,n)
endif

ifeq ($(CFG_CORE_FFA),y)
ifneq ($(CFG_DT),y)
$(error CFG_CORE_FFA depends on CFG_DT)
endif
ifneq ($(CFG_ARM64_core),y)
$(error CFG_CORE_FFA depends on CFG_ARM64_core)
endif
endif

ifeq ($(CFG_CORE_PHYS_RELOCATABLE)-$(CFG_WITH_PAGER),y-y)
$(error CFG_CORE_PHYS_RELOCATABLE and CFG_WITH_PAGER are not compatible)
endif
ifeq ($(CFG_CORE_PHYS_RELOCATABLE),y)
ifneq ($(CFG_CORE_SEL2_SPMC),y)
$(error CFG_CORE_PHYS_RELOCATABLE depends on CFG_CORE_SEL2_SPMC)
endif
endif

ifeq ($(CFG_CORE_FFA)-$(CFG_WITH_PAGER),y-y)
$(error CFG_CORE_FFA and CFG_WITH_PAGER are not compatible)
endif
ifeq ($(CFG_GIC),y)
ifeq ($(CFG_ARM_GICV3),y)
$(call force,CFG_CORE_IRQ_IS_NATIVE_INTR,y)
else
$(call force,CFG_CORE_IRQ_IS_NATIVE_INTR,n)
endif
endif

CFG_CORE_HAFNIUM_INTC ?= n
ifeq ($(CFG_CORE_HAFNIUM_INTC),y)
$(call force,CFG_CORE_IRQ_IS_NATIVE_INTR,y)
endif

# Selects if IRQ is used to signal native interrupt
# if CFG_CORE_IRQ_IS_NATIVE_INTR == y:
#   IRQ signals a native interrupt pending
#   FIQ signals a foreign non-secure interrupt or a managed exit pending
# else: (vice versa)
#   IRQ signals a foreign non-secure interrupt or a managed exit pending
#   FIQ signals a native interrupt pending
CFG_CORE_IRQ_IS_NATIVE_INTR ?= n

# Unmaps all kernel mode code except the code needed to take exceptions
# from user space and restore kernel mode mapping again. This gives more
# strict control over what is accessible while in user mode.
# Addresses CVE-2017-5715 (aka Meltdown) known to affect Arm Cortex-A75
CFG_CORE_UNMAP_CORE_AT_EL0 ?= y

# Initialize PMCR.DP to 1 to prohibit cycle counting in secure state, and
# save/restore PMCR during world switch.
CFG_SM_NO_CYCLE_COUNTING ?= y


# CFG_CORE_ASYNC_NOTIF_GIC_INTID is defined by the platform to some free
# interrupt. Setting it to a non-zero number enables support for using an
# Arm-GIC to notify normal world. This config variable should use a value
# larger or equal to 24 to make it of the type SPI or PPI (secure PPI
# only).
# Note that asynchronous notifactions must be enabled with
# CFG_CORE_ASYNC_NOTIF=y for this variable to be used.
CFG_CORE_ASYNC_NOTIF_GIC_INTID ?= 0

ifeq ($(CFG_ARM32_core),y)
# Configration directive related to ARMv7 optee boot arguments.
# CFG_PAGEABLE_ADDR: if defined, forces pageable data physical address.
# CFG_NS_ENTRY_ADDR: if defined, forces NS World physical entry address.
# CFG_DT_ADDR:       if defined, forces Device Tree data physical address.
endif

# CFG_MAX_CACHE_LINE_SHIFT is used to define platform specific maximum cache
# line size in address lines. This must cover all inner and outer cache levels.
# When data is aligned with this and cache operations are performed then those
# only affect correct data.
#
# Default value (6 lines or 64 bytes) should cover most architectures, override
# this in platform config if different.
CFG_MAX_CACHE_LINE_SHIFT ?= 6

core-platform-cppflags	+= -I$(arch-dir)/include
core-platform-subdirs += \
	$(addprefix $(arch-dir)/, kernel crypto mm tee) $(platform-dir)

ifneq ($(CFG_WITH_ARM_TRUSTED_FW),y)
core-platform-subdirs += $(arch-dir)/sm
endif

ifneq ($(CFG_TEE_CORE_EMBED_INTERNAL_TESTS),y)
core-platform-subdirs += $(arch-dir)/tests
endif

arm64-platform-cppflags += -DARM64=1 -D__LP64__=1
arm32-platform-cppflags += -DARM32=1 -D__ILP32__=1

platform-cflags-generic ?= -ffunction-sections -fdata-sections -pipe
platform-aflags-generic ?= -pipe

arm32-platform-aflags += -marm

arm32-platform-cflags-no-hard-float ?= -mfloat-abi=soft
arm32-platform-cflags-hard-float ?= -mfloat-abi=hard -funsafe-math-optimizations
arm32-platform-cflags-generic-thumb ?= -mthumb \
			-fno-short-enums -fno-common -mno-unaligned-access
arm32-platform-cflags-generic-arm ?= -marm -fno-omit-frame-pointer -mapcs \
			-fno-short-enums -fno-common -mno-unaligned-access
arm32-platform-aflags-no-hard-float ?=

arm64-platform-cflags-no-hard-float ?= -mgeneral-regs-only
arm64-platform-cflags-hard-float ?=
arm64-platform-cflags-generic := -mstrict-align $(call cc-option,-mno-outline-atomics,)

ifeq ($(CFG_MEMTAG),y)
arm64-platform-cflags += -march=armv8.5-a+memtag
arm64-platform-aflags += -march=armv8.5-a+memtag
endif

platform-cflags-optimization ?= -O$(CFG_CC_OPT_LEVEL)

ifeq ($(CFG_DEBUG_INFO),y)
platform-cflags-debug-info ?= -g3
platform-aflags-debug-info ?= -g
endif

core-platform-cflags += $(platform-cflags-optimization)
core-platform-cflags += $(platform-cflags-generic)
core-platform-cflags += $(platform-cflags-debug-info)

core-platform-aflags += $(platform-aflags-generic)
core-platform-aflags += $(platform-aflags-debug-info)

ifeq ($(call cfg-one-enabled, CFG_CORE_ASLR CFG_CORE_PHYS_RELOCATABLE),y)
core-platform-cflags += -fpie
endif

ifeq ($(CFG_CORE_PAUTH),y)
bp-core-opt := $(call cc-option,-mbranch-protection=pac-ret+leaf)
endif

ifeq ($(CFG_CORE_BTI),y)
bp-core-opt := $(call cc-option,-mbranch-protection=bti)
endif

ifeq (y-y,$(CFG_CORE_PAUTH)-$(CFG_CORE_BTI))
bp-core-opt := $(call cc-option,-mbranch-protection=pac-ret+leaf+bti)
endif

ifeq (y,$(filter $(CFG_CORE_BTI) $(CFG_CORE_PAUTH),y))
ifeq (,$(bp-core-opt))
$(error -mbranch-protection not supported)
endif
core-platform-cflags += $(bp-core-opt)
endif

ifeq ($(CFG_ARM64_core),y)
core-platform-cppflags += $(arm64-platform-cppflags)
core-platform-cflags += $(arm64-platform-cflags)
core-platform-cflags += $(arm64-platform-cflags-generic)
core-platform-cflags += $(arm64-platform-cflags-no-hard-float)
core-platform-aflags += $(arm64-platform-aflags)
else
core-platform-cppflags += $(arm32-platform-cppflags)
core-platform-cflags += $(arm32-platform-cflags)
core-platform-cflags += $(arm32-platform-cflags-no-hard-float)
ifeq ($(CFG_UNWIND),y)
core-platform-cflags += -funwind-tables
endif
ifeq ($(CFG_SYSCALL_FTRACE),y)
core-platform-cflags += $(arm32-platform-cflags-generic-arm)
else
core-platform-cflags += $(arm32-platform-cflags-generic-thumb)
endif
core-platform-aflags += $(core_arm32-platform-aflags)
core-platform-aflags += $(arm32-platform-aflags)
endif

# Provide default supported-ta-targets if not set by the platform config
ifeq (,$(supported-ta-targets))
supported-ta-targets = ta_arm32
ifeq ($(CFG_ARM64_core),y)
supported-ta-targets += ta_arm64
endif
endif

ta-targets := $(if $(CFG_USER_TA_TARGETS),$(filter $(supported-ta-targets),$(CFG_USER_TA_TARGETS)),$(supported-ta-targets))
unsup-targets := $(filter-out $(ta-targets),$(CFG_USER_TA_TARGETS))
ifneq (,$(unsup-targets))
$(error CFG_USER_TA_TARGETS contains unsupported value(s): $(unsup-targets). Valid values: $(supported-ta-targets))
endif

ifneq ($(filter ta_arm32,$(ta-targets)),)
# Variables for ta-target/sm "ta_arm32"
CFG_ARM32_ta_arm32 := y
arch-bits-ta_arm32 := 32
ta_arm32-platform-cppflags += $(arm32-platform-cppflags)
ta_arm32-platform-cflags += $(arm32-platform-cflags)
ta_arm32-platform-cflags += $(platform-cflags-optimization)
ta_arm32-platform-cflags += $(platform-cflags-debug-info)
ta_arm32-platform-cflags += -fpic

# Thumb mode doesn't support function graph tracing due to missing
# frame pointer support required to trace function call chain. So
# rather compile in ARM mode if function tracing is enabled.
ifeq ($(CFG_FTRACE_SUPPORT),y)
ta_arm32-platform-cflags += $(arm32-platform-cflags-generic-arm)
else
ta_arm32-platform-cflags += $(arm32-platform-cflags-generic-thumb)
endif

ifeq ($(arm32-platform-hard-float-enabled),y)
ta_arm32-platform-cflags += $(arm32-platform-cflags-hard-float)
else
ta_arm32-platform-cflags += $(arm32-platform-cflags-no-hard-float)
endif
ifeq ($(CFG_UNWIND),y)
ta_arm32-platform-cflags += -funwind-tables
endif
ta_arm32-platform-aflags += $(platform-aflags-generic)
ta_arm32-platform-aflags += $(platform-aflags-debug-info)
ta_arm32-platform-aflags += $(arm32-platform-aflags)

ta_arm32-platform-cxxflags += -fpic
ta_arm32-platform-cxxflags += $(arm32-platform-cxxflags)
ta_arm32-platform-cxxflags += $(platform-cflags-optimization)
ta_arm32-platform-cxxflags += $(platform-cflags-debug-info)

ifeq ($(arm32-platform-hard-float-enabled),y)
ta_arm32-platform-cxxflags += $(arm32-platform-cflags-hard-float)
else
ta_arm32-platform-cxxflags += $(arm32-platform-cflags-no-hard-float)
endif

ta-mk-file-export-vars-ta_arm32 += CFG_ARM32_ta_arm32
ta-mk-file-export-vars-ta_arm32 += ta_arm32-platform-cppflags
ta-mk-file-export-vars-ta_arm32 += ta_arm32-platform-cflags
ta-mk-file-export-vars-ta_arm32 += ta_arm32-platform-aflags
ta-mk-file-export-vars-ta_arm32 += ta_arm32-platform-cxxflags

ta-mk-file-export-add-ta_arm32 += CROSS_COMPILE ?= arm-linux-gnueabihf-_nl_
ta-mk-file-export-add-ta_arm32 += CROSS_COMPILE32 ?= $$(CROSS_COMPILE)_nl_
ta-mk-file-export-add-ta_arm32 += CROSS_COMPILE_ta_arm32 ?= $$(CROSS_COMPILE32)_nl_
ta-mk-file-export-add-ta_arm32 += COMPILER ?= gcc_nl_
ta-mk-file-export-add-ta_arm32 += COMPILER_ta_arm32 ?= $$(COMPILER)_nl_
ta-mk-file-export-add-ta_arm32 += PYTHON3 ?= python3_nl_
endif

ifneq ($(filter ta_arm64,$(ta-targets)),)
# Variables for ta-target/sm "ta_arm64"
CFG_ARM64_ta_arm64 := y
arch-bits-ta_arm64 := 64
ta_arm64-platform-cppflags += $(arm64-platform-cppflags)
ta_arm64-platform-cflags += $(arm64-platform-cflags)
ta_arm64-platform-cflags += $(platform-cflags-optimization)
ta_arm64-platform-cflags += $(platform-cflags-debug-info)
ta_arm64-platform-cflags += -fpic
ta_arm64-platform-cflags += $(arm64-platform-cflags-generic)
ifeq ($(arm64-platform-hard-float-enabled),y)
ta_arm64-platform-cflags += $(arm64-platform-cflags-hard-float)
else
ta_arm64-platform-cflags += $(arm64-platform-cflags-no-hard-float)
endif
ta_arm64-platform-aflags += $(platform-aflags-generic)
ta_arm64-platform-aflags += $(platform-aflags-debug-info)
ta_arm64-platform-aflags += $(arm64-platform-aflags)

ta_arm64-platform-cxxflags += -fpic
ta_arm64-platform-cxxflags += $(platform-cflags-optimization)
ta_arm64-platform-cxxflags += $(platform-cflags-debug-info)

ifeq ($(CFG_TA_PAUTH),y)
bp-ta-opt := $(call cc-option,-mbranch-protection=pac-ret+leaf)
endif

ifeq ($(CFG_TA_BTI),y)
bp-ta-opt := $(call cc-option,-mbranch-protection=bti)
endif

ifeq (y-y,$(CFG_TA_PAUTH)-$(CFG_TA_BTI))
bp-ta-opt := $(call cc-option,-mbranch-protection=pac-ret+leaf+bti)
endif

ifeq (y,$(filter $(CFG_TA_BTI) $(CFG_TA_PAUTH),y))
ifeq (,$(bp-ta-opt))
$(error -mbranch-protection not supported)
endif
ta_arm64-platform-cflags += $(bp-ta-opt)
endif

ta-mk-file-export-vars-ta_arm64 += CFG_ARM64_ta_arm64
ta-mk-file-export-vars-ta_arm64 += ta_arm64-platform-cppflags
ta-mk-file-export-vars-ta_arm64 += ta_arm64-platform-cflags
ta-mk-file-export-vars-ta_arm64 += ta_arm64-platform-aflags
ta-mk-file-export-vars-ta_arm64 += ta_arm64-platform-cxxflags

ta-mk-file-export-add-ta_arm64 += CROSS_COMPILE64 ?= $$(CROSS_COMPILE)_nl_
ta-mk-file-export-add-ta_arm64 += CROSS_COMPILE_ta_arm64 ?= $$(CROSS_COMPILE64)_nl_
ta-mk-file-export-add-ta_arm64 += COMPILER ?= gcc_nl_
ta-mk-file-export-add-ta_arm64 += COMPILER_ta_arm64 ?= $$(COMPILER)_nl_
ta-mk-file-export-add-ta_arm64 += PYTHON3 ?= python3_nl_
endif

# Set cross compiler prefix for each TA target
$(foreach sm, $(ta-targets), $(eval CROSS_COMPILE_$(sm) ?= $(CROSS_COMPILE$(arch-bits-$(sm)))))

arm32-sysreg-txt = core/arch/arm/kernel/arm32_sysreg.txt
arm32-sysregs-$(arm32-sysreg-txt)-h := arm32_sysreg.h
arm32-sysregs-$(arm32-sysreg-txt)-s := arm32_sysreg.S
arm32-sysregs += $(arm32-sysreg-txt)

ifeq ($(CFG_ARM_GICV3),y)
arm32-gicv3-sysreg-txt = core/arch/arm/kernel/arm32_gicv3_sysreg.txt
arm32-sysregs-$(arm32-gicv3-sysreg-txt)-h := arm32_gicv3_sysreg.h
arm32-sysregs-$(arm32-gicv3-sysreg-txt)-s := arm32_gicv3_sysreg.S
arm32-sysregs += $(arm32-gicv3-sysreg-txt)
endif

arm32-sysregs-out := $(out-dir)/$(sm)/include/generated

define process-arm32-sysreg
FORCE-GENSRC$(sm): $$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-h)
cleanfiles := $$(cleanfiles) $$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-h)

$$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-h): $(1) scripts/arm32_sysreg.py
	@$(cmd-echo-silent) '  GEN     $$@'
	$(q)mkdir -p $$(dir $$@)
	$(q)scripts/arm32_sysreg.py --guard __$$(arm32-sysregs-$(1)-h) \
		< $$< > $$@

FORCE-GENSRC$(sm): $$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-s)
cleanfiles := $$(cleanfiles) $$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-s)

$$(arm32-sysregs-out)/$$(arm32-sysregs-$(1)-s): $(1) scripts/arm32_sysreg.py
	@$(cmd-echo-silent) '  GEN     $$@'
	$(q)mkdir -p $$(dir $$@)
	$(q)scripts/arm32_sysreg.py --s_file < $$< > $$@
endef #process-arm32-sysreg

$(foreach sr, $(arm32-sysregs), $(eval $(call process-arm32-sysreg,$(sr))))
