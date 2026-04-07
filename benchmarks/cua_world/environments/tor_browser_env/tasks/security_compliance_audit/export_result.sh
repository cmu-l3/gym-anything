#!/bin/bash
# export_result.sh for security_compliance_audit task
# Collects all auditable state: prefs.js, torrc, permissions.sqlite,
# places.sqlite history, and the compliance report file.

echo "=== Exporting security_compliance_audit results ==="

TASK_NAME="security_compliance_audit"

# Take final screenshot
DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end.png 2>/dev/null || true

# Read task start timestamp
START_TS=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

# Run Python to collect all results atomically
python3 << 'PYEOF'
import os
import json
import glob
import sqlite3
import re

TASK_NAME = "security_compliance_audit"
result = {}

# ─── Read start timestamp ───
try:
    with open(f"/tmp/{TASK_NAME}_start_ts", "r") as f:
        start_ts = float(f.read().strip())
except Exception:
    start_ts = 0
result["task_start"] = start_ts

# ─── Find profile and Tor data directories ───
profile_dir = None
tor_data_dir = None
for arch in ["x86_64", "aarch64", "tor-browser"]:
    candidate = f"/home/ga/.local/share/torbrowser/tbb/{arch}/tor-browser/Browser/TorBrowser/Data/Browser/profile.default"
    if os.path.isdir(candidate):
        profile_dir = candidate
        break
for arch in ["x86_64", "aarch64", "tor-browser"]:
    candidate = f"/home/ga/.local/share/torbrowser/tbb/{arch}/tor-browser/Browser/TorBrowser/Data/Tor"
    if os.path.isdir(candidate):
        tor_data_dir = candidate
        break

result["profile_found"] = profile_dir is not None
result["tor_data_found"] = tor_data_dir is not None

# ─── Check prefs.js ───
prefs_file = os.path.join(profile_dir, "prefs.js") if profile_dir else ""
prefs_content = ""
if os.path.isfile(prefs_file):
    result["prefs_file_exists"] = True
    with open(prefs_file, "r", errors="ignore") as f:
        prefs_content = f.read()
else:
    result["prefs_file_exists"] = False

# Security slider
slider_match = re.search(r'browser\.security_level\.security_slider.*?(\d+)', prefs_content)
result["security_slider"] = int(slider_match.group(1)) if slider_match else 1
slider_val = result["security_slider"]
# Tor Browser v15 uses INVERTED slider values:
#   slider=4 → Standard, slider=2 → Safer, slider=1 → Safest
result["security_level"] = {4: "standard", 2: "safer", 1: "safest"}.get(slider_val, "unknown")

# HTTPS-Only Mode (all windows vs private-only)
result["https_only_all"] = bool(re.search(r'dom\.security\.https_only_mode"?\s*,\s*true', prefs_content))
result["https_only_private"] = bool(re.search(r'dom\.security\.https_only_mode_pbm"?\s*,\s*true', prefs_content))

# History disabled
history_disabled = bool(re.search(r'places\.history\.enabled.*false', prefs_content))
private_autostart = bool(re.search(r'browser\.privatebrowsing\.autostart.*true', prefs_content))
result["history_never_saved"] = history_disabled or private_autostart

# Speculative connection prefs
result["prefetch_disabled"] = bool(re.search(r'network\.prefetch-next.*false', prefs_content))

spec_match = re.search(r'network\.http\.speculative-parallel-limit.*?(\d+)', prefs_content)
result["speculative_parallel_limit"] = int(spec_match.group(1)) if spec_match else -1

# network.dns.disablePrefetch: Tor Browser defaults this to true even if not
# in prefs.js. Only report false if it's explicitly set to false in prefs.js.
dns_prefetch_explicit_false = bool(re.search(r'network\.dns\.disablePrefetch.*false', prefs_content))
dns_prefetch_explicit_true = bool(re.search(r'network\.dns\.disablePrefetch.*true', prefs_content))
if dns_prefetch_explicit_false:
    result["dns_prefetch_disabled"] = False
elif dns_prefetch_explicit_true:
    result["dns_prefetch_disabled"] = True
else:
    # Not in prefs.js = Tor Browser default = true
    result["dns_prefetch_disabled"] = True

# ─── Check torrc ───
torrc_path = os.path.join(tor_data_dir, "torrc") if tor_data_dir else ""
torrc_content = ""
if os.path.isfile(torrc_path):
    result["torrc_exists"] = True
    with open(torrc_path, "r", errors="ignore") as f:
        torrc_content = f.read()
    result["torrc_modified_after_start"] = os.path.getmtime(torrc_path) > start_ts
else:
    result["torrc_exists"] = False
    result["torrc_modified_after_start"] = False

torrc_lower = torrc_content.lower()
# Check for ExitNodes with allowed countries
exitnodes_match = re.search(r'^\s*exitnodes\s+(.+)', torrc_lower, re.MULTILINE)
result["torrc_has_exitnodes"] = exitnodes_match is not None
if exitnodes_match:
    exitnodes_val = exitnodes_match.group(1).strip()
    result["torrc_exitnodes_value"] = exitnodes_val
    # Check if it contains the required countries
    has_ch = "{ch}" in exitnodes_val
    has_is = "{is}" in exitnodes_val
    has_nl = "{nl}" in exitnodes_val
    result["torrc_exitnodes_ch"] = has_ch
    result["torrc_exitnodes_is"] = has_is
    result["torrc_exitnodes_nl"] = has_nl
    result["torrc_exitnodes_all_required"] = has_ch and has_is and has_nl
else:
    result["torrc_exitnodes_value"] = ""
    result["torrc_exitnodes_ch"] = False
    result["torrc_exitnodes_is"] = False
    result["torrc_exitnodes_nl"] = False
    result["torrc_exitnodes_all_required"] = False

result["torrc_has_strictnodes_1"] = bool(re.search(r'^\s*strictnodes\s+1', torrc_lower, re.MULTILINE))

# ─── Check compliance report ───
report_path = "/home/ga/Documents/AuditPackage/compliance_report.txt"
if os.path.isfile(report_path):
    result["report_exists"] = True
    result["report_size"] = os.path.getsize(report_path)
    result["report_is_new"] = os.path.getmtime(report_path) > start_ts
    with open(report_path, "r", errors="ignore") as f:
        report_content = f.read()
    result["report_content"] = report_content[:5000]
    # Check structure
    result["report_has_req1"] = "## REQ-1" in report_content or "## req-1" in report_content.lower()
    result["report_has_req2"] = "## REQ-2" in report_content or "## req-2" in report_content.lower()
    result["report_has_req3"] = "## REQ-3" in report_content or "## req-3" in report_content.lower()
    result["report_has_req4"] = "## REQ-4" in report_content or "## req-4" in report_content.lower()
    result["report_has_summary"] = "## summary" in report_content.lower() or "## Summary" in report_content
    # Check status values
    result["report_has_compliant"] = "COMPLIANT" in report_content.upper()
    result["report_has_remediated"] = "REMEDIATED" in report_content.upper()
    # Check for evidence content (IP addresses, preference names)
    ip_pattern = re.findall(r'\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}', report_content)
    result["report_contains_ip"] = len(ip_pattern) > 0
    result["report_ip_addresses"] = ip_pattern[:5]
else:
    result["report_exists"] = False
    result["report_size"] = 0
    result["report_is_new"] = False
    result["report_content"] = ""
    result["report_has_req1"] = False
    result["report_has_req2"] = False
    result["report_has_req3"] = False
    result["report_has_req4"] = False
    result["report_has_summary"] = False
    result["report_has_compliant"] = False
    result["report_has_remediated"] = False
    result["report_contains_ip"] = False
    result["report_ip_addresses"] = []

# ─── Check browsing history ───
places_paths = glob.glob("/home/ga/.local/share/torbrowser/tbb/*/tor-browser/Browser/TorBrowser/Data/Browser/profile.default/places.sqlite")
result["history_check_torproject"] = False
result["history_check_torproject_api"] = False
result["history_canvas_test"] = False
result["history_visit_count"] = 0

if places_paths:
    places_db = places_paths[0]
    temp_db = "/tmp/places_audit_copy.sqlite"
    os.system(f'cp "{places_db}" "{temp_db}" 2>/dev/null')
    os.system(f'cp "{places_db}-wal" "{temp_db}-wal" 2>/dev/null')
    os.system(f'cp "{places_db}-shm" "{temp_db}-shm" 2>/dev/null')
    try:
        conn = sqlite3.connect(temp_db)
        c = conn.cursor()
        c.execute("SELECT url FROM moz_places")
        urls = [r[0].lower() for r in c.fetchall()]
        for u in urls:
            if "check.torproject.org" in u:
                result["history_check_torproject"] = True
            if "check.torproject.org/api/ip" in u:
                result["history_check_torproject_api"] = True
            if "canvas_test.html" in u:
                result["history_canvas_test"] = True
        # Count visits to check.torproject.org
        c.execute("SELECT COUNT(*) FROM moz_places WHERE url LIKE '%check.torproject.org%'")
        result["history_check_torproject_count"] = c.fetchone()[0]
        # Total visit count
        c.execute("SELECT COUNT(*) FROM moz_historyvisits")
        result["history_visit_count"] = c.fetchone()[0]
        conn.close()
    except Exception as e:
        print(f"Error reading places.sqlite: {e}")
    # Clean up
    for ext in ["", "-wal", "-shm"]:
        try:
            os.unlink(f"{temp_db}{ext}")
        except:
            pass

# ─── Check if Tor Browser is still running ───
import subprocess
try:
    out = subprocess.check_output(["bash", "-c", "DISPLAY=:1 wmctrl -l 2>/dev/null"], text=True)
    result["tor_browser_running"] = bool(re.search(r"tor browser", out, re.IGNORECASE))
except:
    result["tor_browser_running"] = False

result["export_timestamp"] = __import__("datetime").datetime.now().isoformat()

# ─── Write result JSON ───
with open(f"/tmp/{TASK_NAME}_result.json", "w") as f:
    json.dump(result, f, indent=2)

os.chmod(f"/tmp/{TASK_NAME}_result.json", 0o666)
print(json.dumps(result, indent=2))
PYEOF

echo "=== Export complete ==="
cat /tmp/${TASK_NAME}_result.json 2>/dev/null || echo "Result file not created"
