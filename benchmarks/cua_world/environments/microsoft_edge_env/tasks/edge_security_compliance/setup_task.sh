#!/bin/bash
# Setup for Edge Security Compliance task
# Creates security_policy.txt, sets non-compliant Edge preferences,
# then launches Edge so the agent must bring it into compliance.

set -e

TASK_NAME="edge_security_compliance"
POLICY_FILE="/home/ga/Desktop/security_policy.txt"
COMPLIANCE_REPORT="/home/ga/Desktop/compliance_report.txt"
START_TS_FILE="/tmp/task_start_ts_${TASK_NAME}.txt"
BASELINE_FILE="/tmp/task_baseline_${TASK_NAME}.json"

echo "=== Setting up ${TASK_NAME} ==="

# Source shared utilities if available
if [ -f "/workspace/utils/task_utils.sh" ]; then
    source /workspace/utils/task_utils.sh
fi

# ── STEP 1: Kill Edge to safely edit Preferences ─────────────────────────────
echo "[1/5] Stopping Microsoft Edge..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 2
pkill -9 -u ga -f microsoft-edge 2>/dev/null || true
pkill -9 -u ga -f msedge 2>/dev/null || true
sleep 2

# ── STEP 2: Remove stale compliance report ───────────────────────────────────
echo "[2/5] Removing stale compliance report..."
rm -f "${COMPLIANCE_REPORT}"

# ── STEP 3: Create the corporate security policy document ────────────────────
echo "[3/5] Creating security policy document..."
cat > "${POLICY_FILE}" << 'POLICY_EOF'
ACME CORPORATION - WEB BROWSER SECURITY POLICY
Document: IT-POL-BROWSER-2024
Effective Date: January 1, 2024
Applies to: All corporate workstations using Microsoft Edge

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
MANDATORY BROWSER SECURITY REQUIREMENTS
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

The following settings MUST be configured on every corporate browser installation:

REQUIREMENT 1: SmartScreen Phishing & Malware Protection — ENABLED
Microsoft Defender SmartScreen must be active at all times. This protects
employees from phishing sites and malware downloads. Setting location:
Edge Settings > Privacy, search, and services > Security

REQUIREMENT 2: Built-in Password Manager — DISABLED
Storing corporate credentials in the browser password manager is prohibited
under NIST 800-63B and our credential management policy. Employees must use
the enterprise-approved password manager (KeePass/1Password). Setting location:
Edge Settings > Passwords (or Settings > Personal info > Passwords)

REQUIREMENT 3: Address and Form Autofill — DISABLED
Browser-side autofill of addresses and payment info creates data leakage risk
when forms are pre-populated on unauthorized sites. Setting location:
Edge Settings > Personal info > Addresses and more

REQUIREMENT 4: Default Search Engine — DuckDuckGo
Corporate policy mandates privacy-respecting search to prevent query data from
being harvested by advertising networks. Set DuckDuckGo (https://duckduckgo.com)
as the default search engine. Setting location:
Edge Settings > Privacy, search, and services > Address bar and search

REQUIREMENT 5: Tracking Prevention Level — Strict
Browser tracking prevention must be set to "Strict" to block third-party
trackers, including those on corporate partner sites. Setting location:
Edge Settings > Privacy, search, and services > Tracking prevention

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
COMPLIANCE CONFIRMATION
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After configuring all five requirements, save a compliance confirmation report
to /home/ga/Desktop/compliance_report.txt. The report must list each
requirement and confirm that the setting has been applied.

Questions: it-security@acme.example.com
POLICY_EOF
chown ga:ga "${POLICY_FILE}"
echo "Security policy created at ${POLICY_FILE}"

# ── STEP 4: Set non-compliant preferences in Edge profile ────────────────────
echo "[4/5] Setting non-compliant Edge preferences (Lesson 35: kill before DB write)..."

PREFS_DIR="/home/ga/.config/microsoft-edge/Default"
mkdir -p "$PREFS_DIR"

python3 << 'PYEOF'
import json, os, sys

prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
baseline_path = "/tmp/task_baseline_edge_security_compliance.json"

# Load or initialize preferences
if os.path.exists(prefs_path):
    try:
        with open(prefs_path) as f:
            prefs = json.load(f)
    except Exception:
        prefs = {}
else:
    prefs = {}

# Record baseline values before modification
baseline = {
    "safebrowsing_enabled_before": prefs.get("safebrowsing", {}).get("enabled", True),
    "password_manager_before":     prefs.get("credentials_enable_service", True),
    "autofill_before":             prefs.get("autofill", {}).get("enabled", True),
}

# Apply non-compliant settings (violates the policy)
if "safebrowsing" not in prefs:
    prefs["safebrowsing"] = {}
prefs["safebrowsing"]["enabled"] = False          # VIOLATION: SmartScreen off

prefs["credentials_enable_service"] = True        # VIOLATION: password manager on

if "autofill" not in prefs:
    prefs["autofill"] = {}
prefs["autofill"]["enabled"] = True               # VIOLATION: autofill on

with open(prefs_path, "w") as f:
    json.dump(prefs, f, indent=2)

with open(baseline_path, "w") as f:
    json.dump(baseline, f)

print(f"Non-compliant prefs written. Baseline: {baseline}")
PYEOF

chown -R ga:ga "$PREFS_DIR"

# Record task start timestamp (AFTER all setup writes, before agent starts)
date +%s > "${START_TS_FILE}"
echo "Task start timestamp: $(cat ${START_TS_FILE})"

# ── STEP 5: Launch Edge and take start screenshot ─────────────────────────────
echo "[5/5] Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --password-store=basic \
    > /tmp/edge.log 2>&1 &"

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

DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true
echo "Start screenshot saved to /tmp/${TASK_NAME}_start.png"

echo "=== Setup complete for ${TASK_NAME} ==="
echo "Policy at: ${POLICY_FILE}"
echo "Agent must configure 5 settings and create: ${COMPLIANCE_REPORT}"
