#!/bin/bash
echo "=== Exporting allergist_series_contamination_cleanup result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/allergist_contamination_end_screenshot.png

TASK_START=$(cat /tmp/allergist_contamination_start_ts 2>/dev/null || echo "0")
STUDY_DIR="/home/ga/DICOM/studies/airway_series"
QUARANTINE_DIR="/home/ga/DICOM/quarantine"
EXPORT_DIR="/home/ga/DICOM/exports"
REPORT_FILE="$EXPORT_DIR/contamination_report.txt"

# Load contaminant manifest
ORIGINAL_CT=$(cat /tmp/allergist_contamination_original_ct 2>/dev/null || echo "0")
INJECTED_COUNT=$(cat /tmp/allergist_contamination_injected_count 2>/dev/null || echo "0")

# Check which contaminant files remain
python3 << 'PYEOF'
import os, json

study_dir = "/home/ga/DICOM/studies/airway_series"
quarantine_dir = "/home/ga/DICOM/quarantine"
task_start = int(open("/tmp/allergist_contamination_start_ts").read().strip()) if os.path.exists("/tmp/allergist_contamination_start_ts") else 0

# Load manifest
manifest = {}
if os.path.exists("/tmp/allergist_contaminant_manifest.json"):
    with open("/tmp/allergist_contaminant_manifest.json") as f:
        manifest = json.load(f)

contaminant_names = manifest.get("contaminant_filenames", [])
original_ct_count = manifest.get("original_ct_count", 0)
injected_count = manifest.get("contaminant_count", 0)

# Check which contaminant files are still in the study directory
contaminants_remaining = 0
contaminants_removed = 0
for cname in contaminant_names:
    cpath = os.path.join(study_dir, cname)
    if os.path.exists(cpath):
        contaminants_remaining += 1
    else:
        contaminants_removed += 1

# Count current files in study directory
current_total = len([f for f in os.listdir(study_dir) if os.path.isfile(os.path.join(study_dir, f))]) if os.path.isdir(study_dir) else 0

# Count quarantined files
quarantined = len([f for f in os.listdir(quarantine_dir) if os.path.isfile(os.path.join(quarantine_dir, f))]) if os.path.isdir(quarantine_dir) else 0

# Check how many legitimate CT files remain
# A properly cleaned directory should have approximately the original CT count
ct_files_preserved = current_total >= (original_ct_count - 2)  # allow for minor variance

# Check report
report_file = "/home/ga/DICOM/exports/contamination_report.txt"
report_exists = os.path.exists(report_file)
report_is_new = False
report_size = 0
report_mentions_modality = False
report_mentions_count = False

if report_exists:
    report_size = os.path.getsize(report_file)
    report_mtime = int(os.path.getmtime(report_file))
    report_is_new = report_mtime > task_start
    with open(report_file, errors='replace') as f:
        text = f.read().lower()
    report_mentions_modality = any(k in text for k in ['modality', 'ct', 'mr', 'mri', 'magnetic resonance', 'computed tomography'])
    # Check if report mentions a number of files
    import re
    numbers = re.findall(r'\b\d+\b', text)
    report_mentions_count = any(int(n) in range(1, 10) for n in numbers if n.isdigit())

result = {
    "task_start": task_start,
    "contaminants_injected": injected_count,
    "contaminants_remaining": contaminants_remaining,
    "contaminants_removed": contaminants_removed,
    "current_total_files": current_total,
    "original_ct_count": original_ct_count,
    "ct_files_preserved": ct_files_preserved,
    "quarantined_files": quarantined,
    "report_exists": report_exists,
    "report_is_new": report_is_new,
    "report_size": report_size,
    "report_mentions_modality": report_mentions_modality,
    "report_mentions_count": report_mentions_count,
}

with open("/tmp/allergist_contamination_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result:")
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/allergist_contamination_result.json 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
