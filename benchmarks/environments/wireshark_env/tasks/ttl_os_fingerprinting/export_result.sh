#!/bin/bash
echo "=== Exporting TTL OS Fingerprinting Result ==="

source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Paths
REPORT_CSV="/home/ga/Documents/captures/ttl_fingerprint_report.csv"
SUMMARY_TXT="/home/ga/Documents/captures/ttl_fingerprint_summary.txt"
GT_CSV="/tmp/ttl_ground_truth/ground_truth.csv"
GT_STATS="/tmp/ttl_ground_truth/ground_truth_stats.json"

# Check file existence and timestamps
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
if [ -f "$REPORT_CSV" ]; then
    REPORT_EXISTS="true"
    MTIME=$(stat -c %Y "$REPORT_CSV")
    if [ "$MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

SUMMARY_EXISTS="false"
if [ -f "$SUMMARY_TXT" ]; then
    SUMMARY_EXISTS="true"
fi

# Compare User CSV with Ground Truth using Python in the container
# We output a JSON verification report to be used by verifier.py
VERIFICATION_JSON=$(mktemp /tmp/verification.XXXXXX.json)

python3 << PYEOF
import csv
import json
import os
import re

report_csv = "$REPORT_CSV"
gt_csv = "$GT_CSV"
summary_txt = "$SUMMARY_TXT"
gt_stats_file = "$GT_STATS"
output_json = "$VERIFICATION_JSON"

result = {
    "csv_valid": False,
    "row_count": 0,
    "metrics": {
        "completeness": 0.0,
        "ttl_accuracy": 0.0,
        "initial_ttl_accuracy": 0.0,
        "hop_count_accuracy": 0.0,
        "os_classification_accuracy": 0.0
    },
    "summary_checks": {
        "total_count_correct": False,
        "os_counts_match": 0.0,
        "min_max_hop_correct": False
    }
}

try:
    # 1. Load Ground Truth
    gt_data = {}
    with open(gt_csv, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            gt_data[row['ip']] = row
            
    with open(gt_stats_file, 'r') as f:
        gt_stats = json.load(f)

    # 2. Load User CSV
    if os.path.exists(report_csv):
        user_data = {}
        try:
            with open(report_csv, 'r') as f:
                # Handle potential BOM or weird encoding issues roughly
                content = f.read()
                f.seek(0)
                
                # Check for header
                if "ip" in content.lower() and "observed" in content.lower():
                    result["csv_valid"] = True
                    reader = csv.DictReader(f)
                    # Normalize headers (strip spaces)
                    reader.fieldnames = [name.strip().lower() for name in reader.fieldnames]
                    
                    for row in reader:
                        # Find IP column
                        ip_val = None
                        for k in row:
                            if k == 'ip': ip_val = row[k]
                        
                        if ip_val and ip_val in gt_data:
                            user_data[ip_val] = row
                            
                    result["row_count"] = len(user_data)
        except Exception as e:
            result["csv_error"] = str(e)

        # 3. Compare Data
        if result["csv_valid"] and gt_data:
            total_gt = len(gt_data)
            matched_ips = len(user_data)
            result["metrics"]["completeness"] = matched_ips / total_gt if total_gt > 0 else 0

            correct_ttl = 0
            correct_initial = 0
            correct_hop = 0
            correct_os = 0

            for ip, u_row in user_data.items():
                g_row = gt_data[ip]
                
                # Loose integer parsing
                try:
                    if int(float(u_row.get('observed_ttl', -1))) == int(g_row['observed_ttl']):
                        correct_ttl += 1
                except: pass
                
                try:
                    if int(float(u_row.get('initial_ttl', -1))) == int(g_row['initial_ttl']):
                        correct_initial += 1
                except: pass
                
                try:
                    # Allow off-by-one error in hop count logic if consistent
                    u_hop = int(float(u_row.get('hop_count', -999)))
                    g_hop = int(g_row['hop_count'])
                    if abs(u_hop - g_hop) <= 1:
                        correct_hop += 1
                except: pass
                
                # Fuzzy string matching for OS
                u_os = str(u_row.get('os_family', '')).lower()
                g_os = str(g_row['os_family']).lower()
                # Remove common separators
                u_os_clean = re.sub(r'[^a-z]', '', u_os)
                g_os_clean = re.sub(r'[^a-z]', '', g_os)
                
                if g_os_clean in u_os_clean or u_os_clean in g_os_clean:
                    correct_os += 1
                # Special cases
                if "linux" in g_os and "linux" in u_os: correct_os += 1
                elif "windows" in g_os and "windows" in u_os: correct_os += 1
                elif "cisco" in g_os and "cisco" in u_os: correct_os += 1
                
            # Normalize counts > matched_ips due to double counting logic above? No, logic is simple if/elif
            # Actually I double counted in the special cases block potentially? No, just elifs.
            # Fix double counting just in case
            if correct_os > matched_ips: correct_os = matched_ips

            div = matched_ips if matched_ips > 0 else 1
            result["metrics"]["ttl_accuracy"] = correct_ttl / div
            result["metrics"]["initial_ttl_accuracy"] = correct_initial / div
            result["metrics"]["hop_count_accuracy"] = correct_hop / div
            result["metrics"]["os_classification_accuracy"] = correct_os / div

    # 4. Check Summary Text
    if os.path.exists(summary_txt) and result["csv_valid"]:
        try:
            with open(summary_txt, 'r') as f:
                text = f.read().lower()
            
            # Check total count
            if str(len(gt_data)) in text:
                result["summary_checks"]["total_count_correct"] = True
            
            # Check min/max IPs
            if gt_stats.get("max_hop_ip", "").lower() in text:
                result["summary_checks"]["min_max_hop_correct"] = True
            
            # Check OS counts
            matched_os_counts = 0
            total_os_categories = len(gt_stats.get("os_counts", {}))
            for os_name, count in gt_stats.get("os_counts", {}).items():
                if str(count) in text and os_name.split('/')[0].lower() in text:
                    matched_os_counts += 1
            
            if total_os_categories > 0:
                result["summary_checks"]["os_counts_match"] = matched_os_counts / total_os_categories
                
        except Exception as e:
            result["summary_error"] = str(e)

except Exception as e:
    result["critical_error"] = str(e)

with open(output_json, 'w') as f:
    json.dump(result, f)
PYEOF

# Read the python verification result
cat "$VERIFICATION_JSON" > /tmp/verification_data.json

# Create final result JSON for framework
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "summary_exists": $SUMMARY_EXISTS,
    "verification_data": $(cat /tmp/verification_data.json),
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Save to shared path
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" "$VERIFICATION_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="