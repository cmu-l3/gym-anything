#!/bin/bash
set -e
echo "=== Setting up Season Performance Report Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Prepare Data Directory
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# 2. Clean previous artifacts
rm -f /home/ga/Documents/ValleyCats_MidSeason_2024.odt 2>/dev/null || true
rm -f /home/ga/Documents/team_stats_2024.json 2>/dev/null || true

# 3. Create the JSON data file with realistic baseball stats
cat > /home/ga/Documents/team_stats_2024.json << 'JSONEOF'
{
  "team": {
    "name": "Tri-City ValleyCats",
    "league": "Frontier League (Independent Professional)",
    "ballpark": "Joseph L. Bruno Stadium, Troy, NY 12180",
    "season": 2024,
    "report_period": "Games 1-50, April 9 - June 28, 2024",
    "record": {
      "wins": 28,
      "losses": 22,
      "winning_pct": ".560",
      "home": "16-9",
      "away": "12-13"
    },
    "division_standing": "2nd place, East Division (1.5 GB)"
  },
  "position_players": [
    {"name": "Darius Hawkins", "pos": "CF", "g": 49, "ab": 192, "avg": ".287", "hr": 8, "rbi": 31, "sb": 12, "note": "Leadoff hitter, elite speed"},
    {"name": "Marco Espinoza", "pos": "SS", "g": 50, "ab": 199, "avg": ".302", "hr": 4, "rbi": 28, "sb": 18, "note": "Team batting leader"},
    {"name": "Tyler Branson", "pos": "1B", "g": 48, "ab": 183, "avg": ".268", "hr": 14, "rbi": 42, "sb": 1, "note": "Power source, leads in HR"},
    {"name": "Kenji Watanabe", "pos": "LF", "g": 47, "ab": 178, "avg": ".275", "hr": 9, "rbi": 35, "sb": 6, "note": "Consistent contact"},
    {"name": "Dmitri Volkov", "pos": "3B", "g": 46, "ab": 170, "avg": ".241", "hr": 7, "rbi": 26, "sb": 3, "note": "Solid defense, bat slumping"},
    {"name": "Isaiah Chambers", "pos": "RF", "g": 45, "ab": 166, "avg": ".259", "hr": 6, "rbi": 24, "sb": 8, "note": "Plus arm"},
    {"name": "Nelson Acevedo", "pos": "C", "g": 38, "ab": 138, "avg": ".232", "hr": 5, "rbi": 22, "sb": 0, "note": "Great game caller"},
    {"name": "Jonah Whitfield", "pos": "2B", "g": 48, "ab": 182, "avg": ".291", "hr": 3, "rbi": 19, "sb": 14, "note": "High OBP"},
    {"name": "Rasheed Okafor", "pos": "DH", "g": 44, "ab": 161, "avg": ".254", "hr": 10, "rbi": 33, "sb": 2, "note": "Raw power"},
    {"name": "Liam Kowalski", "pos": "C", "g": 18, "ab": 64, "avg": ".218", "hr": 2, "rbi": 12, "sb": 0, "note": "Backup catcher"},
    {"name": "Xavier Delgado", "pos": "OF", "g": 32, "ab": 114, "avg": ".246", "hr": 4, "rbi": 16, "sb": 5, "note": "Fourth outfielder"},
    {"name": "Caleb Thornton", "pos": "INF", "g": 29, "ab": 94, "avg": ".223", "hr": 3, "rbi": 14, "sb": 1, "note": "Utility infielder"}
  ],
  "pitchers": [
    {"name": "Alejandro Fuentes", "role": "SP", "wl": "6-2", "era": "3.12", "ip": "68.1", "so": 70, "sv": 0, "note": "Ace"},
    {"name": "Ryan McAllister", "role": "SP", "wl": "5-3", "era": "3.78", "ip": "64.0", "so": 61, "sv": 0, "note": "Reliable No. 2"},
    {"name": "Tadashi Kimura", "role": "SP", "wl": "4-3", "era": "4.15", "ip": "56.2", "so": 49, "sv": 0, "note": "Ground ball pitcher"},
    {"name": "Bryce Underwood", "role": "SP", "wl": "3-4", "era": "4.62", "ip": "52.2", "so": 42, "sv": 0, "note": "Struggles late in games"},
    {"name": "Jamal Pittman", "role": "CL", "wl": "2-1", "era": "2.45", "ip": "33.0", "so": 40, "sv": 14, "note": "Dominant closer"},
    {"name": "Eduardo Salinas", "role": "RP", "wl": "3-0", "era": "3.24", "ip": "41.2", "so": 44, "sv": 2, "note": "Setup man"},
    {"name": "Connor Ashworth", "role": "RP", "wl": "1-2", "era": "4.89", "ip": "29.1", "so": 26, "sv": 0, "note": "Control issues"},
    {"name": "Nikolai Petersen", "role": "RP", "wl": "2-1", "era": "3.67", "ip": "34.1", "so": 34, "sv": 1, "note": "Long relief"}
  ],
  "coaching_notes": [
    "Focus on reducing bullpen walks in the second half.",
    "Espinoza and Whitfield are setting the table well; need more clutch hitting from middle order.",
    "Defense has improved, but outfield communication needs work."
  ]
}
JSONEOF
chown ga:ga /home/ga/Documents/team_stats_2024.json

# 4. Record initial state
echo "0" > /tmp/task_file_exists
date +%s > /tmp/task_start_time

# 5. Launch OpenOffice Writer
echo "Launching Apache OpenOffice Writer..."
if ! pgrep -f "soffice" > /dev/null; then
    su - ga -c "DISPLAY=:1 /opt/openoffice4/program/soffice --writer &"
fi

# 6. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenOffice"; then
        echo "Window found."
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "OpenOffice" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenOffice" 2>/dev/null || true

# 7. Dismiss any startup dialogs (Welcome Wizard, etc.)
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Return 2>/dev/null || true

# 8. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="