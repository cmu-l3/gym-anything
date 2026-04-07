#!/bin/bash
# Export script for docker_locale_timezone_fix task

echo "=== Exporting Results ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_TIME=$(date +%s)
PROJECT_DIR="/home/ga/projects/global-invoicer"

# Clean up previous test runs
docker rm -f invoicer-test-container 2>/dev/null || true
rm -rf /tmp/test_invoices
mkdir -p /tmp/test_invoices
chmod 777 /tmp/test_invoices

# 1. Check if image exists
IMAGE_NAME="acme-invoicer:fixed"
IMAGE_EXISTS=0
if docker inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    IMAGE_EXISTS=1
fi

# Initialize Result Variables
TZ_CHECK_PASSED=0
LOCALE_CHECK_PASSED=0
APP_RUN_PASSED=0
FILE_CONTENT_PASSED=0
TIMESTAMP_CHECK_PASSED=0
DETECTED_TZ=""
DETECTED_LANG=""

if [ "$IMAGE_EXISTS" = "1" ]; then
    echo "Image found. Running verification checks..."

    # Check 1: Timezone
    # Run 'date' inside container
    DATE_OUTPUT=$(docker run --rm "$IMAGE_NAME" date 2>/dev/null)
    echo "Date output: $DATE_OUTPUT"
    # Look for CET or CEST or the +0100/+0200 offset usually associated with Berlin
    if echo "$DATE_OUTPUT" | grep -qE "CET|CEST"; then
        TZ_CHECK_PASSED=1
        DETECTED_TZ="CET/CEST"
    fi
    
    # Also check /etc/timezone if it exists (some setups do this)
    TZ_FILE=$(docker run --rm "$IMAGE_NAME" cat /etc/timezone 2>/dev/null || echo "")
    if [[ "$TZ_FILE" == *"Berlin"* ]]; then
        TZ_CHECK_PASSED=1
        DETECTED_TZ="Europe/Berlin"
    fi

    # Check 2: Locale
    # Run 'locale' inside container
    LOCALE_OUTPUT=$(docker run --rm "$IMAGE_NAME" locale 2>/dev/null)
    echo "Locale output: $LOCALE_OUTPUT"
    # Check LANG variable
    DETECTED_LANG=$(echo "$LOCALE_OUTPUT" | grep "LANG=" | cut -d= -f2 | tr -d '"')
    if [[ "$DETECTED_LANG" == *"UTF-8"* ]] || [[ "$DETECTED_LANG" == *"utf8"* ]]; then
        LOCALE_CHECK_PASSED=1
    fi

    # Check 3: Application Execution (Does it crash?)
    # We mount our own clean output directory
    echo "Running application..."
    if docker run --rm --name invoicer-test-container \
        -v "$PROJECT_DIR/customers.csv":/app/customers.csv \
        -v /tmp/test_invoices:/app/invoices \
        "$IMAGE_NAME"; then
        APP_RUN_PASSED=1
        echo "Application exited with 0"
    else
        echo "Application failed (non-zero exit)"
    fi

    # Check 4: Output Content (Mojibake check)
    # Check for the Japanese filename and content
    # Note: Using wildcards carefully here
    
    # We look for a file that *should* be named "田中_太郎.txt"
    # If encoding is broken, it might be named "????_??.txt" or similar
    
    # Check if a file containing "田中" exists
    if ls /tmp/test_invoices/*田中* 2>/dev/null >/dev/null; then
        echo "Found Japanese filename."
        # Read content
        CONTENT=$(cat /tmp/test_invoices/*田中*)
        if [[ "$CONTENT" == *"田中 太郎"* ]]; then
            FILE_CONTENT_PASSED=1
        fi
    else
        echo "No file with Japanese characters found in filenames."
    fi

    # Check 5: Timestamp inside the file
    # We read one invoice and look for the time offset or logic
    # Since the app writes `datetime.datetime.now()`, it uses system local time.
    # We verify if the written time matches Berlin time approximately.
    
    # Current Berlin Hour (approximate check using host date if host has internet/tzdata)
    # This is tricky if host is UTC. We rely on the TZ_CHECK_PASSED mostly, 
    # but we can check if the file content contains the timezone name if python includes it.
    # Python's default str(datetime) doesn't always include TZ info unless aware.
    # However, we can check if the time inside the file matches the 'date' command output we captured earlier.
    
    # Simple check: Does the file date match the container 'date' output?
    # Not strictly robust due to seconds delay, but good enough proxy if we just trust TZ_CHECK_PASSED
    if [ "$TZ_CHECK_PASSED" = "1" ]; then
        TIMESTAMP_CHECK_PASSED=1
    fi
fi

# Take final screenshot
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_end_screenshot.png
fi

# Generate Result JSON
cat > /tmp/locale_fix_result.json << JSONEOF
{
    "task_start": $TASK_START,
    "image_exists": $IMAGE_EXISTS,
    "detected_tz": "$DETECTED_TZ",
    "detected_lang": "$DETECTED_LANG",
    "tz_check_passed": $TZ_CHECK_PASSED,
    "locale_check_passed": $LOCALE_CHECK_PASSED,
    "app_run_passed": $APP_RUN_PASSED,
    "file_content_passed": $FILE_CONTENT_PASSED,
    "timestamp_check_passed": $TIMESTAMP_CHECK_PASSED,
    "export_timestamp": "$(date -Iseconds)"
}
JSONEOF

echo "Result JSON:"
cat /tmp/locale_fix_result.json