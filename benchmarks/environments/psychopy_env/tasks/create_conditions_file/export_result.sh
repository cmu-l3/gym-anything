#!/bin/bash
echo "=== Exporting create_conditions_file result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_end.png

# Single Python call for all analysis
python3 << 'PYEOF'
import json
import os
import sys
import csv
import datetime
import subprocess

OUTPUT_FILE = "/home/ga/PsychoPyExperiments/conditions/my_flanker_conditions.csv"
RESULT_FILE = "/tmp/create_conditions_file_result.json"

results = {
    "file_exists": False,
    "file_modified": False,
    "file_size": 0,
    "row_count": 0,
    "has_header": False,
    "has_stimulus_col": False,
    "has_condition_col": False,
    "has_direction_col": False,
    "has_corrans_col": False,
    "has_congruent": False,
    "has_incongruent": False,
    "header_line": "",
    "sample_rows": "",
    "task_start_time": 0,
    "result_nonce": "",
    "timestamp": datetime.datetime.now().isoformat(),
    # Semantic validation
    "has_arrows": False,
    "has_both_directions": False,
    "has_valid_corrans": False,
    "unique_stimuli_count": 0,
    "unique_conditions_count": 0,
}

# Read task start time
try:
    with open("/home/ga/.task_start_time") as f:
        results["task_start_time"] = int(f.read().strip())
except:
    pass

# Read nonce
try:
    with open("/home/ga/.task_nonce") as f:
        results["result_nonce"] = f.read().strip()
except:
    pass

if os.path.isfile(OUTPUT_FILE):
    results["file_exists"] = True
    results["file_size"] = os.path.getsize(OUTPUT_FILE)

    mtime = int(os.path.getmtime(OUTPUT_FILE))
    if mtime > results["task_start_time"]:
        results["file_modified"] = True

    try:
        with open(OUTPUT_FILE, "r", newline="") as f:
            content = f.read()

        results["header_line"] = content.split("\n")[0] if content else ""

        # Get sample rows (first 4 lines)
        lines = content.strip().split("\n")
        results["sample_rows"] = "|".join(lines[:4])

        # Parse CSV
        with open(OUTPUT_FILE, "r", newline="") as f:
            reader = csv.DictReader(f)
            headers = [h.strip().lower() for h in (reader.fieldnames or [])]
            rows = []
            for row in reader:
                rows.append({k.strip().lower(): (v.strip() if v else "") for k, v in row.items()})

        results["row_count"] = len(rows)

        # Check columns
        results["has_stimulus_col"] = "stimulus" in headers
        results["has_condition_col"] = "condition" in headers
        results["has_direction_col"] = "direction" in headers
        results["has_corrans_col"] = any(h in headers for h in ["corrans", "correct", "correctans"])

        col_count = sum([
            results["has_stimulus_col"],
            results["has_condition_col"],
            results["has_direction_col"],
            results["has_corrans_col"],
        ])
        results["has_header"] = col_count >= 3

        # Check conditions
        conditions = set()
        directions = set()
        corrans_values = set()
        stimuli = set()

        for row in rows:
            cond = row.get("condition", "").lower()
            if "incongruent" in cond:
                conditions.add("incongruent")
            elif "congruent" in cond:
                conditions.add("congruent")
            elif "neutral" in cond:
                conditions.add("neutral")

            direction = row.get("direction", "").lower()
            if direction:
                directions.add(direction)

            corrans = row.get("corrans", row.get("correct", row.get("correctans", ""))).lower()
            if corrans:
                corrans_values.add(corrans)

            stim = row.get("stimulus", "")
            if stim:
                stimuli.add(stim)
                if "<" in stim or ">" in stim:
                    results["has_arrows"] = True

        results["has_congruent"] = "congruent" in conditions
        results["has_incongruent"] = "incongruent" in conditions
        results["has_both_directions"] = "left" in directions and "right" in directions
        results["has_valid_corrans"] = "left" in corrans_values and "right" in corrans_values
        results["unique_stimuli_count"] = len(stimuli)
        results["unique_conditions_count"] = len(conditions)

    except Exception as e:
        print(f"CSV analysis error: {e}", file=sys.stderr)

with open(RESULT_FILE, "w") as f:
    json.dump(results, f, indent=2)

os.chmod(RESULT_FILE, 0o666)
print(f"Result saved to {RESULT_FILE}")
PYEOF

cat /tmp/create_conditions_file_result.json
echo "=== Export complete ==="
