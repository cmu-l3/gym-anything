#!/bin/bash
# Populate synthetic visitor data for Matomo
# This makes the Visitors Dashboard task more meaningful by providing data to display

set -e

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/task_utils.sh" 2>/dev/null || true

echo "=== Populating Synthetic Visitor Data ==="

# Check if Docker is available
if ! command -v docker &> /dev/null; then
    echo "Docker not available, skipping visitor data population"
    exit 0
fi

# Check if matomo-db container is running
if ! docker ps --format "{{.Names}}" 2>/dev/null | grep -q "matomo-db"; then
    echo "matomo-db container not running, skipping visitor data population"
    exit 0
fi

# Helper function to execute SQL
mysql_exec() {
    docker exec matomo-db mysql -u matomo -pmatomo123 matomo -N -e "$1" 2>/dev/null
}

# Check if site exists
SITE_COUNT=$(mysql_exec "SELECT COUNT(*) FROM matomo_site" 2>/dev/null || echo "0")
if [ "$SITE_COUNT" = "0" ]; then
    echo "No sites configured, skipping visitor data population"
    exit 0
fi

# Get the first site ID
SITE_ID=$(mysql_exec "SELECT idsite FROM matomo_site LIMIT 1" 2>/dev/null || echo "1")
echo "Populating data for site ID: $SITE_ID"

# Calculate date range (last 60 days to cover "last 30 days" filter with margin)
END_DATE=$(date +%Y-%m-%d)
START_DATE=$(date -d "-60 days" +%Y-%m-%d 2>/dev/null || date -v-60d +%Y-%m-%d 2>/dev/null || echo "2025-01-01")

echo "Date range: $START_DATE to $END_DATE"

# Check if data already exists (avoid duplicate inserts)
EXISTING_VISITS=$(mysql_exec "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
if [ "$EXISTING_VISITS" -gt 100 ]; then
    echo "Visitor data already exists ($EXISTING_VISITS visits), skipping population"
    exit 0
fi

echo "Generating synthetic visitor data..."

# Generate 30-60 days of visitor data
# Each day will have 5-20 visits with varying metrics

# Sample user agents for variety
USER_AGENTS=(
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0 Safari/537.36"
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 Chrome/119.0.0.0 Safari/537.36"
    "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Safari/605.1.15"
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0"
    "Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36"
)

# Sample referrers
REFERRERS=(
    "https://www.google.com/search?q=techblog"
    "https://twitter.com/techblog"
    "https://www.facebook.com/"
    "https://www.linkedin.com/"
    ""
)

# Sample pages
PAGES=(
    "/"
    "/about"
    "/blog"
    "/blog/article-1"
    "/blog/article-2"
    "/contact"
    "/newsletter"
    "/newsletter/thank-you"
)

# Sample countries (ISO codes)
COUNTRIES=("US" "GB" "DE" "FR" "CA" "AU" "JP" "BR" "IN" "NL")

# Generate random IP address
random_ip() {
    echo "$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256)).$((RANDOM % 256))"
}

# Generate visitor ID hash (16 char hex)
random_visitor_id() {
    head -c 16 /dev/urandom 2>/dev/null | md5sum 2>/dev/null | head -c 16 || \
    printf '%016x' $((RANDOM * RANDOM * RANDOM)) | head -c 16
}

# Build SQL statements in batches for efficiency
SQL_BATCH=""
VISIT_ID=1

# Get current max visit ID
MAX_VISIT_ID=$(mysql_exec "SELECT COALESCE(MAX(idvisit), 0) FROM matomo_log_visit" 2>/dev/null || echo "0")
VISIT_ID=$((MAX_VISIT_ID + 1))

echo "Starting from visit ID: $VISIT_ID"

# Generate data for each day in range
CURRENT_DATE="$START_DATE"
while [[ "$CURRENT_DATE" < "$END_DATE" ]] || [[ "$CURRENT_DATE" == "$END_DATE" ]]; do
    # Generate 5-20 visits per day
    VISITS_TODAY=$((5 + RANDOM % 16))

    for ((v=0; v<VISITS_TODAY; v++)); do
        # Random hour and minute
        HOUR=$((8 + RANDOM % 14))  # 8am to 10pm
        MINUTE=$((RANDOM % 60))
        SECOND=$((RANDOM % 60))

        VISIT_TIME="${CURRENT_DATE} $(printf '%02d:%02d:%02d' $HOUR $MINUTE $SECOND)"

        # Random visitor attributes
        VISITOR_ID=$(random_visitor_id)
        IP=$(random_ip)
        USER_AGENT="${USER_AGENTS[$((RANDOM % ${#USER_AGENTS[@]}))]}"
        REFERRER="${REFERRERS[$((RANDOM % ${#REFERRERS[@]}))]}"
        COUNTRY="${COUNTRIES[$((RANDOM % ${#COUNTRIES[@]}))]}"

        # Visit metrics
        ACTIONS=$((1 + RANDOM % 8))  # 1-8 pages per visit
        VISIT_DURATION=$((30 + RANDOM % 600))  # 30 seconds to 10 minutes

        # Determine if new visitor (30% chance) or returning (70% chance)
        NEW_VISITOR=$((RANDOM % 10 < 3 ? 1 : 0))

        # Escape single quotes in user agent and referrer
        USER_AGENT_ESC=$(echo "$USER_AGENT" | sed "s/'/''/g")
        REFERRER_ESC=$(echo "$REFERRER" | sed "s/'/''/g")

        # Build INSERT statement for log_visit
        SQL_BATCH="${SQL_BATCH}INSERT INTO matomo_log_visit (
            idvisit, idsite, idvisitor, visit_first_action_time, visit_last_action_time,
            visit_total_actions, visit_total_time, visitor_returning, visitor_count_visits,
            location_country, config_browser_name, config_browser_version,
            referer_type, referer_url
        ) VALUES (
            $VISIT_ID, $SITE_ID, UNHEX('$VISITOR_ID'), '$VISIT_TIME',
            DATE_ADD('$VISIT_TIME', INTERVAL $VISIT_DURATION SECOND),
            $ACTIONS, $VISIT_DURATION, $((1 - NEW_VISITOR)), $((1 + RANDOM % 5)),
            '$COUNTRY', 'CH', '120',
            $((RANDOM % 3 + 1)), '$REFERRER_ESC'
        );\n"

        VISIT_ID=$((VISIT_ID + 1))
    done

    # Move to next day
    CURRENT_DATE=$(date -d "$CURRENT_DATE + 1 day" +%Y-%m-%d 2>/dev/null || \
                   date -j -v+1d -f "%Y-%m-%d" "$CURRENT_DATE" +%Y-%m-%d 2>/dev/null || \
                   echo "")

    # If date calculation fails, break
    if [ -z "$CURRENT_DATE" ]; then
        break
    fi
done

# Execute the batch SQL
if [ -n "$SQL_BATCH" ]; then
    echo "Inserting visitor records..."
    # Use printf to handle the escaped newlines properly
    printf "$SQL_BATCH" | docker exec -i matomo-db mysql -u matomo -pmatomo123 matomo 2>/dev/null || true
    echo "Visitor data insertion complete"
fi

# Verify data was inserted
FINAL_COUNT=$(mysql_exec "SELECT COUNT(*) FROM matomo_log_visit WHERE idsite=$SITE_ID" 2>/dev/null || echo "0")
echo "Total visits in database: $FINAL_COUNT"

# Generate archive tables (summary data) via Matomo's archiving
# This makes the dashboard show aggregated metrics
echo "Triggering Matomo archive process..."
docker exec matomo php /var/www/html/console core:archive --force-all-websites 2>/dev/null || \
docker exec matomo php /var/www/html/console core:archive 2>/dev/null || \
echo "Archive process skipped (may need manual trigger or Matomo not fully installed)"

echo "=== Visitor Data Population Complete ==="
echo "Sites: $SITE_COUNT"
echo "Total visits: $FINAL_COUNT"
