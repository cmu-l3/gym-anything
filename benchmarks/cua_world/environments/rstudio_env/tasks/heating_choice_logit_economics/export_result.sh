#!/bin/bash
echo "=== Exporting heating_choice_logit_economics result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
take_screenshot /tmp/task_final.png

# Check if mlogit was installed
MLOGIT_INSTALLED=$(R --vanilla --slave -e "cat('mlogit' %in% installed.packages()[,'Package'])" 2>/dev/null || echo "FALSE")

# Run Python script to parse outputs and build JSON
python3 << PYEOF
import sys, os, csv, json

task_start = int("$TASK_START")
out_dir = "/home/ga/RProjects/output"
coefs_file = os.path.join(out_dir, "heating_coefs.csv")
econ_file = os.path.join(out_dir, "heating_economics.csv")
plot_file = os.path.join(out_dir, "heating_shares.png")

data = {
    "task_start": task_start,
    "mlogit_installed": "$MLOGIT_INSTALLED" == "TRUE",
    "coefs_csv_exists": False,
    "coefs_csv_new": False,
    "ic_coef": None,
    "oc_coef": None,
    "econ_csv_exists": False,
    "econ_csv_new": False,
    "tradeoff_ratio": None,
    "plot_exists": False,
    "plot_new": False,
    "plot_size_kb": 0
}

def get_float(s):
    try:
        return float(s.replace('"', '').strip())
    except ValueError:
        return None

# Parse coefficients CSV
if os.path.isfile(coefs_file):
    data["coefs_csv_exists"] = True
    data["coefs_csv_new"] = os.path.getmtime(coefs_file) > task_start
    try:
        with open(coefs_file, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.reader(f)
            for row in reader:
                row_lower = [str(x).lower().strip().replace('"', '') for x in row]
                
                # Check for 'ic'
                if 'ic' in row_lower:
                    for v in row:
                        val = get_float(v)
                        if val is not None and val != 0 and data["ic_coef"] is None:
                            data["ic_coef"] = val
                
                # Check for 'oc'
                if 'oc' in row_lower:
                    for v in row:
                        val = get_float(v)
                        if val is not None and val != 0 and data["oc_coef"] is None:
                            data["oc_coef"] = val
    except Exception as e:
        pass

# Parse economics CSV (trade-off ratio)
if os.path.isfile(econ_file):
    data["econ_csv_exists"] = True
    data["econ_csv_new"] = os.path.getmtime(econ_file) > task_start
    try:
        with open(econ_file, 'r', encoding='utf-8', errors='ignore') as f:
            reader = csv.reader(f)
            for row in reader:
                for v in row:
                    val = get_float(v)
                    if val is not None and 0.1 <= val <= 10.0:
                        data["tradeoff_ratio"] = val
                        break
    except Exception as e:
        pass

# Check plot PNG
if os.path.isfile(plot_file):
    data["plot_exists"] = True
    data["plot_new"] = os.path.getmtime(plot_file) > task_start
    data["plot_size_kb"] = os.path.getsize(plot_file) / 1024.0

# Write to temp JSON file
with open("/tmp/temp_result.json", "w") as f:
    json.dump(data, f)
PYEOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json 2>/dev/null || sudo cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f /tmp/temp_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="