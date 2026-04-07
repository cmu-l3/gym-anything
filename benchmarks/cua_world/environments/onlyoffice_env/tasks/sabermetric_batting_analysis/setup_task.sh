#!/bin/bash
set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sabermetric Batting Analysis Task ==="

# Record task start timestamp for anti-gaming
echo $(date +%s) > /tmp/task_start_time.txt

cleanup_temp_files
kill_onlyoffice ga
sleep 1

WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

CSV_PATH="$WORKSPACE_DIR/mlb_2023_batting_raw.csv"

# Create python script to fetch/generate the data
cat > /tmp/prepare_mlb_data.py << 'PYEOF'
#!/usr/bin/env python3
import sys
import os
import urllib.request
import csv
from io import StringIO

output_path = sys.argv[1]

# Fallback data in case the network request fails (top ~20 players from 2023)
fallback_data = """Player,Team,G,AB,R,H,2B,3B,HR,RBI,SB,CS,BB,SO,HBP,SF,IBB
Ronald Acuna Jr.,ATL,159,643,149,217,35,4,41,106,73,14,80,84,9,3,3
Freddie Freeman,LAD,161,637,131,211,59,2,29,102,23,1,72,121,12,5,1
Matt Olson,ATL,162,608,127,172,27,3,54,139,1,0,104,167,4,4,14
Shohei Ohtani,LAA,135,497,102,151,26,8,44,95,20,6,91,143,3,3,21
Mookie Betts,LAD,152,584,126,179,40,1,39,107,14,3,93,107,8,5,3
Corey Seager,TEX,119,477,88,156,42,0,33,96,2,1,49,88,4,6,9
Juan Soto,SDP,162,568,97,156,32,1,35,109,12,5,132,129,2,5,11
Yordan Alvarez,HOU,114,410,77,120,24,1,31,97,0,0,69,92,5,6,6
Corbin Carroll,ARI,155,565,116,161,30,10,25,76,54,5,57,125,14,4,0
Marcus Semien,TEX,162,670,122,185,40,4,29,100,14,3,73,110,2,5,0
Luis Arraez,MIA,147,574,71,203,30,3,10,69,3,2,35,34,4,4,3
Julio Rodriguez,SEA,155,654,103,180,37,2,32,103,37,10,47,175,7,2,0
Kyle Tucker,HOU,157,574,97,163,37,5,29,112,30,5,80,92,4,7,5
Ozzie Albies,ATL,148,596,96,167,30,5,33,109,13,1,46,107,4,7,0
Austin Riley,ATL,159,636,117,179,32,3,37,97,3,1,59,172,9,3,0
Bo Bichette,TOR,135,571,69,175,30,3,20,73,5,3,27,115,2,4,0
Gunnar Henderson,BAL,150,560,100,143,29,9,28,82,10,3,56,122,6,5,0
Francisco Lindor,NYM,160,602,108,153,33,2,31,98,31,4,66,137,5,7,0
Rafael Devers,BOS,153,580,90,157,34,0,33,100,5,2,50,126,8,3,0
Pete Alonso,NYM,154,568,92,123,21,2,46,118,4,1,65,151,15,5,0
"""

try:
    # Try to fetch real data via pandas (installed in onlyoffice_env)
    import pandas as pd
    
    batting_url = "https://raw.githubusercontent.com/chadwickbureau/baseballdatabank/master/core/Batting.csv"
    people_url = "https://raw.githubusercontent.com/chadwickbureau/baseballdatabank/master/core/People.csv"
    
    batting_df = pd.read_csv(batting_url)
    people_df = pd.read_csv(people_url)
    
    # Filter 2023 season
    df_2023 = batting_df[batting_df['yearID'] == 2023].copy()
    
    # Sum stats for players with multiple stints
    counting_cols = ['G', 'AB', 'R', 'H', '2B', '3B', 'HR', 'RBI', 'SB', 'CS', 'BB', 'SO', 'IBB', 'HBP', 'SH', 'SF']
    df_grouped = df_2023.groupby('playerID')[counting_cols].sum().reset_index()
    
    # Filter qualified batters (~300+ ABs for simplicity)
    df_qualified = df_grouped[df_grouped['AB'] >= 300].copy()
    
    # Merge with names
    df_merged = pd.merge(df_qualified, people_df[['playerID', 'nameFirst', 'nameLast']], on='playerID', how='left')
    df_merged['Player'] = df_merged['nameFirst'] + ' ' + df_merged['nameLast']
    
    # Get team (if multi-stint, take the last one or just mark 'TOT')
    teams = df_2023.drop_duplicates('playerID', keep='last')[['playerID', 'teamID']]
    df_final = pd.merge(df_merged, teams, on='playerID', how='left')
    df_final.rename(columns={'teamID': 'Team'}, inplace=True)
    
    # Select final columns
    final_cols = ['Player', 'Team'] + counting_cols
    # Ensure no SH column is strictly required to match task perfectly, but it's okay to have it.
    df_export = df_final[final_cols].copy()
    
    df_export.to_csv(output_path, index=False)
    print("Successfully generated full 2023 dataset.")
    
except Exception as e:
    print(f"Network/Processing failed: {e}. Using fallback data.")
    with open(output_path, 'w', encoding='utf-8') as f:
        f.write(fallback_data.strip() + "\n")

PYEOF

# Run data preparation script
sudo -u ga python3 /tmp/prepare_mlb_data.py "$CSV_PATH"

# Ensure permissions
chown ga:ga "$CSV_PATH"

# Launch ONLYOFFICE with the CSV file
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$CSV_PATH' > /tmp/onlyoffice_launch.log 2>&1 &"
sleep 5

# Wait for ONLYOFFICE window
wait_for_window "ONLYOFFICE" 30

# Maximize and focus the window
WID=$(get_onlyoffice_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 1
    
    # Close any welcome/format dialogs if they pop up
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 0.5
    DISPLAY=:1 xdotool key Return 2>/dev/null || true
fi

# Take initial screenshot
take_screenshot /tmp/task_initial_state.png ga

echo "=== Task Setup Complete ==="