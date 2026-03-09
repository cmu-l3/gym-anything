#!/bin/bash
# Export script for Edge Security Compliance task

echo "=== Exporting Edge Security Compliance Result ==="

# Take final screenshot while Edge is still running
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Kill Edge to flush preferences to disk before reading them
echo "Killing Edge to flush preferences..."
pkill -f "microsoft-edge" 2>/dev/null || true
pkill -f "msedge" 2>/dev/null || true
sleep 3

# Now read Preferences file (Edge has flushed changes)
python3 << 'PYEOF'
import json, os, re

task_start = 0
try:
    task_start = int(open("/tmp/task_start_timestamp").read().strip())
except:
    pass

# Read Edge Preferences
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
prefs = {}
prefs_readable = False
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, "r") as f:
            prefs = json.load(f)
        prefs_readable = True
    except Exception as e:
        print(f"Preferences read error: {e}")

# Check specific compliance settings
# 1. SmartScreen (safebrowsing.enabled)
sb = prefs.get("safebrowsing", {})
smartscreen_enabled = sb.get("enabled", False)

# 2. Password manager (credentials_enable_service)
password_manager_disabled = not prefs.get("credentials_enable_service", True)

# 3. Address autofill (autofill.enabled)
autofill_section = prefs.get("autofill", {})
autofill_disabled = not autofill_section.get("enabled", True)

# Check initial vs current for SafeBrowsing (to detect change)
initial_prefs = {}
if os.path.exists("/tmp/esc_initial_preferences.json"):
    try:
        with open("/tmp/esc_initial_preferences.json", "r") as f:
            initial_prefs = json.load(f)
    except:
        pass

initial_sb = initial_prefs.get("safebrowsing", {}).get("enabled", False)
initial_pw = initial_prefs.get("credentials_enable_service", True)
initial_af = initial_prefs.get("autofill", {}).get("enabled", True)

smartscreen_changed = (initial_sb != smartscreen_enabled)
password_changed = (initial_pw != prefs.get("credentials_enable_service", True))
autofill_changed = (initial_af != autofill_section.get("enabled", True))

# Check compliance report
report_path = "/home/ga/Desktop/compliance_report.txt"
report_exists = os.path.exists(report_path)
report_size = 0
report_mtime = 0
report_modified_after_start = False
report_mentions_duckduckgo = False
report_mentions_strict = False
report_mentions_smartscreen = False

if report_exists:
    stat = os.stat(report_path)
    report_size = stat.st_size
    report_mtime = int(stat.st_mtime)
    report_modified_after_start = report_mtime > task_start
    try:
        content = open(report_path, "r", errors="replace").read()
        lower = content.lower()
        report_mentions_duckduckgo = "duckduckgo" in lower
        report_mentions_strict = "strict" in lower
        report_mentions_smartscreen = any(w in lower for w in ["smartscreen", "smart screen", "defender", "safe browsing"])
    except:
        pass

result = {
    "task": "edge_security_compliance",
    "task_start": task_start,
    "preferences_readable": prefs_readable,
    "settings": {
        "smartscreen_enabled": smartscreen_enabled,
        "smartscreen_was_disabled": not initial_sb,
        "smartscreen_changed": smartscreen_changed,
        "password_manager_disabled": password_manager_disabled,
        "password_was_enabled": initial_pw,
        "password_changed": password_changed,
        "autofill_disabled": autofill_disabled,
        "autofill_was_enabled": initial_af,
        "autofill_changed": autofill_changed
    },
    "compliance_report": {
        "exists": report_exists,
        "size_bytes": report_size,
        "modified_after_start": report_modified_after_start,
        "mentions_duckduckgo": report_mentions_duckduckgo,
        "mentions_strict": report_mentions_strict,
        "mentions_smartscreen": report_mentions_smartscreen
    }
}

with open("/tmp/edge_security_compliance_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"SmartScreen enabled: {smartscreen_enabled} (was disabled: {not initial_sb})")
print(f"Password manager disabled: {password_manager_disabled} (was enabled: {initial_pw})")
print(f"Autofill disabled: {autofill_disabled} (was enabled: {initial_af})")
print(f"Report exists: {report_exists}, DuckDuckGo mentioned: {report_mentions_duckduckgo}, Strict: {report_mentions_strict}")
PYEOF

echo "=== Export Complete ==="
