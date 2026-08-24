ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:17.0
THEOS_PACKAGE_SCHEME = rootless

INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DoubleTapReachability

DoubleTapReachability_FILES = Tweak.xm
DoubleTapReachability_CFLAGS = -fobjc-arc
DoubleTapReachability_LDFLAGS = -fobjc-link-runtime
DoubleTapReachability_FRAMEWORKS = UIKit

SUBPROJECTS += DoubleTapReachabilityPrefs.bundle

include $(THEOS_MAKE_PATH)/tweak.mk
include $(THEOS_MAKE_PATH)/aggregate.mk
