# Cowly

APP      = Cowly
SCHEME   = Cowly
PROJECT  = $(APP).xcodeproj
BUILD    = build
DIST     = dist

.PHONY: all project debug release run clean dist

all: debug

project:
	xcodegen generate

debug: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Debug \
		-derivedDataPath $(BUILD) build

release: project
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration Release \
		-derivedDataPath $(BUILD) build

run: debug
	@pkill -f "$(APP).app" || true
	open $(BUILD)/Build/Products/Debug/$(APP).app

VERSION := $(shell /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" $(BUILD)/Build/Products/Release/$(APP).app/Contents/Info.plist 2>/dev/null)

# Builds the disk image people actually download: the app next to an
# Applications shortcut, so installing is one drag.
dist: release
	@rm -rf $(DIST) && mkdir -p $(DIST)/stage
	cp -R $(BUILD)/Build/Products/Release/$(APP).app $(DIST)/stage/
	ln -s /Applications $(DIST)/stage/Applications
	hdiutil create -volname "$(APP)" -srcfolder $(DIST)/stage \
		-ov -format UDZO -fs HFS+ $(DIST)/$(APP)-$(VERSION).dmg
	@rm -rf $(DIST)/stage
	@shasum -a 256 $(DIST)/$(APP)-$(VERSION).dmg

clean:
	rm -rf $(BUILD) $(DIST) $(PROJECT)
