ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:14.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HookValidate

HookValidate_FILES = Tweak.xm
HookValidate_FRAMEWORKS = Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
