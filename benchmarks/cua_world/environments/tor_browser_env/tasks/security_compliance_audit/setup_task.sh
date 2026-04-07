#!/bin/bash
# setup_task.sh for security_compliance_audit task
# Resets Tor Browser to an unhardened baseline, pre-seeds the audit package,
# and launches the browser for the agent to audit.

set -e
echo "=== Setting up security_compliance_audit task ==="

TASK_NAME="security_compliance_audit"

# ─── 1. Kill any existing Tor Browser instances ───
echo "Killing any existing Tor Browser instances..."
pkill -u ga -f "tor-browser" 2>/dev/null || true
pkill -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
pkill -u ga -f "torbrowser" 2>/dev/null || true
sleep 3
pkill -9 -u ga -f "tor-browser" 2>/dev/null || true
pkill -9 -u ga -f "firefox.*TorBrowser" 2>/dev/null || true
sleep 2

# ─── 2. Find Tor Browser profile and Tor data directory ───
PROFILE_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Browser/profile.default" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
do
    if [ -d "$candidate" ]; then
        PROFILE_DIR="$candidate"
        echo "Found Tor Browser profile at: $PROFILE_DIR"
        break
    fi
done

TOR_DATA_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser/Browser/TorBrowser/Data/Tor" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser/Browser/TorBrowser/Data/Tor" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser/Browser/TorBrowser/Data/Tor"
do
    if [ -d "$candidate" ]; then
        TOR_DATA_DIR="$candidate"
        echo "Found Tor data dir at: $TOR_DATA_DIR"
        break
    fi
done

PREFS_FILE="$PROFILE_DIR/prefs.js"

# ─── 3. Delete stale output files BEFORE recording timestamp ───
rm -f /home/ga/Documents/AuditPackage/compliance_report.txt

# ─── 4. Reset browser to unhardened baseline ───
if [ -n "$PROFILE_DIR" ] && [ -f "$PREFS_FILE" ]; then
    echo "Resetting prefs to unhardened baseline..."
    # Remove security level setting (revert to Standard)
    sed -i '/browser\.security_level\.security_slider/d' "$PREFS_FILE" 2>/dev/null || true
    # Remove HTTPS-Only mode settings
    sed -i '/dom\.security\.https_only_mode/d' "$PREFS_FILE" 2>/dev/null || true
    # Remove history prefs (revert to remembering history)
    sed -i '/places\.history\.enabled/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/browser\.privatebrowsing\.autostart/d' "$PREFS_FILE" 2>/dev/null || true
    # Remove speculative connection prefs (let them revert to defaults)
    sed -i '/network\.prefetch-next/d' "$PREFS_FILE" 2>/dev/null || true
    sed -i '/network\.http\.speculative-parallel-limit/d' "$PREFS_FILE" 2>/dev/null || true
    # NOTE: Do NOT remove network.dns.disablePrefetch — leave it at Tor Browser's
    # default (true). This tests whether the agent checks before blindly changing.
    sed -i '/browser\.sessionstore\.privacy_level/d' "$PREFS_FILE" 2>/dev/null || true

    # Force unhardened values via user.js (overrides prefs.js on startup).
    # user.js is read once at launch and takes precedence over prefs.js.
    USER_JS="$PROFILE_DIR/user.js"
    # Append our reset prefs (idempotent — remove old ones first)
    sed -i '/SCA_TASK_RESET/d' "$USER_JS" 2>/dev/null || true
    cat >> "$USER_JS" << 'USERJS'
user_pref("browser.security_level.security_slider", 4); // SCA_TASK_RESET — v15: 4=Standard
user_pref("dom.security.https_only_mode", false); // SCA_TASK_RESET
user_pref("dom.security.https_only_mode_pbm", false); // SCA_TASK_RESET
user_pref("places.history.enabled", true); // SCA_TASK_RESET
user_pref("browser.privatebrowsing.autostart", false); // SCA_TASK_RESET
user_pref("network.prefetch-next", true); // SCA_TASK_RESET
user_pref("network.http.speculative-parallel-limit", 6); // SCA_TASK_RESET
USERJS
    echo "Wrote user.js overrides for unhardened baseline"

    echo "Prefs reset to baseline"
fi

# ─── 5. Reset torrc (remove any exit geofencing) ───
if [ -n "$TOR_DATA_DIR" ] && [ -f "$TOR_DATA_DIR/torrc" ]; then
    sed -i '/^ExitNodes/d' "$TOR_DATA_DIR/torrc" 2>/dev/null || true
    sed -i '/^StrictNodes/d' "$TOR_DATA_DIR/torrc" 2>/dev/null || true
    echo "Reset torrc (removed ExitNodes/StrictNodes)"
fi

# ─── 6. Clear canvas permissions ───
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/permissions.sqlite" ]; then
    sqlite3 "$PROFILE_DIR/permissions.sqlite" \
        "DELETE FROM moz_perms WHERE type='canvas/extractData';" 2>/dev/null || true
    echo "Cleared canvas extraction permissions"
fi

# ─── 7. Clear browsing history for clean baseline ───
if [ -n "$PROFILE_DIR" ] && [ -f "$PROFILE_DIR/places.sqlite" ]; then
    rm -f "$PROFILE_DIR/places.sqlite" \
          "$PROFILE_DIR/places.sqlite-shm" \
          "$PROFILE_DIR/places.sqlite-wal" 2>/dev/null || true
    echo "Cleared browsing history"
fi

# ─── 8. Create AuditPackage directory and pre-seed files ───
mkdir -p /home/ga/Documents/AuditPackage

# Write the security policy document
cat > /home/ga/Documents/AuditPackage/security_policy.md << 'POLICY_EOF'
# Organizational Security Policy: Tor Browser Deployment
## Classification: INTERNAL — Compliance Audit Required
## Document Version: 2.1 | Effective Date: 2026-01-15

This document defines the mandatory security configuration for all Tor Browser
installations used within the organization. The auditor must verify each
requirement, remediate any non-compliant items, and produce a compliance report.

**Important**: Complete REQ-3 (including the canvas fingerprinting test) before
applying the REQ-1 security level change, as the Safest security level disables
JavaScript on local pages, which would prevent the canvas test from running.

---

### REQ-1: Browser Hardening Profile

The following three settings must all be active simultaneously:

1. **Security Level** must be set to **"Safest"**. Verify via the shield icon
   in the toolbar or Settings > Privacy & Security.

2. **HTTPS-Only Mode** must be enabled in **all windows** — not just private
   windows. Navigate to Settings > Privacy & Security > HTTPS-Only Mode.
   The correct setting is "Enable HTTPS-Only Mode in all windows." The option
   "Enable HTTPS-Only Mode in private windows only" does NOT satisfy this
   requirement.

3. **History retention** must be set to **"Never remember history"**. This is
   configured via Settings > Privacy & Security > History dropdown.

---

### REQ-2: Tor Exit Node Geofencing

Exit traffic must be restricted to relays located in privacy-friendly
jurisdictions. Edit the Tor configuration file (torrc) to set:

    ExitNodes {ch},{is},{nl}
    StrictNodes 1

This restricts exit relays to Switzerland, Iceland, and the Netherlands.
Both directives are required — setting ExitNodes without StrictNodes 1
makes the restriction advisory rather than enforced.

After modifying the torrc, restart the Tor connection through the browser
(close and reopen Tor Browser, or use Settings > Connection to reconnect).
Then verify the configuration works:

1. Visit check.torproject.org and confirm the exit node is in an allowed
   country (CH, IS, or NL).
2. Request a **New Identity** (Tor Browser menu > New Identity) to get a
   fresh circuit.
3. Visit check.torproject.org again and confirm the new exit node is also
   in an allowed country.

Both verification checks must show exit nodes in allowed countries.

---

### REQ-3: Speculative Connection Prevention and Canvas Fingerprinting Resistance

**Part A — Speculative Connections**: The following about:config preferences
must be set to prevent the browser from making speculative network connections
that could leak metadata:

  - network.http.speculative-parallel-limit = 0
  - network.prefetch-next = false
  - network.dns.disablePrefetch = true

Check each preference's current value before modifying. Some may already be
correctly configured by Tor Browser's defaults — report those as COMPLIANT
rather than REMEDIATED.

**Part B — Canvas Fingerprinting**: Verify that HTML5 canvas data extraction
is blocked by the browser. A test page is provided at:

    file:///home/ga/Documents/AuditPackage/canvas_test.html

Open this page, click "Draw Test Pattern" to render the canvas, then click
"Export Canvas Data" to attempt extraction. The browser should block the
extraction and show a message indicating the data was blocked (minimal bytes
returned). If canvas protection is working correctly, report this as COMPLIANT.
Do NOT disable this protection.

---

### REQ-4: Active Circuit Verification and Documentation

Document the current active Tor circuit by collecting the following information:

1. The **entry guard's relay name** — visible in the circuit display when you
   click the padlock or onion icon on any loaded page (e.g., check.torproject.org).
   The circuit display shows the path: [Your computer] > [Guard] > [Middle] > [Exit].

2. The **exit node's IP address** — fetch from check.torproject.org/api/ip
   (this returns just the IP address as plain text).

3. The **exit node's country** — shown on check.torproject.org's main page
   (it displays "Your IP address appears to be: X.X.X.X" along with location info).

Verify that the exit node's country matches one of the allowed countries from
REQ-2 (Switzerland, Iceland, or Netherlands). If it does not match, report
REQ-2 as needing investigation and document the discrepancy.

Include all extracted values (guard name, exit IP, exit country) as evidence
in your compliance report.

---

## Report Format

Create the compliance report at:

    /home/ga/Documents/AuditPackage/compliance_report.txt

Use the following format for each requirement:

    ## REQ-N
    - Initial State: [exact preference names/values observed before changes]
    - Status: COMPLIANT | REMEDIATED | FAILED
    - Evidence: [specific values, IP addresses, or test results after changes]
    - Action Taken: [what was changed, or "None - already compliant"]

End with:

    ## Summary
    - COMPLIANT: [count]
    - REMEDIATED: [count]
    - FAILED: [count]
POLICY_EOF

# Write the canvas fingerprinting test page
cat > /home/ga/Documents/AuditPackage/canvas_test.html << 'CANVAS_EOF'
<!DOCTYPE html>
<html>
<head><title>Canvas Fingerprint Resistance Test</title>
<style>
  body { font-family: monospace; background: #1a1a2e; color: #e0e0e0; padding: 20px; }
  canvas { border: 1px solid #444; display: block; margin: 10px 0; }
  #result { padding: 15px; margin: 10px 0; border: 2px solid #444; min-height: 40px;
            font-size: 14px; word-break: break-all; }
  .pass { border-color: #00ff88; color: #00ff88; }
  .fail { border-color: #ff4444; color: #ff4444; }
  button { background: #16213e; color: #e0e0e0; border: 1px solid #0f3460;
           padding: 10px 20px; cursor: pointer; font-size: 16px; margin: 5px; }
  button:hover { background: #1a3a6e; }
</style></head>
<body>
<h1>Canvas Data Extraction Test</h1>
<p>This page tests whether the browser blocks canvas fingerprinting.
   Click "Draw Test Pattern" first, then "Export Canvas Data".</p>
<canvas id="testCanvas" width="400" height="300"></canvas>
<button onclick="drawChart()">Draw Test Pattern</button>
<button onclick="exportCanvas()">Export Canvas Data</button>
<div id="result">Click "Draw Test Pattern" first, then "Export Canvas Data".</div>
<script>
function drawChart() {
  var c = document.getElementById('testCanvas');
  var ctx = c.getContext('2d');
  ctx.fillStyle = '#0a0a23';
  ctx.fillRect(0, 0, 400, 300);
  ctx.strokeStyle = '#1a1a4e';
  for (var i = 0; i < 400; i += 20) { ctx.beginPath(); ctx.moveTo(i,0); ctx.lineTo(i,300); ctx.stroke(); }
  for (var i = 0; i < 300; i += 20) { ctx.beginPath(); ctx.moveTo(0,i); ctx.lineTo(400,i); ctx.stroke(); }
  var colors = ['#ff6b6b','#4ecdc4','#45b7d1','#96ceb4','#ffeaa7','#dfe6e9'];
  for (var i = 0; i < 30; i++) {
    ctx.beginPath();
    ctx.arc(30+Math.random()*340, 30+Math.random()*240, 4+Math.random()*8, 0, Math.PI*2);
    ctx.fillStyle = colors[i % colors.length];
    ctx.fill();
  }
  ctx.fillStyle = '#ffffff';
  ctx.font = '16px monospace';
  ctx.fillText('AUDIT TEST PATTERN', 100, 280);
  document.getElementById('result').textContent = 'Pattern drawn. Now click "Export Canvas Data".';
  document.getElementById('result').className = '';
}
function exportCanvas() {
  var c = document.getElementById('testCanvas');
  try {
    var data = c.toDataURL('image/png');
    var el = document.getElementById('result');
    if (data.length < 500) {
      el.textContent = 'BLOCKED: Canvas extraction returned minimal data (' + data.length + ' bytes). Browser is protecting against canvas fingerprinting. Protection is ACTIVE.';
      el.className = 'pass';
    } else {
      el.textContent = 'WARNING: Canvas data extracted successfully (' + data.length + ' bytes). Fingerprinting protection may be disabled.';
      el.className = 'fail';
    }
  } catch(e) {
    var el = document.getElementById('result');
    el.textContent = 'BLOCKED: ' + e.message + '. Canvas fingerprinting protection is ACTIVE.';
    el.className = 'pass';
  }
}
</script></body></html>
CANVAS_EOF

chown -R ga:ga /home/ga/Documents/AuditPackage

# ─── 9. Record task start timestamp (AFTER deleting stale outputs) ───
date +%s > /tmp/${TASK_NAME}_start_ts
echo "Task start timestamp: $(cat /tmp/${TASK_NAME}_start_ts)"

# ─── 10. Launch Tor Browser ───
TOR_BROWSER_DIR=""
for candidate in \
    "/home/ga/.local/share/torbrowser/tbb/x86_64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/aarch64/tor-browser" \
    "/home/ga/.local/share/torbrowser/tbb/tor-browser"
do
    if [ -d "$candidate/Browser" ]; then
        TOR_BROWSER_DIR="$candidate"
        break
    fi
done

echo "Launching Tor Browser from: $TOR_BROWSER_DIR"
if [ -n "$TOR_BROWSER_DIR" ] && [ -f "$TOR_BROWSER_DIR/start-tor-browser.desktop" ]; then
    su - ga -c "cd $TOR_BROWSER_DIR && DISPLAY=:1 ./start-tor-browser.desktop --detach > /tmp/tor_browser.log 2>&1 &"
else
    su - ga -c "DISPLAY=:1 torbrowser-launcher > /tmp/tor_browser.log 2>&1 &"
fi

# ─── 11. Wait for Tor Browser process ───
echo "Waiting for Tor Browser process..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if pgrep -u ga -f "firefox.*TorBrowser\|tor-browser" > /dev/null; then
        echo "Tor Browser process started after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# ─── 12. Wait for Tor Browser window ───
echo "Waiting for Tor Browser window..."
ELAPSED=0
TIMEOUT=120
while [ $ELAPSED -lt $TIMEOUT ]; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser|connecting|download"; then
        echo "Tor Browser window appeared after ${ELAPSED}s"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

# ─── 13. Wait for Tor network connection (up to 5 minutes) ───
echo "Waiting for Tor network connection..."
ELAPSED=0
TIMEOUT=300
TOR_CONNECTED=false
while [ $ELAPSED -lt $TIMEOUT ]; do
    WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
    if echo "$WINDOW_TITLE" | grep -qiE "connecting|establishing|starting|download"; then
        :
    elif [ -n "$WINDOW_TITLE" ]; then
        if echo "$WINDOW_TITLE" | grep -qiE "explore|duckduckgo|privacy|search|new tab|about:blank"; then
            echo "Tor Browser connected after ${ELAPSED}s"
            TOR_CONNECTED=true
            break
        elif echo "$WINDOW_TITLE" | grep -qiE "^tor browser$"; then
            sleep 10
            WINDOW_TITLE_RECHECK=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "tor browser" | head -1 | cut -d' ' -f5- || echo "")
            if ! echo "$WINDOW_TITLE_RECHECK" | grep -qiE "connecting|establishing"; then
                TOR_CONNECTED=true
                break
            fi
        fi
    fi
    sleep 3
    ELAPSED=$((ELAPSED + 3))
    if [ $((ELAPSED % 30)) -eq 0 ]; then
        echo "Still waiting for Tor connection... (${ELAPSED}s)"
    fi
done

if [ "$TOR_CONNECTED" = "false" ]; then
    echo "ERROR: Tor Browser did not connect within ${TIMEOUT}s"
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_failed.png 2>/dev/null || true
    exit 1
fi

# Extra wait for page to fully render
sleep 10

# ─── 14. Remove user.js overrides now that browser is running with baseline ───
# This prevents user.js from interfering if the agent restarts the browser
# (e.g., to reload torrc for REQ-2). The running browser already has the
# unhardened baseline values in memory; removing user.js entries means future
# restarts won't undo the agent's changes.
if [ -n "$PROFILE_DIR" ]; then
    USER_JS="$PROFILE_DIR/user.js"
    sed -i '/SCA_TASK_RESET/d' "$USER_JS" 2>/dev/null || true
    echo "Removed user.js reset overrides (browser already running with baseline)"
fi

# ─── 15. Focus and maximize window, take start screenshot ───
WINDOW_ID=$(DISPLAY=:1 wmctrl -l | grep -iE "tor browser" | head -1 | awk '{print $1}')
if [ -n "$WINDOW_ID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WINDOW_ID" 2>/dev/null || true
    DISPLAY=:1 wmctrl -i -r "$WINDOW_ID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

sleep 2
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_start.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_start.png 2>/dev/null || true

echo "=== security_compliance_audit task setup complete ==="
echo "Tor Browser is running with unhardened baseline settings."
echo "Policy document at /home/ga/Documents/AuditPackage/security_policy.md"
echo "Canvas test page at /home/ga/Documents/AuditPackage/canvas_test.html"
echo "Agent must audit 4 security requirements and produce a compliance report."
