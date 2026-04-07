#!/bin/bash
echo "=== Exporting debug_geospatial_analysis results ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="debug_geospatial_analysis"
PROJECT_DIR="/home/ga/PycharmProjects/city_mobility"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"

# 1. Take Screenshot
take_screenshot /tmp/${TASK_NAME}_end_screenshot.png

# 2. Run Pytest
echo "Running tests..."
# We run as 'ga' user
PYTEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

# 3. Static Analysis / Code Checks via Grep
# Used to verify *how* they fixed it, or if they just deleted tests (anti-gaming)

# Check Geo Fix: Look for radians conversion
GEO_FIXED=false
if grep -q "radians" "$PROJECT_DIR/mobility/geo.py"; then
    GEO_FIXED=true
fi

# Check Sorting Fix: Look for sort_values
SORT_FIXED=false
if grep -q "sort_values" "$PROJECT_DIR/mobility/processing.py"; then
    SORT_FIXED=true
fi

# Check Speed Unit Fix: Look for 3.6 multiplication or equivalent division
SPEED_FIXED=false
if grep -q "3.6" "$PROJECT_DIR/mobility/metrics.py" || grep -q "1000.*3600" "$PROJECT_DIR/mobility/metrics.py"; then
    SPEED_FIXED=true
fi

# Check Filter Fix: Look for < 150 (or reasonable upper bound) and NOT > 5
FILTER_FIXED=false
METRICS_CONTENT=$(cat "$PROJECT_DIR/mobility/metrics.py")
# The bug was `df['speed_kph'] > 5`. Fix should be `df['speed_kph'] < 150` (approx)
if [[ "$METRICS_CONTENT" != *"> 5"* ]] && [[ "$METRICS_CONTENT" == *"<"* ]]; then
    FILTER_FIXED=true
fi

# 4. JSON Export
cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "timestamp": "$(date -Iseconds)",
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "tests_total": $TESTS_TOTAL,
    "code_checks": {
        "geo_radians_found": $GEO_FIXED,
        "processing_sort_found": $SORT_FIXED,
        "metrics_conversion_found": $SPEED_FIXED,
        "metrics_filter_fixed": $FILTER_FIXED
    },
    "test_details": {
        "geo_pass": $(echo "$PYTEST_OUTPUT" | grep -q "test_haversine_known_distance PASSED" && echo "true" || echo "false"),
        "sort_pass": $(echo "$PYTEST_OUTPUT" | grep -q "test_calculate_deltas_sorting PASSED" && echo "true" || echo "false"),
        "units_pass": $(echo "$PYTEST_OUTPUT" | grep -q "test_calculate_speed_units PASSED" && echo "true" || echo "false"),
        "filter_pass": $(echo "$PYTEST_OUTPUT" | grep -q "test_identify_congestion_keeps_traffic_jam PASSED" && echo "true" || echo "false")
    }
}
EOF

# Move to final location safely
mv "$RESULT_FILE" /tmp/task_result.json 2>/dev/null || cp "$RESULT_FILE" /tmp/task_result.json

echo "=== Export complete ==="
cat /tmp/task_result.json