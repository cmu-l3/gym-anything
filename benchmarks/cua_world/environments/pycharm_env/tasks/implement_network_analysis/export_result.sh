#!/bin/bash
echo "=== Exporting implement_network_analysis result ==="

source /workspace/scripts/task_utils.sh

PROJECT_DIR="/home/ga/PycharmProjects/citation_network"
RESULT_FILE="/tmp/network_analysis_result.json"

# Take final screenshot
take_screenshot /tmp/task_end.png

# 1. Run Tests
echo "Running tests..."
# We run as 'ga' user
TEST_OUTPUT=$(su - ga -c "cd $PROJECT_DIR && python3 -m pytest tests/ -v 2>&1")
EXIT_CODE=$?

# 2. Parse Test Results
TESTS_PASSED=$(echo "$TEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$TEST_OUTPUT" | grep -c " FAILED" || true)
TESTS_TOTAL=$((TESTS_PASSED + TESTS_FAILED))

# Breakdown by module (rough grep)
PAGERANK_PASSED=$(echo "$TEST_OUTPUT" | grep "test_pagerank" | grep -c " PASSED" || true)
BETWEENNESS_PASSED=$(echo "$TEST_OUTPUT" | grep "test_betweenness" | grep -c " PASSED" || true)
CLUSTERING_PASSED=$(echo "$TEST_OUTPUT" | grep "test_clustering" | grep -c " PASSED" || true)
COMMUNITY_PASSED=$(echo "$TEST_OUTPUT" | grep "test_label_propagation" | grep -c " PASSED" || true)
IO_PASSED=$(echo "$TEST_OUTPUT" | grep "test_read\|test_write\|test_adjacency" | grep -c " PASSED" || true)
GRAPH_PASSED=$(echo "$TEST_OUTPUT" | grep "test_add_nodes\|test_neighbors\|test_node_count\|test_is_directed" | grep -c " PASSED" || true)

# 3. Anti-Gaming: Verify Checksums
echo "Verifying test integrity..."
CURRENT_CHECKSUMS=$(sha256sum "$PROJECT_DIR/tests/"*.py "$PROJECT_DIR/network/graph.py" 2>/dev/null)
CHECKSUMS_MATCH="true"

# Compare with stored checksums
# We need to be careful about file paths in output, so we check just the hashes
# Stored format: "HASH  /path/to/file"
while read -r line; do
    HASH=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')
    BASE=$(basename "$FILE")
    
    # Find corresponding current hash
    CURRENT_HASH=$(echo "$CURRENT_CHECKSUMS" | grep "$BASE" | awk '{print $1}')
    
    if [ "$HASH" != "$CURRENT_HASH" ]; then
        echo "WARNING: Checksum mismatch for $BASE"
        CHECKSUMS_MATCH="false"
    fi
done < /tmp/initial_checksums.txt

# 4. Check for 'NotImplementedError' (to ensure actual implementation attempt)
STUBS_REMAINING=$(grep -r "NotImplementedError" "$PROJECT_DIR/network/" | grep -v "graph.py" | wc -l)

# 5. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "tests_total": $TESTS_TOTAL,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "pytest_exit_code": $EXIT_CODE,
    "breakdown": {
        "pagerank_passed": $PAGERANK_PASSED,
        "betweenness_passed": $BETWEENNESS_PASSED,
        "clustering_passed": $CLUSTERING_PASSED,
        "community_passed": $COMMUNITY_PASSED,
        "io_passed": $IO_PASSED,
        "graph_passed": $GRAPH_PASSED
    },
    "integrity": {
        "checksums_match": $CHECKSUMS_MATCH,
        "stubs_remaining_count": $STUBS_REMAINING
    },
    "screenshot_path": "/tmp/task_end.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"
cat "$RESULT_FILE"
echo "=== Export complete ==="