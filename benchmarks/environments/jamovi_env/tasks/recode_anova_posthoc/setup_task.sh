#!/bin/bash
set -e
echo "=== Setting up Recode & ANOVA Task ==="

# 1. Record Start Time for Anti-Gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists
DATA_SRC="/opt/jamovi_datasets/Exam Anxiety.csv"
DATA_DST="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

mkdir -p /home/ga/Documents/Jamovi
if [ -f "$DATA_SRC" ]; then
    cp "$DATA_SRC" "$DATA_DST"
    chown ga:ga "$DATA_DST"
    chmod 644 "$DATA_DST"
else
    echo "ERROR: Source dataset not found at $DATA_SRC"
    exit 1
fi

# 3. Calculate Ground Truth Statistics (Python)
# We calculate the expected ANOVA F-statistic and Group Counts based on the specific recoding logic.
# This serves as the "Golden Source" for verification.
cat > /tmp/calculate_ground_truth.py << 'PYEOF'
import pandas as pd
import scipy.stats as stats
import json
import numpy as np

try:
    # Load data
    df = pd.read_csv("/home/ga/Documents/Jamovi/ExamAnxiety.csv")
    
    # Apply recoding logic
    # <= 50 -> Low
    # 50 < x <= 75 -> Medium
    # > 75 -> High
    def recode(x):
        if x <= 50: return "Low"
        elif x <= 75: return "Medium"
        else: return "High"
    
    df['AnxietyLevel'] = df['Anxiety'].apply(recode)
    
    # Calculate group counts
    counts = df['AnxietyLevel'].value_counts().to_dict()
    
    # Calculate ANOVA
    groups = [df[df['AnxietyLevel'] == g]['Exam'].values for g in df['AnxietyLevel'].unique()]
    f_stat, p_val = stats.f_oneway(*groups)
    
    # Calculate means per group
    means = df.groupby('AnxietyLevel')['Exam'].mean().to_dict()
    
    result = {
        "group_counts": counts,
        "f_statistic": float(f_stat),
        "p_value": float(p_val),
        "means": {k: float(v) for k, v in means.items()},
        "groups_found": list(df['AnxietyLevel'].unique())
    }
    
    with open("/tmp/ground_truth.json", "w") as f:
        json.dump(result, f, indent=2)
        
    print("Ground truth calculated successfully.")
    
except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback default values if calculation fails (should not happen with valid data)
    with open("/tmp/ground_truth.json", "w") as f:
        json.dump({"error": str(e)}, f)
PYEOF

python3 /tmp/calculate_ground_truth.py
chown ga:ga /tmp/ground_truth.json

# 4. Clean up previous artifacts
rm -f "/home/ga/Documents/Jamovi/ExamAnxietyRecoded.omv"
rm -f /tmp/task_result.json

# 5. Launch Jamovi (Empty State)
# The task requires the agent to OPEN the file, so we start Jamovi empty.
echo "Launching Jamovi..."
su - ga -c "setsid /usr/local/bin/launch-jamovi > /tmp/jamovi.log 2>&1 &"

# Wait for window
echo "Waiting for Jamovi window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "jamovi"; then
        echo "Jamovi window detected."
        break
    fi
    sleep 1
done

# Maximize
sleep 5
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# 6. Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="