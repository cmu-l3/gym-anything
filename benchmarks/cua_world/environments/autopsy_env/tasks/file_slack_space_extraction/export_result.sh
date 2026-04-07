#!/bin/bash
echo "=== Exporting results for file_slack_space_extraction ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Kill Autopsy to release any locks
kill_autopsy
sleep 2

# Process agent output via Python
python3 << 'PYEOF'
import json, os, re

result = {
    "report_exists": False,
    "report_mtime": 0,
    "target_file": "",
    "logical_size_bytes": "",
    "starting_sector": "",
    "extracted_key": "",
    "start_time": 0,
    "error": ""
}

try:
    with open("/tmp/slack_start_time", "r") as f:
        result["start_time"] = int(f.read().strip())
except Exception:
    pass

report_path = "/home/ga/Reports/slack_extraction_report.txt"
if os.path.exists(report_path):
    result["report_exists"] = True
    result["report_mtime"] = int(os.path.getmtime(report_path))
    
    try:
        with open(report_path, "r", errors="replace") as f:
            content = f.read()

        m_file = re.search(r'TARGET_FILE:\s*(.+)', content, re.IGNORECASE)
        if m_file: result["target_file"] = m_file.group(1).strip()

        m_size = re.search(r'LOGICAL_SIZE_BYTES:\s*(\d+)', content, re.IGNORECASE)
        if m_size: result["logical_size_bytes"] = m_size.group(1).strip()

        m_sector = re.search(r'STARTING_SECTOR:\s*(\d+)', content, re.IGNORECASE)
        if m_sector: result["starting_sector"] = m_sector.group(1).strip()

        m_key = re.search(r'EXTRACTED_KEY:\s*(.+)', content, re.IGNORECASE)
        if m_key: result["extracted_key"] = m_key.group(1).strip()
    except Exception as e:
        result["error"] = f"Error reading report: {str(e)}"

with open("/tmp/slack_extraction_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(f"Export finished. Result JSON written.")
PYEOF

echo "=== Export complete ==="