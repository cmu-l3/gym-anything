#!/bin/bash
echo "=== Setting up titanic_sql_database_builder task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

# Ensure Documents directory exists
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up any previous attempts
rm -f /home/ga/Documents/titanic.db 2>/dev/null || true
rm -f /home/ga/Documents/survival_summary.txt 2>/dev/null || true
rm -f /home/ga/Documents/import_titanic.py 2>/dev/null || true

# Download the real Titanic dataset
echo "Downloading Titanic dataset..."
wget -q -O /home/ga/Documents/titanic.csv "https://raw.githubusercontent.com/datasciencedojo/datasets/master/titanic.csv" || {
    echo "WARNING: Primary download failed, attempting fallback..."
    wget -q -O /home/ga/Documents/titanic.csv "https://vincentarelbundock.github.io/Rdatasets/csv/carData/TitanicSurvival.csv" || true
}

# Verify dataset exists and fix permissions
if [ -f /home/ga/Documents/titanic.csv ]; then
    chown ga:ga /home/ga/Documents/titanic.csv
    chmod 644 /home/ga/Documents/titanic.csv
    echo "Dataset ready: $(wc -l < /home/ga/Documents/titanic.csv) lines"
else
    echo "ERROR: Failed to download dataset!"
fi

# Record task start timestamp for anti-gaming checks
date +%s > /tmp/titanic_task_start_ts
chmod 666 /tmp/titanic_task_start_ts

# Close any open activities first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch the Terminal activity for the agent to use
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Take a verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/titanic_task_start.png" 2>/dev/null || true

echo "=== titanic_sql_database_builder task setup complete ==="
echo "Dataset downloaded to /home/ga/Documents/titanic.csv"
echo "Agent must create SQLite DB, table, parse CSV, and output summary."