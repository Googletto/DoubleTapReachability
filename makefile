ARCHS = arm64
TARGET = iphone:clang:14.5:17.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DoubleTapReachability
DoubleTapReachability_FILES = Tweak.xm
DoubleTapReachability_CFLAGS = -fobjc-arc
DoubleTapReachability_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk

after-install::
	install.exec "killall -9 SpringBoard"
