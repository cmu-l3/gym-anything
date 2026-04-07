#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Retrieve initial count
INITIAL_COUNT=$(cat /tmp/initial_phys_count.txt 2>/dev/null || echo "0")
FINAL_COUNT=$(mysql -u freemed -pfreemed freemed -N -e "SELECT COUNT(*) FROM physician;" 2>/dev/null || echo "0")

# 1. Query the FreeMED database specifically for the physician
# Replace newlines and tabs to ensure clean extraction
PHYSICIAN_DATA=$(mysql -u freemed -pfreemed freemed -N -e "SELECT phyfname, phylname, physpecialty, phynpi, phyphone, phyfax FROM physician WHERE phylname LIKE '%Pendelton%' LIMIT 1" 2>/dev/null)

FOUND="false"
FNAME=""
LNAME=""
SPEC=""
NPI=""
PHONE=""
FAX=""

if [ -n "$PHYSICIAN_DATA" ]; then
    FOUND="true"
    FNAME=$(echo "$PHYSICIAN_DATA" | cut -f1)
    LNAME=$(echo "$PHYSICIAN_DATA" | cut -f2)
    SPEC=$(echo "$PHYSICIAN_DATA" | cut -f3)
    NPI=$(echo "$PHYSICIAN_DATA" | cut -f4)
    PHONE=$(echo "$PHYSICIAN_DATA" | cut -f5)
    FAX=$(echo "$PHYSICIAN_DATA" | cut -f6)
fi

# 2. General database dump to catch misfiled records (e.g. if saved to addressbook instead)
mysqldump -u freemed -pfreemed freemed > /tmp/db_dump.sql
DUMP_HAS_NAME=$(grep -i "Pendelton" /tmp/db_dump.sql | wc -l)
DUMP_HAS_NPI=$(grep "1928374650" /tmp/db_dump.sql | wc -l)

# Escape strings safely for JSON
FNAME_ESC=$(echo "$FNAME" | sed 's/"/\\"/g')
LNAME_ESC=$(echo "$LNAME" | sed 's/"/\\"/g')
SPEC_ESC=$(echo "$SPEC" | sed 's/"/\\"/g')

# Write to JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "physician_found": $FOUND,
    "fname": "$FNAME_ESC",
    "lname": "$LNAME_ESC",
    "specialty": "$SPEC_ESC",
    "npi": "$NPI",
    "phone": "$PHONE",
    "fax": "$FAX",
    "initial_count": $INITIAL_COUNT,
    "final_count": $FINAL_COUNT,
    "dump_has_name_count": $DUMP_HAS_NAME,
    "dump_has_npi_count": $DUMP_HAS_NPI
}
EOF

# Ensure file exists with correct permissions
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="