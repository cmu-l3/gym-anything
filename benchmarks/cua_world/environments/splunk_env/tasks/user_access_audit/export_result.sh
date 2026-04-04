#!/bin/bash
echo "=== Exporting user_access_audit result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end_screenshot.png

ANALYSIS=$(python3 - << 'PYEOF'
import sys, json, subprocess, os, re

try:
    with open('/tmp/audit_initial_saved_searches.json') as f:
        initial_ss = json.load(f)
except:
    initial_ss = []

try:
    with open('/tmp/audit_initial_lookups.json') as f:
        initial_lookups = json.load(f)
except:
    initial_lookups = []

try:
    with open('/tmp/audit_initial_lookup_defs.json') as f:
        initial_lookup_defs = json.load(f)
except:
    initial_lookup_defs = []

# Check for ANY new lookup file
lookup_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/lookup-table-files?output_mode=json&count=0'],
    capture_output=True, text=True
)

lookup_file_exists = False
lookup_row_count = 0
new_lookup_name = ""

try:
    lookup_data = json.loads(lookup_result.stdout)
    for entry in lookup_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_lookups:
            lookup_file_exists = True
            new_lookup_name = name
            break
except:
    pass

# Try to read lookup file from filesystem
if lookup_file_exists and new_lookup_name:
    lookup_paths = [
        f'/opt/splunk/etc/apps/search/lookups/{new_lookup_name}',
        f'/opt/splunk/etc/users/admin/search/lookups/{new_lookup_name}',
    ]
    for path in lookup_paths:
        if os.path.exists(path):
            try:
                with open(path) as f:
                    lines = f.readlines()
                data_lines = [l for l in lines[1:] if l.strip()]
                lookup_row_count = len(data_lines)
                break
            except:
                pass

# Also check filesystem directly as fallback for any new .csv
if not lookup_file_exists:
    for app_dir in ['/opt/splunk/etc/apps/search/lookups',
                    '/opt/splunk/etc/users/admin/search/lookups']:
        if os.path.exists(app_dir):
            for fname in os.listdir(app_dir):
                if fname.endswith('.csv') and fname not in initial_lookups:
                    lookup_file_exists = True
                    new_lookup_name = fname
                    try:
                        with open(os.path.join(app_dir, fname)) as f:
                            lines = f.readlines()
                        data_lines = [l for l in lines[1:] if l.strip()]
                        lookup_row_count = len(data_lines)
                    except:
                        pass
                    break

# Check for ANY new lookup definition
ld_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/data/transforms/lookups?output_mode=json&count=0'],
    capture_output=True, text=True
)

lookup_def_exists = False
try:
    ld_data = json.loads(ld_result.stdout)
    for entry in ld_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_lookup_defs:
            lookup_def_exists = True
            break
except:
    pass

# Check for ANY new saved search that uses a lookup
ss_result = subprocess.run(
    ['curl', '-sk', '-u', 'admin:SplunkAdmin1!',
     'https://localhost:8089/servicesNS/-/-/saved/searches?output_mode=json&count=0'],
    capture_output=True, text=True
)

found_report = False
report_name = ""
report_search = ""
report_uses_lookup = False

try:
    ss_data = json.loads(ss_result.stdout)
    for entry in ss_data.get('entry', []):
        name = entry.get('name', '')
        if name not in initial_ss:
            search_text = entry.get('content', {}).get('search', '')
            low = search_text.lower()
            uses_lookup = ('| lookup' in low or 'inputlookup' in low or
                           'outputlookup' in low)
            if not found_report or uses_lookup:
                found_report = True
                report_name = name
                report_search = search_text
                report_uses_lookup = uses_lookup
                if uses_lookup:
                    break
except:
    pass

output = {
    "lookup_file_exists": lookup_file_exists,
    "lookup_row_count": lookup_row_count,
    "new_lookup_name": new_lookup_name,
    "lookup_def_exists": lookup_def_exists,
    "found_report": found_report,
    "report_name": report_name,
    "report_search": report_search,
    "report_uses_lookup": report_uses_lookup
}
print(json.dumps(output))
PYEOF
)

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << ENDJSON
{
    "analysis": ${ANALYSIS},
    "export_timestamp": "$(date -Iseconds)"
}
ENDJSON

safe_write_json "$TEMP_JSON" /tmp/user_access_audit_result.json
echo "Result saved to /tmp/user_access_audit_result.json"
cat /tmp/user_access_audit_result.json
echo "=== Export complete ==="
