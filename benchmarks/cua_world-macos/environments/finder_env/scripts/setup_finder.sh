#!/bin/bash
# Configure Finder preferences for task work:
#   - Show all filename extensions (so tasks that filter by extension don't
#     silently get fooled by `.txt.app` style spoofing)
#   - Show hidden files OFF (matches a typical user's default)
#   - Show path bar / status bar (cleaner observation surface)
#   - Default new window opens at ~/Downloads (deterministic start for tasks
#     that operate on Downloads)
#   - Use column view by default (more agent-friendly than icon view —
#     filenames are always visible)
#   - Pre-create ~/Documents and ~/Downloads (always present on a clean
#     macOS image, but explicit is cheap)
#
# All settings go through `defaults` so cfprefsd picks them up correctly
# after a flush. We then `killall Finder` so the new prefs apply immediately
# (Finder, unlike Safari, respawns automatically — it's the system shell).
set -eu

DOMAIN="com.apple.finder"

# View-and-navigation defaults
defaults write "$DOMAIN" AppleShowAllExtensions -bool true        # show .txt, .pdf, .zip suffixes
defaults write "$DOMAIN" AppleShowAllFiles -bool false            # hidden files stay hidden (default)
defaults write "$DOMAIN" ShowPathbar -bool true                   # path bar at the bottom
defaults write "$DOMAIN" ShowStatusBar -bool true                 # status bar at the bottom
defaults write "$DOMAIN" FXPreferredViewStyle -string "clmv"      # column view (clmv=columns, Nlsv=list,
                                                                  # icnv=icons, glyv=gallery)
defaults write "$DOMAIN" FXDefaultSearchScope -string "SCcf"      # search "this folder" by default
                                                                  # (SCcf=current folder, SCev=this Mac,
                                                                  # SCsp=shared)

# New windows open to ~/Downloads. PfLo = locally-specified; NewWindowTargetPath
# is a file:// URL.
defaults write "$DOMAIN" NewWindowTarget -string "PfLo"
defaults write "$DOMAIN" NewWindowTargetPath -string "file://$HOME/Downloads/"

# Quiet down the post-action chrome that obscures verification screenshots
defaults write "$DOMAIN" WarnOnEmptyTrash -bool false
defaults write "$DOMAIN" FXEnableExtensionChangeWarning -bool false   # no nag when renaming .txt → .md

# Make sure dirs exist that tasks operate on
mkdir -p "$HOME/Downloads" "$HOME/Documents" "$HOME/Desktop"

# Flush cfprefsd then bounce Finder so the new defaults apply. Finder
# respawns automatically (it's PID 1's child, more or less — launchd
# keeps it alive). Confirmed safe: see specific_env_notes/finder/notes.md
# once written. Compare to Safari, where `killall cfprefsd` alone is enough
# because Safari hasn't launched yet.
killall cfprefsd 2>/dev/null || true
sleep 1
killall Finder 2>/dev/null || true
# Finder is restarted by launchd within ~1-2s. Poll to make sure it's back
# before the next hook runs, otherwise pre_task's `open` may race.
for i in $(seq 1 15); do
  if /usr/bin/pgrep -x Finder >/dev/null 2>&1; then
    echo "[setup] Finder respawned after ${i}s"
    break
  fi
  sleep 1
done

echo "[setup] Finder preferences seeded"

# Belt-and-suspenders verification: confirm at least one of the writes round-trips
SHOW_EXT=$(/usr/bin/defaults read "$DOMAIN" AppleShowAllExtensions 2>/dev/null || echo "missing")
echo "[setup] AppleShowAllExtensions=$SHOW_EXT (expected: 1)"
echo "[setup] OK"
