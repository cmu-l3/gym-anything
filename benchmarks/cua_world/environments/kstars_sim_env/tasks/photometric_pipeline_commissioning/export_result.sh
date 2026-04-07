#!/bin/bash
set -e
echo "=== Exporting photometric_pipeline_commissioning results ==="

source /workspace/scripts/task_utils.sh

# ── Clean temp files from previous runs ──────────────────────────────
rm -f /tmp/_fits_inventory.json /tmp/_export_meta.json /tmp/task_result.json 2>/dev/null || true

# ── Final screenshot ─────────────────────────────────────────────────
take_screenshot /tmp/task_final.png

# ── Read task start time ─────────────────────────────────────────────
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# ── Read telescope position ──────────────────────────────────────────
FINAL_RA=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.RA" 2>/dev/null || echo "unknown")
FINAL_DEC=$(indi_getprop -1 "Telescope Simulator.EQUATORIAL_EOD_COORD.DEC" 2>/dev/null || echo "unknown")

# ── Read focuser position ────────────────────────────────────────────
FOCUS_POS=$(indi_getprop -1 "Focuser Simulator.ABS_FOCUS_POSITION.FOCUS_ABSOLUTE_POSITION" 2>/dev/null || echo "unknown")

# ── Collect FITS file metadata from all directories ──────────────────
python3 - "$TASK_START" << 'PYEOF'
import os, sys, json, glob

task_start = int(sys.argv[1]) if sys.argv[1] != "0" else 0

dirs_to_scan = {
    "focus_test":  "/home/ga/Images/focus_test",
    "bias":        "/home/ga/Calibration/bias",
    "flats_V":     "/home/ga/Calibration/flats_V",
    "sa98_V":      "/home/ga/Science/sa98_V",
    "sa98_B":      "/home/ga/Science/sa98_B",
    "m67_V":       "/home/ga/Science/m67_V",
    "m67_B":       "/home/ga/Science/m67_B",
}

all_fits = []
dir_counts = {}

for label, dirpath in dirs_to_scan.items():
    count = 0
    if not os.path.isdir(dirpath):
        dir_counts[label] = 0
        continue
    for fname in sorted(os.listdir(dirpath)):
        if not fname.lower().endswith(('.fits', '.fit')):
            continue
        fpath = os.path.join(dirpath, fname)
        try:
            stat = os.stat(fpath)
            entry = {
                "name": fname,
                "path": fpath,
                "category": label,
                "size": stat.st_size,
                "mtime": int(stat.st_mtime),
            }
            # Try reading FITS headers
            try:
                from astropy.io import fits as afits
                with afits.open(fpath) as hdul:
                    hdr = hdul[0].header
                    entry["filter"] = str(hdr.get("FILTER", ""))
                    entry["exptime"] = float(hdr.get("EXPTIME", 0))
                    entry["imagetyp"] = str(hdr.get("IMAGETYP", hdr.get("FRAME", "")))
                    entry["naxis1"] = int(hdr.get("NAXIS1", 0))
                    entry["naxis2"] = int(hdr.get("NAXIS2", 0))
                    # Focus position if available
                    fp = hdr.get("FOCUSPOS", hdr.get("FOCUS_POSITION", None))
                    if fp is not None:
                        entry["focus_position"] = int(fp)
            except Exception:
                pass
            all_fits.append(entry)
            if stat.st_size > 2048 and stat.st_mtime > task_start:
                count += 1
        except Exception:
            pass
    dir_counts[label] = count

result = {
    "fits_files": all_fits,
    "dir_counts": dir_counts,
}

with open("/tmp/_fits_inventory.json", "w") as f:
    json.dump(result, f)
PYEOF

FITS_INVENTORY=$(cat /tmp/_fits_inventory.json 2>/dev/null || echo '{"fits_files":[],"dir_counts":{}}')

# ── Check focus script ───────────────────────────────────────────────
FOCUS_SCRIPT_EXISTS="false"
FOCUS_SCRIPT_B64=""
if [ -f "/home/ga/find_best_focus.py" ]; then
    FOCUS_SCRIPT_EXISTS="true"
    FOCUS_SCRIPT_B64=$(base64 -w 0 /home/ga/find_best_focus.py 2>/dev/null || echo "")
fi

# ── Check pipeline script ────────────────────────────────────────────
PIPELINE_SCRIPT_EXISTS="false"
PIPELINE_SCRIPT_B64=""
if [ -f "/home/ga/reduce_and_calibrate.py" ]; then
    PIPELINE_SCRIPT_EXISTS="true"
    PIPELINE_SCRIPT_B64=$(base64 -w 0 /home/ga/reduce_and_calibrate.py 2>/dev/null || echo "")
fi

# ── Check output JSON ────────────────────────────────────────────────
OUTPUT_JSON_EXISTS="false"
if [ -f "/home/ga/Documents/photometric_pipeline.json" ]; then
    OUTPUT_JSON_EXISTS="true"
fi

# ── Write result JSON ────────────────────────────────────────────────
# Write FITS inventory to a temp file (already done above)
# Write other metadata to a separate temp file
cat > /tmp/_export_meta.json << METAEOF
{
    "task_start": $TASK_START,
    "telescope_ra": "$FINAL_RA",
    "telescope_dec": "$FINAL_DEC",
    "focuser_position": "$FOCUS_POS",
    "focus_script_exists": $FOCUS_SCRIPT_EXISTS,
    "focus_script_b64": "$FOCUS_SCRIPT_B64",
    "pipeline_script_exists": $PIPELINE_SCRIPT_EXISTS,
    "pipeline_script_b64": "$PIPELINE_SCRIPT_B64",
    "output_json_exists": $OUTPUT_JSON_EXISTS
}
METAEOF

# Assemble final JSON using Python (handles JSON merging safely)
python3 - << 'PYEOF'
import json, os

# Load FITS inventory
try:
    with open("/tmp/_fits_inventory.json") as f:
        fits_inv = json.load(f)
except Exception:
    fits_inv = {"fits_files": [], "dir_counts": {}}

# Load metadata
try:
    with open("/tmp/_export_meta.json") as f:
        meta = json.load(f)
except Exception:
    meta = {}

# Load output JSON if it exists
output_json_content = None
output_json_path = "/home/ga/Documents/photometric_pipeline.json"
if os.path.isfile(output_json_path):
    try:
        with open(output_json_path) as f:
            output_json_content = json.load(f)
    except Exception:
        pass

import time
result = {
    "task_start": meta.get("task_start", 0),
    "timestamp": int(time.time()),
    "telescope": {
        "final_ra": meta.get("telescope_ra", "unknown"),
        "final_dec": meta.get("telescope_dec", "unknown")
    },
    "focuser_position": meta.get("focuser_position", "unknown"),
    "fits_files": fits_inv.get("fits_files", []),
    "dir_counts": fits_inv.get("dir_counts", {}),
    "focus_script": {
        "exists": meta.get("focus_script_exists", False),
        "content_b64": meta.get("focus_script_b64", "")
    },
    "pipeline_script": {
        "exists": meta.get("pipeline_script_exists", False),
        "content_b64": meta.get("pipeline_script_b64", "")
    },
    "output_json": {
        "exists": meta.get("output_json_exists", False),
        "content": output_json_content
    }
}

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
PYEOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete: /tmp/task_result.json ==="
