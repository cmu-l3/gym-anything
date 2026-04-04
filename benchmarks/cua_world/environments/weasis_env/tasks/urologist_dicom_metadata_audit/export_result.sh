#!/bin/bash
echo "=== Exporting urologist_dicom_metadata_audit result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        DISPLAY=:1 import -window root "${1:-/tmp/screenshot.png}" 2>/dev/null || \
        DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true
    }
fi

take_screenshot /tmp/urologist_metadata_end_screenshot.png

TASK_START=$(cat /tmp/urologist_metadata_start_ts 2>/dev/null || echo "0")
EXPORT_DIR="/home/ga/DICOM/exports"
REPORT_FILE="$EXPORT_DIR/metadata_audit_report.txt"
STUDY_DIR="/home/ga/DICOM/studies/renal_audit"

# --- Check current DICOM metadata values ---
python3 << 'PYEOF'
import os, json

try:
    import pydicom
except ImportError:
    result = {"error": "pydicom not available"}
    with open("/tmp/urologist_metadata_audit_result.json", "w") as f:
        json.dump(result, f)
    exit(0)

study_dir = "/home/ga/DICOM/studies/renal_audit"
task_start = int(open("/tmp/urologist_metadata_start_ts").read().strip()) if os.path.exists("/tmp/urologist_metadata_start_ts") else 0

# Read current DICOM tag values
sex_values = set()
body_part_values = set()
referring_physician_values = set()
files_checked = 0

for root, dirs, files in os.walk(study_dir):
    for fname in files:
        fpath = os.path.join(root, fname)
        try:
            ds = pydicom.dcmread(fpath, force=True)
            sex_values.add(str(getattr(ds, 'PatientSex', '')))
            body_part_values.add(str(getattr(ds, 'BodyPartExamined', '')))
            ref_phys = str(getattr(ds, 'ReferringPhysicianName', ''))
            referring_physician_values.add(ref_phys)
            files_checked += 1
        except Exception:
            continue

# Check report
report_file = "/home/ga/DICOM/exports/metadata_audit_report.txt"
report_exists = os.path.exists(report_file)
report_is_new = False
report_size = 0
report_mentions_sex = False
report_mentions_body_part = False
report_mentions_physician = False

if report_exists:
    report_size = os.path.getsize(report_file)
    report_mtime = int(os.path.getmtime(report_file))
    report_is_new = report_mtime > task_start
    with open(report_file, errors='replace') as f:
        text = f.read().lower()
    report_mentions_sex = any(k in text for k in ['patient sex', 'patientsex', 'sex', '0010,0040', 'gender'])
    report_mentions_body_part = any(k in text for k in ['body part', 'bodypart', 'body_part', '0018,0015', 'abdomen', 'head'])
    report_mentions_physician = any(k in text for k in ['referring', 'physician', '0008,0090', 'doctor', 'dr.'])

# Determine if corrections were made
sex_corrected = 'M' in sex_values and 'F' not in sex_values
body_part_corrected = any(v.upper() in ['ABDOMEN', 'CHEST', 'TORSO', 'BODY'] for v in body_part_values) and 'HEAD' not in [v.upper() for v in body_part_values]
physician_corrected = any(v.strip() != '' for v in referring_physician_values) and '' not in referring_physician_values

result = {
    "task_start": task_start,
    "files_checked": files_checked,
    "current_sex_values": list(sex_values),
    "current_body_part_values": list(body_part_values),
    "current_physician_values": list(referring_physician_values),
    "sex_corrected": sex_corrected,
    "body_part_corrected": body_part_corrected,
    "physician_corrected": physician_corrected,
    "report_exists": report_exists,
    "report_is_new": report_is_new,
    "report_size": report_size,
    "report_mentions_sex": report_mentions_sex,
    "report_mentions_body_part": report_mentions_body_part,
    "report_mentions_physician": report_mentions_physician,
}

with open("/tmp/urologist_metadata_audit_result.json", "w") as f:
    json.dump(result, f, indent=2)

print("Result:")
print(json.dumps(result, indent=2))
PYEOF

chmod 666 /tmp/urologist_metadata_audit_result.json 2>/dev/null || true

echo ""
echo "=== Export Complete ==="
