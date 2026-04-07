#!/bin/bash
# Setup script for world_data_import_functions task

echo "=== Setting up World Data Import & Functions Task ==="

source /workspace/scripts/task_utils.sh

# 1. Start Services
# Ensure MySQL is running
if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL service..."
    systemctl start mysql
    sleep 5
fi

# Ensure MySQL Workbench is running (minimized or background for agent to open/focus)
if [ "$(is_workbench_running)" = "false" ]; then
    echo "Starting MySQL Workbench..."
    start_workbench
    sleep 10
fi
focus_workbench

# 2. Prepare Directories
mkdir -p /home/ga/Documents/imports
mkdir -p /home/ga/Documents/exports
chown -R ga:ga /home/ga/Documents

# 3. Clean Previous State
echo "Cleaning previous artifacts..."
mysql -u root -p'GymAnything#2024' -e "DROP DATABASE IF EXISTS world_analytics;" 2>/dev/null
rm -f /home/ga/Documents/imports/country_indicators.csv
rm -f /home/ga/Documents/exports/country_analysis.csv

# 4. Generate Real Input Data
# We query the existing 'world' database to generate the CSV.
# We calculate PopulationDensity and GNPPerCapita roughly for the CSV so the agent just imports them.
# Note: GNP is in millions in world DB.
echo "Generating input CSV from world database..."

# Create a temporary SQL script to generate the CSV format
# We handle NULLs and Division by Zero
cat > /tmp/generate_csv.sql << SQL_EOF
SELECT 
    Code as CountryCode,
    Name as CountryName,
    Population,
    SurfaceArea,
    GNP,
    LifeExpectancy,
    ROUND(IF(SurfaceArea=0, 0, Population/SurfaceArea), 2) as PopulationDensity,
    ROUND(IF(Population=0, 0, (GNP*1000000)/Population), 2) as GNPPerCapita
FROM world.country
ORDER BY Code;
SQL_EOF

# Execute query and format as CSV
# Header
echo "CountryCode,CountryName,Population,SurfaceArea,GNP,LifeExpectancy,PopulationDensity,GNPPerCapita" > /home/ga/Documents/imports/country_indicators.csv

# Body (using mysql batch mode to output tab separated, then converting tab to comma)
# We use sed to handle potential commas in Country Names if any (though world db is mostly clean, we quote strings)
mysql -u root -p'GymAnything#2024' -N < /tmp/generate_csv.sql | sed 's/\t/,/g' >> /home/ga/Documents/imports/country_indicators.csv

# Ensure the file is owned by ga
chown ga:ga /home/ga/Documents/imports/country_indicators.csv

# Verify CSV generation
LINE_COUNT=$(wc -l < /home/ga/Documents/imports/country_indicators.csv)
echo "Generated CSV with $LINE_COUNT lines."

# 5. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_timestamp

# 6. Take Screenshot
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Input file prepared at: /home/ga/Documents/imports/country_indicators.csv"