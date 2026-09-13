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

IDENTITY := $(shell security find-identity -v -p codesigning | grep "Developer ID Application" | head -n 1 | sed -E 's/.*"(.*)"/\1/')

# Builds the Apple-quality styled disk image: custom background, icon positions,
# Applications symlink, and Developer ID code signature.
dist: release
	@swift scripts/generate_dmg_background.swift Cowly/Resources/dmg_background.png
	@rm -rf $(DIST)/stage && mkdir -p $(DIST)/stage
	cp -R $(BUILD)/Build/Products/Release/$(APP).app $(DIST)/stage/
	@if [ -n "$(IDENTITY)" ]; then \
		echo "Signing $(APP).app with $(IDENTITY)..."; \
		codesign --force --sign "$(IDENTITY)" --timestamp --options runtime $(DIST)/stage/$(APP).app; \
	fi
	create-dmg \
		--volname "$(APP)" \
		--volicon "Cowly/Resources/AppIcon.icns" \
		--background "Cowly/Resources/dmg_background.png" \
		--window-pos 200 120 \
		--window-size 660 420 \
		--icon-size 128 \
		--text-size 12 \
		--icon "$(APP).app" 180 190 \
		--hide-extension "$(APP).app" \
		--app-drop-link 480 190 \
		--format UDZO \
		--filesystem HFS+ \
		--overwrite \
		"$(DIST)/$(APP)-$(VERSION).dmg" \
		"$(DIST)/stage"
	@if [ -n "$(IDENTITY)" ]; then \
		echo "Signing DMG with $(IDENTITY)..."; \
		codesign --force --sign "$(IDENTITY)" --timestamp "$(DIST)/$(APP)-$(VERSION).dmg"; \
	fi
	@rm -rf $(DIST)/stage
	@shasum -a 256 $(DIST)/$(APP)-$(VERSION).dmg

clean:
	rm -rf $(BUILD) $(DIST) $(PROJECT)
