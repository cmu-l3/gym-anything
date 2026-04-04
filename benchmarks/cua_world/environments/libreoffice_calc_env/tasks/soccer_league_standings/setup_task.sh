#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Soccer League Standings Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create match results CSV with realistic season data
cat > /home/ga/Documents/match_results.csv << 'EOF'
Match Date,Home Team,Home Goals,Away Goals,Away Team
2024-03-02,Eagles,3,1,Panthers
2024-03-02,Tigers,2,2,Lions
2024-03-02,Bears,1,0,Sharks
2024-03-02,Wolves,2,1,Hawks
2024-03-09,Lions,3,0,Eagles
2024-03-09,Panthers,1,1,Tigers
2024-03-09,Sharks,2,1,Wolves
2024-03-09,Hawks,0,2,Bears
2024-03-16,Eagles,4,0,Sharks
2024-03-16,Tigers,3,1,Bears
2024-03-16,Lions,2,1,Wolves
2024-03-16,Panthers,1,2,Hawks
2024-03-23,Bears,1,1,Eagles
2024-03-23,Wolves,0,3,Tigers
2024-03-23,Hawks,2,0,Lions
2024-03-23,Sharks,1,2,Panthers
2024-03-30,Eagles,2,0,Wolves
2024-03-30,Tigers,1,0,Hawks
2024-03-30,Lions,3,1,Panthers
2024-03-30,Bears,2,2,Sharks
2024-04-06,Panthers,0,1,Eagles
2024-04-06,Sharks,0,2,Tigers
2024-04-06,Hawks,1,1,Wolves
2024-04-06,Lions,2,0,Bears
2024-04-13,Eagles,3,0,Hawks
2024-04-13,Wolves,1,2,Panthers
2024-04-13,Bears,0,1,Lions
2024-04-13,Tigers,4,1,Sharks
EOF

chown ga:ga /home/ga/Documents/match_results.csv
echo "✅ Created match_results.csv with season data"

# Create initial spreadsheet with match results and empty standings template
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
import csv

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Sheet 1: Match Results
matches_table = Table(name="Match Results")
doc.spreadsheet.addElement(matches_table)

# Read and populate match results
with open('/home/ga/Documents/match_results.csv', 'r') as f:
    reader = csv.reader(f)
    for row_data in reader:
        row = TableRow()
        for value in row_data:
            cell = TableCell()
            p = P(text=value)
            cell.addElement(p)
            row.addElement(cell)
        matches_table.addElement(row)

# Add empty cells to complete the table
for _ in range(5):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    matches_table.addElement(row)

# Sheet 2: Standings (template with headers)
standings_table = Table(name="Standings")
doc.spreadsheet.addElement(standings_table)

# Add header row
header_row = TableRow()
headers = ["Position", "Team", "P", "W", "D", "L", "GF", "GA", "GD", "Pts"]
for header in headers:
    cell = TableCell()
    p = P(text=header)
    cell.addElement(p)
    header_row.addElement(cell)
standings_table.addElement(header_row)

# Add team names (extracted from matches)
teams = ["Eagles", "Tigers", "Lions", "Bears", "Wolves", "Hawks", "Panthers", "Sharks"]
for team in teams:
    row = TableRow()
    # Empty position cell
    cell = TableCell()
    row.addElement(cell)
    # Team name
    cell = TableCell()
    p = P(text=team)
    cell.addElement(p)
    row.addElement(cell)
    # Empty cells for stats
    for _ in range(8):
        cell = TableCell()
        row.addElement(cell)
    standings_table.addElement(row)

# Add empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(15):
        cell = TableCell()
        row.addElement(cell)
    standings_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/league_standings.ods")
print("✅ Created league_standings.ods with match data and standings template")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/league_standings.ods
sudo chmod 666 /home/ga/Documents/league_standings.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/league_standings.ods > /tmp/calc_standings_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_standings_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Navigate to Standings sheet
echo "Navigating to Standings sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Position cursor at first data cell (B2 - first team name)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down Right
sleep 0.3

echo "=== Soccer League Standings Task Setup Complete ==="
echo ""
echo "📊 League Information:"
echo "   - 8 teams in the league"
echo "   - 28 matches played (partial season)"
echo "   - Match results in 'Match Results' sheet"
echo "   - Standings template in 'Standings' sheet"
echo ""
echo "📝 Your Task:"
echo "   1. Calculate statistics for each team:"
echo "      • Matches Played (P)"
echo "      • Wins (W), Draws (D), Losses (L)"
echo "      • Goals For (GF), Goals Against (GA)"
echo "      • Goal Difference (GD = GF - GA)"
echo "      • Points (Pts = W*3 + D*1)"
echo "   2. Sort by Points (descending), then Goal Difference (descending)"
echo "   3. Add position numbers (1, 2, 3, ...)"
echo ""
echo "💡 Tips:"
echo "   - Use COUNTIFS to count wins/draws/losses"
echo "   - Use SUMIF to sum goals for/against"
echo "   - Use absolute references (\$) when copying formulas"
echo "   - Sort entire table: Data → Sort (2 sort keys)"
echo ""
echo "🏆 The league champion will be determined by your calculations!"