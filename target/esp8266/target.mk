TARGET_OBJ_FILES := main.o \
					uart.o \
					interface_commands.o \
					info_commands.o \
					wifi_commands.o \
					ip_commands.o \
					ip_commands_info.o \
					ip_commands_common.o \
					ip_commands_socket.o \
					config_store.o \


TARGET_OBJ_PATHS := $(addprefix $(TARGET_DIR)/,$(TARGET_OBJ_FILES))

TOOLCHAIN_PREFIX ?= xtensa-lx106-elf-
XTENSA_TOOCHAIN := sdk/xtensa-lx106-elf
CC := $(XTENSA_TOOCHAIN)/bin/$(TOOLCHAIN_PREFIX)gcc
AR := $(XTENSA_TOOCHAIN)/bin/$(TOOLCHAIN_PREFIX)ar
LD := $(XTENSA_TOOCHAIN)/bin/$(TOOLCHAIN_PREFIX)gcc


XTENSA_LIBS ?= $(shell $(CC) -print-sysroot)
XTENSA_LIBS = $(XTENSA_TOOCHAIN)/include

ESPTOOL ?= sdk/esptool-ck/esptool.exe

SDK_BASE ?= sdk/esp_iot_sdk_v0.9.3

SDK_EXAMPLE_DIR := $(SDK_BASE)/examples/IoT_Demo

SDK_DRIVER_OBJ_FILES := 
SDK_DRIVER_OBJ_PATHS := $(addprefix $(SDK_AT_DIR)/driver/,$(SDK_DRIVER_OBJ_FILES))

CPPFLAGS += -I$(XTENSA_LIBS)/include \
			-I$(SDK_BASE)/include \
			-Itarget/esp8266 \
			-I$(SDK_EXAMPLE_DIR)/include

LDFLAGS  += -L$(XTENSA_LIBS)/lib \
			-L$(XTENSA_LIBS)/arch/lib \
			-L$(SDK_BASE)/lib

CFLAGS+=-std=c99
CPPFLAGS+=-DESP_PLATFORM=1

LIBS := c gcc hal phy net80211 lwip wpa main json ssl pp

#-Werror 
CFLAGS += -Os -g -O2 -Wpointer-arith -Wno-implicit-function-declaration -Wl,-EL -fno-inline-functions -nostdlib -mlongcalls -mno-text-section-literals  -D__ets__ -DICACHE_FLASH

LDFLAGS	+= -nostdlib -Wl,--no-check-sections -u call_user_start -Wl,-static

LD_SCRIPT := $(SDK_BASE)/ld/eagle.app.v6.ld

APP_AR:=$(BIN_DIR)/app.a
APP_OUT:=$(BIN_DIR)/app.out
APP_FW_1 := $(BIN_DIR)/0x00000.bin
APP_FW_2 := $(BIN_DIR)/0x40000.bin
FULL_FW := $(BIN_DIR)/firmware.bin

$(COMMON_OBJ_PATHS) $(TARGET_OBJ_PATHS) $(SDK_DRIVER_OBJ_PATHS): | get-tools


$(APP_AR): $(COMMON_OBJ_PATHS) $(TARGET_OBJ_PATHS) $(SDK_DRIVER_OBJ_PATHS)
	$(AR) cru $@ $^

$(APP_AR): | $(BIN_DIR)

$(APP_OUT): $(APP_AR)
	$(LD) -T$(LD_SCRIPT) $(LDFLAGS) -Wl,--start-group $(addprefix -l,$(LIBS)) $(APP_AR) -Wl,--end-group -o $@

$(APP_FW_1): $(APP_OUT) $(ESPTOOL)
	$(ESPTOOL) -eo $(APP_OUT) -bo $@ -bs .text -bs .data -bs .rodata -bc -ec

$(APP_FW_2): $(APP_OUT) $(ESPTOOL)
	$(ESPTOOL) -eo $(APP_OUT) -es .irom0.text $@ -ec

$(FULL_FW): $(APP_FW_1) $(APP_FW_2)
	dd if=/dev/zero ibs=4k count=124 | LC_ALL=C tr "\000" "\377" >$(FULL_FW)
	dd if=$(APP_FW_1) of=$(FULL_FW) bs=4k seek=0 conv=notrunc
	dd if=$(APP_FW_2) of=$(FULL_FW) bs=4k seek=64 conv=notrunc

firmware: $(APP_FW_1) $(APP_FW_2) $(FULL_FW)

all: firmware

clean-sdk:
	rm -rf sdk

sdk:
	mkdir.exe -p sdk

sdk/xtensa-lx106-elf.7z:
	wget --no-check-certificate -O sdk/xtensa-lx106-elf.7z https://github.com/williambernardet/esp8266-tools/raw/master/toolchain/xtensa-lx106-elf.7z

$(CC): | sdk/xtensa-lx106-elf.7z
	7za x -y -osdk sdk/xtensa-lx106-elf.7z

sdk/esp_iot_sdk_v0.9.3_14_11_21.zip: | sdk
	wget --no-check-certificate -O sdk/esp_iot_sdk_v0.9.3_14_11_21.zip https://github.com/williambernardet/esp8266-tools/raw/master/sdk/esp_iot_sdk_v0.9.3_14_11_21.zip

sdk/esp_iot_sdk_v0.9.3_14_11_21_patch1.zip: | sdk
	wget --no-check-certificate -O sdk/esp_iot_sdk_v0.9.3_14_11_21_patch1.zip https://github.com/williambernardet/esp8266-tools/raw/master/sdk/esp_iot_sdk_v0.9.3_14_11_21_patch1.zip

sdk/esp_iot_sdk_v0.9.3: | sdk/esp_iot_sdk_v0.9.3_14_11_21.zip sdk/esp_iot_sdk_v0.9.3_14_11_21_patch1.zip
	7za x -y -osdk sdk/esp_iot_sdk_v0.9.3_14_11_21.zip
	7za x -y -osdk sdk/esp_iot_sdk_v0.9.3_14_11_21_patch1.zip
	patch sdk/esp_iot_sdk_v0.9.3/include/c_types.h < target/esp8266/c_types.h.diff

sdk/esptool-ck: | sdk
	cd sdk && git clone https://github.com/igrr/esptool-ck

$(ESPTOOL): | sdk/esptool-ck
	cd sdk/esptool-ck && make all

get-tools: sdk/esp_iot_sdk_v0.9.3 $(CC) $(ESPTOOL)
	echo All Done...

.PHONY: all firmware clean-sdk get-tools
