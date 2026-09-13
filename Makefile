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
NOTARY_PROFILE ?= CowlyNotary

.PHONY: all project debug release run clean dist notarize staple verify

# Builds the Apple-quality styled disk image: custom background, icon positions,
# Applications symlink, entitlements, and Developer ID code signature.
dist: release
	@swift scripts/generate_dmg_background.swift Cowly/Resources/dmg_background.png
	@rm -rf $(DIST)/stage && mkdir -p $(DIST)/stage
	cp -R $(BUILD)/Build/Products/Release/$(APP).app $(DIST)/stage/
	@if [ -n "$(IDENTITY)" ]; then \
		echo "Signing $(APP).app with $(IDENTITY)..."; \
		codesign --force --deep --sign "$(IDENTITY)" --timestamp --options runtime \
			--entitlements Cowly/Resources/Cowly.entitlements $(DIST)/stage/$(APP).app; \
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
	@echo "\nDMG built at $(DIST)/$(APP)-$(VERSION).dmg"
	@echo "To notarize with Apple so Gatekeeper accepts it seamlessly, run: make notarize"

# Submits the DMG to Apple Notary Service and staples the ticket
notarize:
	@if [ ! -f "$(DIST)/$(APP)-$(VERSION).dmg" ]; then \
		echo "DMG not found. Running make dist first..."; \
		$(MAKE) dist; \
	fi
	@echo "Submitting $(DIST)/$(APP)-$(VERSION).dmg to Apple Notary Service using keychain profile '$(NOTARY_PROFILE)'..."
	@xcrun notarytool submit "$(DIST)/$(APP)-$(VERSION).dmg" --keychain-profile "$(NOTARY_PROFILE)" --wait
	@echo "Stapling notarization ticket to DMG..."
	@xcrun stapler staple "$(DIST)/$(APP)-$(VERSION).dmg"
	@echo "\nVerification:"
	@spctl --assess -vvv --type open --context context:primary-signature "$(DIST)/$(APP)-$(VERSION).dmg"
	@echo "\n✅ Successfully notarized and stapled! The DMG will now open seamlessly on any Mac without Gatekeeper warnings."

staple:
	xcrun stapler staple "$(DIST)/$(APP)-$(VERSION).dmg"

verify:
	@echo "=== Checking Cowly.app ==="
	codesign -dvvv --entitlements - $(BUILD)/Build/Products/Release/$(APP).app
	@echo "\n=== Checking Gatekeeper assessment for DMG ==="
	spctl --assess -vvv --type open --context context:primary-signature "$(DIST)/$(APP)-$(VERSION).dmg"

clean:
	rm -rf $(BUILD) $(DIST) $(PROJECT)
