#!/bin/bash
echo "=== Exporting fix_async_server Result ==="

. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_async_server"
PROJECT_DIR="/home/ga/PycharmProjects/async_scheduler"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/${TASK_NAME}_start_ts 2>/dev/null || echo "0")

DISPLAY=:1 import -window root /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/${TASK_NAME}_end_screenshot.png 2>/dev/null || true

PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v --tb=short 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# Bug 1: time.sleep replaced with await asyncio.sleep in worker.py
BUG1_FIXED=false
WORKER_CONTENT=$(cat "$PROJECT_DIR/server/worker.py" 2>/dev/null || echo "")
if ! echo "$WORKER_CONTENT" | grep -q 'time\.sleep'; then
    if echo "$WORKER_CONTENT" | grep -q 'await asyncio\.sleep\|await asyncio.sleep'; then
        BUG1_FIXED=true
    fi
fi
echo "$PYTEST_OUTPUT" | grep -q "test_process_job_does_not_block_event_loop PASSED" && BUG1_FIXED=true

# Bug 2: run_workers uses asyncio.gather or create_task (not sequential loop with await)
BUG2_FIXED=false
if echo "$WORKER_CONTENT" | grep -qE 'asyncio\.gather|asyncio\.create_task|gather\('; then
    BUG2_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_run_workers_concurrent_timing PASSED" && BUG2_FIXED=true

# Bug 3: JobRegistry uses asyncio.Lock
BUG3_FIXED=false
REGISTRY_CONTENT=$(cat "$PROJECT_DIR/server/registry.py" 2>/dev/null || echo "")
if echo "$REGISTRY_CONTENT" | grep -qE 'asyncio\.Lock\(\)|self\._lock|async with'; then
    BUG3_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_concurrent_updates_preserve_counts PASSED" && BUG3_FIXED=true

# Bug 4: await response.json() in client.py
BUG4_FIXED=false
CLIENT_CONTENT=$(cat "$PROJECT_DIR/server/client.py" 2>/dev/null || echo "")
if echo "$CLIENT_CONTENT" | grep -q 'await response\.json\(\)\|await resp\.json()'; then
    BUG4_FIXED=true
fi
# Also accept if the pattern is `data = await response.json()`
if echo "$CLIENT_CONTENT" | grep -qE 'await.*\.json\(\)'; then
    BUG4_FIXED=true
fi
echo "$PYTEST_OUTPUT" | grep -q "test_fetch_job_status_returns_dict PASSED" && BUG4_FIXED=true

cat > "$RESULT_FILE" << EOF
{
    "task_name": "$TASK_NAME",
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "bug1_blocking_sleep_fixed": $BUG1_FIXED,
    "bug2_sequential_workers_fixed": $BUG2_FIXED,
    "bug3_registry_lock_added": $BUG3_FIXED,
    "bug4_await_response_json_fixed": $BUG4_FIXED
}
EOF

echo "Pytest: $TESTS_PASSED passed, $TESTS_FAILED failed"
echo "Bug 1 (blocking sleep) fixed: $BUG1_FIXED"
echo "Bug 2 (sequential workers) fixed: $BUG2_FIXED"
echo "Bug 3 (missing lock) fixed: $BUG3_FIXED"
echo "Bug 4 (missing await json) fixed: $BUG4_FIXED"
echo "=== Export Complete ==="
