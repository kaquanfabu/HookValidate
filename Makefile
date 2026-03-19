ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0
ENABLE_ARC = 1  # 启用 ARC
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HookValidate

HookValidate_FILES = Tweak.xm
HookValidate_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
