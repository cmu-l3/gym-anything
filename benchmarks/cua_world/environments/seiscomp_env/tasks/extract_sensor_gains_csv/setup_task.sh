#!/bin/bash
echo "=== Setting up extract_sensor_gains_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp check)
date +%s > /tmp/task_start_time.txt

# Ensure MariaDB is running
echo "--- Ensuring MariaDB is running ---"
systemctl start mariadb || true
for i in $(seq 1 20); do
    if mysqladmin ping -h localhost 2>/dev/null; then
        echo "MariaDB is ready"
        break
    fi
    sleep 2
done

# Clean any pre-existing output files to prevent cheating
rm -f /home/ga/bhz_gains.csv 2>/dev/null || true

# Generate ground truth data using Python to ensure perfect CSV format
# This runs queries directly against SeisComP's complex schema
echo "--- Generating ground truth data ---"
python3 << 'EOF'
import subprocess
import csv

# Query joins Network -> Station -> SensorLocation -> Stream to find BHZ
cmd = """mysql -u sysop -psysop seiscomp -N -e "SELECT n.code, s.code, l.code, st.code, st.gain, st.gainFrequency FROM Network n JOIN Station s ON s._parent_oid = n._oid JOIN SensorLocation l ON l._parent_oid = s._oid JOIN Stream st ON st._parent_oid = l._oid WHERE st.code = 'BHZ';" """

try:
    out = subprocess.check_output(cmd, shell=True).decode('utf-8')
    with open('/tmp/ground_truth.csv', 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['Network', 'Station', 'Location', 'Channel', 'Gain', 'GainFrequency'])
        for line in out.strip().split('\n'):
            if line.strip():
                # MariaDB -N output is tab-separated
                writer.writerow(line.split('\t'))
    print("Ground truth generated successfully.")
except Exception as e:
    print(f"Error generating ground truth: {e}")
EOF

# Secure the ground truth file so the agent cannot easily read it during the task
chmod 600 /tmp/ground_truth.csv
chown root:root /tmp/ground_truth.csv

# Open a terminal for the agent to work in
echo "--- Opening terminal ---"
su - ga -c "DISPLAY=:1 gnome-terminal --maximize" &
sleep 3

# Take initial screenshot
take_screenshot /tmp/task_initial.png ga

echo "=== Task setup complete ==="