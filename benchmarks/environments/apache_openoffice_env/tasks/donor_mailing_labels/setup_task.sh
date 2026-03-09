#!/bin/bash
# Setup script for donor_mailing_labels task
# Generates a realistic CSV of donors with mixed donation amounts

echo "=== Setting up Donor Mailing Labels Task ==="
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Ensure directories exist
sudo -u ga mkdir -p /home/ga/Documents
sudo -u ga mkdir -p /home/ga/Desktop

# Clean up previous runs
rm -f /home/ga/Documents/donor_data.csv 2>/dev/null || true
rm -f /home/ga/Documents/golden_circle_labels.odt 2>/dev/null || true

# Generate realistic donor data using Python
# We explicitly set a seed for reproducibility if needed, though random is fine as long as we export the data for verification
python3 << 'PYEOF'
import csv
import random
import os

output_file = "/home/ga/Documents/donor_data.csv"

# Realistic data pools
first_names = ["James", "Mary", "John", "Patricia", "Robert", "Jennifer", "Michael", "Linda", "William", "Elizabeth", "David", "Barbara", "Richard", "Susan", "Joseph", "Jessica", "Thomas", "Sarah", "Charles", "Karen", "Christopher", "Nancy", "Daniel", "Lisa", "Matthew", "Margaret", "Anthony", "Betty", "Donald", "Sandra"]
last_names = ["Smith", "Johnson", "Williams", "Brown", "Jones", "Garcia", "Miller", "Davis", "Rodriguez", "Martinez", "Hernandez", "Lopez", "Gonzalez", "Wilson", "Anderson", "Thomas", "Taylor", "Moore", "Jackson", "Martin", "Lee", "Perez", "Thompson", "White", "Harris", "Sanchez", "Clark", "Ramirez", "Lewis", "Robinson"]
streets = ["Maple", "Oak", "Cedar", "Pine", "Elm", "Washington", "Lake", "Hill", "Main", "Park"]
cities = ["Springfield", "Riverside", "Georgetown", "Franklin", "Clinton", "Fairview", "Madison", "Salem", "Manchester", "Bristol"]
states = ["CA", "NY", "TX", "FL", "IL", "PA", "OH", "GA", "NC", "MI"]

def generate_donor(id):
    # Determine if this will be a high-value donor (approx 40% chance)
    is_high_value = random.random() < 0.40
    
    if is_high_value:
        donation = random.randint(1000, 5000)
    else:
        donation = random.randint(50, 999)

    return {
        "DonorID": f"D-{id:04d}",
        "FirstName": random.choice(first_names),
        "LastName": random.choice(last_names),
        "Address": f"{random.randint(100, 9999)} {random.choice(streets)} St",
        "City": random.choice(cities),
        "State": random.choice(states),
        "Zip": f"{random.randint(10000, 99999)}",
        "Phone": f"555-{random.randint(100, 999)}-{random.randint(1000, 9999)}",
        "TotalDonation": donation,
        "LastGiftDate": f"2023-{random.randint(1, 12):02d}-{random.randint(1, 28):02d}"
    }

donors = [generate_donor(i) for i in range(1, 51)]

with open(output_file, 'w', newline='') as csvfile:
    fieldnames = ["DonorID", "FirstName", "LastName", "Address", "City", "State", "Zip", "Phone", "TotalDonation", "LastGiftDate"]
    writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
    
    writer.writeheader()
    for donor in donors:
        writer.writerow(donor)

print(f"Generated {len(donors)} donor records at {output_file}")
PYEOF

# Set ownership
chown ga:ga /home/ga/Documents/donor_data.csv

# Create OpenOffice desktop shortcut if missing (standard setup)
if [ ! -f "/home/ga/Desktop/openoffice-writer.desktop" ] && [ -x "/opt/openoffice4/program/soffice" ]; then
    cat > /home/ga/Desktop/openoffice-writer.desktop << 'DESKTOP'
[Desktop Entry]
Version=1.0
Type=Application
Name=OpenOffice Writer
Comment=Create and edit text documents
Exec=/opt/openoffice4/program/soffice --writer %U
Icon=/opt/openoffice4/program/soffice
Terminal=false
Categories=Office;WordProcessor;
DESKTOP
    chown ga:ga /home/ga/Desktop/openoffice-writer.desktop
    chmod +x /home/ga/Desktop/openoffice-writer.desktop
fi

# Record start time
date +%s > /tmp/task_start_time.txt
echo "0" > /tmp/initial_file_size.txt

take_screenshot /tmp/task_initial.png
echo "=== Setup Complete ==="