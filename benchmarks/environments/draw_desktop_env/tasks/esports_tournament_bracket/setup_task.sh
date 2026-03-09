#!/bin/bash
# Setup script for esports_tournament_bracket
# Generates random match results and sets up draw.io

echo "=== Setting up Esports Tournament Bracket Task ==="

# 1. Clean up previous run artifacts
rm -f /home/ga/Desktop/winter_major_bracket.drawio
rm -f /home/ga/Desktop/winter_major_bracket.png
rm -f /home/ga/Desktop/match_results.txt
rm -f /tmp/bracket_ground_truth.json

# 2. Generate Random Match Results & Ground Truth
# We use Python to ensure the logic (A vs B -> Winner) is consistent and saved
python3 << 'PYEOF'
import json
import random

# Pool of realistic esports teams
teams = [
    "T1", "G2 Esports", "Team Liquid", "Cloud9", 
    "Fnatic", "FaZe Clan", "NAVI", "Team Vitality",
    "Gen.G", "DRX", "100 Thieves", "EDG"
]

# Select 8 random teams for the bracket
bracket_teams = random.sample(teams, 8)

# Structure: 
# QF1: T0 vs T1, QF2: T2 vs T3, QF3: T4 vs T5, QF4: T6 vs T7
# SF1: Winner QF1 vs Winner QF2
# SF2: Winner QF3 vs Winner QF4
# Final: Winner SF1 vs Winner SF2

match_log = []
ground_truth = {
    "quarterfinals": [],
    "semifinals": [],
    "finals": [],
    "champion": ""
}

# --- Quarterfinals ---
sf_slots = []
match_log.append("=== WINTER MAJOR QUARTERFINALS ===")
for i in range(0, 8, 2):
    tA = bracket_teams[i]
    tB = bracket_teams[i+1]
    
    # Random score (Best of 3)
    scoreA = 2
    scoreB = random.randint(0, 1)
    if random.choice([True, False]): # Swap winner
        scoreA, scoreB = scoreB, scoreA
    
    winner = tA if scoreA > scoreB else tB
    sf_slots.append(winner)
    
    match_log.append(f"Match {i//2 + 1}: {tA} vs {tB} -> {winner} wins ({scoreA}-{scoreB})")
    ground_truth["quarterfinals"].append(winner)

match_log.append("")

# --- Semifinals ---
final_slots = []
match_log.append("=== WINTER MAJOR SEMIFINALS ===")
for i in range(0, 4, 2):
    tA = sf_slots[i]
    tB = sf_slots[i+1]
    
    scoreA = 2
    scoreB = random.randint(0, 1)
    if random.choice([True, False]):
        scoreA, scoreB = scoreB, scoreA
        
    winner = tA if scoreA > scoreB else tB
    final_slots.append(winner)
    
    match_log.append(f"Semi-Final {i//2 + 1}: {tA} vs {tB} -> {winner} wins ({scoreA}-{scoreB})")
    ground_truth["semifinals"].append(winner)

match_log.append("")

# --- Grand Final ---
match_log.append("=== WINTER MAJOR GRAND FINAL ===")
tA = final_slots[0]
tB = final_slots[1]

# Best of 5
scoreA = 3
scoreB = random.randint(0, 2)
if random.choice([True, False]):
    scoreA, scoreB = scoreB, scoreA

champion = tA if scoreA > scoreB else tB
ground_truth["finals"].append(champion) # Technically listing finalists is redundant if we have champ, but good for checking
ground_truth["champion"] = champion

match_log.append(f"Grand Final: {tA} vs {tB} -> {champion} wins ({scoreA}-{scoreB})")
match_log.append(f"\nCHAMPION: {champion}")

# Save Match Log for Agent
with open('/home/ga/Desktop/match_results.txt', 'w') as f:
    f.write('\n'.join(match_log))

# Save Ground Truth for Verifier (Hidden)
with open('/tmp/bracket_ground_truth.json', 'w') as f:
    json.dump(ground_truth, f, indent=2)

print(f"Generated match results for {len(bracket_teams)} teams. Champion: {champion}")
PYEOF

chown ga:ga /home/ga/Desktop/match_results.txt
chmod 644 /home/ga/Desktop/match_results.txt

# 3. Launch draw.io
# Find binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found"
    exit 1
fi

echo "Launching draw.io..."
# Disable updates to prevent popups
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# 4. Wait for window and handle startup dialog
echo "Waiting for window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "draw.io"; then
        echo "Window found."
        break
    fi
    sleep 1
done

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Dismiss "Create New/Open Existing" dialog with Escape -> creates blank diagram
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Record start time
date +%s > /tmp/task_start_time.txt

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="