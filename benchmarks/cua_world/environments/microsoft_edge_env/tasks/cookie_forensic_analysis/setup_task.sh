#!/bin/bash
# Setup for Cookie Forensic Analysis task
# Cleans browser state, creates briefing doc, launches Edge.

set -e

TASK_NAME="cookie_forensic_analysis"
BRIEFING_FILE="/home/ga/Desktop/forensic_briefing.txt"
REPORT_FILE="/home/ga/Desktop/cookie_forensic_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
EDGE_CONFIG_DIR="/home/ga/.config/microsoft-edge/Default"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill Edge and Clean State ──────────────────────────────────────
echo "[1/4] Stopping Edge and cleaning state..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
sleep 1

# Remove previous report
rm -f "${REPORT_FILE}"

# Clear Cookies and History to ensure a clean forensic start
# This forces the agent to actually visit the sites to get data
if [ -d "$EDGE_CONFIG_DIR" ]; then
    echo "Clearing cookies and history databases..."
    rm -f "$EDGE_CONFIG_DIR/Cookies" "$EDGE_CONFIG_DIR/Cookies-journal"
    rm -f "$EDGE_CONFIG_DIR/History" "$EDGE_CONFIG_DIR/History-journal"
    # Also clear Network Persistent State if exists
    rm -f "$EDGE_CONFIG_DIR/Network Persistent State"
fi

# ── STEP 2: Create Briefing Document ───────────────────────────────────────
echo "[2/4] Creating forensic briefing document..."
cat > "${BRIEFING_FILE}" << 'BRIEFING_EOF'
DIGITAL FORENSICS UNIT — COOKIE TRACKING ANALYSIS
===================================================
Classification: UNCLASSIFIED // FOR TRAINING USE ONLY

OBJECTIVE:
Profile the tracking ecosystem of three target websites to assess
their data collection posture. This analysis will inform operational
security guidance for field personnel.

TARGET SITES:
1. https://www.cnn.com (major news portal)
2. https://www.weather.com (weather information service)
3. https://www.wikipedia.org (reference encyclopedia)

REQUIRED ANALYSIS:
- Visit each target site and allow full page load
- Inspect all cookies deposited by each site using Developer Tools
  (Application tab > Cookies) or Settings > Cookies and site permissions.
- Identify third-party tracking domains (ad networks, analytics, social)
- Document cookie counts per site
- Compare tracking intensity across the three sites
- Identify which site poses the greatest tracking exposure and which is safest

DELIVERABLE:
Save your forensic analysis report to:
/home/ga/Desktop/cookie_forensic_report.txt

The report must include:
1. Per-site cookie counts
2. Specific names of tracking domains observed (e.g., doubleclick.net)
3. A comparative summary (Who tracks most? Who tracks least?)

Report should be thorough and reference specific tracking domains
observed during your analysis.
BRIEFING_EOF
chown ga:ga "${BRIEFING_FILE}"

# ── STEP 3: Record Timestamp ───────────────────────────────────────────────
echo "[3/4] Recording task start timestamp..."
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 4: Launch Edge ────────────────────────────────────────────────────
echo "[4/4] Launching Microsoft Edge..."
# Launching with basic password store to avoid keyring popups
# Starting at about:blank so agent must navigate manually
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    about:blank > /tmp/edge.log 2>&1 &"

# Wait for Edge window
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

# Maximize window
sleep 2
DISPLAY=:1 wmctrl -r "Microsoft Edge" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== Setup complete for ${TASK_NAME} ==="