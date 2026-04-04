#!/bin/bash
# Export script for DevTools Network Audit task

echo "=== Exporting DevTools Network Audit Result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Use Python for robust data extraction and JSON generation
python3 << 'PYEOF'
import json, os, re, shutil, sqlite3, tempfile

task_start = 0
try:
    task_start = int(open("/tmp/task_start_timestamp").read().strip())
except:
    pass

# Read baseline visit counts
def read_baseline(path, default=0):
    try:
        return int(open(path).read().strip())
    except:
        return default

initial_bbc = read_baseline("/tmp/dna_initial_bbc")
initial_reuters = read_baseline("/tmp/dna_initial_reuters")
initial_guardian = read_baseline("/tmp/dna_initial_guardian")

# Query Edge history database (copy first to avoid lock issues)
def query_history(query):
    history_path = "/home/ga/.config/microsoft-edge/Default/History"
    if not os.path.exists(history_path):
        return []
    tmp = tempfile.mktemp(suffix=".sqlite3")
    try:
        shutil.copy2(history_path, tmp)
        conn = sqlite3.connect(tmp)
        rows = conn.execute(query).fetchall()
        conn.close()
        return rows
    except Exception as e:
        return []
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)

# Count visits to each target domain
def count_visits(domain):
    rows = query_history(f"SELECT COUNT(*) FROM urls WHERE url LIKE '%{domain}%'")
    return rows[0][0] if rows else 0

bbc_visits = count_visits("bbc.com")
reuters_visits = count_visits("reuters.com")
guardian_visits = count_visits("theguardian.com")

bbc_new = bbc_visits > initial_bbc
reuters_new = reuters_visits > initial_reuters
guardian_new = guardian_visits > initial_guardian

# Analyze the report file
report_path = "/home/ga/Desktop/network_audit_report.txt"
report_exists = os.path.exists(report_path)
report_size = 0
report_mtime = 0
report_modified_after_start = False
has_bbc = False
has_reuters = False
has_guardian = False
has_size_values = False
has_request_count = False

if report_exists:
    stat = os.stat(report_path)
    report_size = stat.st_size
    report_mtime = int(stat.st_mtime)
    report_modified_after_start = report_mtime > task_start

    try:
        content = open(report_path, "r", errors="replace").read().lower()
        has_bbc = "bbc" in content
        has_reuters = "reuters" in content
        has_guardian = "guardian" in content or "theguardian" in content

        # Check for size values: numbers + KB/MB/KiB/MiB/bytes unit
        has_size_values = bool(re.search(r'\d+(\.\d+)?\s*(kb|mb|kib|mib|bytes|b)\b', content, re.IGNORECASE))

        # Check for request count: number + requests/resources/items
        has_request_count = bool(re.search(r'\d+\s*(requests?|resources?|items?|files?)', content, re.IGNORECASE))
    except Exception:
        pass

result = {
    "task": "devtools_network_audit",
    "task_start": task_start,
    "history": {
        "bbc_total_visits": bbc_visits,
        "bbc_new_visits": bbc_new,
        "reuters_total_visits": reuters_visits,
        "reuters_new_visits": reuters_new,
        "guardian_total_visits": guardian_visits,
        "guardian_new_visits": guardian_new
    },
    "report": {
        "exists": report_exists,
        "size_bytes": report_size,
        "modified_after_start": report_modified_after_start,
        "has_bbc": has_bbc,
        "has_reuters": has_reuters,
        "has_guardian": has_guardian,
        "has_size_values": has_size_values,
        "has_request_count": has_request_count
    }
}

with open("/tmp/devtools_network_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Report exists: {report_exists}, size: {report_size} bytes")
print(f"BBC visited: {bbc_new}, Reuters: {reuters_new}, Guardian: {guardian_new}")
print(f"Report has BBC: {has_bbc}, Reuters: {has_reuters}, Guardian: {has_guardian}")
print(f"Has size values: {has_size_values}, Has request count: {has_request_count}")
PYEOF

echo "=== Export Complete ==="
