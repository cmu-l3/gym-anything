#!/bin/bash
echo "=== Setting up international_field_trip_accounting task ==="

SUGAR_ENV="DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"

mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# Record task start timestamp
date +%s > /tmp/trip_accounting_start_ts
chmod 666 /tmp/trip_accounting_start_ts

# 1. Create rates.json
cat > /home/ga/Documents/rates.json << 'EOF'
{
  "amount": 1.0,
  "base": "USD",
  "date": "2023-10-01",
  "rates": {
    "EUR": 0.945,
    "GBP": 0.815,
    "JPY": 149.24,
    "INR": 83.05
  }
}
EOF

# 2. Create base field_trip_expenses.csv
# We will inject a random amount for Airport Coffee to prevent hardcoding
RANDOM_JPY=$(( 400 + RANDOM % 400 ))

cat > /home/ga/Documents/field_trip_expenses.csv << EOF
Date,Item,Category,Amount,Currency
2023-10-01,Flight to Tokyo,Transport,850.00,USD
2023-10-02,Tokyo Hotel,Accommodation,45000,JPY
2023-10-02,Sushi Dinner,Food,6500,JPY
2023-10-03,Bullet Train,Transport,14000,JPY
2023-10-03,Museum Entry,Activities,2000,JPY
2023-10-04,Flight to London,Transport,620.00,USD
2023-10-05,London Hotel,Accommodation,350,GBP
2023-10-05,Fish and Chips,Food,18,GBP
2023-10-06,Tower of London,Activities,33,GBP
2023-10-07,Eurostar to Paris,Transport,110,EUR
2023-10-07,Paris Hotel,Accommodation,280,EUR
2023-10-08,Croissants,Food,12,EUR
2023-10-08,Louvre,Activities,17,EUR
2023-10-09,Flight to Delhi,Transport,450.00,USD
2023-10-10,Delhi Hotel,Accommodation,12000,INR
2023-10-10,Curry Dinner,Food,1500,INR
2023-10-11,Taj Mahal Tour,Activities,4500,INR
2023-10-12,Airport Coffee,Food,${RANDOM_JPY},JPY
EOF

chown ga:ga /home/ga/Documents/rates.json
chown ga:ga /home/ga/Documents/field_trip_expenses.csv

# Close any open activity first to return to home view
su - ga -c "$SUGAR_ENV xdotool key alt+shift+q" 2>/dev/null || true
sleep 3

# Take verification screenshot
su - ga -c "$SUGAR_ENV scrot /tmp/trip_task_start.png" 2>/dev/null || true

echo "=== international_field_trip_accounting task setup complete ==="
echo "Data files created with randomized values."