#!/bin/bash
echo "=== Exporting Protein Structure NMA Result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_end.png

# Paths
CSV_PATH="/home/ga/RProjects/output/flexible_residues.csv"
PLOT_PATH="/home/ga/RProjects/output/nma_fluctuations.png"
PDB_PATH="/home/ga/RProjects/output/mode7_trajectory.pdb"

# Check CSV
CSV_EXISTS="false"
CSV_IS_NEW="false"
LID_DOMAIN_FLEXIBLE="false"
NMP_DOMAIN_FLEXIBLE="false"
CSV_ROW_COUNT=0

if [ -f "$CSV_PATH" ]; then
    CSV_EXISTS="true"
    if file_modified_after "$CSV_PATH" "$TASK_START"; then
        CSV_IS_NEW="true"
    fi
    CSV_ROW_COUNT=$(wc -l < "$CSV_PATH" || echo "0")

    # Analyze CSV content using Python
    # AdK LID domain is approx 120-160, NMP is approx 30-60
    # We check if these regions are represented in the high fluctuation list
    DOMAINS_CHECK=$(python3 << PYEOF
import csv
import sys

try:
    lid_count = 0
    nmp_count = 0
    with open("$CSV_PATH", 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                # Handle flexible column naming
                res_col = next(col for col in row.keys() if 'residue' in col.lower() or 'resno' in col.lower())
                val_col = next(col for col in row.keys() if 'fluctuation' in col.lower() or 'rmsf' in col.lower() or 'value' in col.lower())
                
                res_num = int(row[res_col])
                val = float(row[val_col])
                
                if val > 1.0: # Basic check
                    if 120 <= res_num <= 160:
                        lid_count += 1
                    if 30 <= res_num <= 60:
                        nmp_count += 1
            except (ValueError, StopIteration):
                continue
    
    print(f"{lid_count} {nmp_count}")
except Exception:
    print("0 0")
PYEOF
)
    LID_COUNT=$(echo "$DOMAINS_CHECK" | awk '{print $1}')
    NMP_COUNT=$(echo "$DOMAINS_CHECK" | awk '{print $2}')
    
    # Thresholds: Expect at least some residues in these regions to be flagged
    if [ "$LID_COUNT" -ge 5 ]; then LID_DOMAIN_FLEXIBLE="true"; fi
    if [ "$NMP_COUNT" -ge 5 ]; then NMP_DOMAIN_FLEXIBLE="true"; fi
fi

# Check Plot
PLOT_EXISTS="false"
PLOT_IS_NEW="false"
PLOT_SIZE_KB=0
if [ -f "$PLOT_PATH" ]; then
    PLOT_EXISTS="true"
    if file_modified_after "$PLOT_PATH" "$TASK_START"; then
        PLOT_IS_NEW="true"
    fi
    PLOT_SIZE_KB=$(du -k "$PLOT_PATH" | cut -f1)
fi

# Check Trajectory PDB
PDB_EXISTS="false"
PDB_IS_NEW="false"
PDB_SIZE_KB=0
PDB_HAS_MODELS="false"

if [ -f "$PDB_PATH" ]; then
    PDB_EXISTS="true"
    if file_modified_after "$PDB_PATH" "$TASK_START"; then
        PDB_IS_NEW="true"
    fi
    PDB_SIZE_KB=$(du -k "$PDB_PATH" | cut -f1)
    
    # Check if it looks like a multi-model PDB (trajectory)
    MODEL_COUNT=$(grep "^MODEL" "$PDB_PATH" | wc -l)
    if [ "$MODEL_COUNT" -gt 1 ]; then
        PDB_HAS_MODELS="true"
    fi
fi

# Check bio3d installation
BIO3D_INSTALLED="false"
if R --vanilla --slave -e "quit(status=!require('bio3d', quietly=TRUE))"; then
    BIO3D_INSTALLED="true"
fi

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "bio3d_installed": $BIO3D_INSTALLED,
    "csv_exists": $CSV_EXISTS,
    "csv_is_new": $CSV_IS_NEW,
    "csv_row_count": $CSV_ROW_COUNT,
    "lid_domain_flexible": $LID_DOMAIN_FLEXIBLE,
    "nmp_domain_flexible": $NMP_DOMAIN_FLEXIBLE,
    "lid_count": ${LID_COUNT:-0},
    "nmp_count": ${NMP_COUNT:-0},
    "plot_exists": $PLOT_EXISTS,
    "plot_is_new": $PLOT_IS_NEW,
    "plot_size_kb": $PLOT_SIZE_KB,
    "pdb_exists": $PDB_EXISTS,
    "pdb_is_new": $PDB_IS_NEW,
    "pdb_has_models": $PDB_HAS_MODELS,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="