#!/bin/bash
# Shared utility functions for WordPress tasks

# WordPress installation directory
WP_DIR="/var/www/html/wordpress"

# Debug log location
VERIFIER_DEBUG_LOG="/tmp/verifier_debug.log"

# Database connection via Docker - WITH ERROR HANDLING
wp_db_query() {
    local query="$1"
    local result
    local exit_code

    # Capture both stdout and stderr, check exit code
    result=$(docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -N -e "$query" 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "DB_ERROR: Query failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        # Return empty string but log the error
        echo ""
        return 1
    fi

    # Check for MySQL error messages in output
    if echo "$result" | grep -qi "ERROR"; then
        echo "DB_ERROR: MySQL error in result" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Query: $query" >> "$VERIFIER_DEBUG_LOG"
        echo "DB_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        echo ""
        return 1
    fi

    echo "$result"
    return 0
}

# Execute WP-CLI command - WITH ERROR HANDLING
wp_cli() {
    local result
    local exit_code

    cd "$WP_DIR"
    result=$(wp "$@" --allow-root 2>&1)
    exit_code=$?

    if [ $exit_code -ne 0 ]; then
        echo "WP_CLI_ERROR: Command failed with exit code $exit_code" >> "$VERIFIER_DEBUG_LOG"
        echo "WP_CLI_ERROR: Args: $@" >> "$VERIFIER_DEBUG_LOG"
        echo "WP_CLI_ERROR: Output: $result" >> "$VERIFIER_DEBUG_LOG"
        # Still return the result for parsing, but log the error
    fi

    echo "$result"
    return $exit_code
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Get post count by type and status
get_post_count() {
    local post_type="${1:-post}"
    local post_status="${2:-publish}"
    wp_cli post list --post_type="$post_type" --post_status="$post_status" --format=count
}

# Get user count
get_user_count() {
    wp_cli user list --format=count
}

# Check if post exists by title (case-insensitive)
post_exists_by_title() {
    local title="$1"
    local post_type="${2:-post}"
    local count=$(wp_db_query "SELECT COUNT(*) FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$title')) AND post_type='$post_type' AND post_status IN ('publish', 'draft', 'pending')")
    [ "$count" -gt 0 ]
}

# Get post ID by title
get_post_id_by_title() {
    local title="$1"
    local post_type="${2:-post}"
    wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$title')) AND post_type='$post_type' ORDER BY ID DESC LIMIT 1"
}

# Get post data by ID
get_post_data() {
    local post_id="$1"
    wp_db_query "SELECT ID, post_title, post_status, post_type, post_date, post_content FROM wp_posts WHERE ID=$post_id"
}

# Get categories for a post
get_post_categories() {
    local post_id="$1"
    wp_cli post term list "$post_id" category --format=csv --fields=name 2>/dev/null | tail -n +2 | tr '\n' ',' | sed 's/,$//'
}

# Get tags for a post
get_post_tags() {
    local post_id="$1"
    wp_cli post term list "$post_id" post_tag --format=csv --fields=name 2>/dev/null | tail -n +2 | tr '\n' ',' | sed 's/,$//'
}

# Check if category exists
category_exists() {
    local category="$1"
    local count=$(wp_db_query "SELECT COUNT(*) FROM wp_terms t
        INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id
        WHERE tt.taxonomy='category' AND LOWER(TRIM(t.name)) = LOWER(TRIM('$category'))")
    [ "$count" -gt 0 ]
}

# Check if user exists by username
user_exists() {
    local username="$1"
    local count=$(wp_db_query "SELECT COUNT(*) FROM wp_users WHERE LOWER(user_login) = LOWER('$username')")
    [ "$count" -gt 0 ]
}

# Get user data by username
get_user_data() {
    local username="$1"
    wp_db_query "SELECT ID, user_login, user_email, display_name FROM wp_users WHERE LOWER(user_login) = LOWER('$username')"
}

# Safe JSON string escape
json_escape() {
    local str="$1"
    echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
}

# Create result JSON with proper escaping
create_result_json() {
    local temp_file="$1"
    shift

    # Build JSON from key=value pairs
    echo "{" > "$temp_file"
    local first=true
    while [ $# -gt 0 ]; do
        local key="${1%%=*}"
        local value="${1#*=}"

        if [ "$first" = true ]; then
            first=false
        else
            echo "," >> "$temp_file"
        fi

        # Check if value looks like a number or boolean
        if [[ "$value" =~ ^-?[0-9]+$ ]] || [[ "$value" =~ ^-?[0-9]+\.[0-9]+$ ]] || [ "$value" = "true" ] || [ "$value" = "false" ] || [ "$value" = "null" ]; then
            printf '    "%s": %s' "$key" "$value" >> "$temp_file"
        else
            printf '    "%s": "%s"' "$key" "$(json_escape "$value")" >> "$temp_file"
        fi

        shift
    done
    echo "" >> "$temp_file"
    echo "}" >> "$temp_file"
}

# Safe file write with permission handling
safe_write_result() {
    local content="$1"
    local dest="${2:-/tmp/task_result.json}"

    # Create temp file
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)
    echo "$content" > "$temp_json"

    # Remove old file and copy new one (with sudo fallback)
    rm -f "$dest" 2>/dev/null || sudo rm -f "$dest" 2>/dev/null || true
    cp "$temp_json" "$dest" 2>/dev/null || sudo cp "$temp_json" "$dest"
    chmod 666 "$dest" 2>/dev/null || sudo chmod 666 "$dest" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $dest"
    cat "$dest"
}
