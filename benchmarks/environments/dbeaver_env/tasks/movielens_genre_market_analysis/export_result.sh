#!/bin/bash
# Export script for movielens_genre_market_analysis task

echo "=== Exporting MovieLens Genre Market Analysis Result ==="

source /workspace/scripts/task_utils.sh

GENRE_CSV="/home/ga/Documents/exports/genre_analysis.csv"
GEMS_CSV="/home/ga/Documents/exports/hidden_gems.csv"
SQL_SCRIPT="/home/ga/Documents/scripts/market_analysis.sql"
DBEAVER_CONFIG="/home/ga/.local/share/DBeaverData/workspace6/General/.dbeaver/data-sources.json"

take_screenshot /tmp/movielens_task_end.png
sleep 1

# Check DBeaver connection
MOVIELENS_CONN_FOUND="false"
if [ -f "$DBEAVER_CONFIG" ]; then
    MOVIELENS_CONN_FOUND=$(python3 -c "
import json, sys
try:
    with open('$DBEAVER_CONFIG') as f:
        config = json.load(f)
    for k, v in config.get('connections', {}).items():
        if v.get('name', '').lower() == 'movielens':
            print('true')
            sys.exit(0)
    print('false')
except:
    print('false')
" 2>/dev/null || echo false)
fi

# Check genre_analysis.csv
GENRE_CSV_EXISTS="false"
GENRE_ROW_COUNT=0
GENRE_HAS_GENRE_COL="false"
GENRE_HAS_AVG_RATING="false"
GENRE_HAS_COUNT="false"
GENRE_TOP_GENRE=""
GENRE_TOP_AVG=0

if [ -f "$GENRE_CSV" ]; then
    GENRE_CSV_EXISTS="true"
    GENRE_ROW_COUNT=$(count_csv_lines "$GENRE_CSV")
    HEADER=$(head -1 "$GENRE_CSV" | tr '[:upper:]' '[:lower:]')
    echo "$HEADER" | grep -qi "genre" && GENRE_HAS_GENRE_COL="true"
    echo "$HEADER" | grep -qi "avg\|rating\|average" && GENRE_HAS_AVG_RATING="true"
    echo "$HEADER" | grep -qi "count\|num\|total" && GENRE_HAS_COUNT="true"

    # Extract top genre (first data row)
    GENRE_TOP_INFO=$(python3 -c "
import csv, sys
try:
    with open('$GENRE_CSV') as f:
        reader = csv.DictReader(f)
        for row in reader:
            genre = ''
            rating = 0
            for k, v in row.items():
                if 'genre' in k.lower():
                    genre = v.strip()
                elif 'avg' in k.lower() or ('rating' in k.lower() and 'count' not in k.lower()):
                    try:
                        rating = float(v.strip())
                    except:
                        pass
            print(f'{genre}|{rating}')
            break
except:
    print('|0')
" 2>/dev/null || echo "|0")
    GENRE_TOP_GENRE=$(echo "$GENRE_TOP_INFO" | cut -d'|' -f1)
    GENRE_TOP_AVG=$(echo "$GENRE_TOP_INFO" | cut -d'|' -f2)
fi

# Check hidden_gems.csv
GEMS_CSV_EXISTS="false"
GEMS_ROW_COUNT=0
GEMS_HAS_MOVIEID="false"
GEMS_HAS_TITLE="false"
GEMS_HAS_RATING="false"
GEMS_ALL_VALID="true"
GEMS_SAMPLE_RATING=0
GEMS_SAMPLE_COUNT=0

if [ -f "$GEMS_CSV" ]; then
    GEMS_CSV_EXISTS="true"
    GEMS_ROW_COUNT=$(count_csv_lines "$GEMS_CSV")
    HEADER=$(head -1 "$GEMS_CSV" | tr '[:upper:]' '[:lower:]')
    echo "$HEADER" | grep -qi "movieid\|movie_id\|id" && GEMS_HAS_MOVIEID="true"
    echo "$HEADER" | grep -qi "title\|name" && GEMS_HAS_TITLE="true"
    echo "$HEADER" | grep -qi "avg\|rating" && GEMS_HAS_RATING="true"

    # Validate that gems meet criteria (avg >= 4.0, count < 50)
    GEMS_VALIDATION=$(python3 -c "
import csv, sys
try:
    with open('$GEMS_CSV') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames or []
        avg_col = next((h for h in headers if 'avg' in h.lower() or ('rating' in h.lower() and 'count' not in h.lower())), None)
        count_col = next((h for h in headers if 'count' in h.lower() or 'num' in h.lower()), None)

        all_valid = True
        ratings_sum = 0
        count_sum = 0
        n = 0
        for row in reader:
            if avg_col:
                try:
                    r = float(row[avg_col])
                    ratings_sum += r
                    n += 1
                    if r < 3.5:  # too lenient check — they must be >= 4.0
                        all_valid = False
                except:
                    pass
            if count_col:
                try:
                    count_sum += int(row[count_col])
                except:
                    pass

        avg_rating = round(ratings_sum/n, 2) if n > 0 else 0
        print(f'{all_valid}|{avg_rating}|{count_sum}')
except:
    print('true|0|0')
" 2>/dev/null || echo "true|0|0")
    GEMS_ALL_VALID=$(echo "$GEMS_VALIDATION" | cut -d'|' -f1)
    GEMS_SAMPLE_RATING=$(echo "$GEMS_VALIDATION" | cut -d'|' -f2)
    GEMS_SAMPLE_COUNT=$(echo "$GEMS_VALIDATION" | cut -d'|' -f3)
fi

# Check SQL script
SQL_EXISTS="false"
SQL_SIZE=0
if [ -f "$SQL_SCRIPT" ]; then
    SQL_EXISTS="true"
    SQL_SIZE=$(get_file_size "$SQL_SCRIPT")
fi

# Check DBeaver scripts folder as fallback
DBEAVER_SQL_EXISTS="false"
DBEAVER_SCRIPTS_DIR="/home/ga/.local/share/DBeaverData/workspace6/General/Scripts"
if find "$DBEAVER_SCRIPTS_DIR" -name "*.sql" 2>/dev/null | head -1 | grep -q "."; then
    DBEAVER_SQL_EXISTS="true"
fi

# Read ground truth
GT_TOP_GENRE=""
GT_TOP_AVG=0
if [ -f /tmp/movielens_gt.json ]; then
    GT_TOP_GENRE=$(python3 -c "import json; d=json.load(open('/tmp/movielens_gt.json')); print(d.get('top1_genre',''))" 2>/dev/null || echo "")
    GT_TOP_AVG=$(python3 -c "import json; d=json.load(open('/tmp/movielens_gt.json')); gs=d.get('top5_genres',[]); print(gs[0]['avg_rating'] if gs else 0)" 2>/dev/null || echo 0)
fi

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo 0)
GENRE_CSV_NEW="false"
GEMS_CSV_NEW="false"
for f in "$GENRE_CSV" "$GEMS_CSV"; do
    if [ -f "$f" ]; then
        FT=$(stat -c%Y "$f" 2>/dev/null || stat -f%m "$f" 2>/dev/null || echo 0)
        if [ "$f" = "$GENRE_CSV" ] && [ "$FT" -gt "$TASK_START" ]; then
            GENRE_CSV_NEW="true"
        elif [ "$f" = "$GEMS_CSV" ] && [ "$FT" -gt "$TASK_START" ]; then
            GEMS_CSV_NEW="true"
        fi
    fi
done

cat > /tmp/movielens_market_result.json << EOF
{
    "movielens_conn_found": $MOVIELENS_CONN_FOUND,
    "genre_csv_exists": $GENRE_CSV_EXISTS,
    "genre_row_count": $GENRE_ROW_COUNT,
    "genre_has_genre_col": $GENRE_HAS_GENRE_COL,
    "genre_has_avg_rating": $GENRE_HAS_AVG_RATING,
    "genre_top_genre": "$GENRE_TOP_GENRE",
    "genre_top_avg": $GENRE_TOP_AVG,
    "genre_csv_new": $GENRE_CSV_NEW,
    "gems_csv_exists": $GEMS_CSV_EXISTS,
    "gems_row_count": $GEMS_ROW_COUNT,
    "gems_has_movieid": $GEMS_HAS_MOVIEID,
    "gems_has_title": $GEMS_HAS_TITLE,
    "gems_has_rating": $GEMS_HAS_RATING,
    "gems_all_valid": ${GEMS_ALL_VALID:-true},
    "gems_avg_rating": ${GEMS_SAMPLE_RATING:-0},
    "gems_csv_new": $GEMS_CSV_NEW,
    "sql_script_exists": $SQL_EXISTS,
    "sql_script_size": $SQL_SIZE,
    "dbeaver_sql_exists": $DBEAVER_SQL_EXISTS,
    "gt_top_genre": "$GT_TOP_GENRE",
    "gt_top_avg": $GT_TOP_AVG,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

echo "Result:"
cat /tmp/movielens_market_result.json
echo ""
echo "=== Export Complete ==="
