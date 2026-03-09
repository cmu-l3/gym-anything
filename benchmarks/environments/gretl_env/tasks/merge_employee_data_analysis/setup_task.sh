#!/bin/bash
set -e
echo "=== Setting up Task: Merge Employee Data Analysis ==="

source /workspace/scripts/task_utils.sh

# Directories
DATA_DIR="/home/ga/Documents/gretl_data"
OUTPUT_DIR="/home/ga/Documents/gretl_output"
mkdir -p "$DATA_DIR" "$OUTPUT_DIR"
chown ga:ga "$DATA_DIR" "$OUTPUT_DIR"

# Source Data (using cps5_small from POE5 as base)
SOURCE_GDT="$GRETL_MASTER_DATA_DIR/cps5_small.gdt"
PAYROLL_CSV="$DATA_DIR/payroll.csv"
HR_CSV="$DATA_DIR/hr_records.csv"

# Ensure source exists, fallback to system paths if needed
if [ ! -f "$SOURCE_GDT" ]; then
    echo "Searching for cps5_small.gdt..."
    SOURCE_GDT=$(find /usr/share/gretl -name "cps5_small.gdt" 2>/dev/null | head -1)
fi

if [ -z "$SOURCE_GDT" ] || [ ! -f "$SOURCE_GDT" ]; then
    echo "ERROR: cps5_small.gdt not found. Cannot generate task data."
    exit 1
fi

echo "Using source data: $SOURCE_GDT"

# Generate CSVs using gretlcli
# We create an 'emp_id' variable based on the index to serve as the join key
# payroll.csv: emp_id, wage
# hr_records.csv: emp_id, educ, exper, female
cat << EOF > /tmp/gen_data.inp
open "$SOURCE_GDT" --quiet
series emp_id = index
store "$PAYROLL_CSV" emp_id wage --csv
store "$HR_CSV" emp_id educ exper female --csv
quit
EOF

echo "Generating CSV files..."
gretlcli -b /tmp/gen_data.inp > /dev/null

# Clean up and set permissions
rm -f /tmp/gen_data.inp
chown ga:ga "$PAYROLL_CSV" "$HR_CSV"
chmod 644 "$PAYROLL_CSV" "$HR_CSV"

# Verify generation
if [ -f "$PAYROLL_CSV" ] && [ -f "$HR_CSV" ]; then
    echo "Data generation successful."
    echo "Payroll size: $(wc -l < "$PAYROLL_CSV") lines"
    echo "HR Records size: $(wc -l < "$HR_CSV") lines"
else
    echo "ERROR: Failed to generate CSV files."
    exit 1
fi

# Clean previous outputs
rm -f "$OUTPUT_DIR/wage_gap_results.txt"
rm -f "$OUTPUT_DIR/merged_data.gdt"

# Record start time
date +%s > /tmp/task_start_time.txt

# Launch Gretl EMPTY (no dataset)
echo "Launching Gretl..."
kill_gretl
launch_gretl "" "/home/ga/gretl_task.log"

# Wait for window and maximize
wait_for_gretl 60
maximize_gretl
focus_gretl

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="