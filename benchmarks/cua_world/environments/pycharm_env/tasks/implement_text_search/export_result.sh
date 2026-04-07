#!/bin/bash
echo "=== Exporting text search result ==="

source /workspace/scripts/task_utils.sh

TASK_DIR="/home/ga/PycharmProjects/search_engine"
RESULT_FILE="/tmp/task_result.json"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Verify Anti-Gaming (Tests not modified)
TESTS_MODIFIED=false
if ! md5sum -c /tmp/test_checksums.md5 >/dev/null 2>&1; then
    TESTS_MODIFIED=true
    echo "WARNING: Test files have been modified!"
fi

# 3. Check Source Modification (Did agent actually work?)
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
SOURCE_MODIFIED=false
# Check if any engine/ file has mtime > start time
if find "$TASK_DIR/engine" -name "*.py" -newermt "@$TASK_START" | grep -q .; then
    SOURCE_MODIFIED=true
fi

# 4. Run Tests and Capture Detailed Output
echo "Running tests..."
# Run pytest as ga user
PYTEST_OUT=$(su - ga -c "cd '$TASK_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT=$?

# 5. Parse Test Results
# Extract counts
TOTAL_PASSED=$(echo "$PYTEST_OUT" | grep -o "[0-9]* passed" | awk '{print $1}' || echo "0")
TOTAL_FAILED=$(echo "$PYTEST_OUT" | grep -o "[0-9]* failed" | awk '{print $1}' || echo "0")

# Check individual modules
TOKENIZER_PASS=$(echo "$PYTEST_OUT" | grep "test_tokenizer.py" | grep -c "PASSED" || echo "0")
INDEXER_PASS=$(echo "$PYTEST_OUT" | grep "test_indexer.py" | grep -c "PASSED" || echo "0")
SCORER_PASS=$(echo "$PYTEST_OUT" | grep "test_scorer.py" | grep -c "PASSED" || echo "0")
QUERY_PASS=$(echo "$PYTEST_OUT" | grep "test_query.py" | grep -c "PASSED" || echo "0")
SEARCHER_PASS=$(echo "$PYTEST_OUT" | grep "test_searcher.py" | grep -c "PASSED" || echo "0")

# 6. Create JSON Result
cat > "$RESULT_FILE" << EOF
{
    "timestamp": $(date +%s),
    "tests_modified": $TESTS_MODIFIED,
    "source_modified": $SOURCE_MODIFIED,
    "pytest_exit_code": $PYTEST_EXIT,
    "total_passed": ${TOTAL_PASSED:-0},
    "total_failed": ${TOTAL_FAILED:-0},
    "module_results": {
        "tokenizer": ${TOKENIZER_PASS:-0},
        "indexer": ${INDEXER_PASS:-0},
        "scorer": ${SCORER_PASS:-0},
        "query": ${QUERY_PASS:-0},
        "searcher": ${SEARCHER_PASS:-0}
    },
    "pytest_output_sample": "$(echo "$PYTEST_OUT" | tail -n 20 | sed 's/"/\\"/g')"
}
EOF

# Fix permissions
chmod 666 "$RESULT_FILE"

echo "Result exported to $RESULT_FILE"