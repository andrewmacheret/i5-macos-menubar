APP_NAME := I-5 Express
APP := build/$(APP_NAME).app
INSTALL_DIR := $(HOME)/Applications
# The Command Line Tools ship the Swift Testing macros outside the default search path.
# Full Xcode finds them by itself, so only add the flag for the Command Line Tools.
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(findstring CommandLineTools,$(shell xcode-select -p)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: help app run install uninstall test status clean

help:
	@echo "make app        Build build/$(APP_NAME).app"
	@echo "make run        Build and open the app"
	@echo "make install    Copy the app to ~/Applications and open it"
	@echo "make uninstall  Quit and remove it from ~/Applications"
	@echo "make test       Run the parser and schedule tests"
	@echo "make status     Print the current status in the terminal"

app:
	swift build -c release --product I5Express
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --show-bin-path)/I5Express" "$(APP)/Contents/MacOS/"
	cp Resources/Info.plist "$(APP)/Contents/"
	rm -rf build/AppIcon.iconset
	swift scripts/make_icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

run: app
	-pkill -x I5Express
	open "$(APP)"

install: app
	-pkill -x I5Express
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP)" "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

uninstall:
	-pkill -x I5Express
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"

test:
	swift test $(TEST_FLAGS)

status:
	@swift run -c release i5

clean:
	rm -rf .build build
