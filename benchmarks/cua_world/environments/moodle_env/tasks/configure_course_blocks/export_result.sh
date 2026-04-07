#!/bin/bash
# Export script for Configure Course Blocks task

echo "=== Exporting Configure Course Blocks Result ==="

# Source shared utilities
. /workspace/scripts/task_utils.sh

# Fallback definitions
if ! type moodle_query &>/dev/null; then
    echo "Warning: task_utils.sh functions not available, using inline definitions"
    _get_mariadb_method() { cat /tmp/mariadb_method 2>/dev/null || echo "native"; }
    moodle_query() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -N -B -e "$query" 2>/dev/null
        fi
    }
    take_screenshot() {
        local output_file="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$output_file" 2>/dev/null || echo "Could not take screenshot"
    }
    safe_write_json() {
        local temp_file="$1"; local dest_path="$2"
        rm -f "$dest_path" 2>/dev/null || true
        cp "$temp_file" "$dest_path"; chmod 666 "$dest_path" 2>/dev/null || true
        rm -f "$temp_file"; echo "Result saved to $dest_path"
    }
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# Retrieve context ID
CONTEXT_ID=$(cat /tmp/target_context_id 2>/dev/null)
if [ -z "$CONTEXT_ID" ]; then
    echo "Context ID missing, attempting lookup..."
    COURSE_ID=$(moodle_query "SELECT id FROM mdl_course WHERE shortname='HIST201'" | tr -d '[:space:]')
    CONTEXT_ID=$(moodle_query "SELECT id FROM mdl_context WHERE contextlevel=50 AND instanceid=$COURSE_ID" | tr -d '[:space:]')
fi

# Get counts
INITIAL_BLOCK_COUNT=$(cat /tmp/initial_block_count 2>/dev/null || echo "0")
CURRENT_BLOCK_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_block_instances WHERE parentcontextid=$CONTEXT_ID" | tr -d '[:space:]')
CURRENT_BLOCK_COUNT=${CURRENT_BLOCK_COUNT:-0}

echo "Block count: initial=$INITIAL_BLOCK_COUNT, current=$CURRENT_BLOCK_COUNT"

# Check for Calendar Block
CALENDAR_EXISTS="false"
CALENDAR_CHECK=$(moodle_query "SELECT COUNT(*) FROM mdl_block_instances WHERE parentcontextid=$CONTEXT_ID AND blockname='calendar_month'" | tr -d '[:space:]')
if [ "$CALENDAR_CHECK" -gt 0 ]; then
    CALENDAR_EXISTS="true"
    echo "Calendar block found."
else
    echo "Calendar block NOT found."
fi

# Check for HTML (Text) Blocks
# There might be multiple HTML blocks, we need to check if any of them match our criteria.
# We will extract ALL html blocks in this context and parse their configdata.
HTML_BLOCKS_JSON="[]"
HTML_BLOCKS_DATA=$(moodle_query "SELECT id, configdata FROM mdl_block_instances WHERE parentcontextid=$CONTEXT_ID AND blockname='html'")

if [ -n "$HTML_BLOCKS_DATA" ]; then
    echo "Processing HTML blocks..."
    # We use PHP to decode the base64+serialized configdata
    # We construct a PHP script to process the query output directly or iterate
    
    # Let's handle row by row in a loop is tricky with multiline base64, but usually it's one line in TSV output from mysql -B
    # Actually, mysql -N -B output is tab separated. Configdata is base64, so it shouldn't contain newlines or tabs usually.
    
    # Create a PHP script to parse the configdata
    cat > /tmp/parse_blocks.php << 'PHPCODE'
<?php
$input = file_get_contents("php://stdin");
$lines = explode("\n", trim($input));
$blocks = [];
foreach ($lines as $line) {
    if (empty($line)) continue;
    $parts = explode("\t", $line);
    if (count($parts) < 2) continue;
    
    $id = $parts[0];
    $b64 = $parts[1];
    
    $config = new stdClass();
    if (!empty($b64)) {
        try {
            $decoded = base64_decode($b64);
            if ($decoded !== false) {
                $unserialized = unserialize($decoded);
                if ($unserialized !== false) {
                    $config = $unserialized;
                }
            }
        } catch (Exception $e) {}
    }
    
    $blocks[] = [
        'id' => $id,
        'title' => isset($config->title) ? $config->title : '',
        'text' => isset($config->text) ? $config->text : ''
    ];
}
echo json_encode($blocks);
PHPCODE

    # Run the PHP script passing the SQL output
    HTML_BLOCKS_JSON=$(echo "$HTML_BLOCKS_DATA" | php /tmp/parse_blocks.php)
    echo "Parsed HTML blocks: $HTML_BLOCKS_JSON"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/blocks_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "context_id": ${CONTEXT_ID:-0},
    "initial_block_count": ${INITIAL_BLOCK_COUNT:-0},
    "current_block_count": ${CURRENT_BLOCK_COUNT:-0},
    "calendar_exists": $CALENDAR_EXISTS,
    "html_blocks": $HTML_BLOCKS_JSON,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/configure_course_blocks_result.json

echo ""
cat /tmp/configure_course_blocks_result.json
echo ""
echo "=== Export Complete ==="