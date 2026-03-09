#!/bin/bash
echo "=== Setting up Offer Letter Batch Task ==="
source /workspace/scripts/task_utils.sh

# Copy hire data to the user's Documents folder
cp /workspace/tasks/offer_letter_batch/assets/new_hires.json /home/ga/Documents/new_hires.json
chown ga:ga /home/ga/Documents/new_hires.json
chmod 644 /home/ga/Documents/new_hires.json

# Remove any pre-existing output files to ensure clean start
rm -f /home/ga/Documents/offer_letter_Okonkwo_Amara.odt
rm -f /home/ga/Documents/offer_letter_Tremblay_Kevin.odt
rm -f /home/ga/Documents/offer_letter_Nair_Preethi.odt
rm -f /home/ga/Documents/offer_letter_Vasquez_Jordan.odt
rm -f /home/ga/Documents/offer_letter_Petrov_Marcus.odt

# Record baseline
echo "0" > /tmp/initial_offer_letters_count
date -u +"%Y-%m-%dT%H:%M:%SZ" > /tmp/task_start_timestamp

# Ensure OpenOffice Writer is running
if ! pgrep -f "soffice" > /dev/null 2>&1; then
    DISPLAY=:0 /opt/openoffice4/program/soffice --writer &
    sleep 4
fi

take_screenshot "offer_letter_setup"
echo "=== Setup Complete: new_hires.json placed at /home/ga/Documents/ ==="
echo "=== Expected output: 5 offer letter .odt files in /home/ga/Documents/ ==="
