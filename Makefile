CERT = AC Voice Dev

# ----- Release config (override via env or .env file) -----
# Find your identity:  security find-identity -v -p codesigning
# Looks like: "Developer ID Application: Andres Cala (ABCDE12345)"
DEVELOPER_ID_APPLICATION ?= $(shell security find-identity -v -p codesigning 2>/dev/null | grep "Developer ID Application" | head -1 | sed -E 's/.*"(Developer ID Application:[^"]+)".*/\1/')
TEAM_ID                  ?= $(shell echo "$(DEVELOPER_ID_APPLICATION)" | sed -E 's/.*\(([A-Z0-9]+)\).*/\1/')
APPLE_ID                 ?=
NOTARY_PROFILE           ?= AC-Voice-Notary
SCHEME                   = ACVoice
APP_NAME                 = AC Voice
BUILD_DIR                = build
ARCHIVE_PATH             = $(BUILD_DIR)/$(SCHEME).xcarchive
EXPORT_DIR               = $(BUILD_DIR)/export
APP_PATH                 = $(EXPORT_DIR)/$(APP_NAME).app
DMG_PATH                 = $(BUILD_DIR)/AC-Voice.dmg

# Build + install + launch in one step
install:
	@bash install.sh

# Create a self-signed code-signing certificate (run once, ever)
cert:
	@echo "Creating self-signed certificate '$(CERT)'..."
	@security create-certificate \
		-k ~/Library/Keychains/login.keychain-db \
		-Z SHA256 \
		"$(CERT)" \
		-t code-signing 2>/dev/null || \
	( \
		echo "" && \
		echo "Automatic creation failed — do it manually:" && \
		echo "  1. Open Keychain Access" && \
		echo "  2. Menu: Keychain Access → Certificate Assistant → Create a Certificate" && \
		echo "  3. Name: AC Voice Dev" && \
		echo "  4. Certificate Type: Code Signing" && \
		echo "  5. Click Continue through all steps" && \
		echo "" && \
		open -a "Keychain Access" \
	)

# Reset TCC and re-grant (use if permission gets stuck)
reset-permissions:
	tccutil reset Accessibility com.crutech.acvoice
	@echo "Accessibility permission reset. Launch the app and grant it again."

# ============================================================
# Release pipeline (Developer ID, notarized, stapled, .dmg)
# ============================================================

# Run once to store notarization credentials in keychain.
# Needs an app-specific password from https://appleid.apple.com
notary-creds:
	@if [ -z "$(APPLE_ID)" ]; then echo "Set APPLE_ID=you@example.com"; exit 1; fi
	@if [ -z "$(TEAM_ID)" ]; then echo "TEAM_ID not detected. Install Developer ID cert first."; exit 1; fi
	xcrun notarytool store-credentials "$(NOTARY_PROFILE)" \
		--apple-id "$(APPLE_ID)" \
		--team-id "$(TEAM_ID)"

# Sanity check that the env is ready
release-check:
	@if [ -z "$(DEVELOPER_ID_APPLICATION)" ]; then \
		echo "ERROR: No 'Developer ID Application' certificate found in keychain."; \
		echo "Create one in Xcode → Settings → Accounts → Manage Certificates → + Developer ID Application."; \
		exit 1; \
	fi
	@echo "Identity: $(DEVELOPER_ID_APPLICATION)"
	@echo "Team:     $(TEAM_ID)"
	@xcrun notarytool history --keychain-profile "$(NOTARY_PROFILE)" >/dev/null 2>&1 || \
		( echo "ERROR: notary profile '$(NOTARY_PROFILE)' not set up. Run: make notary-creds APPLE_ID=you@example.com"; exit 1 )

# Regenerate xcodeproj (in case project.yml changed)
generate:
	xcodegen generate

# Archive with Developer ID signing + Hardened Runtime + release entitlements
archive: release-check generate
	rm -rf $(ARCHIVE_PATH)
	xcodebuild archive \
		-project ACVoice.xcodeproj \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(ARCHIVE_PATH) \
		CODE_SIGN_STYLE=Manual \
		CODE_SIGN_IDENTITY="$(DEVELOPER_ID_APPLICATION)" \
		DEVELOPMENT_TEAM=$(TEAM_ID) \
		ENABLE_HARDENED_RUNTIME=YES \
		CODE_SIGN_ENTITLEMENTS=$(CURDIR)/Whisperer/ACVoice.release.entitlements \
		OTHER_CODE_SIGN_FLAGS="--timestamp --options=runtime"

# Export the .app from the archive
export: archive
	rm -rf $(EXPORT_DIR)
	xcodebuild -exportArchive \
		-archivePath $(ARCHIVE_PATH) \
		-exportOptionsPlist ExportOptions.plist \
		-exportPath $(EXPORT_DIR)

# Submit the .app to Apple for notarization, then staple
notarize: export
	rm -f $(BUILD_DIR)/AC-Voice.zip
	ditto -c -k --keepParent "$(APP_PATH)" $(BUILD_DIR)/AC-Voice.zip
	xcrun notarytool submit $(BUILD_DIR)/AC-Voice.zip \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	xcrun stapler staple "$(APP_PATH)"
	@echo "Verifying staple..."
	xcrun stapler validate "$(APP_PATH)"
	spctl -a -t exec -vv "$(APP_PATH)"

# Build a distributable .dmg (requires `brew install create-dmg`)
dmg: notarize package-dmg

# Package the already-notarized .app into a .dmg (no rebuild)
# Uses hdiutil — no AppleScript, no Finder timeout flakes.
package-dmg:
	@if [ ! -d "$(APP_PATH)" ]; then echo "Missing $(APP_PATH). Run 'make notarize' first."; exit 1; fi
	rm -f $(DMG_PATH)
	rm -rf $(BUILD_DIR)/dmg-stage
	mkdir -p $(BUILD_DIR)/dmg-stage
	cp -R "$(APP_PATH)" $(BUILD_DIR)/dmg-stage/
	ln -s /Applications $(BUILD_DIR)/dmg-stage/Applications
	hdiutil create \
		-volname "AC Voice" \
		-srcfolder $(BUILD_DIR)/dmg-stage \
		-ov -format UDZO \
		$(DMG_PATH)
	rm -rf $(BUILD_DIR)/dmg-stage
	@echo "Notarizing the .dmg itself..."
	xcrun notarytool submit $(DMG_PATH) --keychain-profile "$(NOTARY_PROFILE)" --wait
	xcrun stapler staple $(DMG_PATH)
	xcrun stapler validate $(DMG_PATH)
	@echo ""
	@echo "Done: $(DMG_PATH)"

# One-shot release: archive → export → notarize → staple → dmg
release: dmg

# Clean release artifacts
clean-release:
	rm -rf $(BUILD_DIR)

.PHONY: install cert reset-permissions \
        notary-creds release-check generate \
        archive export notarize dmg package-dmg release clean-release
