#!/bin/bash
set -e

echo "=== Exporting Blended Enrollment Campaign results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use Python to query DB and build a clean JSON result
cat > /tmp/extract_blended_result.py << 'PYEOF'
import subprocess
import json
import os
import sys

def query(sql):
    """Run a MySQL query inside the Vicidial container, return raw output."""
    cmd = [
        "docker", "exec", "vicidial",
        "mysql", "-ucron", "-p1234", "-D", "asterisk",
        "-N", "-B", "-e", sql
    ]
    try:
        out = subprocess.check_output(cmd, stderr=subprocess.DEVNULL)
        return out.decode("utf-8").strip()
    except subprocess.CalledProcessError:
        return ""

def parse_rows(raw, headers):
    """Parse tab-separated MySQL output into list of dicts."""
    rows = []
    if not raw:
        return rows
    for line in raw.split("\n"):
        if not line:
            continue
        parts = line.split("\t")
        if len(parts) >= len(headers):
            rows.append(dict(zip(headers, parts[:len(headers)])))
    return rows

# 1. Campaign
campaign_raw = query(
    "SELECT campaign_id, campaign_name, active, dial_method, auto_dial_level, "
    "campaign_recording, campaign_cid, campaign_script, allow_closers, closer_campaigns "
    "FROM vicidial_campaigns WHERE campaign_id='PSHLTH26'"
)
campaign_headers = [
    "campaign_id", "campaign_name", "active", "dial_method", "auto_dial_level",
    "campaign_recording", "campaign_cid", "campaign_script", "allow_closers", "closer_campaigns"
]
campaigns = parse_rows(campaign_raw, campaign_headers)

# 2. List
list_raw = query(
    "SELECT list_id, list_name, campaign_id, active "
    "FROM vicidial_lists WHERE list_id='8800'"
)
lists = parse_rows(list_raw, ["list_id", "list_name", "campaign_id", "active"])

# 3. Lead count
lead_count_raw = query("SELECT COUNT(*) FROM vicidial_list WHERE list_id='8800'")
try:
    lead_count = int(lead_count_raw)
except (ValueError, TypeError):
    lead_count = 0

# 4. Script (use HEX for text to avoid escaping issues)
script_raw = query(
    "SELECT script_id, script_name, active, HEX(script_text) "
    "FROM vicidial_scripts WHERE script_id='PS_ENROLL'"
)
script_headers = ["script_id", "script_name", "active", "text_hex"]
scripts = parse_rows(script_raw, script_headers)
for s in scripts:
    try:
        s["script_text"] = bytes.fromhex(s.pop("text_hex")).decode("utf-8")
    except Exception:
        s["script_text"] = ""
        s.pop("text_hex", None)

# 5. Campaign statuses
status_raw = query(
    "SELECT status, status_name, selectable, human_answered, sale, "
    "customer_contact, not_interested, unworkable, scheduled_callback "
    "FROM vicidial_campaign_statuses WHERE campaign_id='PSHLTH26'"
)
status_headers = [
    "status", "status_name", "selectable", "human_answered", "sale",
    "customer_contact", "not_interested", "unworkable", "scheduled_callback"
]
statuses = parse_rows(status_raw, status_headers)

# 6. Call Time
ct_raw = query(
    "SELECT call_time_id, call_time_name, ct_default_start, ct_default_stop, "
    "ct_saturday_start, ct_saturday_stop, ct_sunday_start, ct_sunday_stop "
    "FROM vicidial_call_times WHERE call_time_id='PS_HOURS'"
)
ct_headers = [
    "call_time_id", "call_time_name", "ct_default_start", "ct_default_stop",
    "ct_saturday_start", "ct_saturday_stop", "ct_sunday_start", "ct_sunday_stop"
]
call_times = parse_rows(ct_raw, ct_headers)

# 7. Voicemail
vm_raw = query(
    "SELECT voicemail_id, fullname, pass, active "
    "FROM vicidial_voicemail WHERE voicemail_id='8800'"
)
voicemails = parse_rows(vm_raw, ["voicemail_id", "fullname", "pass", "active"])

# 8. Inbound Group
ig_raw = query(
    "SELECT group_id, group_name, active, call_time_id, "
    "after_hours_action, after_hours_voicemail, after_hours_message_filename "
    "FROM vicidial_inbound_groups WHERE group_id='PS_INBOUND'"
)
ig_headers = [
    "group_id", "group_name", "active", "call_time_id",
    "after_hours_action", "after_hours_voicemail", "after_hours_message_filename"
]
inbound_groups = parse_rows(ig_raw, ig_headers)

# 9. Lead Recycling
lr_raw = query(
    "SELECT campaign_id, status, attempt_delay, attempt_maximum, active "
    "FROM vicidial_lead_recycle WHERE campaign_id='PSHLTH26'"
)
lr_headers = ["campaign_id", "status", "attempt_delay", "attempt_maximum", "active"]
lead_recycles = parse_rows(lr_raw, lr_headers)

# Assemble result
result = {
    "task_start": int(open("/tmp/task_start_time.txt").read().strip()) if os.path.exists("/tmp/task_start_time.txt") else 0,
    "task_end": TASK_END,
    "campaign": campaigns[0] if campaigns else None,
    "list": lists[0] if lists else None,
    "lead_count": lead_count,
    "script": scripts[0] if scripts else None,
    "statuses": statuses,
    "call_time": call_times[0] if call_times else None,
    "voicemail": voicemails[0] if voicemails else None,
    "inbound_group": inbound_groups[0] if inbound_groups else None,
    "lead_recycles": lead_recycles,
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

# Inject the end timestamp into the Python script
sed -i "s/TASK_END/${TASK_END}/g" /tmp/extract_blended_result.py

python3 /tmp/extract_blended_result.py

chmod 666 /tmp/task_result.json
rm -f /tmp/extract_blended_result.py

echo "=== Export complete ==="
