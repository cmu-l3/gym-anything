#!/bin/bash
echo "=== Setting up Chinook Partner Sales ETL Task ==="

source /workspace/scripts/task_utils.sh

# Directories
DATA_DIR="/home/ga/Documents/data"
EXPORT_DIR="/home/ga/Documents/exports"
DB_PATH="/home/ga/Documents/databases/chinook.db"

# Create directories
mkdir -p "$DATA_DIR" "$EXPORT_DIR"
chown -R ga:ga /home/ga/Documents/

# Clean up previous runs
rm -f "$DATA_DIR/festival_sales.csv"
rm -f "$EXPORT_DIR/festival_sales_exceptions.csv"

# Record start time
date +%s > /tmp/task_start_time.txt

# Create the Input CSV with specific Valid and Invalid rows
# We need to ensure we use real data from Chinook for the valid rows.
# Valid 1: Customer 1 (luisg@embraer.com.br), Track: For Those About To Rock (We Salute You), Artist: AC/DC
# Valid 2: Customer 2 (leonekohler@surfeu.de), Track: Balls to the Wall, Artist: Accept
# Valid 3: Customer 3 (ftremblay@gmail.com), Track: Fast As a Shark, Artist: Accept
# Valid 4: Customer 4 (bjorn.hansen@yahoo.no), Track: Restless and Wild, Artist: Accept
# Valid 5: Customer 5 (frantisekw@jetbrains.com), Track: Princess of the Dawn, Artist: Accept

# Invalid 1: Bad Email (fake@example.com)
# Invalid 2: Bad Artist for Song (Song: Balls to the Wall, Artist: AC/DC)
# Invalid 3: Bad Song (Song: Non Existent Song, Artist: AC/DC)
# Invalid 4: Bad Email + Bad Song

cat > "$DATA_DIR/festival_sales.csv" << EOF
SaleDate,UserEmail,SongTitle,ArtistName,Price
2025-01-01,luisg@embraer.com.br,For Those About To Rock (We Salute You),AC/DC,0.99
2025-01-02,leonekohler@surfeu.de,Balls to the Wall,Accept,0.99
2025-01-03,fake@example.com,Put The Finger On You,AC/DC,0.99
2025-01-04,ftremblay@gmail.com,Fast As a Shark,Accept,0.99
2025-01-05,luisg@embraer.com.br,Non Existent Song,AC/DC,0.99
2025-01-06,bjorn.hansen@yahoo.no,Restless and Wild,Accept,0.99
2025-01-07,leonekohler@surfeu.de,Balls to the Wall,AC/DC,0.99
2025-01-08,frantisekw@jetbrains.com,Princess of the Dawn,Accept,0.99
2025-01-09,totally.fake@email.net,Fake Song,Fake Artist,0.99
EOF

# Set permissions
chown ga:ga "$DATA_DIR/festival_sales.csv"

# Ensure DBeaver is running
if ! is_dbeaver_running; then
    echo "Starting DBeaver..."
    su - ga -c "DISPLAY=:1 dbeaver &" 2>/dev/null &
    sleep 10
fi

# Focus DBeaver
focus_dbeaver

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="
echo "Input file created: $DATA_DIR/festival_sales.csv"
echo "Expected Valid Rows: 5"
echo "Expected Exception Rows: 4"