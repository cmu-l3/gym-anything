#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Decathlon Scoring Calculator Task ==="

# Record start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
DOCS_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# ==========================================
# 1. Create Scoring Rules Text File
# ==========================================
RULES_PATH="$DOCS_DIR/scoring_rules.txt"
cat > "$RULES_PATH" << 'EOF'
WORLD ATHLETICS (IAAF) DECATHLON SCORING RULES
----------------------------------------------
The decathlon consists of 10 events. Points are calculated based on three parameters (A, B, and C) specific to each event. 

TRACK EVENTS (100m, 400m, 110m Hurdles, 1500m):
Formula: Points = INT(A * (B - P)^C)
(Where P is the athlete's performance in seconds. If P > B, points = 0)

FIELD EVENTS (Long Jump, Shot Put, High Jump, Discus, Pole Vault, Javelin):
Formula: Points = INT(A * (P - B)^C)
(Where P is the athlete's performance in centimeters or meters. If P < B, points = 0)

IMPORTANT NOTES:
- "INT" means taking the integer part of the number (rounding down).
- "^" represents "to the power of" (exponentiation).
- Pay close attention to the units (e.g., Jumps are usually in cm, Throws in m). The raw results provided already match the correct units for the parameters.
EOF
chown ga:ga "$RULES_PATH"

# ==========================================
# 2. Generate Data (Parameters & Results)
# ==========================================
cat > /tmp/generate_decathlon_data.py << 'PYEOF'
import csv
import random
import os

workspace = "/home/ga/Documents/Spreadsheets"

# --- Parameters ---
# Format: Event, Type, A, B, C
parameters = [
    ["100m", "Track", 25.4347, 18.0, 1.81],
    ["Long_Jump_cm", "Field", 0.14354, 220.0, 1.4],
    ["Shot_Put_m", "Field", 51.39, 1.5, 1.05],
    ["High_Jump_cm", "Field", 0.8465, 75.0, 1.42],
    ["400m", "Track", 1.53775, 82.0, 1.81],
    ["110m_Hurdles", "Track", 5.74352, 28.5, 1.92],
    ["Discus_m", "Field", 12.91, 4.0, 1.1],
    ["Pole_Vault_cm", "Field", 0.2797, 100.0, 1.35],
    ["Javelin_m", "Field", 10.14, 7.0, 1.08],
    ["1500m", "Track", 0.03768, 480.0, 1.85]
]

with open(os.path.join(workspace, "iaaf_parameters.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Event", "Type", "A", "B", "C"])
    writer.writerows(parameters)

# --- Raw Results ---
random.seed(12345)
athletes = [
    "Ashton Eaton", "Kevin Mayer", "Damian Warner", "Roman Sebrle", 
    "Tomas Dvorak", "Trey Hardee", "Daley Thompson", "Dan O'Brien", 
    "Bryan Clay", "Erki Nool", "Pierce LePage", "Lindon Victor", 
    "Ayden Owens-Delerme", "Leo Neugebauer", "Kyle Garland", 
    "Harrison Williams", "Johannes Erm", "Sander Skotheim", 
    "Karel Tilga", "Janek Oiglane", "Niklas Kaul", "Arthur Abele", 
    "Ilya Shkurenyov", "Maicel Uibo", "Rico Freimuth", "Eelco Sintnicolaas", 
    "Leonel Suarez", "Michael Smith", "Dave Johnson", "Christian Plaziat"
]

results = []
for a in athletes:
    results.append([
        a,
        round(random.uniform(10.2, 11.4), 2),      # 100m (s)
        int(random.uniform(690, 810)),             # LJ (cm)
        round(random.uniform(13.5, 16.5), 2),      # SP (m)
        int(random.uniform(192, 212)),             # HJ (cm)
        round(random.uniform(46.5, 51.5), 2),      # 400m (s)
        round(random.uniform(13.6, 15.2), 2),      # 110mH (s)
        round(random.uniform(42.0, 52.0), 2),      # DT (m)
        int(random.uniform(460, 540)),             # PV (cm)
        round(random.uniform(55.0, 72.0), 2),      # JT (m)
        round(random.uniform(255.0, 295.0), 2)     # 1500m (s)
    ])

with open(os.path.join(workspace, "decathlon_raw_results.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["Athlete", "100m_s", "Long_Jump_cm", "Shot_Put_m", "High_Jump_cm", "400m_s", "110m_Hurdles_s", "Discus_m", "Pole_Vault_cm", "Javelin_m", "1500m_s"])
    writer.writerows(results)
PYEOF

python3 /tmp/generate_decathlon_data.py
chown -R ga:ga "$WORKSPACE_DIR"

# ==========================================
# 3. Finalize Setup
# ==========================================
# Take initial screenshot of desktop state before agent acts
su - ga -c "DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null" || true

echo "=== Setup complete ==="