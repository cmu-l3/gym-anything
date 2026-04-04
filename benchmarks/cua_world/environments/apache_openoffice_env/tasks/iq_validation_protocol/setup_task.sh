#!/bin/bash
echo "=== Setting up IQ Validation Protocol Task ==="
source /workspace/scripts/task_utils.sh

# Copy instrument data to the user's Documents folder
cp /workspace/tasks/iq_validation_protocol/assets/instrument_data.json /home/ga/Documents/instrument_data.json
chown ga:ga /home/ga/Documents/instrument_data.json
chmod 644 /home/ga/Documents/instrument_data.json

# Remove any pre-existing output file to ensure clean start
rm -f /home/ga/Documents/VAL-IQ-UPLC-2024-004.odt

# Record baseline - no prior IQ protocol document
echo "0" > /tmp/initial_iq_doc_exists
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_timestamp

# Ensure OpenOffice Writer is running
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    DISPLAY=:0 /opt/openoffice4/program/soffice --writer &
    sleep 4
fi

take_screenshot "iq_validation_setup"
echo "=== Setup Complete: instrument_data.json placed at /home/ga/Documents/ ==="
echo "=== Output target: /home/ga/Documents/VAL-IQ-UPLC-2024-004.odt ==="
