#!/bin/bash
set -e
echo "=== Setting up join_table_to_layer task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
GVSIG_DATA_DIR="/home/ga/gvsig_data"
EXPORTS_DIR="$GVSIG_DATA_DIR/exports"
mkdir -p "$EXPORTS_DIR"
chown -R ga:ga "$GVSIG_DATA_DIR"

# Clean previous artifacts
rm -f "$EXPORTS_DIR/countries_with_indicators."* 2>/dev/null || true

# -------------------------------------------------------------------
# 1. Create World Bank Indicators CSV with REAL data
# -------------------------------------------------------------------
CSV_FILE="$GVSIG_DATA_DIR/world_bank_indicators.csv"
echo "Creating World Bank indicators CSV at $CSV_FILE..."

cat > "$CSV_FILE" << 'CSVEOF'
ISO3,COUNTRY,CO2_PC,LIFE_EXP,INTERNET_PCT
AFG,Afghanistan,0.20,64.83,18.4
AGO,Angola,0.60,61.15,36.0
ALB,Albania,1.57,76.99,72.2
ARE,United Arab Emirates,20.70,78.46,98.5
ARG,Argentina,3.70,76.52,87.1
AUS,Australia,15.22,83.20,96.2
AUT,Austria,7.37,81.54,92.4
BEL,Belgium,8.15,81.36,92.7
BGD,Bangladesh,0.53,72.87,31.5
BRA,Brazil,1.95,75.88,81.3
CAN,Canada,14.43,82.43,97.0
CHE,Switzerland,4.02,83.45,96.0
CHL,Chile,4.35,80.18,82.3
CHN,China,7.41,77.10,70.6
COL,Colombia,1.60,77.29,69.8
DEU,Germany,7.72,81.33,93.0
DNK,Denmark,5.18,81.56,98.1
EGY,Egypt,2.21,71.99,71.9
ESP,Spain,5.15,83.56,93.2
FIN,Finland,7.20,81.88,92.2
FRA,France,4.52,82.66,89.6
GBR,United Kingdom,5.20,81.77,96.5
GRC,Greece,5.62,80.10,78.4
IDN,Indonesia,2.03,71.72,53.7
IND,India,1.74,69.89,43.0
IRL,Ireland,7.75,82.81,92.0
IRN,Iran,7.81,76.68,79.0
ISR,Israel,6.92,82.97,87.5
ITA,Italy,5.13,83.51,85.0
JPN,Japan,8.55,84.62,90.2
KOR,Korea Republic of,11.59,83.23,96.5
MEX,Mexico,3.17,75.05,71.5
MYS,Malaysia,7.63,76.16,89.6
NGA,Nigeria,0.51,54.69,35.5
NLD,Netherlands,8.39,82.28,93.2
NOR,Norway,7.54,83.16,98.4
NZL,New Zealand,6.87,82.31,93.2
PAK,Pakistan,0.89,66.99,17.1
POL,Poland,7.98,78.73,87.0
PRT,Portugal,4.44,81.95,82.0
QAT,Qatar,32.82,80.23,99.7
RUS,Russia,11.12,73.08,82.6
SAU,Saudi Arabia,15.26,75.13,97.9
SWE,Sweden,3.61,82.80,96.4
THA,Thailand,3.65,77.74,77.8
TUR,Turkey,4.65,77.69,77.7
UKR,Ukraine,4.28,73.62,75.0
USA,United States,13.68,77.28,90.0
VNM,Vietnam,2.76,75.40,68.7
ZAF,South Africa,6.75,64.13,68.2
CSVEOF

chown ga:ga "$CSV_FILE"
chmod 644 "$CSV_FILE"

# -------------------------------------------------------------------
# 2. Record original shapefile stats (to compare later)
# -------------------------------------------------------------------
# Install pyshp for analysis if not present
if ! pip3 freeze | grep -q pyshp; then
    pip3 install pyshp --quiet 2>/dev/null || true
fi

python3 << 'PYEOF' 2>/dev/null || true
import shapefile
try:
    sf = shapefile.Reader("/home/ga/gvsig_data/countries/ne_110m_admin_0_countries")
    # Subtract 1 for DeletionFlag if present, but len(fields) usually includes it
    field_count = len(sf.fields) 
    with open("/tmp/original_field_count.txt", "w") as f:
        f.write(str(field_count))
except Exception as e:
    print(f"Warning: {e}")
PYEOF

# -------------------------------------------------------------------
# 3. Launch gvSIG Desktop
# -------------------------------------------------------------------
# Kill any existing instances
pkill -f "gvSIG" 2>/dev/null || true
sleep 2

# Launch fresh gvSIG (no project)
launch_gvsig ""

# Take initial screenshot
sleep 5
take_screenshot /tmp/task_initial.png
if [ -f /tmp/task_initial.png ]; then
    echo "Initial screenshot captured"
else
    echo "WARNING: Failed to capture initial screenshot"
fi

echo "=== Setup complete ==="