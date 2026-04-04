#!/bin/bash
echo "=== Exporting Cox Survival Cancer Result ==="

TASK_START=$(cat /tmp/cox_survival_cancer_start_ts 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 import -window root /tmp/cox_survival_cancer_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/cox_survival_cancer_end_screenshot.png 2>/dev/null || true

COX_CSV="/home/ga/RProjects/output/gbsg_cox_results.csv"
PH_CSV="/home/ga/RProjects/output/gbsg_ph_test.csv"
KM_PNG="/home/ga/RProjects/output/gbsg_km_curves.png"
FOREST_PNG="/home/ga/RProjects/output/gbsg_forest_plot.png"

# --- Cox results CSV ---
COX_EXISTS=false
COX_IS_NEW=false
COX_HAS_HR=false
COX_HAS_PVALUE=false
COX_HR_HORTHY_VALID=false
COX_ROW_COUNT=0

if [ -f "$COX_CSV" ]; then
    COX_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$COX_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && COX_IS_NEW=true

    COX_ROW_COUNT=$(wc -l < "$COX_CSV" 2>/dev/null || echo "0")

    python3 << PYEOF
import csv, sys, os

path = "$COX_CSV"
try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    # Check for HR and p_value columns (flexible naming)
    hr_col = next((h for h in headers if 'hazard' in h or h in ('hr', 'hr_estimate', 'ratio')), None)
    pv_col = next((h for h in headers if 'p_value' in h or 'pval' in h or h == 'p'), None)
    cov_col = next((h for h in headers if 'covariate' in h or 'term' in h or 'variable' in h), None)

    has_hr = hr_col is not None
    has_pv = pv_col is not None
    print(f"has_hr={str(has_hr).lower()}")
    print(f"has_pv={str(has_pv).lower()}")

    # Check horTh HR < 1 (hormonal therapy should be protective)
    if cov_col and hr_col:
        for row in rows:
            cov = str(row.get(cov_col, '')).lower()
            if 'horth' in cov or 'hormon' in cov or 'hort' in cov:
                try:
                    hr_val = float(row[hr_col])
                    # Accept range 0.3–1.2 (slight flexibility around 1)
                    if 0.3 <= hr_val <= 1.2:
                        print("horthy_valid=true")
                    else:
                        print("horthy_valid=false")
                except:
                    print("horthy_valid=false")
                break
        else:
            print("horthy_valid=unknown")
    else:
        print("horthy_valid=unknown")

except Exception as e:
    print(f"has_hr=false")
    print(f"has_pv=false")
    print(f"horthy_valid=false")
    sys.exit(0)
PYEOF
fi

# Parse Python output
COX_PY_OUTPUT=$(python3 << PYEOF 2>/dev/null
import csv, sys

path = "$COX_CSV"
if not __import__('os').path.exists(path):
    print("has_hr=false|has_pv=false|horthy_valid=false")
    sys.exit(0)

try:
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        headers = [h.lower().strip() for h in (reader.fieldnames or [])]
        rows = list(reader)

    hr_col = next((h for h in headers if 'hazard' in h or h in ('hr', 'hr_estimate', 'ratio')), None)
    pv_col = next((h for h in headers if 'p_value' in h or 'pval' in h or h == 'p'), None)
    cov_col = next((h for h in headers if 'covariate' in h or 'term' in h or 'variable' in h), None)

    has_hr = str(hr_col is not None).lower()
    has_pv = str(pv_col is not None).lower()
    horthy_valid = "unknown"

    if cov_col and hr_col:
        for row in rows:
            cov = str(row.get(cov_col, '')).lower()
            if 'horth' in cov or 'hormon' in cov or 'hort' in cov:
                try:
                    hr_val = float(row[hr_col])
                    horthy_valid = "true" if 0.3 <= hr_val <= 1.2 else "false"
                except:
                    horthy_valid = "false"
                break

    print(f"has_hr={has_hr}|has_pv={has_pv}|horthy_valid={horthy_valid}")
except Exception as e:
    print("has_hr=false|has_pv=false|horthy_valid=false")
PYEOF
)

IFS='|' read -r HR_FIELD PV_FIELD HORTHY_FIELD <<< "$COX_PY_OUTPUT"
COX_HAS_HR=$(echo "$HR_FIELD" | cut -d= -f2)
COX_HAS_PVALUE=$(echo "$PV_FIELD" | cut -d= -f2)
COX_HR_HORTHY_VALID=$(echo "$HORTHY_FIELD" | cut -d= -f2)

# --- PH test CSV ---
PH_EXISTS=false
PH_IS_NEW=false
PH_HAS_CHISQ=false
PH_ROW_COUNT=0

if [ -f "$PH_CSV" ]; then
    PH_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$PH_CSV" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && PH_IS_NEW=true

    PH_ROW_COUNT=$(wc -l < "$PH_CSV" 2>/dev/null || echo "0")

    PH_CHECK=$(python3 -c "
import csv, os
path = '$PH_CSV'
if not os.path.exists(path):
    print('false')
    exit()
with open(path, newline='') as f:
    reader = csv.DictReader(f)
    headers = [h.lower().strip() for h in (reader.fieldnames or [])]
chisq_col = next((h for h in headers if 'chisq' in h or 'chi' in h or 'stat' in h), None)
print(str(chisq_col is not None).lower())
" 2>/dev/null || echo "false")
    PH_HAS_CHISQ="$PH_CHECK"
fi

# --- KM PNG ---
KM_EXISTS=false
KM_IS_NEW=false
KM_SIZE=0
KM_IS_PNG=false

if [ -f "$KM_PNG" ]; then
    KM_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$KM_PNG" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && KM_IS_NEW=true
    KM_SIZE=$(stat -c %s "$KM_PNG" 2>/dev/null || echo "0")
    # Validate PNG header
    PNG_HEADER=$(python3 -c "
with open('$KM_PNG', 'rb') as f:
    h = f.read(8)
print(str(h == b'\x89PNG\r\n\x1a\n').lower())
" 2>/dev/null || echo "false")
    KM_IS_PNG="$PNG_HEADER"
fi

# --- Forest plot PNG ---
FOREST_EXISTS=false
FOREST_IS_NEW=false
FOREST_SIZE=0
FOREST_IS_PNG=false

if [ -f "$FOREST_PNG" ]; then
    FOREST_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$FOREST_PNG" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && FOREST_IS_NEW=true
    FOREST_SIZE=$(stat -c %s "$FOREST_PNG" 2>/dev/null || echo "0")
    PNG_HEADER=$(python3 -c "
with open('$FOREST_PNG', 'rb') as f:
    h = f.read(8)
print(str(h == b'\x89PNG\r\n\x1a\n').lower())
" 2>/dev/null || echo "false")
    FOREST_IS_PNG="$PNG_HEADER"
fi

# --- Script modification check ---
SCRIPT="/home/ga/RProjects/survival_analysis.R"
SCRIPT_EXISTS=false
SCRIPT_IS_MODIFIED=false
SCRIPT_HAS_COXPH=false
SCRIPT_HAS_COXZPH=false

if [ -f "$SCRIPT" ]; then
    SCRIPT_EXISTS=true
    FILE_MTIME=$(stat -c %Y "$SCRIPT" 2>/dev/null || echo "0")
    [ "$FILE_MTIME" -gt "$TASK_START" ] && SCRIPT_IS_MODIFIED=true
    grep -q "coxph(" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_COXPH=true
    grep -q "cox.zph(" "$SCRIPT" 2>/dev/null && SCRIPT_HAS_COXZPH=true
fi

cat > /tmp/cox_survival_cancer_result.json << EOF
{
    "task_start": $TASK_START,
    "cox_csv": {
        "exists": $COX_EXISTS,
        "is_new": $COX_IS_NEW,
        "has_hr_column": $COX_HAS_HR,
        "has_pvalue_column": $COX_HAS_PVALUE,
        "horthy_hr_valid": "$COX_HR_HORTHY_VALID",
        "row_count": $COX_ROW_COUNT
    },
    "ph_test_csv": {
        "exists": $PH_EXISTS,
        "is_new": $PH_IS_NEW,
        "has_chisq_column": $PH_HAS_CHISQ,
        "row_count": $PH_ROW_COUNT
    },
    "km_png": {
        "exists": $KM_EXISTS,
        "is_new": $KM_IS_NEW,
        "size_bytes": $KM_SIZE,
        "is_valid_png": $KM_IS_PNG
    },
    "forest_png": {
        "exists": $FOREST_EXISTS,
        "is_new": $FOREST_IS_NEW,
        "size_bytes": $FOREST_SIZE,
        "is_valid_png": $FOREST_IS_PNG
    },
    "script": {
        "exists": $SCRIPT_EXISTS,
        "modified": $SCRIPT_IS_MODIFIED,
        "has_coxph": $SCRIPT_HAS_COXPH,
        "has_cox_zph": $SCRIPT_HAS_COXZPH
    }
}
EOF

echo "=== Export Complete ==="
echo "Result: /tmp/cox_survival_cancer_result.json"
cat /tmp/cox_survival_cancer_result.json
