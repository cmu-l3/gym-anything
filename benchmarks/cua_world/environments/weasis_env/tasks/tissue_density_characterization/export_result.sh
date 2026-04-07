#!/usr/bin/env bash
set -e

# ─── Source shared utilities ────────────────────────────────────────────────
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 import -window root "$1" 2>/dev/null || DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# ─── Configuration ──────────────────────────────────────────────────────────
EXPORT_DIR="/home/ga/DICOM/exports/tissue_char"
RESULT_PREFIX="tissue_char"
RESULT_FILE="/tmp/${RESULT_PREFIX}_result.json"

# ─── Take final screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/${RESULT_PREFIX}_end.png

# ─── Read start timestamp ──────────────────────────────────────────────────
TASK_START=$(cat /tmp/${RESULT_PREFIX}_start_ts 2>/dev/null || echo 0)

# ─── Collect results via Python (safer JSON handling) ──────────────────────
python3 << PYEOF
import json
import os
import re

task_start = int("${TASK_START}" or "0")
export_dir = "${EXPORT_DIR}"

result = {
    "task_start": task_start,
    "img_exists": False,
    "img_size": 0,
    "img_new": False,
    "rpt_exists": False,
    "rpt_size": 0,
    "rpt_new": False,
    "rpt_content": "",
    "parsed": {}
}

# ── Check density_analysis.png (also accept .jpg/.jpeg) ──
img_path = None
for ext in ["png", "jpg", "jpeg"]:
    candidate = os.path.join(export_dir, "density_analysis." + ext)
    if os.path.isfile(candidate):
        img_path = candidate
        break

if img_path:
    result["img_exists"] = True
    result["img_size"] = os.path.getsize(img_path)
    img_mtime = int(os.path.getmtime(img_path))
    result["img_new"] = img_mtime >= task_start

# ── Check density_report.txt ──
rpt_path = os.path.join(export_dir, "density_report.txt")
if os.path.isfile(rpt_path):
    result["rpt_exists"] = True
    result["rpt_size"] = os.path.getsize(rpt_path)
    rpt_mtime = int(os.path.getmtime(rpt_path))
    result["rpt_new"] = rpt_mtime >= task_start
    try:
        with open(rpt_path, "r", errors="replace") as f:
            result["rpt_content"] = f.read(3000)
    except Exception:
        result["rpt_content"] = ""

# ── Parse report content for key values ──
content = result["rpt_content"]
parsed = {}

# Peak slice number
m = re.search(r'[Ss]lice[:\s#]*(\d+)', content)
if not m:
    m = re.search(r'[Pp]eak[:\s]*(\d+)', content)
parsed["slice_num"] = int(m.group(1)) if m else None

# Transverse diameter
m = re.search(r'(?:[Tt]ransverse|[Dd]iameter|[Cc]ardiac|[Ww]idth)[:\s]*(\d+\.?\d*)\s*(?:mm)?', content)
if not m:
    m = re.search(r'(\d{2,3}\.?\d*)\s*mm', content)
parsed["diameter_mm"] = float(m.group(1)) if m else None

# Soft-tissue mean HU
m = re.search(r'[Ss]oft[\s-]*[Tt]issue.*?[Mm]ean\s*(?:HU)?[:\s]*(-?\d+\.?\d*)', content)
if not m:
    m = re.search(r'[Ss]oft[\s-]*[Tt]issue.*?(-?\d+\.?\d*)\s*HU', content)
if not m:
    m = re.search(r'[Mm]ean\s*HU[:\s]*(-?\d+\.?\d*)', content)
if not m:
    m = re.search(r'[Mm]ean[:\s]*(-?\d+\.?\d*)\s*HU', content)
parsed["st_mean_hu"] = float(m.group(1)) if m else None

# Soft-tissue std dev
m = re.search(r'[Ss]td\s*[Dd]ev(?:iation)?[:\s]*(\d+\.?\d*)', content)
if not m:
    m = re.search(r'[Ss]igma[:\s]*(\d+\.?\d*)', content)
parsed["st_std"] = float(m.group(1)) if m else None

# Bone mean HU
m = re.search(r'[Bb]one.*?[Mm]ean\s*(?:HU)?[:\s]*(-?\d+\.?\d*)', content)
if not m:
    m = re.search(r'[Bb]one.*?(-?\d+\.?\d*)\s*HU', content)
if not m:
    m = re.search(r'[Vv]ertebr.*?[Mm]ean\s*(?:HU)?[:\s]*(-?\d+\.?\d*)', content)
parsed["bone_mean_hu"] = float(m.group(1)) if m else None

# Ratio
m = re.search(r'[Rr]atio[:\s]*(\d+\.?\d*)', content)
parsed["ratio"] = float(m.group(1)) if m else None

# Tissue classification
m = re.search(r'(?:[Cc]lass(?:ification)?|[Tt]issue\s*[Tt]ype)[:\s]*(fat|water|soft[\s-]*tissue|dense|calcified)', content, re.IGNORECASE)
if not m:
    # Broader search for the classification keyword anywhere
    m = re.search(r'\b(soft[\s-]*tissue|fat|water|dense|calcified)\b', content, re.IGNORECASE)
parsed["classification"] = m.group(1).lower().replace("-", " ").strip() if m else None

result["parsed"] = parsed

# ── Write result JSON ──
with open("${RESULT_FILE}", "w") as f:
    json.dump(result, f, indent=2)
os.chmod("${RESULT_FILE}", 0o666)

print("Export result written to ${RESULT_FILE}")
print("  Image: exists={}, size={}, new={}".format(result["img_exists"], result["img_size"], result["img_new"]))
print("  Report: exists={}, size={}, new={}".format(result["rpt_exists"], result["rpt_size"], result["rpt_new"]))
print("  Parsed: {}".format(json.dumps(parsed)))
PYEOF

echo "=== tissue_density_characterization export complete ==="
