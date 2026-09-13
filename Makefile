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

# Zips the release build for a GitHub release. The app is ad-hoc signed, so
# ditto is used to preserve the signature inside the archive.
dist: release
	@rm -rf $(DIST) && mkdir -p $(DIST)
	ditto -c -k --sequesterRsrc --keepParent \
		$(BUILD)/Build/Products/Release/$(APP).app \
		$(DIST)/$(APP).zip
	@shasum -a 256 $(DIST)/$(APP).zip

clean:
	rm -rf $(BUILD) $(DIST) $(PROJECT)
