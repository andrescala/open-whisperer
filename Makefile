CERT = AC Voice Dev

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

.PHONY: install cert reset-permissions
