#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Initialize variables
PEM_EXISTS="false"
PEM_CREATED_DURING_TASK="false"
CERT_SUBJECT=""
PEM_FILENAME=""

# Find any PEM file in the Downloads directory
PEM_FILE=$(find /home/ga/Downloads -maxdepth 1 -name "*.pem" -type f | head -n 1)

if [ -n "$PEM_FILE" ]; then
    PEM_EXISTS="true"
    PEM_FILENAME=$(basename "$PEM_FILE")
    
    # Check if the file was created after the task started
    OUTPUT_MTIME=$(stat -c %Y "$PEM_FILE" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -ge "$TASK_START" ]; then
        PEM_CREATED_DURING_TASK="true"
    fi
    
    # Extract the cryptographic subject of the certificate using openssl
    # Strip quotes, backslashes, and newlines to prevent JSON syntax issues
    CERT_SUBJECT=$(openssl x509 -in "$PEM_FILE" -noout -subject 2>/dev/null | tr -d '\n' | tr -d '"' | tr -d '\\')
    if [ -z "$CERT_SUBJECT" ]; then
        CERT_SUBJECT="INVALID_CERT"
    fi
fi

# Query Firefox Places database for history (Anti-gaming check)
PROFILE_DIR="/home/ga/.mozilla/firefox/default.profile"
PLACES_DB="$PROFILE_DIR/places.sqlite"

WIKI_VISITED="false"
CERT_VIEWER_VISITED="false"

if [ -f "$PLACES_DB" ]; then
    # Copy DB to tmp to avoid locking issues while Firefox is running
    cp "$PLACES_DB" /tmp/places_copy.sqlite
    
    WIKI_COUNT=$(sqlite3 /tmp/places_copy.sqlite "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%wikipedia.org%';" 2>/dev/null || echo "0")
    if [ "$WIKI_COUNT" -gt 0 ]; then
        WIKI_VISITED="true"
    fi
    
    CERT_COUNT=$(sqlite3 /tmp/places_copy.sqlite "SELECT COUNT(*) FROM moz_places WHERE url LIKE '%about:certificate%';" 2>/dev/null || echo "0")
    if [ "$CERT_COUNT" -gt 0 ]; then
        CERT_VIEWER_VISITED="true"
    fi
    
    rm -f /tmp/places_copy.sqlite
fi

# Create JSON result (use temp file for permission safety)
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "pem_exists": $PEM_EXISTS,
    "pem_filename": "$PEM_FILENAME",
    "pem_created_during_task": $PEM_CREATED_DURING_TASK,
    "cert_subject": "$CERT_SUBJECT",
    "wiki_visited": $WIKI_VISITED,
    "cert_viewer_visited": $CERT_VIEWER_VISITED
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null
chmod 666 /tmp/task_result.json 2>/dev/null
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="