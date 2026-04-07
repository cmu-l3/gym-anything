#!/bin/bash
set -e
echo "=== Exporting supernova_photometric_classification results ==="

source /workspace/scripts/task_utils.sh

# ── Final screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── Read task start time ─────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── Read telescope position ──────────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null || echo "unknown")
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null || echo "unknown")

# ── Collect FITS file metadata from all subdirectories ───────────────
FITS_JSON="[]"

python3 - "$TASK_START" << 'PYEOF'
import os, sys, json, glob

task_start = int(sys.argv[1]) if sys.argv[1] != "0" else 0
base = "/home/ga/Images/sn_followup"
fits_list = []

for root, dirs, files in os.walk(base):
    for fname in sorted(files):
        if not fname.lower().endswith(".fits"):
            continue
        fpath = os.path.join(root, fname)
        try:
            stat = os.stat(fpath)
            rel = os.path.relpath(root, base)
            entry = {
                "name": fname,
                "path": fpath,
                "subdir": rel,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime)
            }
            # Try to read FITS headers with astropy
            try:
                from astropy.io import fits as afits
                with afits.open(fpath) as hdul:
                    hdr = hdul[0].header
                    entry["filter"] = str(hdr.get("FILTER", ""))
                    entry["exptime"] = float(hdr.get("EXPTIME", 0))
                    entry["imagetyp"] = str(hdr.get("IMAGETYP", hdr.get("FRAME", "")))
                    entry["naxis1"] = int(hdr.get("NAXIS1", 0))
                    entry["naxis2"] = int(hdr.get("NAXIS2", 0))
            except Exception:
                pass
            fits_list.append(entry)
        except Exception:
            pass

with open("/tmp/_fits_inventory.json", "w") as f:
    json.dump(fits_list, f)
PYEOF

FITS_JSON=$(cat /tmp/_fits_inventory.json 2>/dev/null || echo "[]")

# ── Check finding chart ──────────────────────────────────────────────
CHART_EXISTS="false"
CHART_SIZE=0
CHART_MTIME=0
CHART_PATH="/home/ga/Images/sn_followup/charts/finding_chart.png"
if [ -f "$CHART_PATH" ]; then
    CHART_EXISTS="true"
    CHART_SIZE=$(stat -c%s "$CHART_PATH" 2>/dev/null || echo "0")
    CHART_MTIME=$(stat -c%Y "$CHART_PATH" 2>/dev/null || echo "0")
fi

# ── Check Python reduction script ────────────────────────────────────
SCRIPT_EXISTS="false"
SCRIPT_B64=""
SCRIPT_PATH="/home/ga/reduce_photometry.py"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
    SCRIPT_B64=$(base64 -w 0 "$SCRIPT_PATH" 2>/dev/null || echo "")
fi

# ── Check classification.json ────────────────────────────────────────
CLASS_EXISTS="false"
CLASS_CONTENT="null"
CLASS_PATH="/home/ga/classification.json"
if [ -f "$CLASS_PATH" ]; then
    CLASS_EXISTS="true"
    CLASS_CONTENT=$(cat "$CLASS_PATH" 2>/dev/null || echo "null")
fi

# ── Check ATel draft ─────────────────────────────────────────────────
ATEL_EXISTS="false"
ATEL_B64=""
ATEL_MTIME=0
ATEL_PATH="/home/ga/Documents/atel_draft.txt"
if [ -f "$ATEL_PATH" ]; then
    ATEL_EXISTS="true"
    ATEL_B64=$(head -80 "$ATEL_PATH" | base64 -w 0 2>/dev/null || echo "")
    ATEL_MTIME=$(stat -c%Y "$ATEL_PATH" 2>/dev/null || echo "0")
fi

# ── Write result JSON ────────────────────────────────────────────────
cat > /tmp/task_result.json << RESULT_EOF
{
  "task_start": $TASK_START,
  "timestamp": $(date +%s),
  "telescope": {
    "final_ra": "$FINAL_RA",
    "final_dec": "$FINAL_DEC"
  },
  "fits_files": $FITS_JSON,
  "finding_chart": {
    "exists": $CHART_EXISTS,
    "size": $CHART_SIZE,
    "mtime": $CHART_MTIME
  },
  "reduction_script": {
    "exists": $SCRIPT_EXISTS,
    "content_b64": "$SCRIPT_B64"
  },
  "classification_json": {
    "exists": $CLASS_EXISTS,
    "content": $CLASS_CONTENT
  },
  "atel_draft": {
    "exists": $ATEL_EXISTS,
    "content_b64": "$ATEL_B64",
    "mtime": $ATEL_MTIME
  }
}
RESULT_EOF

echo "=== Export complete: /tmp/task_result.json ==="
