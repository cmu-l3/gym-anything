#!/bin/bash
set -e
echo "=== Setting up compute_variable_ttest task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Verify BFI25.csv exists and has sufficient data
BFI_FILE="/home/ga/Documents/Jamovi/BFI25.csv"
if [ ! -f "$BFI_FILE" ]; then
    echo "ERROR: BFI25.csv not found"
    exit 1
fi

# Pre-compute ground truth values for verification using Python
# We calculate the expected means and t-stats so verification is robust
python3 << 'PYEOF'
import csv
import statistics
import math
import json

data = []
with open("/home/ga/Documents/Jamovi/BFI25.csv") as f:
    reader = csv.DictReader(f)
    for row in reader:
        try:
            # Parse items
            a1 = int(row['A1'])
            a2 = int(row['A2'])
            a3 = int(row['A3'])
            a4 = int(row['A4'])
            a5 = int(row['A5'])
            gender = int(row['gender'])
            
            # Logic: A1r = 7 - A1
            a1r = 7 - a1
            
            # Logic: Agreeableness = Mean(A1r, A2, A3, A4, A5)
            agree = statistics.mean([a1r, a2, a3, a4, a5])
            
            data.append({'gender': gender, 'agree': agree})
        except ValueError:
            continue

males = [d['agree'] for d in data if d['gender'] == 1]
females = [d['agree'] for d in data if d['gender'] == 2]

male_mean = statistics.mean(males)
female_mean = statistics.mean(females)

# Welch's t-test (default in Jamovi often, but Student's is also common)
# We will calculate Student's t-test values here as standard reference
n1, n2 = len(males), len(females)
var1 = statistics.variance(males)
var2 = statistics.variance(females)

# Pooled variance for Student's t-test
dof = n1 + n2 - 2
pool_var = ((n1 - 1) * var1 + (n2 - 1) * var2) / dof
se = math.sqrt(pool_var * (1/n1 + 1/n2))
t_stat = (male_mean - female_mean) / se

results = {
    "male_mean": round(male_mean, 4),
    "female_mean": round(female_mean, 4),
    "t_stat": round(t_stat, 4),
    "n_males": n1,
    "n_females": n2
}

with open("/tmp/ground_truth.json", "w") as f:
    json.dump(results, f)
    
print(f"Ground truth calculated: {results}")
PYEOF

chmod 644 /tmp/ground_truth.json

# Kill any existing Jamovi instances
pkill -f "org.jamovi.jamovi" 2>/dev/null || true
pkill -f "jamovi" 2>/dev/null || true
sleep 2

# Launch Jamovi with BFI25.csv
echo "Launching Jamovi with BFI25.csv..."
su - ga -c "setsid /usr/local/bin/launch-jamovi /home/ga/Documents/Jamovi/BFI25.csv > /tmp/jamovi_task.log 2>&1 &"

# Wait for Jamovi window to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "jamovi"; then
        echo "Jamovi window detected after ${i}s"
        break
    fi
    sleep 1
done

sleep 5

# Maximize and focus Jamovi
DISPLAY=:1 wmctrl -r "jamovi" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "jamovi" 2>/dev/null || true

# Dismiss any dialogs (like first run welcome)
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="