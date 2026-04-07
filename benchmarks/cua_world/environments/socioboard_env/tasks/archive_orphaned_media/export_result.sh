#!/bin/bash
echo "=== Exporting archive_orphaned_media result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Export current file system state and ground truth into a single JSON
python3 << 'EOF'
import os
import json

src_dir = "/opt/socioboard/socioboard-api/publish/media_uploads"
archive_dir = "/home/ga/archive_orphaned"
report_file = "/home/ga/orphan_report.txt"
gt_file = "/var/backups/.sb_media_state.json"

# Read file system state
src_files = os.listdir(src_dir) if os.path.exists(src_dir) else []
archive_files = os.listdir(archive_dir) if os.path.exists(archive_dir) else []

# Read agent's report
report_content = ""
if os.path.exists(report_file):
    with open(report_file, 'r') as f:
        report_content = f.read().strip()

# Read ground truth
gt_data = {}
if os.path.exists(gt_file):
    with open(gt_file, 'r') as f:
        gt_data = json.load(f)

# Package for verifier
result = {
    "src_files": src_files,
    "archive_files": archive_files,
    "report_content": report_content,
    "ground_truth": gt_data,
    "archive_dir_exists": os.path.exists(archive_dir),
    "report_file_exists": os.path.exists(report_file)
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f)
EOF

# Ensure verifier can read it
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="