#!/bin/bash
# Setup script for world_integrity_audit task

echo "=== Setting up World Database Integrity Audit Task ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type is_mysql_running &>/dev/null; then
    is_mysql_running() { mysqladmin ping -h localhost -u root -p'GymAnything#2024' 2>/dev/null && echo "true" || echo "false"; }
fi
if ! type start_workbench &>/dev/null; then
    start_workbench() { su - ga -c "DISPLAY=:1 /snap/bin/mysql-workbench-community > /tmp/mysql-workbench.log 2>&1 &"; sleep 10; }
fi
if ! type is_workbench_running &>/dev/null; then
    is_workbench_running() { pgrep -f "mysql-workbench" > /dev/null 2>&1 && echo "true" || echo "false"; }
fi
if ! type focus_workbench &>/dev/null; then
    focus_workbench() { local wid=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "workbench\|mysql" | head -1 | awk '{print $1}'); [ -n "$wid" ] && DISPLAY=:1 wmctrl -ia "$wid" 2>/dev/null || true; }
fi

date +%s > /tmp/task_start_timestamp

if [ "$(is_mysql_running)" = "false" ]; then
    echo "Starting MySQL..."
    systemctl start mysql
    sleep 5
fi

# Verify World DB is loaded
CITY_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city;" 2>/dev/null)
echo "World DB city count before injection: ${CITY_COUNT:-0}"

if [ "${CITY_COUNT:-0}" -lt 4000 ]; then
    echo "ERROR: World database not loaded correctly (expected ~4079 cities, got ${CITY_COUNT:-0})"
    exit 1
fi

# Clean up any previous injection (idempotent setup)
mysql -u root -p'GymAnything#2024' world -e "
    DELETE FROM city WHERE CountryCode IN ('ZZZ', 'ZZX');
" 2>/dev/null || true

# Also remove any previously injected zero-population test cities
mysql -u root -p'GymAnything#2024' world -e "
    DELETE FROM city WHERE Population = 0 AND District = 'InjectedZero';
" 2>/dev/null || true

# Remove any pre-existing duplicate cities (keep the lowest ID per unique (Name,CountryCode,District))
# This ensures the DB starts clean so our injected duplicates are the ONLY ones
mysql -u root -p'GymAnything#2024' world -e "
    DELETE FROM city WHERE ID NOT IN (
        SELECT minid FROM (
            SELECT MIN(ID) AS minid
            FROM city
            GROUP BY Name, CountryCode, District
        ) t
    );
" 2>/dev/null || true

# Record real city count before injection (this is the clean baseline)
CLEAN_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city;" 2>/dev/null)
echo "${CLEAN_COUNT:-0}" > /tmp/initial_real_city_count

# --- INJECT DATA QUALITY ISSUES ---
echo "Injecting referential integrity violations..."

# Issue 1: 35 cities with invalid CountryCode 'ZZZ' (doesn't exist in country table)
# These represent cities from a failed ETL import with unknown country codes
mysql -u root -p'GymAnything#2024' world << 'SQL'
SET FOREIGN_KEY_CHECKS = 0;
INSERT INTO city (Name, CountryCode, District, Population) VALUES
    ('Northhaven',   'ZZZ', 'Region Alpha',   145200),
    ('Eastport',     'ZZZ', 'Region Alpha',   89300),
    ('Southgate',    'ZZZ', 'Region Beta',    210000),
    ('Westfield',    'ZZZ', 'Region Beta',    67500),
    ('Centerburg',   'ZZZ', 'Region Gamma',   325000),
    ('Hilltop',      'ZZZ', 'Region Gamma',   44100),
    ('Riverside',    'ZZZ', 'Region Delta',   198700),
    ('Lakewood',     'ZZZ', 'Region Delta',   76400),
    ('Brookside',    'ZZZ', 'Region Epsilon', 154300),
    ('Pinecrest',    'ZZZ', 'Region Epsilon', 91200),
    ('Oakville',     'ZZZ', 'Region Zeta',    267800),
    ('Mapleburg',    'ZZZ', 'Region Zeta',    38900),
    ('Cedartown',    'ZZZ', 'Region Eta',     112500),
    ('Elmwood',      'ZZZ', 'Region Eta',     53700),
    ('Willowdale',   'ZZZ', 'Region Theta',   184600),
    ('Birchwood',    'ZZZ', 'Region Theta',   29800),
    ('Ashford',      'ZZZ', 'Region Iota',    95400),
    ('Stonehaven',   'ZZZ', 'Region Iota',    341200),
    ('Moorfield',    'ZZZ', 'Region Kappa',   72100),
    ('Ferndale',     'ZZZ', 'Region Kappa',   157800),
    ('Cliffside',    'ZZZ', 'Region Lambda',  43600),
    ('Redwood',      'ZZZ', 'Region Lambda',  228900),
    ('Sunnydale',    'ZZZ', 'Region Mu',      86300),
    ('Clearwater',   'ZZZ', 'Region Mu',      174500),
    ('Highridge',    'ZZZ', 'Region Nu',      61200),
    ('Valleyview',   'ZZZ', 'Region Nu',      308700),
    ('Springhill',   'ZZZ', 'Region Xi',      54800),
    ('Autumn Falls', 'ZZZ', 'Region Xi',      119600),
    ('Winterbourne', 'ZZZ', 'Region Omicron', 83200),
    ('Summerton',    'ZZZ', 'Region Omicron', 197400),
    ('Dawnridge',    'ZZZ', 'Region Pi',      47300),
    ('Duskholm',     'ZZZ', 'Region Pi',      262100),
    ('Midway',       'ZZZ', 'Region Rho',     136900),
    ('Crossroads',   'ZZZ', 'Region Rho',     71500),
    ('Junctionville','ZZZ', 'Region Sigma',   189300);
SET FOREIGN_KEY_CHECKS = 1;
SQL

# Issue 2: 10 cities with invalid CountryCode 'ZZX' (also doesn't exist)
mysql -u root -p'GymAnything#2024' world << 'SQL'
SET FOREIGN_KEY_CHECKS = 0;
INSERT INTO city (Name, CountryCode, District, Population) VALUES
    ('Portsmith',    'ZZX', 'District A',   223400),
    ('Harborview',   'ZZX', 'District A',   58700),
    ('Coastline',    'ZZX', 'District B',   341100),
    ('Tidewater',    'ZZX', 'District B',   92600),
    ('Bayshore',     'ZZX', 'District C',   165800),
    ('Covebury',     'ZZX', 'District C',   47200),
    ('Inletton',     'ZZX', 'District D',   278500),
    ('Shoreham',     'ZZX', 'District D',   83900),
    ('Beachfront',   'ZZX', 'District E',   134600),
    ('Seacliff',     'ZZX', 'District E',   61300);
SET FOREIGN_KEY_CHECKS = 1;
SQL

# Issue 3: 8 cities with Population = 0 (invalid — tagged with special District)
mysql -u root -p'GymAnything#2024' world << 'SQL'
SET FOREIGN_KEY_CHECKS = 0;
INSERT INTO city (Name, CountryCode, District, Population) VALUES
    ('EmptyCity1',  'USA', 'InjectedZero', 0),
    ('EmptyCity2',  'GBR', 'InjectedZero', 0),
    ('EmptyCity3',  'FRA', 'InjectedZero', 0),
    ('EmptyCity4',  'DEU', 'InjectedZero', 0),
    ('EmptyCity5',  'AUS', 'InjectedZero', 0),
    ('EmptyCity6',  'CAN', 'InjectedZero', 0),
    ('EmptyCity7',  'JPN', 'InjectedZero', 0),
    ('EmptyCity8',  'ITA', 'InjectedZero', 0);
SET FOREIGN_KEY_CHECKS = 1;
SQL

# Issue 4: 3 duplicate cities (same Name+CountryCode+District as existing real cities)
# We use well-known cities so they're clearly real
mysql -u root -p'GymAnything#2024' world << 'SQL'
SET FOREIGN_KEY_CHECKS = 0;
INSERT INTO city (Name, CountryCode, District, Population)
    SELECT Name, CountryCode, District, Population FROM city
    WHERE Name IN ('London', 'Paris', 'Berlin')
    AND CountryCode IN ('GBR', 'FRA', 'DEU')
    LIMIT 3;
SET FOREIGN_KEY_CHECKS = 1;
SQL

# Verify injection
TOTAL_AFTER=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city;" 2>/dev/null)
ZZZ_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city WHERE CountryCode='ZZZ';" 2>/dev/null)
ZZX_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city WHERE CountryCode='ZZX';" 2>/dev/null)
ZERO_POP=$(mysql -u root -p'GymAnything#2024' world -N -e "SELECT COUNT(*) FROM city WHERE Population=0;" 2>/dev/null)

echo "After injection: total=${TOTAL_AFTER} ZZZ=${ZZZ_COUNT} ZZX=${ZZX_COUNT} pop0=${ZERO_POP}"
echo "${ZZZ_COUNT:-0}" > /tmp/initial_zzz_count
echo "${ZZX_COUNT:-0}" > /tmp/initial_zzx_count
echo "${ZERO_POP:-0}" > /tmp/initial_zero_pop

# Record South America city count from clean data (needed for verification)
SA_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city c
    JOIN country co ON c.CountryCode = co.Code
    WHERE co.Continent = 'South America'
    AND c.Population > 0
" 2>/dev/null)
echo "${SA_COUNT:-0}" > /tmp/expected_sa_count
echo "Expected South America cities (clean): ${SA_COUNT:-0}"

# Clean previous export
rm -f /home/ga/Documents/exports/south_america_cities.csv 2>/dev/null || true

if [ "$(is_workbench_running)" = "false" ]; then
    start_workbench
    sleep 10
fi
focus_workbench

take_screenshot /tmp/task_start_screenshot.png
echo "=== Setup Complete ==="
echo "Injected: ${ZZZ_COUNT:-0} ZZZ orphans, ${ZZX_COUNT:-0} ZZX orphans, ${ZERO_POP:-0} zero-population, duplicates of London/Paris/Berlin"
