#!/bin/bash
echo "=== Exporting bootstrap_birthwt_inference result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
OUTPUT_DIR="/home/ga/RProjects/output"

take_screenshot /tmp/task_final.png

# Paths
CI_CSV="$OUTPUT_DIR/bootstrap_ci.csv"
PERM_CSV="$OUTPUT_DIR/permutation_tests.csv"
COMP_CSV="$OUTPUT_DIR/parametric_vs_bootstrap.csv"
PLOT_PNG="$OUTPUT_DIR/bootstrap_figures.png"
SCRIPT="$OUTPUT_DIR/../bootstrap_analysis.R"

# Helper function to check file stats
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        local size=$(stat -c %s "$f" 2>/dev/null || echo "0")
        local is_new="false"
        if [ "$mtime" -gt "$TASK_START" ]; then is_new="true"; fi
        echo "{\"exists\": true, \"is_new\": $is_new, \"size\": $size, \"path\": \"$f\"}"
    else
        echo "{\"exists\": false, \"is_new\": false, \"size\": 0, \"path\": \"$f\"}"
    fi
}

# Python script to parse the CSVs and extract validation metrics
# This runs inside the container to process the files locally
PYTHON_PARSER=$(cat <<PYEOF
import csv
import json
import os
import sys

results = {}

def safe_float(x):
    try: return float(x)
    except: return None

# 1. Parse Bootstrap CI CSV
ci_path = "$CI_CSV"
ci_data = {"rows": 0, "cols": [], "stats": {}}
if os.path.exists(ci_path):
    try:
        with open(ci_path, 'r') as f:
            reader = csv.DictReader(f)
            ci_data["cols"] = reader.fieldnames
            for row in reader:
                ci_data["rows"] += 1
                stat = row.get("statistic", "").strip()
                if stat:
                    ci_data["stats"][stat] = {
                        "observed": safe_float(row.get("observed")),
                        "boot_se": safe_float(row.get("boot_se")),
                        "ci_bca_lower": safe_float(row.get("ci_bca_lower")),
                        "ci_bca_upper": safe_float(row.get("ci_bca_upper"))
                    }
    except Exception as e:
        ci_data["error"] = str(e)
results["bootstrap_ci"] = ci_data

# 2. Parse Permutation CSV
perm_path = "$PERM_CSV"
perm_data = {"rows": 0, "cols": [], "tests": {}}
if os.path.exists(perm_path):
    try:
        with open(perm_path, 'r') as f:
            reader = csv.DictReader(f)
            perm_data["cols"] = reader.fieldnames
            for row in reader:
                perm_data["rows"] += 1
                test = row.get("test_name", "").strip()
                if test:
                    perm_data["tests"][test] = {
                        "p_perm": safe_float(row.get("p_value_permutation")),
                        "p_class": safe_float(row.get("p_value_classical")),
                        "n_perm": safe_float(row.get("n_permutations"))
                    }
    except Exception as e:
        perm_data["error"] = str(e)
results["permutation"] = perm_data

# 3. Parse Comparison CSV
comp_path = "$COMP_CSV"
comp_data = {"rows": 0, "cols": [], "comparisons": {}}
if os.path.exists(comp_path):
    try:
        with open(comp_path, 'r') as f:
            reader = csv.DictReader(f)
            comp_data["cols"] = reader.fieldnames
            for row in reader:
                comp_data["rows"] += 1
                stat = row.get("statistic", "").strip()
                if stat:
                    comp_data["comparisons"][stat] = {
                        "rel_width": safe_float(row.get("relative_width"))
                    }
    except:
        pass
results["comparison"] = comp_data

print(json.dumps(results))
PYEOF
)

# Run the python parser
PARSED_DATA=$(python3 -c "$PYTHON_PARSER" 2>/dev/null || echo "{}")

# Check R script content for required packages/functions
SCRIPT_CONTENT_CHECK="false"
if [ -f "$SCRIPT" ]; then
    if grep -q "boot(" "$SCRIPT" && grep -q "boot.ci" "$SCRIPT"; then
        SCRIPT_CONTENT_CHECK="true"
    fi
fi

# Assemble final JSON
cat > /tmp/temp_result.json <<EOF
{
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)",
    "files": {
        "bootstrap_ci": $(check_file "$CI_CSV"),
        "permutation": $(check_file "$PERM_CSV"),
        "comparison": $(check_file "$COMP_CSV"),
        "plot": $(check_file "$PLOT_PNG"),
        "script": $(check_file "$SCRIPT")
    },
    "script_content_valid": $SCRIPT_CONTENT_CHECK,
    "parsed_data": $PARSED_DATA
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm /tmp/temp_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="