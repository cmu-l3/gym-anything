#!/bin/bash
echo "=== Setting up earthquake_data_analysis task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Clean up previous runs
rm -f /home/ga/Documents/earthquake_analysis.py 2>/dev/null || true
rm -f /home/ga/Documents/earthquake_report.txt 2>/dev/null || true
rm -f /tmp/earthquake_ground_truth.json 2>/dev/null || true

# Download dataset
CSV_PATH="/home/ga/Documents/earthquakes.csv"
echo "Downloading USGS earthquake data..."
curl -sL "https://earthquake.usgs.gov/earthquakes/feed/v1.0/summary/1.0_week.csv" -o "$CSV_PATH"

# Check if download succeeded and has data
if [ ! -s "$CSV_PATH" ] || ! head -n 1 "$CSV_PATH" | grep -q "time.*latitude.*longitude"; then
    echo "Download failed or invalid, generating fallback data..."
    cat > "$CSV_PATH" << 'EOF'
time,latitude,longitude,depth,mag,magType,nst,gap,dmin,rms,net,id,updated,place,type,horizontalError,depthError,magError,magNst,status,locationSource,magSource
2024-01-15T08:23:45.123Z,36.7783,-119.4179,12.5,3.2,ml,,,,,us,us1,,10km NE of Ridgecrest CA,earthquake,,,,,,,
2024-01-15T09:10:00.000Z,34.0522,-118.2437,5.0,2.1,md,,,,,ci,ci1,,5km W of Los Angeles CA,earthquake,,,,,,,
2024-01-16T10:00:00.000Z,37.7749,-122.4194,8.2,4.5,mw,,,,,nc,nc1,,2km S of San Francisco CA,earthquake,,,,,,,
2024-01-16T11:30:00.000Z,33.9300,-116.9700,15.1,1.5,ml,,,,,ci,ci2,,15km E of Banning CA,earthquake,,,,,,,
2024-01-17T12:45:00.000Z,40.7128,-74.0060,2.0,1.2,md,,,,,us,us2,,New York NJ,earthquake,,,,,,,
2024-01-17T14:20:00.000Z,36.7783,-119.4179,10.0,5.5,mw,,,,,us,us3,,12km NE of Ridgecrest CA,earthquake,,,,,,,
2024-01-18T16:05:00.000Z,34.0522,-118.2437,6.5,2.8,ml,,,,,ci,ci3,,4km W of Los Angeles CA,earthquake,,,,,,,
2024-01-18T18:50:00.000Z,37.7749,-122.4194,11.0,3.9,mw,,,,,nc,nc2,,1km S of San Francisco CA,earthquake,,,,,,,
2024-01-19T20:15:00.000Z,33.9300,-116.9700,14.5,1.8,ml,,,,,ci,ci4,,14km E of Banning CA,earthquake,,,,,,,
2024-01-19T22:30:00.000Z,40.7128,-74.0060,3.0,0.9,md,,,,,us,us4,,New York NJ,earthquake,,,,,,,
2024-01-20T01:10:00.000Z,35.6895,139.6917,45.0,6.1,mw,,,,,us,us5,,Tokyo Japan,earthquake,,,,,,,
2024-01-20T04:45:00.000Z,35.6895,139.6917,40.0,4.2,mb,,,,,us,us6,,Tokyo Japan,earthquake,,,,,,,
EOF
fi
chown ga:ga "$CSV_PATH"

# Compute ground truth
python3 << 'PYEOF'
import csv, json, collections

try:
    mags = []
    depths = []
    largest_place = ""
    largest_mag = -1.0

    with open('/home/ga/Documents/earthquakes.csv') as f:
        reader = csv.DictReader(f)
        for r in reader:
            if r.get('mag') and r['mag'].strip() and r.get('depth') and r['depth'].strip():
                try:
                    m = float(r['mag'])
                    d = float(r['depth'])
                    if m >= 0:
                        mags.append(m)
                        depths.append(d)
                        if m > largest_mag:
                            largest_mag = m
                            largest_place = r.get('place', 'Unknown')
                except ValueError:
                    pass

    if mags:
        dist = collections.defaultdict(int)
        for m in mags:
            if m >= 6:
                dist['6+'] += 1
            else:
                lower = int(m)
                upper = lower + 1
                dist[f'{lower}-{upper}'] += 1

        truth = {
            'total': len(mags),
            'largest_mag': round(largest_mag, 1),
            'largest_place': largest_place,
            'avg_depth': round(sum(depths)/len(depths), 1),
            'distribution': dict(dist)
        }
    else:
        truth = {'error': 'No valid data'}

    with open('/tmp/earthquake_ground_truth.json', 'w') as f:
        json.dump(truth, f)
except Exception as e:
    with open('/tmp/earthquake_ground_truth.json', 'w') as f:
        json.dump({'error': str(e)}, f)
PYEOF
chmod 666 /tmp/earthquake_ground_truth.json

# Record start time
date +%s > /tmp/earthquake_task_start_ts
chmod 666 /tmp/earthquake_task_start_ts

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Launch Terminal activity
echo "Launching Terminal activity..."
su - ga -c "$SUGAR_ENV sugar-launch org.laptop.Terminal" &
sleep 10

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/earthquake_task_start.png" 2>/dev/null || true

echo "=== earthquake_data_analysis task setup complete ==="