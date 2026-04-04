#!/bin/bash
set -e
echo "=== Setting up import_csv_data task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Wait for OrientDB to be ready
wait_for_orientdb 120

# Reset state: Drop Airports and IsInCountry classes if they exist from previous runs
echo "Cleaning up previous state..."
orientdb_sql "demodb" "DROP CLASS IsInCountry UNSAFE" > /dev/null 2>&1 || true
orientdb_sql "demodb" "DROP CLASS Airports UNSAFE" > /dev/null 2>&1 || true

# Verify clean state
INITIAL_STATE=$(orientdb_class_exists "demodb" "Airports")
echo "Initial state (Airports exists?): $INITIAL_STATE"

# Create the CSV file with real OpenFlights airport data
cat > /home/ga/airports.csv << 'CSVEOF'
IataCode,Name,City,Country,Latitude,Longitude,Altitude
FCO,Leonardo da Vinci-Fiumicino Airport,Rome,Italy,41.8003,12.2389,13
TXL,Berlin Tegel Airport,Berlin,Germany,52.5597,13.2877,122
CDG,Charles de Gaulle Airport,Paris,France,49.0097,2.5479,392
LHR,Heathrow Airport,London,United Kingdom,51.4706,-0.4619,83
JFK,John F Kennedy International Airport,New York,United States,40.6398,-73.7789,13
NRT,Narita International Airport,Tokyo,Japan,35.7647,140.3864,141
SYD,Sydney Kingsford Smith International Airport,Sydney,Australia,-33.9461,151.1772,21
GIG,Rio de Janeiro-Antonio Carlos Jobim International Airport,Rio de Janeiro,Brazil,-22.8100,-43.2506,28
YYZ,Lester B Pearson International Airport,Toronto,Canada,43.6772,-79.6306,569
MAD,Adolfo Suarez Madrid-Barajas Airport,Madrid,Spain,40.4719,-3.5626,1998
ATH,Athens Eleftherios Venizelos International Airport,Athens,Greece,37.9364,23.9445,308
AMS,Amsterdam Airport Schiphol,Amsterdam,Netherlands,52.3086,4.7639,-11
MXP,Malpensa International Airport,Milan,Italy,45.6306,8.7231,768
MUC,Munich Airport,Munich,Germany,48.3538,11.7861,1487
ORY,Paris-Orly Airport,Paris,France,48.7233,2.3794,291
LGW,London Gatwick Airport,London,United Kingdom,51.1481,-0.1903,202
LAX,Los Angeles International Airport,Los Angeles,United States,33.9425,-118.4081,126
KIX,Kansai International Airport,Osaka,Japan,34.4273,135.2440,26
MEL,Melbourne Airport,Melbourne,Australia,-37.6733,144.8433,434
GRU,Guarulhos - Governador Andre Franco Montoro International Airport,Sao Paulo,Brazil,-23.4356,-46.4731,2459
CSVEOF

# Set permissions
chown ga:ga /home/ga/airports.csv
chmod 644 /home/ga/airports.csv
echo "CSV file created at /home/ga/airports.csv with 20 airports"

# Ensure Firefox is open at OrientDB Studio
ensure_firefox_at_studio "http://localhost:2480/studio/index.html"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="