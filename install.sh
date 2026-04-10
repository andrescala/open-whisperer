#!/bin/bash
set -e

APP_NAME="AC Voice"
SCHEME="ACVoice"
PROJECT="ACVoice.xcodeproj"
CERT="AC Voice Dev"

# ── 1. Build ────────────────────────────────────────────────────────────────
echo "🔨 Building..."
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release build \
  | grep -E "(error:|warning: 'deprecated|BUILD)" | grep -v "deprecated"

# ── 2. Find the built app ────────────────────────────────────────────────────
BUILT=$(find ~/Library/Developer/Xcode/DerivedData/ACVoice-*/Build/Products/Release \
  -maxdepth 1 -name "AC Voice.app" 2>/dev/null | head -1)

if [ -z "$BUILT" ]; then
  echo "❌ Could not find built app in DerivedData"
  exit 1
fi

# ── 3. Install ───────────────────────────────────────────────────────────────
echo "📦 Installing..."
killall "$APP_NAME" 2>/dev/null || true
sleep 0.5
rm -rf "/Applications/$APP_NAME.app"
cp -r "$BUILT" "/Applications/$APP_NAME.app"

# ── 4. Sign with self-signed cert (stable across builds = TCC never resets) ─
if security find-certificate -c "$CERT" ~/Library/Keychains/login.keychain-db &>/dev/null; then
  echo "✅ Signing with '$CERT' certificate..."
  codesign --force --deep --sign "$CERT" "/Applications/$APP_NAME.app"
else
  echo "⚠️  Certificate '$CERT' not found — using ad-hoc signing."
  echo "   Run: make cert   to create a stable certificate and stop TCC resets."
  xattr -dr com.apple.quarantine "/Applications/$APP_NAME.app"
  codesign --force --deep --sign - "/Applications/$APP_NAME.app"
fi

# ── 5. Reset Accessibility so TCC matches the current signature ──────────────
echo "🔐 Resetting Accessibility permission (will prompt once to re-grant)..."
tccutil reset Accessibility com.crutech.acvoice

# ── 6. Launch ────────────────────────────────────────────────────────────────
echo "🚀 Launching AC Voice..."
open "/Applications/$APP_NAME.app"
echo ""
echo "✅ Done! Grant Accessibility when System Settings opens."
echo "   (With a stable cert this only needs re-granting after major rebuilds.)"
