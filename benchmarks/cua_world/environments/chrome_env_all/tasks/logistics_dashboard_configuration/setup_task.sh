#!/usr/bin/env bash
set -euo pipefail

echo "=== Logistics Dashboard Configuration Task Setup ==="
echo "Task: Configure an unattended Chrome dashboard, sanitize personal history, and organize logistics bookmarks."

# Wait for environment to stabilize
sleep 2

# ── 1. Stop Chrome safely ───────────────────────────────────────────────────
echo "Stopping Chrome to inject test data..."
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 2
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# ── 2. Prepare Chrome Profile Directory ─────────────────────────────────────
CHROME_PROFILE="/home/ga/.config/google-chrome/Default"
mkdir -p "$CHROME_PROFILE"
chown -R ga:ga /home/ga/.config/google-chrome/

# ── 3. Create the Dashboard Specification Document ──────────────────────────
cat > "/home/ga/Desktop/dashboard_spec.txt" << 'SPEC_EOF'
GLOBAL LOGISTICS DASHBOARD CONFIGURATION STANDARD
=================================================
This workstation is being repurposed as an unattended logistics monitoring dashboard.

1. BOOKMARK CLEANUP
   - Delete all personal travel and vacation planning bookmarks (Expedia, Airbnb, cruises, etc.)

2. BOOKMARK ORGANIZATION
   - Create a master folder on the bookmark bar named: Global Logistics
   - Inside it, create three subfolders and organize the remaining bookmarks into them:
       a) "Vessel Tracking" (MarineTraffic, VesselFinder, SeaRates, MyShipTracking)
       b) "Port Operations" (LA, Long Beach, NY/NJ, Savannah)
       c) "Intermodal Rail" (UP, BNSF, CSX)

3. DASHBOARD STARTUP
   - Configure Chrome to "Open a specific page or set of pages" on startup.
   - Add exactly these two URLs:
       https://www.marinetraffic.com
       https://www.portoflosangeles.org

4. QUICK SEARCH ENGINES
   - Add a custom search engine with keyword 'mmsi' 
     URL: https://www.vesselfinder.com/?mmsi=%s
   - Add a custom search engine with keyword 'container'
     URL: https://www.searates.com/container/tracking/?number=%s

5. UNATTENDED DISPLAY LOCKDOWN
   - Navigate to Site Settings.
   - Set Notifications to "Don't allow sites to send notifications"
   - Set Location to "Don't allow sites to see your location"
   (Popups on the dashboard monitor are unacceptable)

6. HISTORY SANITIZATION
   - The previous user left vacation planning data in the browsing history.
   - Delete ALL history entries related to personal travel sites (Expedia, Airbnb, cruises, flights, etc.)
   - CRITICAL: Do NOT clear all history! You must preserve the recent maritime and logistics tracking history for operational audits.
SPEC_EOF
chown ga:ga "/home/ga/Desktop/dashboard_spec.txt"

# ── 4. Generate Bookmarks JSON ──────────────────────────────────────────────
echo "Injecting Bookmarks..."
python3 << 'PY_BM_EOF'
import json, time, uuid, os

chrome_base = (int(time.time()) + 11644473600) * 1000000

logistics = [
    ("MarineTraffic", "https://www.marinetraffic.com/"),
    ("VesselFinder", "https://www.vesselfinder.com/"),
    ("SeaRates", "https://www.searates.com/"),
    ("MyShipTracking", "https://www.myshiptracking.com/"),
    ("Port of LA", "https://www.portoflosangeles.org/"),
    ("Port of Long Beach", "https://polb.com/"),
    ("Port NY/NJ", "https://www.panynj.gov/port/en/index.html"),
    ("Port of Savannah", "https://gaports.com/facilities/port-of-savannah/"),
    ("UP Trace", "https://www.up.com/customers/track-trace/"),
    ("BNSF Tracking", "https://www.bnsf.com/"),
    ("CSX Tools", "https://www.csx.com/")
]

travel = [
    ("Expedia", "https://www.expedia.com/"),
    ("Airbnb Miami", "https://www.airbnb.com/"),
    ("Skyscanner", "https://www.skyscanner.com/"),
    ("Kayak Flights", "https://www.kayak.com/"),
    ("Booking.com", "https://www.booking.com/"),
    ("TripAdvisor Bahamas", "https://www.tripadvisor.com/"),
    ("Hotels.com", "https://www.hotels.com/"),
    ("Carnival Cruises", "https://www.carnival.com/"),
    ("Disney Cruise Line", "https://disneycruise.disney.go.com/"),
    ("VRBO Rentals", "https://www.vrbo.com/"),
    ("Cheapflights", "https://www.cheapflights.com/")
]

# Mix them randomly-ish but deterministically
combined = logistics[:5] + travel[:4] + logistics[5:8] + travel[4:8] + logistics[8:] + travel[8:]

children = []
for i, (name, url) in enumerate(combined):
    children.append({
        "date_added": str(chrome_base - (i * 600000000)),
        "guid": str(uuid.uuid4()),
        "id": str(i + 5),
        "name": name,
        "type": "url",
        "url": url
    })

bookmarks = {
    "checksum": "0" * 32,
    "roots": {
        "bookmark_bar": {"children": children, "date_added": str(chrome_base), "date_modified": "0", "id": "1", "name": "Bookmarks bar", "type": "folder"},
        "other": {"children": [], "date_added": str(chrome_base), "id": "2", "name": "Other bookmarks", "type": "folder"},
        "synced": {"children": [], "date_added": str(chrome_base), "id": "3", "name": "Mobile bookmarks", "type": "folder"}
    },
    "version": 1
}

with open("/home/ga/.config/google-chrome/Default/Bookmarks", "w") as f:
    json.dump(bookmarks, f, indent=3)
PY_BM_EOF

# ── 5. Generate History SQLite DB ───────────────────────────────────────────
echo "Injecting SQLite History Database..."
python3 << 'PY_HIST_EOF'
import sqlite3, time, os

os.makedirs("/home/ga/.config/google-chrome/Default", exist_ok=True)
db_path = "/home/ga/.config/google-chrome/Default/History"

# Remove if exists to ensure clean state
if os.path.exists(db_path):
    os.remove(db_path)

conn = sqlite3.connect(db_path)
c = conn.cursor()

# Create minimal schema expected by Chrome
c.execute("CREATE TABLE urls (id INTEGER PRIMARY KEY AUTOINCREMENT, url LONGVARCHAR, title LONGVARCHAR, visit_count INTEGER DEFAULT 0, typed_count INTEGER DEFAULT 0, last_visit_time INTEGER NOT NULL, hidden INTEGER DEFAULT 0)")
c.execute("CREATE TABLE visits (id INTEGER PRIMARY KEY AUTOINCREMENT, url INTEGER NOT NULL, visit_time INTEGER NOT NULL, from_visit INTEGER, transition INTEGER DEFAULT 0, segment_id INTEGER, visit_duration INTEGER DEFAULT 0, incremented_omnibox_typed_score BOOLEAN DEFAULT FALSE)")

chrome_base = (int(time.time()) + 11644473600) * 1000000

logistics_urls = [
    ("https://www.marinetraffic.com/en/ais/home/centerx:-12.0/centery:25.0/zoom:4", "MarineTraffic: Global Ship Tracking"),
    ("https://www.vesselfinder.com/?mmsi=368137000", "VesselFinder - MMSI 368137000"),
    ("https://www.searates.com/container/tracking/", "Container Tracking - SeaRates"),
    ("https://www.portoflosangeles.org/business/supply-chain/port-optimizer", "Port Optimizer - Port of Los Angeles"),
    ("https://polb.com/business/port-of-long-beach-wave/", "WAVE - Port of Long Beach"),
    ("https://www.panynj.gov/port/en/index.html", "Port of NY/NJ"),
    ("https://www.up.com/customers/track-trace/", "Track and Trace - Union Pacific"),
    ("https://www.bnsf.com/ship-with-bnsf/tracking-options/", "Tracking Options - BNSF Railway"),
    ("https://www.csx.com/index.cfm/customers/tools/shipcsx/", "ShipCSX Tracking"),
]

travel_urls = [
    ("https://www.expedia.com/Destinations-In-Bahamas.d18.Flight-Destinations", "Cheap Flights to Bahamas - Expedia"),
    ("https://www.airbnb.com/s/Miami--FL/homes", "Miami Vacation Rentals & Homes - Airbnb"),
    ("https://www.skyscanner.com/flights-to/mia/cheap-flights-to-miami-international-airport.html", "Cheap flights to Miami - Skyscanner"),
    ("https://www.kayak.com/flights", "Search Flights, Hotels & Rental Cars | KAYAK"),
    ("https://www.booking.com/city/us/miami-beach.html", "Miami Beach Hotels - Booking.com"),
    ("https://www.tripadvisor.com/Tourism-g147414-Bahamas-Vacations.html", "Bahamas 2026: Best Places to Visit - TripAdvisor"),
    ("https://www.hotels.com/de1633596/hotels-miami-florida/", "Top Hotels in Miami - Hotels.com"),
    ("https://www.carnival.com/cruise-search", "Find a Cruise | Carnival Cruise Line"),
    ("https://disneycruise.disney.go.com/destinations/bahamas/", "Bahamas Cruises | Disney Cruise Line"),
]

# Generate 25 logistics entries and 20 travel entries
entries = []
for i in range(25):
    url, title = logistics_urls[i % len(logistics_urls)]
    entries.append((url, title))
for i in range(20):
    url, title = travel_urls[i % len(travel_urls)]
    entries.append((url, title))

# Insert into db
for idx, (url, title) in enumerate(entries):
    ts = int(chrome_base - (idx * 500000000))  # Distribute over time
    c.execute("INSERT INTO urls (url, title, visit_count, last_visit_time) VALUES (?, ?, ?, ?)", (url, title, 1, ts))
    c.execute("INSERT INTO visits (url, visit_time) VALUES (?, ?)", (idx + 1, ts))

conn.commit()
conn.close()
PY_HIST_EOF

# Ensure permissions
chown -R ga:ga /home/ga/.config/google-chrome/
chown ga:ga /home/ga/Desktop/dashboard_spec.txt

# Record setup completion timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# ── 6. Start Chrome ─────────────────────────────────────────────────────────
echo "Starting Chrome..."
su - ga -c "DISPLAY=:1 /usr/bin/google-chrome-stable --no-first-run --no-default-browser-check > /dev/null 2>&1 &"

# Wait for window and maximize
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "Chrome"; then
        DISPLAY=:1 wmctrl -r "Chrome" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup Complete ==="