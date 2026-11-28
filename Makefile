APP_NAME := I-5 Express
APP := build/$(APP_NAME).app
DMG := build/I-5-Express.dmg
ZIP := build/I-5-Express.zip
INSTALL_DIR := $(HOME)/Applications
VERSION ?= 1.0
BUILD_NUMBER ?= $(shell git rev-list --count HEAD 2>/dev/null || echo 1)
# UNIVERSAL=1 builds for both Apple silicon and Intel Macs. It needs full Xcode.
ARCHS := $(if $(UNIVERSAL),--arch arm64 --arch x86_64)
# The Command Line Tools ship the Swift Testing macros outside the default search path.
# Full Xcode finds them by itself, so only add the flag for the Command Line Tools.
TESTING_PLUGINS := /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing
TEST_FLAGS := $(if $(findstring CommandLineTools,$(shell xcode-select -p)),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: help app dmg run install uninstall test status screenshots clean

help:
	@echo "make app        Build build/$(APP_NAME).app"
	@echo "make dmg        Build $(DMG) for sharing and $(ZIP) for updates"
	@echo "make run        Build and open the app"
	@echo "make install    Copy the app to ~/Applications and open it"
	@echo "make uninstall  Quit and remove it from ~/Applications"
	@echo "make test       Run the timeline, trust and popover text tests"
	@echo "make status     Print the server's current status in the terminal"
	@echo "make screenshots  Regenerate the images in docs/ from the test fixtures"

app:
	swift build -c release --product I5Express $(ARCHS)
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources" "$(APP)/Contents/Frameworks"
	BIN="$$(swift build -c release $(ARCHS) --show-bin-path)" &&\
	cp "$$BIN/I5Express" "$(APP)/Contents/MacOS/" &&\
	ditto "$$BIN/Sparkle.framework" "$(APP)/Contents/Frameworks/Sparkle.framework"
	install_name_tool -add_rpath @executable_path/../Frameworks "$(APP)/Contents/MacOS/I5Express"
	cp .build/artifacts/sparkle/Sparkle/LICENSE "$(APP)/Contents/Resources/Sparkle-LICENSE.txt"
	cp Resources/Info.plist "$(APP)/Contents/"
	plutil -replace CFBundleShortVersionString -string "$(VERSION)" "$(APP)/Contents/Info.plist"
	plutil -replace CFBundleVersion -string "$(BUILD_NUMBER)" "$(APP)/Contents/Info.plist"
	rm -rf build/AppIcon.iconset
	swift scripts/make_icon.swift build/AppIcon.iconset
	iconutil -c icns build/AppIcon.iconset -o "$(APP)/Contents/Resources/AppIcon.icns"
	codesign --force --sign - "$(APP)"
	@echo "Built $(APP)"

# The DMG is for first installs. The Applications shortcut lets people drag the app straight in.
# The zip is what the app downloads to update itself. ditto keeps the framework's symlinks.
dmg: app
	rm -rf build/dmg "$(DMG)" "$(ZIP)"
	mkdir -p build/dmg
	cp -R "$(APP)" build/dmg/
	ln -s /Applications build/dmg/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg -fs HFS+ -format UDZO -ov "$(DMG)"
	ditto -c -k --sequesterRsrc --keepParent "$(APP)" "$(ZIP)"
	@echo "Built $(DMG) and $(ZIP)"

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
	@swift build -c release --product i5 >/dev/null 2>&1 || swift build -c release --product i5
	@"$$(swift build -c release --show-bin-path)/i5"

screenshots: app
	rm -rf build/snapshots
	"$(APP)/Contents/MacOS/I5Express" --snapshot build/snapshots --fixtures Tests/I5CoreTests/Fixtures
	mkdir -p docs
	cp build/snapshots/popover-confident-dark.png docs/popover-confirmed.png
	cp build/snapshots/popover-holiday-dark.png docs/popover-cant-confirm.png
	cd build/snapshots && cp icons-*.png menubar-*.png notifications-*.png menus-*.png ../../docs/
	cp build/AppIcon.iconset/icon_128x128@2x.png docs/app-icon.png

clean:
	rm -rf .build build
