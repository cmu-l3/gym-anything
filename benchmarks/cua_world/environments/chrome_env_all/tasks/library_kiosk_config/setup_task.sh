#!/bin/bash
set -e
echo "=== Setting up library kiosk configuration task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 1. Create specification document
cat > /home/ga/Desktop/library_terminal_spec.txt << 'SPECEOF'
===============================================================================
  MIDTOWN BRANCH LIBRARY
  Digital Access Terminal Configuration Standard
  Document: DAT-2025-017  |  Rev 3  |  Effective: 2025-06-01
  Prepared by: Library Systems Office, IT Division
===============================================================================

SECTION 1: ACCESSIBILITY (ADA Compliance — 28 CFR Part 36)

  1.1 Font Sizes
      Default font size ............... 20 pixels
      Fixed-width font size ........... 18 pixels
      Minimum font size ............... 14 pixels

  1.2 Chrome Experiments (chrome://flags)
      Force Dark Mode for Web Contents .... Enabled
      Smooth Scrolling ....................... Enabled
      Enable Reader Mode .................... Enabled

SECTION 2: PRIVACY & SECURITY (Shared Terminal Policy)

  2.1 Credential Storage
      Password saving ................. DISABLED
      Address autofill ................ DISABLED
      Payment method autofill ......... DISABLED

  2.2 Tracking & Cookies
      Do Not Track header ............. ENABLED
      Third-party cookies ............. BLOCKED
      Safe Browsing ................... Enhanced Protection

  2.3 Content Permissions (Default for All Sites)
      Notifications ................... BLOCK
      Geolocation ..................... BLOCK
      Camera .......................... BLOCK
      Microphone ...................... BLOCK
      Pop-ups and redirects ........... BLOCK

SECTION 3: NAVIGATION & DOWNLOADS

  3.1 Homepage
      URL: https://www.nypl.org

  3.2 Startup Pages (On Launch)
      Page 1: https://www.nypl.org
      Page 2: https://digitalcollections.nypl.org

  3.3 Downloads
      Default directory: /home/ga/Documents/Patron_Downloads
      Always ask where to save: YES

===============================================================================
  END OF STANDARD — Compliance required before terminal goes live.
===============================================================================
SPECEOF
chown ga:ga /home/ga/Desktop/library_terminal_spec.txt

# 2. Create download directory
mkdir -p /home/ga/Documents/Patron_Downloads
chown ga:ga /home/ga/Documents/Patron_Downloads

# 3. Ensure Chrome is running with default (non-compliant) settings
# Kill any existing Chrome processes first
pkill -f chrome || true
sleep 2

# Reset the CDP user data directory to clean defaults
CDP_DIR="/home/ga/.config/google-chrome-cdp"
if [ -d "$CDP_DIR" ]; then
    rm -rf "$CDP_DIR"
fi
mkdir -p "$CDP_DIR/Default"
chown -R ga:ga "$CDP_DIR"

# Write default non-compliant preferences
cat > "$CDP_DIR/Default/Preferences" << 'PREFEOF'
{
   "profile": {
      "default_content_setting_values": {
         "notifications": 1,
         "geolocation": 1,
         "media_stream_camera": 1,
         "media_stream_mic": 1,
         "popups": 1
      },
      "password_manager_enabled": true
   },
   "browser": {
      "show_home_button": true
   },
   "homepage": "https://www.google.com",
   "homepage_is_newtabpage": false,
   "download": {
      "prompt_for_download": false,
      "default_directory": "/home/ga/Downloads"
   },
   "safebrowsing": {
      "enabled": true,
      "enhanced": false
   },
   "credentials_enable_service": true,
   "autofill": {
      "profile_enabled": true,
      "credit_card_enabled": true
   },
   "enable_do_not_track": false,
   "webkit": {
      "webprefs": {
         "default_font_size": 16,
         "default_fixed_font_size": 13,
         "minimum_font_size": 0
      }
   }
}
PREFEOF
chown -R ga:ga "$CDP_DIR"

# Write clean Local State (no flags enabled)
cat > "$CDP_DIR/Local State" << 'LSEOF'
{
   "browser": {
      "enabled_labs_experiments": []
   }
}
LSEOF
chown ga:ga "$CDP_DIR/Local State"

# 4. Relaunch Chrome with CDP
su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
sleep 5

# Wait for Chrome window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i -E "chrome|chromium"; then
        break
    fi
    sleep 1
done

# Maximize and focus Chrome
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Chrome" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="