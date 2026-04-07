#!/bin/bash
echo "=== Exporting Population Health Age Pyramid Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

OUTPUT_IMG="/home/ga/Documents/age_pyramid.png"
OUTPUT_CSV="/home/ga/Documents/age_data.csv"
SCRIPT_PATH="/home/ga/generate_pyramid.py" # Agent might put it here or in Documents

# Find script if not in home
if [ ! -f "$SCRIPT_PATH" ]; then
    FOUND=$(find /home/ga -name "generate_pyramid.py" | head -n 1)
    if [ -n "$FOUND" ]; then
        SCRIPT_PATH="$FOUND"
    fi
fi

# Check Output Image
IMG_EXISTS="false"
IMG_SIZE="0"
IMG_CREATED_DURING_TASK="false"
if [ -f "$OUTPUT_IMG" ]; then
    IMG_EXISTS="true"
    IMG_SIZE=$(stat -c %s "$OUTPUT_IMG")
    IMG_MTIME=$(stat -c %Y "$OUTPUT_IMG")
    if [ "$IMG_MTIME" -gt "$TASK_START" ]; then
        IMG_CREATED_DURING_TASK="true"
    fi
fi

# Check Output CSV
CSV_EXISTS="false"
if [ -f "$OUTPUT_CSV" ]; then
    CSV_EXISTS="true"
fi

# Check Script
SCRIPT_EXISTS="false"
if [ -f "$SCRIPT_PATH" ]; then
    SCRIPT_EXISTS="true"
fi

# Generate Ground Truth Data for Verification
# We dump the raw age/sex data to a JSON file so the verifier can calculate bins exactly
echo "Generating ground truth data..."
cat > /tmp/generate_ground_truth.py << 'EOF'
import pymysql
import json
import datetime
import pandas as pd

try:
    conn = pymysql.connect(host='localhost', user='root', password='', db='DrTuxTest')
    
    # Query raw data
    df = pd.read_sql("SELECT FchPat_Nee, FchPat_Sexe FROM fchpat", conn)
    
    # Calculate age
    today = datetime.date.today()
    
    def calculate_age(born):
        if not born: return -1
        if isinstance(born, str):
            try:
                born = datetime.datetime.strptime(born, "%Y-%m-%d").date()
            except:
                return -1
        return today.year - born.year - ((today.month, today.day) < (born.month, born.day))

    df['age'] = df['FchPat_Nee'].apply(calculate_age)
    
    # Normalize sex
    df['sex'] = df['FchPat_Sexe'].astype(str).str.upper().str.strip()
    # MedinTux uses 'M' or 'H' for Male, 'F' for Female
    df['sex'] = df['sex'].replace({'H': 'M', 'HOMME': 'M', 'FEMME': 'F'})
    
    # Filter valid ages
    df = df[df['age'] >= 0]
    
    # Create bins
    bins = range(0, 110, 5)
    labels = [f"{i}-{i+4}" for i in range(0, 105, 5)]
    df['age_group'] = pd.cut(df['age'], bins=bins, labels=labels, right=False)
    
    # Group
    grouped = df.groupby(['age_group', 'sex'], observed=False).size().unstack(fill_value=0)
    
    # Ensure M and F columns exist
    if 'M' not in grouped.columns: grouped['M'] = 0
    if 'F' not in grouped.columns: grouped['F'] = 0
    
    result = {
        "bins": grouped.to_dict(orient='index'),
        "total_patients": int(len(df))
    }
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
EOF

python3 /tmp/generate_ground_truth.py > /tmp/ground_truth.json 2>/dev/null || echo '{"error": "Failed to run ground truth script"}' > /tmp/ground_truth.json

# Take final screenshot
take_screenshot /tmp/task_final.png ga

# Prepare files for export (copy to /tmp/ for verifier access via copy_from_env)
cp "$OUTPUT_IMG" /tmp/agent_output.png 2>/dev/null || true
cp "$OUTPUT_CSV" /tmp/agent_data.csv 2>/dev/null || true
cp "$SCRIPT_PATH" /tmp/agent_script.py 2>/dev/null || true

# Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "img_exists": $IMG_EXISTS,
    "img_created_during_task": $IMG_CREATED_DURING_TASK,
    "img_size": $IMG_SIZE,
    "csv_exists": $CSV_EXISTS,
    "script_exists": $SCRIPT_EXISTS,
    "screenshot_path": "/tmp/task_final.png",
    "ground_truth_path": "/tmp/ground_truth.json",
    "agent_csv_path": "/tmp/agent_data.csv",
    "agent_img_path": "/tmp/agent_output.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json
chmod 666 /tmp/ground_truth.json
chmod 666 /tmp/agent_data.csv 2>/dev/null || true
chmod 666 /tmp/agent_output.png 2>/dev/null || true
chmod 666 /tmp/agent_script.py 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"