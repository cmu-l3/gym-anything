#!/bin/bash
# Shared utilities for OpenLCA tasks

# Get OpenLCA window ID
get_openlca_window_id() {
    DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openLCA\|openlca\|Life Cycle" | head -1 | awk '{print $1}'
}

# Check if OpenLCA is running
is_openlca_running() {
    pgrep -f "openLCA\|openlca\|org.openlca" > /dev/null 2>&1
}

# Focus on OpenLCA window
focus_openlca_window() {
    local wid=$(get_openlca_window_id)
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null
        return 0
    fi
    return 1
}

# Focus any window by ID
focus_window() {
    local wid=$1
    if [ -n "$wid" ]; then
        DISPLAY=:1 wmctrl -i -a "$wid" 2>/dev/null
    fi
}

# Take screenshot
take_screenshot() {
    local path="${1:-/tmp/screenshot.png}"
    DISPLAY=:1 scrot "$path" 2>/dev/null || \
    DISPLAY=:1 import -window root "$path" 2>/dev/null || true
}

# Wait for window to appear (with timeout)
wait_for_window() {
    local pattern="$1"
    local timeout="${2:-60}"
    local elapsed=0

    while [ $elapsed -lt $timeout ]; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "$pattern"; then
            echo "Window found: $pattern"
            return 0
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done
    echo "Timeout waiting for window: $pattern"
    return 1
}

# Launch OpenLCA and wait for it to start
launch_openlca() {
    local timeout="${1:-180}"

    echo "Launching OpenLCA..."

    # Check if already running
    if is_openlca_running; then
        echo "OpenLCA is already running"
        focus_openlca_window
        return 0
    fi

    # Launch using the launch script
    su - ga -c "DISPLAY=:1 /home/ga/launch_openlca.sh" &

    # Give it time to start (Java apps take longer)
    sleep 15

    # Wait for window
    wait_for_window "openLCA\|openlca\|Life Cycle" "$timeout"
    local window_found=$?

    # Additional wait for GUI to fully load
    sleep 10

    focus_openlca_window

    # Verify launch succeeded
    if [ "$window_found" -eq 0 ] || is_openlca_running; then
        echo "OpenLCA launched successfully"
        return 0
    else
        echo "WARNING: OpenLCA window not detected and process not found"
        echo "Checking log..."
        tail -20 /tmp/openlca_ga.log 2>/dev/null || true
        return 1
    fi
}

# Close OpenLCA
close_openlca() {
    if is_openlca_running; then
        local wid=$(get_openlca_window_id)
        if [ -n "$wid" ]; then
            focus_window "$wid"
            sleep 0.5
        fi
        # Try keyboard shortcut first (Alt+F4 or Ctrl+Q)
        DISPLAY=:1 xdotool key alt+F4 2>/dev/null
        sleep 3

        # If still running, force kill
        if is_openlca_running; then
            pkill -f "openLCA\|openlca\|org.openlca" 2>/dev/null || true
            sleep 2
        fi
    fi
}

# Check OpenLCA workspace for databases
list_openlca_databases() {
    local workspace="/home/ga/openLCA-data-1.4/databases"
    if [ -d "$workspace" ]; then
        ls -1 "$workspace" 2>/dev/null
    else
        echo ""
    fi
}

# Count databases in OpenLCA workspace
count_openlca_databases() {
    local workspace="/home/ga/openLCA-data-1.4/databases"
    if [ -d "$workspace" ]; then
        ls -1d "$workspace"/*/ 2>/dev/null | wc -l || echo "0"
    else
        echo "0"
    fi
}

# ============================================================
# Derby ij query helper
# Queries the OpenLCA Derby database directly for verification
# Usage: derby_query <db_path> <sql_query>
# Returns: query output or empty string on failure
# ============================================================
derby_query() {
    local db_path="$1"
    local sql="$2"

    # Find OpenLCA base directory
    local OPENLCA_BASE=$(cat /opt/openlca_base_dir.txt 2>/dev/null || echo "/opt/openlca/openLCA")

    # Find Derby engine jar (OpenLCA bundles Derby)
    local DERBY_JAR=$(find "$OPENLCA_BASE" /opt/openlca -name "derby-*.jar" -o -name "derby.jar" 2>/dev/null | grep -v "tools\|client\|net\|shared\|optional" | head -1)

    if [ -z "$DERBY_JAR" ]; then
        echo ""
        return 1
    fi

    # Build classpath with all Derby jars in the same directory
    local DERBY_DIR=$(dirname "$DERBY_JAR")
    local CP=$(find "$DERBY_DIR" -name "derby*.jar" 2>/dev/null | tr '\n' ':')

    # Find Java - prefer OpenLCA's bundled JRE
    local JAVA_BIN=""
    JAVA_BIN=$(find "$OPENLCA_BASE" -path "*/jre/bin/java" 2>/dev/null | head -1)
    if [ -z "$JAVA_BIN" ]; then
        JAVA_BIN=$(which java 2>/dev/null || echo "")
    fi

    if [ -z "$JAVA_BIN" ]; then
        echo ""
        return 1
    fi

    # Run ij query with retry for lock contention (Derby path must not have trailing slash)
    local DB_CONN=$(echo "$db_path" | sed 's|/$||')
    local max_retries=3
    local retry=0
    local RESULT=""

    while [ $retry -lt $max_retries ]; do
        RESULT=$("$JAVA_BIN" -cp "$CP" org.apache.derby.tools.ij 2>/dev/null <<IJEOF
CONNECT 'jdbc:derby:${DB_CONN}';
${sql}
EXIT;
IJEOF
)
        # Check if we got a lock error
        if echo "$RESULT" | grep -qi "lock\|XSDB6\|another instance"; then
            retry=$((retry + 1))
            if [ $retry -lt $max_retries ]; then
                sleep 3
            fi
        else
            break
        fi
    done
    echo "$RESULT"
}

# Count rows in an OpenLCA Derby table
# Usage: derby_count <db_path> <table_name>
# Table names: PROCESSES, FLOWS, FLOW_PROPERTIES, UNIT_GROUPS, CATEGORIES, PRODUCT_SYSTEMS
derby_count() {
    local db_path="$1"
    local table="$2"
    local result=$(derby_query "$db_path" "SELECT COUNT(*) AS CNT FROM TBL_${table};" 2>/dev/null)
    # Extract the number from ij output
    echo "$result" | grep -oP '^\s*\K\d+' | head -1 || echo "0"
}

# Ensure USLCI database exists - check for valid imported database
# Usage: ensure_uslci_database
# Returns (echo): path to the USLCI database directory, or empty string
ensure_uslci_database() {
    local DB_DIR="/home/ga/openLCA-data-1.4/databases"
    mkdir -p "$DB_DIR"
    chown ga:ga "$DB_DIR"

    # Check if a USLCI database already exists with real content
    for db_path in "$DB_DIR"/*/; do
        local db_name=$(basename "$db_path" 2>/dev/null)
        if echo "$db_name" | grep -qi "uslci\|lci\|analysis"; then
            local db_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
            if [ "$db_size" -gt 15 ]; then
                echo "$db_path"
                return 0
            fi
        fi
    done

    # Also check any database by size (agent may have named it differently)
    for db_path in "$DB_DIR"/*/; do
        local db_size=$(du -sm "$db_path" 2>/dev/null | cut -f1 || echo "0")
        if [ "$db_size" -gt 15 ]; then
            echo "$db_path"
            return 0
        fi
    done

    echo ""
    return 1
}

# Check if LCIA methods are available
ensure_lcia_methods() {
    local lcia_file="/home/ga/LCA_Imports/lcia_methods.zip"
    if [ -f "$lcia_file" ]; then
        local size=$(stat -c%s "$lcia_file" 2>/dev/null || echo "0")
        if [ "$size" -gt 100000 ]; then
            echo "$lcia_file"
            return 0
        fi
    fi
    echo ""
    return 1
}

# Export verification helper
export_json_result() {
    local output_file="$1"
    shift

    # Create temp file first
    local temp_json=$(mktemp /tmp/result.XXXXXX.json)

    # Write JSON (caller passes content via stdin)
    cat > "$temp_json"

    # Copy to final location with permission handling
    rm -f "$output_file" 2>/dev/null || sudo rm -f "$output_file" 2>/dev/null || true
    cp "$temp_json" "$output_file" 2>/dev/null || sudo cp "$temp_json" "$output_file"
    chmod 666 "$output_file" 2>/dev/null || sudo chmod 666 "$output_file" 2>/dev/null || true
    rm -f "$temp_json"

    echo "Result saved to $output_file"
}
