#!/bin/bash
echo "=== Setting up Legacy Concert Normalization Task ==="

source /workspace/scripts/task_utils.sh

# Directory setup
mkdir -p /home/ga/Documents/databases
mkdir -p /home/ga/Documents/scripts
chown -R ga:ga /home/ga/Documents

# Clean previous artifacts
rm -f /home/ga/Documents/concerts_raw.csv
rm -f /home/ga/Documents/databases/concert_bookings.db

# Generate realistic raw data using Python
echo "Generating raw concert data..."
python3 << 'PYEOF'
import csv
import random
from datetime import datetime, timedelta

venues = [
    ("The Fillmore", "San Francisco", 1200),
    ("Red Rocks Amphitheatre", "Morrison", 9525),
    ("Madison Square Garden", "New York", 20789),
    ("The Hollywood Bowl", "Los Angeles", 17500),
    ("Ryman Auditorium", "Nashville", 2362),
    ("9:30 Club", "Washington DC", 1200),
    ("First Avenue", "Minneapolis", 1500)
]

artists = [
    ("The Midnight", "Synthwave"),
    ("Tame Impala", "Psychedelic Rock"),
    ("Vulfpeck", "Funk"),
    ("Khruangbin", "Psychedelic Funk"),
    ("Glass Animals", "Indie Pop"),
    ("St. Vincent", "Art Rock"),
    ("Thundercat", "Funk/Jazz")
]

concert_names = ["Tour opener", "Late Night Show", "Special Acoustic Set", "Album Launch", "Benefit Concert"]

data = []
# Generate ~50 records
start_date = datetime(2023, 1, 1)

for _ in range(50):
    venue = random.choice(venues)
    artist = random.choice(artists)
    concert_name = f"{artist[0]} - {random.choice(concert_names)}"
    
    # Random date within a year
    date_obj = start_date + timedelta(days=random.randint(0, 365))
    date_str = date_obj.strftime("%Y-%m-%d")
    
    price = round(random.uniform(25.0, 150.0), 2)
    
    # Row structure: ConcertName, ConcertDate, TicketPrice, VenueName, VenueCity, VenueCapacity, ArtistName, ArtistGenre
    row = [concert_name, date_str, price, venue[0], venue[1], venue[2], artist[0], artist[1]]
    data.append(row)

# Write to CSV
with open('/home/ga/Documents/concerts_raw.csv', 'w', newline='') as f:
    writer = csv.writer(f)
    writer.writerow(["ConcertName", "ConcertDate", "TicketPrice", "VenueName", "VenueCity", "VenueCapacity", "ArtistName", "ArtistGenre"])
    writer.writerows(data)

# Save ground truth statistics for verification
import json
gt = {
    "total_rows": len(data),
    "distinct_venues": len(venues),
    "distinct_artists": len(artists),
    "venue_names": [v[0] for v in venues],
    "artist_names": [a[0] for a in artists]
}
with open('/tmp/concert_ground_truth.json', 'w') as f:
    json.dump(gt, f)

print(f"Generated {len(data)} rows of raw data.")
PYEOF

chown ga:ga /home/ga/Documents/concerts_raw.csv

# Record task start time
date +%s > /tmp/task_start_time.txt

# Start DBeaver if not running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 /usr/share/dbeaver-ce/dbeaver > /tmp/dbeaver.log 2>&1 &"
    sleep 10
fi

# Focus DBeaver
focus_dbeaver
maximize_window "DBeaver"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="