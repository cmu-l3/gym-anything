#!/bin/bash
set -euo pipefail

echo "=== Setting up Ranked Choice Voting Tabulation Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Source utils if available, otherwise define stubs
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
else
    cleanup_temp_files() { rm -f /tmp/*.log 2>/dev/null || true; }
    kill_onlyoffice() { pkill -f onlyoffice 2>/dev/null || true; }
fi

cleanup_temp_files
kill_onlyoffice ga || true
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Generate the realistic 5,000-row CVR sample
cat > /tmp/generate_cvr.py << 'PYEOF'
import csv
import random

# Use a specific seed to ensure exact deterministic totals matching the task metadata
random.seed(907)

def make_rows(r1, count, r2_dist):
    rows = []
    for r2_cand, r2_count in r2_dist:
        for _ in range(r2_count):
            rows.append([r1, r2_cand, "Undervote"])
    return rows

# Ground truth matching 2022 proportions
peltola_rows = make_rows("Mary Peltola", 1985, [("Sarah Palin", 300), ("Nick Begich", 500), ("Undervote", 1185)])
palin_rows = make_rows("Sarah Palin", 1560, [("Mary Peltola", 200), ("Nick Begich", 800), ("Undervote", 560)])
begich_rows = make_rows("Nick Begich", 1410, [("Sarah Palin", 710), ("Mary Peltola", 405), ("Undervote", 295)])
other_rows = make_rows("Undervote", 45, [("Undervote", 45)])

all_rows = peltola_rows + palin_rows + begich_rows + other_rows
random.shuffle(all_rows)

output_path = '/home/ga/Documents/Spreadsheets/alaska_2022_cvr_sample.csv'
with open(output_path, 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["Record_ID", "Precinct", "Rank_1_Choice", "Rank_2_Choice", "Rank_3_Choice"])
    for i, row in enumerate(all_rows, 10001):
        precinct = f"0{random.randint(1, 40):02d}-{random.randint(100, 999)}"
        writer.writerow([f"CVR-{i}", precinct] + row)

print(f"Successfully generated {len(all_rows)} CVR records.")
PYEOF

sudo -u ga python3 /tmp/generate_cvr.py

# Ensure ONLYOFFICE starts cleanly
echo "Starting ONLYOFFICE Spreadsheet Editor..."
sudo -u ga DISPLAY=:1 onlyoffice-desktopeditors "$WORKSPACE_DIR/alaska_2022_cvr_sample.csv" > /dev/null 2>&1 &

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ONLYOFFICE"; then
        echo "ONLYOFFICE window detected."
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "ONLYOFFICE" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ONLYOFFICE" 2>/dev/null || true
sleep 2

# Take initial screenshot for verification evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="