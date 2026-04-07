#!/bin/bash
echo "=== Exporting supernova_candidate_triage results ==="

source /workspace/scripts/task_utils.sh

# Take final proof screenshot
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
OBS_DIR="/home/ga/Observations"

# Collect newly created FITS frame info
FITS_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for target in ['AT2026a', 'AT2026b', 'AT2026c', 'AT2026d']:
        pattern = os.path.join('$OBS_DIR', target, 'fresh', '*.fits')
        for f in glob.glob(pattern) + glob.glob(pattern.replace('.fits', '.fit')):
            try:
                stat = os.stat(f)
                files.append({
                    'target': target,
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Collect newly generated archival PNG info
PNG_INFO=$(python3 -c "
import os, json, glob
files = []
try:
    for target in ['AT2026a', 'AT2026b', 'AT2026c', 'AT2026d']:
        pattern = os.path.join('$OBS_DIR', target, 'archive', '*.png')
        for f in glob.glob(pattern):
            try:
                stat = os.stat(f)
                files.append({
                    'target': target,
                    'name': os.path.basename(f),
                    'path': f,
                    'size': stat.st_size,
                    'mtime': stat.st_mtime
                })
            except: pass
except: pass
print(json.dumps(files))
" 2>/dev/null || echo "[]")

# Extract report content for parsing
REPORT_PATH="/home/ga/Observations/triage_report.txt"
REPORT_EXISTS="false"
REPORT_MTIME=0
REPORT_B64=""

if [ -f "$REPORT_PATH" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_PATH" 2>/dev/null || echo "0")
    REPORT_B64=$(head -n 50 "$REPORT_PATH" | base64 -w 0 2>/dev/null || echo "")
fi

REPORT_EXISTS_PY=$([ "$REPORT_EXISTS" = "true" ] && echo "True" || echo "False")

# Generate structured JSON
python3 - << PYEOF
import json

result = {
    "task_start": $TASK_START,
    "timestamp": $(date +%s),
    "fits_files": $FITS_INFO,
    "png_files": $PNG_INFO,
    "report_exists": $REPORT_EXISTS_PY,
    "report_mtime": $REPORT_MTIME,
    "report_b64": "$REPORT_B64"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
print("Result written to /tmp/task_result.json")
PYEOF

echo "=== Export complete ==="