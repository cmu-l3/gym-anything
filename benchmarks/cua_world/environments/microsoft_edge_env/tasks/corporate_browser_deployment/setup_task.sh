#!/bin/bash
# Setup for Corporate Browser Deployment task
# Creates deployment_spec.txt, resets Edge to non-compliant defaults,
# then launches Edge so the agent must deploy the corporate standard.

set -e

TASK_NAME="corporate_browser_deployment"
SPEC_FILE="/home/ga/Desktop/deployment_spec.txt"
DEPLOYMENT_LOG="/home/ga/Desktop/deployment_log.txt"
EXPORT_FILE="/home/ga/Documents/browser_config_export.html"
DOWNLOAD_DIR="/home/ga/Documents/Downloads"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
PROFILE_DIR="/home/ga/.config/microsoft-edge/Default"

echo "=== Setting up ${TASK_NAME} ==="

# ── STEP 1: Kill all browsers to safely edit Preferences ─────────────────────
echo "[1/7] Stopping all browsers..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
pkill -u ga -f firefox 2>/dev/null || true
pkill -u ga -f chromium 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
pkill -9 -u ga -f firefox 2>/dev/null || true
pkill -9 -f '/snap/firefox' 2>/dev/null || true
pkill -9 -u ga -f chromium 2>/dev/null || true
sleep 2

# ── STEP 2: Remove stale artifacts ───────────────────────────────────────────
echo "[2/7] Removing stale artifacts..."
rm -f "${DEPLOYMENT_LOG}"
rm -f "${EXPORT_FILE}"
mkdir -p "$(dirname "${EXPORT_FILE}")"
mkdir -p "${DOWNLOAD_DIR}"
chown ga:ga "${DOWNLOAD_DIR}"
chown ga:ga "$(dirname "${EXPORT_FILE}")"

# ── STEP 3: Reset Edge Bookmarks to clean skeleton ───────────────────────────
echo "[3/7] Resetting bookmarks to empty state..."
mkdir -p "$PROFILE_DIR"

cat > "$PROFILE_DIR/Bookmarks" << 'EOF'
{
   "roots": {
      "bookmark_bar": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000002",
         "id": "1",
         "name": "Favorites bar",
         "type": "folder"
      },
      "other": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000003",
         "id": "2",
         "name": "Other favorites",
         "type": "folder"
      },
      "synced": {
         "children": [],
         "date_added": "13200000000000000",
         "date_last_used": "0",
         "date_modified": "0",
         "guid": "00000000-0000-4000-a000-000000000004",
         "id": "3",
         "name": "Mobile favorites",
         "type": "folder"
      }
   },
   "version": 1
}
EOF
chown ga:ga "$PROFILE_DIR/Bookmarks"

# ── STEP 4: Set non-compliant Edge preferences ───────────────────────────────
echo "[4/7] Setting non-compliant Edge preferences..."

python3 << 'PYEOF'
import json, os

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"

# Load existing preferences or start fresh
prefs = {}
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
    except Exception:
        prefs = {}

# Ensure bookmark bar is visible
if "bookmark_bar" not in prefs:
    prefs["bookmark_bar"] = {}
prefs["bookmark_bar"]["show_on_all_tabs"] = True

# Reset startup to new tab page (NOT custom pages)
if "session" not in prefs:
    prefs["session"] = {}
prefs["session"]["restore_on_startup"] = 5
prefs["session"]["startup_urls"] = []

# Disable home button (or set to default)
if "browser" not in prefs:
    prefs["browser"] = {}
prefs["browser"]["show_home_button"] = False

# Set tracking prevention to Basic (1) — agent must change to Strict (3)
if "tracking_prevention" not in prefs:
    prefs["tracking_prevention"] = {}
prefs["tracking_prevention"]["enabled"] = True
prefs["tracking_prevention"]["tracking_prevention_level"] = 1

# Enable password saving — agent must disable
prefs["credentials_enable_service"] = True

# Enable autofill — agent must disable
if "autofill" not in prefs:
    prefs["autofill"] = {}
prefs["autofill"]["profile_enabled"] = True
prefs["autofill"]["credit_card_enabled"] = True

# Disable Do Not Track — agent must enable
prefs["enable_do_not_track"] = False

# Set download directory to default — agent must change
if "savefile" not in prefs:
    prefs["savefile"] = {}
prefs["savefile"]["default_directory"] = "/home/ga/Downloads"

with open(prefs_path, 'w') as f:
    json.dump(prefs, f, indent=2)

print("Non-compliant preferences written successfully.")
PYEOF

chown -R ga:ga "$PROFILE_DIR"

# ── STEP 5: Create the deployment specification document ─────────────────────
echo "[5/7] Creating deployment specification..."
cat > "${SPEC_FILE}" << 'SPEC_EOF'
MERIDIAN FINANCIAL SERVICES - Edge Browser Standard v3.2
Document: IT-OPS-2026-037 | Effective: 2026-01-15
IT Operations Division | Classification: Internal

================================================================
              ANALYST WORKSTATION BROWSER DEPLOYMENT
================================================================

Deploy the following configuration on the analyst's Microsoft Edge
browser. All changes must be made through the Edge graphical interface.

----------------------------------------------------------------
SECTION 1: FAVORITES BAR ORGANIZATION
----------------------------------------------------------------

Create three folders on the Favorites Bar with the following bookmarks:

  Folder: "Market Data"
      Markets         https://finance.yahoo.com
      Terminal         https://www.bloomberg.com
      Wire             https://www.reuters.com

  Folder: "Regulatory"
      SEC EDGAR        https://www.sec.gov
      FINRA            https://www.finra.org

  Folder: "Internal Tools"
      Code Repos       https://github.com
      Wiki             https://confluence.atlassian.net

----------------------------------------------------------------
SECTION 2: STARTUP & HOME PAGE
----------------------------------------------------------------

Configure Edge to open these pages on startup:
  1. https://finance.yahoo.com
  2. https://github.com

Set the Home button URL to:
  https://intranet.meridianfs.com

----------------------------------------------------------------
SECTION 3: PRIVACY & SECURITY
----------------------------------------------------------------

  Tracking prevention level:       Strict
  Offer to save passwords:         Off
  Save and fill addresses:         Off
  Send "Do Not Track" requests:    On

----------------------------------------------------------------
SECTION 4: SEARCH & DOWNLOADS
----------------------------------------------------------------

  Default search engine:           DuckDuckGo
  Default download folder:         /home/ga/Documents/Downloads

----------------------------------------------------------------
SECTION 5: EXPORT & DOCUMENTATION
----------------------------------------------------------------

  Export favorites to:  /home/ga/Documents/browser_config_export.html
  Deployment log:       /home/ga/Desktop/deployment_log.txt

  The deployment log must list each configuration change made
  and its final value, confirming that the standard was applied.

================================================================
Questions: it-ops@meridianfs.example.com
SPEC_EOF
chown ga:ga "${SPEC_FILE}"
echo "Deployment spec created at ${SPEC_FILE}"

# ── STEP 6: Record task start timestamp ──────────────────────────────────────
echo "[6/7] Recording start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 7: Launch Edge and take start screenshot ────────────────────────────
echo "[7/7] Launching Microsoft Edge..."

# Use xhost and full path for robustness across cached environments
DISPLAY=:1 xhost +local: 2>/dev/null || true

su - ga -c 'DISPLAY=:1 xhost +local: 2>/dev/null || true; DISPLAY=:1 nohup /usr/bin/microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &'

# Wait for Edge window to appear
TIMEOUT=30
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "edge|microsoft"; then
        echo "Edge window appeared after ${ELAPSED}s"
        break
    fi
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
sleep 3

# Maximize Edge window
DISPLAY=:1 wmctrl -r "Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="
echo "Spec at: ${SPEC_FILE}"
echo "Agent must apply all sections and create:"
echo "  - Export: ${EXPORT_FILE}"
echo "  - Log:    ${DEPLOYMENT_LOG}"
