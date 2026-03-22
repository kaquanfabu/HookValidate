ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = HookValidate

HookValidate_FILES = Tweak.xm
HookValidate_FRAMEWORKS = UIKit Foundation
HookValidate_CFLAGS = -fobjc-arc -DDEBUG=1  # 调试模式，生产环境去掉 -DDEBUG=1
include $(THEOS_MAKE_PATH)/tweak.mk
