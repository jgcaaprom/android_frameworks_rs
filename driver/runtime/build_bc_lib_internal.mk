#
# Copyright (C) 2012 The Android Open Source Project
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

ifndef BCC_RS_TRIPLE
BCC_RS_TRIPLE := $($(LOCAL_2ND_ARCH_VAR_PREFIX)RS_TRIPLE)
endif

bc_clang_cc1_cflags :=
bc_cflags_opt :=
ifeq ($(USE_CLANG_QCOM),true)
LLVM_PREBUILTS_PATH_QCOM_3.5 := prebuilts/clang/linux-x86/host/llvm-Snapdragon_LLVM_for_Android_3.5/prebuilt/linux-x86_64/bin
LLVM_PREBUILTS_HEADER_PATH_QCOM_3.5 := $(LLVM_PREBUILTS_PATH_QCOM)/../lib/clang/3.5.0/include/

LOCAL_CLANG_EXECUTABLE := $(LLVM_PREBUILTS_PATH_QCOM_3.5)/clang 
LOCAL_LLVM_AS_EXECUTABLE := $(LLVM_PREBUILTS_PATH_QCOM_3.5)/llvm-as
LOCAL_LLVM_LINK_EXECUTABLE := $(LLVM_PREBUILTS_PATH_QCOM_3.5)/llvm-link

bc_cflags_opt := \
  -Ofast -fno-fast-math -mcpu=krait2 -mfpu=neon -mfloat-abi=softfp -marm -v \
  -muse-optlibc \
  -fvectorize-loops \
  -fomit-frame-pointer \
  -foptimize-sibling-calls \
  -ffinite-math-only \
  -funsafe-math-optimizations \
  -funroll-loops \
  -fstrict-aliasing \
  -fstack-protector \
  $(CLANG_QCOM_CONFIG_KRAIT_ALIGN_FLAGS) \
  $(CLANG_QCOM_CONFIG_KRAIT_MEM_FLAGS) \
  $(CLANG_QCOM_CONFIG_KRAIT_PARALLEL_FLAGS) \
  -fstrict-aliasing \
  -Wstrict-aliasing=2 \
  -Werror=strict-aliasing \
  -mllvm -aggressive-jt

bc_clang_cc1_cflags += -target-feature +vfp4 -target-feature +neon
else
bc_cflags_opt := #$(arch_variant_cflags)
LOCAL_CLANG_EXECUTABLE := $(LLVM_PREBUILTS_PATH)/clang$(BUILD_EXECUTABLE_SUFFIX)
LOCAL_LLVM_AS_EXECUTABLE := $(LLVM_PREBUILTS_PATH)/llvm-as$(BUILD_EXECUTABLE_SUFFIX)
LOCAL_LLVM_LINK_EXECUTABLE := $(LLVM_PREBUILTS_PATH)/llvm-link$(BUILD_EXECUTABLE_SUFFIX)
endif

# Set these values always by default
LOCAL_MODULE_TAGS := optional
LOCAL_MODULE_CLASS := SHARED_LIBRARIES

include $(BUILD_SYSTEM)/base_rules.mk

BCC_STRIP_ATTR := $(BUILD_OUT_EXECUTABLES)/bcc_strip_attr$(BUILD_EXECUTABLE_SUFFIX)


ifeq ($(BCC_RS_TRIPLE),armv7-none-linux-gnueabi)
# We need to pass the +long64 flag to the underlying version of Clang, since
# we are generating a library for use with Renderscript (64-bit long type,
# not 32-bit).
#BCC_RS_TRIPLE := armv7a-none-linux-gnueabi
bc_clang_cc1_cflags += -target-feature +long64
endif
bc_translated_clang_cc1_cflags := $(addprefix -Xclang , $(bc_clang_cc1_cflags))

bc_cflags := -MD \
             $(RS_VERSION_DEFINE) \
             -std=c99 \
             -O3 \
             -c \
             -fno-builtin \
             -emit-llvm \
             -target $(BCC_RS_TRIPLE) \
             -fsigned-char \
             $($(LOCAL_2ND_ARCH_VAR_PREFIX)RS_TRIPLE_CFLAGS) \
             $(LOCAL_CFLAGS) \
             $(bc_translated_clang_cc1_cflags) \
             $(LOCAL_CFLAGS_$(my_32_64_bit_suffix)) \
             $(bc_cflags_opt)


ifeq ($(rs_debug_runtime),1)
    bc_cflags += -DRS_DEBUG_RUNTIME
endif

bc_src_files := $(LOCAL_SRC_FILES)
bc_src_files += $(LOCAL_SRC_FILES_$(TARGET_$(LOCAL_2ND_ARCH_VAR_PREFIX)ARCH)) $(LOCAL_SRC_FILES_$(my_32_64_bit_suffix))

c_sources := $(filter %.c,$(bc_src_files))
ll_sources := $(filter %.ll,$(bc_src_files))

c_bc_files := $(patsubst %.c,%.bc, \
    $(addprefix $(intermediates)/, $(c_sources)))

ll_bc_files := $(patsubst %.ll,%.bc, \
    $(addprefix $(intermediates)/, $(ll_sources)))

$(c_bc_files): PRIVATE_INCLUDES := \
    frameworks/rs/scriptc \
    external/clang/lib/Headers
$(c_bc_files): PRIVATE_CFLAGS := $(bc_cflags)

$(c_bc_files): $(intermediates)/%.bc: $(LOCAL_PATH)/%.c  $(LOCAL_CLANG_EXECUTABLE)
	@echo "bc: $(PRIVATE_MODULE) <= $<"
	@mkdir -p $(dir $@)
	$(hide) $(LOCAL_CLANG_EXECUTABLE) $(addprefix -I, $(PRIVATE_INCLUDES)) $(PRIVATE_CFLAGS) $< -o $@

$(ll_bc_files): $(intermediates)/%.bc: $(LOCAL_PATH)/%.ll $(LOCAL_LLVM_AS_EXECUTABLE)
	@mkdir -p $(dir $@)
	$(hide) $(LOCAL_LLVM_AS_EXECUTABLE) $< -o $@

-include $(c_bc_files:%.bc=%.d)
-include $(ll_bc_files:%.bc=%.d)

$(LOCAL_BUILT_MODULE): PRIVATE_BC_FILES := $(c_bc_files) $(ll_bc_files)
$(LOCAL_BUILT_MODULE): $(c_bc_files) $(ll_bc_files)
$(LOCAL_BUILT_MODULE): $(LOCAL_LLVM_LINK_EXECUTABLE) $(clcore_LLVM_LD)
$(LOCAL_BUILT_MODULE): $(LOCAL_LLVM_AS_EXECUTABLE) $(BCC_STRIP_ATTR)
	@echo "bc lib: $(PRIVATE_MODULE) ($@)"
	@mkdir -p $(dir $@)
	$(hide) $(LOCAL_LLVM_LINK_EXECUTABLE) $(PRIVATE_BC_FILES) -o $@.unstripped
	$(hide) $(BCC_STRIP_ATTR) -o $@ $@.unstripped

BCC_RS_TRIPLE :=
