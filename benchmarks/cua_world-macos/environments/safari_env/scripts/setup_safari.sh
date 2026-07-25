#!/bin/bash
# Configure Safari preferences for task work:
#   - Enable Develop menu (needed for Web Inspector / devtools tasks)
#   - Suppress "Welcome to Safari" and tip notifications
#   - Set homepage to about:blank so screenshots are deterministic
#   - Make sure ~/Downloads exists (used by download tasks)
#   - Pre-create ~/Library/Safari (where per-task verifiers look for plists)
#
# All settings go through `defaults`, NOT plist surgery, so the launch-time
# cfprefsd cache picks them up correctly.
set -eu

DOMAIN="com.apple.Safari"

# Develop menu — aspirational. Probed extensively (see
# specific_env_notes/safari/notes.md "Sandbox / Develop menu" section):
# the standard `defaults write` does NOT actually surface the Develop menu
# in Safari's menu bar, even with `killall cfprefsd` or with writes to the
# sandboxed container path. Likely requires a user gesture or specific
# entitlement Apple gates. Tasks that need DevTools should fall back to
# Terminal (`curl -I`), AppleScript `do shell script`, or the
# `Cmd+Option+I` shortcut which works without the menu being visible IF
# the underlying entitlement is enabled.
defaults write "$DOMAIN" IncludeDevelopMenu -bool true
defaults write "$DOMAIN" IncludeInternalDebugMenu -bool false
defaults write "$DOMAIN" WebKitDeveloperExtrasEnabledPreferenceKey -bool true
defaults write "$DOMAIN" "WebKitPreferences.developerExtrasEnabled" -bool true

# Determinate startup state
defaults write "$DOMAIN" HomePage -string "about:blank"
defaults write "$DOMAIN" NewWindowBehavior -int 1                  # open home page in new windows
defaults write "$DOMAIN" NewTabBehavior -int 1                     # open home page in new tabs
defaults write "$DOMAIN" AlwaysRestoreSessionAtLaunch -bool false
defaults write "$DOMAIN" OpenPrivateWindowWhenNotRestoringSessionAtLaunch -bool false

# Quiet down first-run / promotional UI
defaults write "$DOMAIN" SuppressSearchSuggestions -bool true
defaults write "$DOMAIN" ShowFavoritesBar -bool true               # bookmark tasks expect this visible
defaults write "$DOMAIN" ShowFullURLInSmartSearchField -bool true  # needed to read the address bar

# Conservative privacy baseline (per-task verifiers may override)
defaults write "$DOMAIN" SendDoNotTrackHTTPHeader -bool true
defaults write "$DOMAIN" WarnAboutFraudulentWebsites -bool true

# Tip framework (these dialogs show on first launch otherwise)
defaults write "$DOMAIN" DidMigrateDefaultBrowserPromptCount -int 1
defaults write "$DOMAIN" UniversalSearchEnabled -bool false

# Make sure dirs exist that tasks write into
mkdir -p "$HOME/Downloads" "$HOME/Documents" "$HOME/Library/Safari"

echo "[setup] Safari preferences seeded"

# Flush cfprefsd cache so Safari picks up the new defaults on first launch.
# Without this, IncludeDevelopMenu in particular doesn't appear in the menu bar
# until Safari is quit and re-launched — see specific_env_notes/safari/notes.md.
killall cfprefsd 2>/dev/null || true
sleep 1
echo "[setup] cfprefsd flushed"

echo "[setup] verifying Safari bundle one more time:"
ls -d /Applications/Safari.app >/dev/null
echo "[setup] OK"
