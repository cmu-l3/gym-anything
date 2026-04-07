#!/bin/bash
echo "=== Setting up analyze_experiment_data task ==="

export DISPLAY=:1
export XAUTHORITY=/home/ga/.Xauthority

# Suppress LibreOffice "Tip of the Day" and first-run dialogs
LO_CONFIG="/home/ga/.config/libreoffice/4/user/registrymodifications.xcu"
mkdir -p "$(dirname "$LO_CONFIG")"
cat > "$LO_CONFIG" << 'LOEOF'
<?xml version="1.0" encoding="UTF-8"?>
<oor:items xmlns:oor="http://openoffice.org/2001/registry" xmlns:xs="http://www.w3.org/2001/XMLSchema" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
<item oor:path="/org.openoffice.Office.Common/Misc"><prop oor:name="ShowTipOfTheDay" oor:op="fuse"><value>false</value></prop></item>
<item oor:path="/org.openoffice.Setup/Product"><prop oor:name="LastTimeDonateShown" oor:op="fuse"><value>32767</value></prop></item>
<item oor:path="/org.openoffice.Setup/Product"><prop oor:name="LastTimeGetInvolvedShown" oor:op="fuse"><value>32767</value></prop></item>
</oor:items>
LOEOF
chown -R ga:ga /home/ga/.config/libreoffice

# Copy the real Flanker experiment data to Documents
cp /workspace/assets/flanker_rt_data.csv /home/ga/Documents/flanker_rt_data.csv
chown ga:ga /home/ga/Documents/flanker_rt_data.csv

# Verify data file
echo "Data file info:"
wc -l /home/ga/Documents/flanker_rt_data.csv
head -3 /home/ga/Documents/flanker_rt_data.csv

# Get ga user's DBUS session address (needed for GUI apps launched via su)
GA_PID=$(pgrep -u ga -f gnome-session | head -1)
DBUS_ADDR=""
if [ -n "$GA_PID" ]; then
    DBUS_ADDR=$(grep -z DBUS_SESSION_BUS_ADDRESS /proc/$GA_PID/environ 2>/dev/null | tr '\0' '\n' | head -1)
fi

# Open the CSV file in LibreOffice Calc
su - ga -c "${DBUS_ADDR:+$DBUS_ADDR }DISPLAY=:1 setsid libreoffice --calc /home/ga/Documents/flanker_rt_data.csv > /tmp/libreoffice.log 2>&1 &"

# Wait for LibreOffice Calc to appear
for i in $(seq 1 30); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "flanker_rt_data" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "LibreOffice Calc window found: $WID"
        sleep 2
        # Maximize the window
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 2
done

# Handle the CSV import dialog if it appears
sleep 3
# Press Enter to accept default CSV import settings
DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Return 2>/dev/null || true
sleep 2

# Re-check for the main window after import
for i in $(seq 1 10); do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "flanker_rt_data" 2>/dev/null | head -1)
    if [ -n "$WID" ]; then
        echo "LibreOffice Calc ready with data: $WID"
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

echo "=== analyze_experiment_data setup complete ==="
