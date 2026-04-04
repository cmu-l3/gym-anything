#!/bin/bash
# Export script for world_integrity_audit task

echo "=== Exporting World Integrity Audit Result ==="

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi

take_screenshot /tmp/task_end_screenshot.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")

# Count remaining orphaned cities (CountryCode not in country table)
ORPHAN_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city c
    LEFT JOIN country co ON c.CountryCode = co.Code
    WHERE co.Code IS NULL;
" 2>/dev/null)
ORPHAN_COUNT=${ORPHAN_COUNT:-999}

# Count remaining ZZZ cities specifically
ZZZ_REMAINING=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city WHERE CountryCode='ZZZ';
" 2>/dev/null)
ZZZ_REMAINING=${ZZZ_REMAINING:-999}

# Count remaining ZZX cities specifically
ZZX_REMAINING=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city WHERE CountryCode='ZZX';
" 2>/dev/null)
ZZX_REMAINING=${ZZX_REMAINING:-999}

# Count remaining zero-population cities
ZERO_POP_REMAINING=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city WHERE Population = 0;
" 2>/dev/null)
ZERO_POP_REMAINING=${ZERO_POP_REMAINING:-999}

# Count remaining exact duplicates (same Name + CountryCode + District, but multiple rows)
DUPLICATE_COUNT=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT SUM(cnt - 1) FROM (
        SELECT COUNT(*) AS cnt FROM city
        GROUP BY Name, CountryCode, District
        HAVING COUNT(*) > 1
    ) AS dupes;
" 2>/dev/null)
DUPLICATE_COUNT=${DUPLICATE_COUNT:-0}
[ -z "$DUPLICATE_COUNT" ] && DUPLICATE_COUNT=0

# Count current South America cities (after cleanup)
SA_CURRENT=$(mysql -u root -p'GymAnything#2024' world -N -e "
    SELECT COUNT(*) FROM city c
    JOIN country co ON c.CountryCode = co.Code
    WHERE co.Continent = 'South America'
" 2>/dev/null)
SA_CURRENT=${SA_CURRENT:-0}

EXPECTED_SA=$(cat /tmp/expected_sa_count 2>/dev/null || echo "0")

# Check CSV export
CSV_EXISTS="false"
CSV_ROWS=0
CSV_MTIME=0
OUTPUT_FILE="/home/ga/Documents/exports/south_america_cities.csv"
if [ -f "$OUTPUT_FILE" ]; then
    CSV_EXISTS="true"
    CSV_MTIME=$(stat -c%Y "$OUTPUT_FILE" 2>/dev/null || echo "0")
    TOTAL_LINES=$(wc -l < "$OUTPUT_FILE" 2>/dev/null || echo "0")
    CSV_ROWS=$((TOTAL_LINES - 1))
    [ "$CSV_ROWS" -lt 0 ] && CSV_ROWS=0
fi

# Read initial injected counts
INITIAL_ZZZ=$(cat /tmp/initial_zzz_count 2>/dev/null || echo "35")
INITIAL_ZZX=$(cat /tmp/initial_zzx_count 2>/dev/null || echo "10")
INITIAL_ZERO=$(cat /tmp/initial_zero_pop 2>/dev/null || echo "8")

cat > /tmp/world_audit_result.json << EOF
{
    "orphan_count_remaining": $ORPHAN_COUNT,
    "zzz_remaining": $ZZZ_REMAINING,
    "zzx_remaining": $ZZX_REMAINING,
    "zzz_initial": $INITIAL_ZZZ,
    "zzx_initial": $INITIAL_ZZX,
    "zero_pop_remaining": $ZERO_POP_REMAINING,
    "zero_pop_initial": $INITIAL_ZERO,
    "duplicate_count_remaining": $DUPLICATE_COUNT,
    "sa_city_count_current": $SA_CURRENT,
    "sa_city_count_expected": $EXPECTED_SA,
    "csv_exists": $CSV_EXISTS,
    "csv_rows": $CSV_ROWS,
    "csv_mtime": $CSV_MTIME,
    "task_start": $TASK_START,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result: orphans_remaining=${ORPHAN_COUNT} zzz=${ZZZ_REMAINING} zzx=${ZZX_REMAINING} zero_pop=${ZERO_POP_REMAINING} duplicates=${DUPLICATE_COUNT} sa_csv=${CSV_EXISTS}(${CSV_ROWS}rows)"
echo "=== Export Complete ==="
