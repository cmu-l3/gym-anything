#!/bin/bash
# Export script for IHC H-Score Analysis

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting IHC H-Score Results ==="

# 1. Take final screenshot
take_screenshot /tmp/task_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# 2. Generate Ground Truth using a headless macro
# We do this NOW to ensure we measure the exact same image the agent used
echo "Generating ground truth data..."
GT_MACRO="/tmp/calc_ground_truth.ijm"
cat > "$GT_MACRO" << 'MACROEOF'
// Open the sample image (same command as agent uses)
run("Fluorescent Cells (400K)");

// Split channels to get Red
run("Split Channels");
selectWindow("Fluorescent Cells (400K) (red)");

// Set measurements to Area only
run("Set Measurements...", "area limit redirect=None decimal=3");

// Measure Total (>= 20)
setThreshold(20, 255);
run("Measure");
totalArea = getResult("Area", 0);
run("Clear Results");

// Measure Low (20-99)
setThreshold(20, 99);
run("Measure");
lowArea = getResult("Area", 0);
run("Clear Results");

// Measure Medium (100-179)
setThreshold(100, 179);
run("Measure");
medArea = getResult("Area", 0);
run("Clear Results");

// Measure High (180-255)
setThreshold(180, 255);
run("Measure");
highArea = getResult("Area", 0);
run("Clear Results");

// Calculate GT H-Score
// Avoid division by zero
hScore = 0;
if (totalArea > 0) {
    pctLow = (lowArea / totalArea) * 100;
    pctMed = (medArea / totalArea) * 100;
    pctHigh = (highArea / totalArea) * 100;
    hScore = (1 * pctLow) + (2 * pctMed) + (3 * pctHigh);
}

// Print to log in JSON format
print("{");
print("  \"gt_total_area\": " + totalArea + ",");
print("  \"gt_low_area\": " + lowArea + ",");
print("  \"gt_med_area\": " + medArea + ",");
print("  \"gt_high_area\": " + highArea + ",");
print("  \"gt_h_score\": " + hScore);
print("}");
MACROEOF

# Run the macro headless and capture output
FIJI_PATH=$(find_fiji_executable)
"$FIJI_PATH" --headless -macro "$GT_MACRO" > /tmp/ground_truth_output.txt 2>&1

# Extract JSON from macro output
sed -n '/^{/,/^}/p' /tmp/ground_truth_output.txt > /tmp/ground_truth_metrics.json

# 3. Parse User Result and Merge with Ground Truth
python3 << 'PYEOF'
import json, csv, os, re

result_file = "/home/ga/ImageJ_Data/results/h_score_report.csv"
gt_file = "/tmp/ground_truth_metrics.json"
task_start_file = "/tmp/task_start_timestamp"

output = {
    "file_exists": False,
    "file_created_during_task": False,
    "user_data": {},
    "ground_truth": {},
    "parse_error": None
}

# Load Ground Truth
if os.path.exists(gt_file):
    try:
        with open(gt_file, 'r') as f:
            output["ground_truth"] = json.load(f)
    except Exception as e:
        output["ground_truth"] = {"error": str(e)}

# Load User Data
if os.path.exists(result_file):
    output["file_exists"] = True
    
    # Check timestamp
    try:
        task_start = int(open(task_start_file).read().strip())
        file_mtime = int(os.path.getmtime(result_file))
        if file_mtime > task_start:
            output["file_created_during_task"] = True
    except:
        pass

    try:
        with open(result_file, 'r', encoding='utf-8', errors='replace') as f:
            reader = csv.DictReader(f)
            rows = list(reader)
            
            # Helper to find values flexibly
            def find_val(rows, keywords):
                for row in rows:
                    # Check first column (often "Tier" or "Label")
                    first_val = list(row.values())[0] if row else ""
                    if any(k in str(first_val).lower() for k in keywords):
                        # Found the row, now find the Area column
                        for k, v in row.items():
                            if "area" in k.lower():
                                return float(v)
                return 0.0

            def find_h_score(rows):
                # Check for explicit H-Score row
                for row in rows:
                    for v in row.values():
                        if "h_score" in str(v).lower() or "h-score" in str(v).lower():
                            # The score might be in the next column
                            pass 
                
                # Check for column named "H-Score" or "Score" or similar
                # Or check for the last numeric value in a summary section
                # Simplified: Look for a row where key is "H_Score" or similar
                for row in rows:
                    first_val = list(row.values())[0] if row else ""
                    if "score" in str(first_val).lower():
                        # Try to find the numeric value in this row
                        for v in row.values():
                            try:
                                val = float(v)
                                if 0 <= val <= 300: return val
                            except: continue
                return 0.0

            # Extract Areas
            output["user_data"]["low_area"] = find_val(rows, ["low", "1+"])
            output["user_data"]["med_area"] = find_val(rows, ["med", "2+"])
            output["user_data"]["high_area"] = find_val(rows, ["high", "3+"])
            
            # Calculate Total from parts if not explicitly found
            total = find_val(rows, ["total", "sum"])
            if total == 0:
                total = output["user_data"]["low_area"] + output["user_data"]["med_area"] + output["user_data"]["high_area"]
            output["user_data"]["total_area"] = total

            # Extract H-Score
            output["user_data"]["h_score"] = find_h_score(rows)
            
            # If H-Score not found in rows, check if it's a single value in the file
            if output["user_data"]["h_score"] == 0:
                content = open(result_file).read()
                scores = re.findall(r"Score.*?(\d+\.?\d*)", content, re.IGNORECASE)
                if scores:
                    try:
                        val = float(scores[-1])
                        if 0 <= val <= 300: output["user_data"]["h_score"] = val
                    except: pass

    except Exception as e:
        output["parse_error"] = str(e)

with open("/tmp/h_score_result.json", "w") as f:
    json.dump(output, f, indent=2)
PYEOF

echo "=== Export Complete ==="