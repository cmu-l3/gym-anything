#!/bin/bash
# Export script for Create Wiki Activity task

echo "=== Exporting Create Wiki Activity Result ==="

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
    moodle_query_headers() {
        local query="$1"
        local method=$(_get_mariadb_method)
        if [ "$method" = "docker" ]; then
            docker exec moodle-mariadb mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
        else
            mysql -u moodleuser -pmoodlepass moodle -e "$query" 2>/dev/null
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

# Get BIO101 course ID
COURSE_ID=$(cat /tmp/target_course_id 2>/dev/null || moodle_query "SELECT id FROM mdl_course WHERE shortname='BIO101'" | tr -d '[:space:]')

# Get baseline
INITIAL_WIKI_COUNT=$(cat /tmp/initial_wiki_count 2>/dev/null || echo "0")

# Get current wiki count
CURRENT_WIKI_COUNT=$(moodle_query "SELECT COUNT(*) FROM mdl_wiki WHERE course=$COURSE_ID" | tr -d '[:space:]')
CURRENT_WIKI_COUNT=${CURRENT_WIKI_COUNT:-0}

echo "Wiki count: initial=$INITIAL_WIKI_COUNT, current=$CURRENT_WIKI_COUNT"

# Look for the target wiki
# We search by name approximate match
WIKI_DATA=$(moodle_query "SELECT id, name, intro, wikimode, firstpagetitle FROM mdl_wiki WHERE course=$COURSE_ID AND LOWER(name) LIKE '%biology lab notebook%' ORDER BY id DESC LIMIT 1")

WIKI_FOUND="false"
WIKI_ID=""
WIKI_NAME=""
WIKI_INTRO=""
WIKI_MODE=""
WIKI_FIRSTPAGE=""

if [ -n "$WIKI_DATA" ]; then
    WIKI_FOUND="true"
    WIKI_ID=$(echo "$WIKI_DATA" | cut -f1 | tr -d '[:space:]')
    WIKI_NAME=$(echo "$WIKI_DATA" | cut -f2)
    WIKI_INTRO=$(echo "$WIKI_DATA" | cut -f3)
    WIKI_MODE=$(echo "$WIKI_DATA" | cut -f4)
    WIKI_FIRSTPAGE=$(echo "$WIKI_DATA" | cut -f5)
    
    echo "Wiki found: ID=$WIKI_ID, Name='$WIKI_NAME', Mode='$WIKI_MODE'"
else
    echo "Wiki 'Biology Lab Notebook' NOT found in BIO101"
fi

# Check for pages if wiki exists
PAGE1_FOUND="false"
PAGE1_TITLE=""
PAGE1_CONTENT=""
PAGE2_FOUND="false"
PAGE2_TITLE=""
PAGE2_CONTENT=""

if [ "$WIKI_FOUND" = "true" ]; then
    # Get all pages associated with this wiki
    # Join mdl_wiki_subwikis to link wiki -> pages
    # We select page title and the LATEST version content
    
    # Check for Page 1: "Lab Safety Procedures"
    # Using simple LIKE query to find the page
    PAGE1_DATA=$(moodle_query "
        SELECT p.title, v.content 
        FROM mdl_wiki_pages p 
        JOIN mdl_wiki_subwikis s ON p.subwikiid = s.id 
        JOIN mdl_wiki_versions v ON v.pageid = p.id 
        WHERE s.wikiid = $WIKI_ID 
        AND LOWER(p.title) LIKE '%lab safety procedures%' 
        ORDER BY v.id DESC LIMIT 1
    ")
    
    if [ -n "$PAGE1_DATA" ]; then
        PAGE1_FOUND="true"
        PAGE1_TITLE=$(echo "$PAGE1_DATA" | cut -f1)
        PAGE1_CONTENT=$(echo "$PAGE1_DATA" | cut -f2)
        echo "Page 1 found: '$PAGE1_TITLE'"
    fi
    
    # Check for Page 2: "Cell Structure Notes"
    PAGE2_DATA=$(moodle_query "
        SELECT p.title, v.content 
        FROM mdl_wiki_pages p 
        JOIN mdl_wiki_subwikis s ON p.subwikiid = s.id 
        JOIN mdl_wiki_versions v ON v.pageid = p.id 
        WHERE s.wikiid = $WIKI_ID 
        AND LOWER(p.title) LIKE '%cell structure notes%' 
        ORDER BY v.id DESC LIMIT 1
    ")
    
    if [ -n "$PAGE2_DATA" ]; then
        PAGE2_FOUND="true"
        PAGE2_TITLE=$(echo "$PAGE2_DATA" | cut -f1)
        PAGE2_CONTENT=$(echo "$PAGE2_DATA" | cut -f2)
        echo "Page 2 found: '$PAGE2_TITLE'"
    fi
    
    # Debug: List all pages for this wiki
    echo "--- All Pages in Wiki $WIKI_ID ---"
    moodle_query_headers "
        SELECT p.id, p.title 
        FROM mdl_wiki_pages p 
        JOIN mdl_wiki_subwikis s ON p.subwikiid = s.id 
        WHERE s.wikiid = $WIKI_ID
    "
fi

# Escape for JSON
WIKI_NAME_ESC=$(echo "$WIKI_NAME" | sed 's/"/\\"/g')
WIKI_INTRO_ESC=$(echo "$WIKI_INTRO" | sed 's/"/\\"/g')
WIKI_MODE_ESC=$(echo "$WIKI_MODE" | sed 's/"/\\"/g')
WIKI_FIRSTPAGE_ESC=$(echo "$WIKI_FIRSTPAGE" | sed 's/"/\\"/g')

PAGE1_TITLE_ESC=$(echo "$PAGE1_TITLE" | sed 's/"/\\"/g')
PAGE1_CONTENT_ESC=$(echo "$PAGE1_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')
PAGE2_TITLE_ESC=$(echo "$PAGE2_TITLE" | sed 's/"/\\"/g')
PAGE2_CONTENT_ESC=$(echo "$PAGE2_CONTENT" | sed 's/"/\\"/g' | tr -d '\n' | tr -d '\r')

# Create result JSON
TEMP_JSON=$(mktemp /tmp/create_wiki_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "course_id": ${COURSE_ID:-0},
    "initial_wiki_count": ${INITIAL_WIKI_COUNT:-0},
    "current_wiki_count": ${CURRENT_WIKI_COUNT:-0},
    "wiki_found": $WIKI_FOUND,
    "wiki_id": "$WIKI_ID",
    "wiki_name": "$WIKI_NAME_ESC",
    "wiki_intro": "$WIKI_INTRO_ESC",
    "wiki_mode": "$WIKI_MODE_ESC",
    "wiki_firstpage": "$WIKI_FIRSTPAGE_ESC",
    "page1_found": $PAGE1_FOUND,
    "page1_title": "$PAGE1_TITLE_ESC",
    "page1_content": "$PAGE1_CONTENT_ESC",
    "page2_found": $PAGE2_FOUND,
    "page2_title": "$PAGE2_TITLE_ESC",
    "page2_content": "$PAGE2_CONTENT_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/create_wiki_activity_result.json

echo ""
cat /tmp/create_wiki_activity_result.json
echo ""
echo "=== Export Complete ==="