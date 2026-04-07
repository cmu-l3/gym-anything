#!/bin/bash
echo "=== Exporting optimize_data_processing result ==="

PROJECT_DIR="/home/ga/PycharmProjects/data_processing"
RESULT_FILE="/tmp/optimize_task_result.json"
START_TS=$(cat /tmp/optimize_start_ts 2>/dev/null || echo "0")

# Take screenshot
DISPLAY=:1 scrot /tmp/optimize_final.png 2>/dev/null || true

# Run tests and capture output
echo "Running tests..."
# We run correctness and performance separately to distinguish failures
CORRECTNESS_OUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/test_correctness.py -v" 2>&1)
CORRECTNESS_EXIT=$?

PERF_OUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/test_performance.py -v" 2>&1)
PERF_EXIT=$?

# Analyze source code for expected optimizations
# We look for usage of efficient structures/methods

# Dedup: usage of set()
HAS_SET_DEDUP=$(grep -E "set\(|seen = set|seen.add" "$PROJECT_DIR/processing/dedup.py" > /dev/null && echo "true" || echo "false")

# Aggregate: usage of dict/defaultdict/Counter mapping, absence of nested loops
HAS_DICT_AGG=$(grep -E "defaultdict|Counter|\.get\(.*, 0\)|result\[.*\] \+=" "$PROJECT_DIR/processing/aggregate.py" > /dev/null && echo "true" || echo "false")

# TopK: usage of sort/sorted/heapq/nlargest
HAS_FAST_SORT=$(grep -E "sorted\(|\.sort\(|heapq\.nlargest" "$PROJECT_DIR/processing/topk.py" > /dev/null && echo "true" || echo "false")

# Join: usage of index/dict for lookup
HAS_HASH_JOIN=$(grep -E "index =|lookup =|\{.*\}" "$PROJECT_DIR/processing/join.py" > /dev/null && echo "true" || echo "false")

# Create result JSON using python to handle escaping safely
python3 -c "
import json
import time

result = {
    'task_start': $START_TS,
    'correctness_passed': $CORRECTNESS_EXIT == 0,
    'performance_passed': $PERF_EXIT == 0,
    'source_analysis': {
        'dedup_uses_set': $HAS_SET_DEDUP,
        'agg_uses_dict': $HAS_DICT_AGG,
        'topk_uses_fast_sort': $HAS_FAST_SORT,
        'join_uses_hash': $HAS_HASH_JOIN
    },
    'test_output': {
        'correctness': '''$CORRECTNESS_OUT''',
        'performance': '''$PERF_OUT'''
    }
}

with open('$RESULT_FILE', 'w') as f:
    json.dump(result, f, indent=2)
"

# Handle permissions
chmod 666 "$RESULT_FILE" 2>/dev/null || true

echo "Export complete. Result:"
grep -v "test_output" "$RESULT_FILE"