TARGET := iphone:clang

TARGET_SDK_VERSION := 16.5
TARGET_IPHONEOS_DEPLOYMENT_VERSION := 16.0
ARCHS := arm64 arm64e

DEBUG := 0

include $(THEOS)/makefiles/common.mk 

TWEAK_NAME = crossfade
crossfade_FILES = Tweak.xm
crossfade_FRAMEWORKS = CoreMedia AVFoundation AudioToolbox

crossfade_LDFLAGS += -Wl,-segalign,4000 #iOS 9 support
ADDITIONAL_OBJCFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 Music; killall -9 Preferences"
# SUBPROJECTS += crossfademusicprefshook
include $(THEOS_MAKE_PATH)/aggregate.mk
