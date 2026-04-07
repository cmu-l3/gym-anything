#!/bin/bash
echo "=== Exporting scenario_library_maintenance result ==="

# Define paths
BC_ROOT="/opt/bridgecommand"
SCENARIOS_DIR="$BC_ROOT/Scenarios"
QUARANTINE_DIR="/home/ga/Quarantine"
REPORT_FILE="/home/ga/Documents/audit_report.txt"

# Helper function to read a value from INI file
read_ini() {
    local file="$1"
    local key="$2"
    if [ -f "$file" ]; then
        # Grep key, handle optional quotes, return value
        grep -i "^$key" "$file" | sed -E 's/^.*=[[:space:]]*"?([^"]*)"?.*$/\1/' | head -1
    else
        echo "FILE_NOT_FOUND"
    fi
}

# --- Check 1: Quarantine Logic ---
# Expected: Legacy_Fatal_Error moved to Quarantine
FATAL_IN_SCENARIOS="false"
FATAL_IN_QUARANTINE="false"

if [ -d "$SCENARIOS_DIR/Legacy_Fatal_Error" ]; then FATAL_IN_SCENARIOS="true"; fi
if [ -d "$QUARANTINE_DIR/Legacy_Fatal_Error" ]; then FATAL_IN_QUARANTINE="true"; fi

# --- Check 2: Repair Logic (Tug) ---
# Expected: Legacy_Missing_Tug exists in Scenarios, othership.ini Type(1) is "Tug"
TUG_SCEN_EXISTS="false"
TUG_VAL=""
TUG_DESC_EXISTS="false"

if [ -d "$SCENARIOS_DIR/Legacy_Missing_Tug" ]; then
    TUG_SCEN_EXISTS="true"
    TUG_VAL=$(read_ini "$SCENARIOS_DIR/Legacy_Missing_Tug/othership.ini" "Type(1)")
    if [ -f "$SCENARIOS_DIR/Legacy_Missing_Tug/description.txt" ]; then TUG_DESC_EXISTS="true"; fi
fi

# --- Check 3: Repair Logic (Generic) ---
# Expected: Legacy_Unknown_Ship exists, othership.ini Type(1) is "Coaster"
GEN_SCEN_EXISTS="false"
GEN_VAL=""
GEN_DESC_CONTENT=""

if [ -d "$SCENARIOS_DIR/Legacy_Unknown_Ship" ]; then
    GEN_SCEN_EXISTS="true"
    GEN_VAL=$(read_ini "$SCENARIOS_DIR/Legacy_Unknown_Ship/othership.ini" "Type(1)")
    if [ -f "$SCENARIOS_DIR/Legacy_Unknown_Ship/description.txt" ]; then
        GEN_DESC_CONTENT=$(cat "$SCENARIOS_DIR/Legacy_Unknown_Ship/description.txt")
    fi
fi

# --- Check 4: Valid Scenario ---
# Expected: Untouched, but description added
VALID_SCEN_EXISTS="false"
VALID_OWNSHIP=""
VALID_DESC_EXISTS="false"

if [ -d "$SCENARIOS_DIR/Legacy_Valid_Archive" ]; then
    VALID_SCEN_EXISTS="true"
    VALID_OWNSHIP=$(read_ini "$SCENARIOS_DIR/Legacy_Valid_Archive/ownship.ini" "ShipName")
    if [ -f "$SCENARIOS_DIR/Legacy_Valid_Archive/description.txt" ]; then VALID_DESC_EXISTS="true"; fi
fi

# --- Check 5: Report ---
REPORT_EXISTS="false"
if [ -f "$REPORT_FILE" ]; then REPORT_EXISTS="true"; fi

# --- Screenshots ---
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Construct JSON
cat > /tmp/task_result.json << EOF
{
    "fatal_scenario": {
        "in_scenarios": $FATAL_IN_SCENARIOS,
        "in_quarantine": $FATAL_IN_QUARANTINE
    },
    "tug_scenario": {
        "exists": $TUG_SCEN_EXISTS,
        "type_1_value": "$TUG_VAL",
        "description_exists": $TUG_DESC_EXISTS
    },
    "generic_scenario": {
        "exists": $GEN_SCEN_EXISTS,
        "type_1_value": "$GEN_VAL",
        "description_content": "$GEN_DESC_CONTENT"
    },
    "valid_scenario": {
        "exists": $VALID_SCEN_EXISTS,
        "ownship_value": "$VALID_OWNSHIP",
        "description_exists": $VALID_DESC_EXISTS
    },
    "report_exists": $REPORT_EXISTS,
    "timestamp": $(date +%s)
}
EOF

echo "Result JSON generated at /tmp/task_result.json"
cat /tmp/task_result.json