#!/bin/bash
echo "=== Exporting deploy_maven_multi_artifact result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
RESULTS_JSON="/tmp/task_result.json"

# Capture final screenshot
take_screenshot /tmp/task_final.png

# Define the artifacts to check
# Format: "key|path|source_checksum_file"
ARTIFACTS=(
    "lang3_jar|org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.jar|/tmp/checksum_lang3_jar.txt"
    "lang3_pom|org/apache/commons/commons-lang3/3.14.0/commons-lang3-3.14.0.pom|/tmp/checksum_lang3_pom.txt"
    "io_jar|commons-io/commons-io/2.15.1/commons-io-2.15.1.jar|/tmp/checksum_io_jar.txt"
    "io_pom|commons-io/commons-io/2.15.1/commons-io-2.15.1.pom|/tmp/checksum_io_pom.txt"
)

# Start JSON object
echo "{" > "$RESULTS_JSON"
echo "  \"task_start\": $TASK_START," >> "$RESULTS_JSON"
echo "  \"artifacts\": {" >> "$RESULTS_JSON"

FIRST=true

for ITEM in "${ARTIFACTS[@]}"; do
    IFS='|' read -r KEY PATH CHECKSUM_FILE <<< "$ITEM"
    
    SOURCE_SHA256=$(cat "$CHECKSUM_FILE" 2>/dev/null || echo "missing")
    
    echo "Checking artifact: $KEY at $PATH"
    
    # Query Artifactory Storage API
    # Returns JSON with info like: { "uri": "...", "size": "...", "checksums": { "sha256": "..." }, "created": "ISO8601..." }
    API_RESPONSE=$(art_api GET "/api/storage/example-repo-local/$PATH")
    
    # Check if file exists (HTTP 200)
    EXISTS="false"
    SIZE="0"
    REMOTE_SHA256=""
    CREATED_ISO=""
    
    if echo "$API_RESPONSE" | grep -q "\"uri\""; then
        EXISTS="true"
        # Parse JSON manually or with python one-liner since jq might not be robust enough in minimal env
        # Using python for reliable parsing
        PARSED=$(echo "$API_RESPONSE" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    size = data.get('size', 0)
    sha256 = data.get('checksums', {}).get('sha256', '')
    created = data.get('created', '')
    print(f'{size}|{sha256}|{created}')
except:
    print('0||')
")
        IFS='|' read -r SIZE REMOTE_SHA256 CREATED_ISO <<< "$PARSED"
    fi
    
    # Convert ISO timestamp to epoch for comparison (simplified, or pass string to verifier)
    # Verifier is better suited for date parsing. We pass the ISO string.
    
    if [ "$FIRST" = true ]; then
        FIRST=false
    else
        echo "," >> "$RESULTS_JSON"
    fi
    
    echo "    \"$KEY\": {" >> "$RESULTS_JSON"
    echo "      \"exists\": $EXISTS," >> "$RESULTS_JSON"
    echo "      \"path\": \"$PATH\"," >> "$RESULTS_JSON"
    echo "      \"size\": $SIZE," >> "$RESULTS_JSON"
    echo "      \"sha256_remote\": \"$REMOTE_SHA256\"," >> "$RESULTS_JSON"
    echo "      \"sha256_source\": \"$SOURCE_SHA256\"," >> "$RESULTS_JSON"
    echo "      \"created\": \"$CREATED_ISO\"" >> "$RESULTS_JSON"
    echo "    }" >> "$RESULTS_JSON"
done

echo "  }" >> "$RESULTS_JSON"
echo "}" >> "$RESULTS_JSON"

# Fix permissions
chmod 666 "$RESULTS_JSON"

echo "Result export complete."
cat "$RESULTS_JSON"