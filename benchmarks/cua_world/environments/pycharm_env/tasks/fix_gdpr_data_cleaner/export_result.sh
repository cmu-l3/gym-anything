#!/bin/bash
echo "=== Exporting fix_gdpr_data_cleaner Result ==="

source /workspace/scripts/task_utils.sh

TASK_NAME="fix_gdpr_data_cleaner"
PROJECT_DIR="/home/ga/PycharmProjects/gdpr_cleaner"
RESULT_FILE="/tmp/${TASK_NAME}_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Run the test suite (capture output)
echo "Running test suite..."
PYTEST_OUTPUT=$(su - ga -c "cd '$PROJECT_DIR' && python3 -m pytest tests/ -v 2>&1")
PYTEST_EXIT_CODE=$?

TESTS_PASSED=$(echo "$PYTEST_OUTPUT" | grep -c " PASSED" || true)
TESTS_FAILED=$(echo "$PYTEST_OUTPUT" | grep -c " FAILED" || true)
ALL_TESTS_PASS=false
[ "$PYTEST_EXIT_CODE" -eq 0 ] && ALL_TESTS_PASS=true

# 3. Verify Deterministic Hashing & Data Integrity
# We run the pipeline TWICE. If hashing is deterministic, email_hash column must be identical.
# If hashing is random (using hash()), they will differ between runs.
echo "Running verification checks..."

OUTPUT_CSV="$PROJECT_DIR/data/clean_signups.csv"
RUN1_CSV="/tmp/run1.csv"
RUN2_CSV="/tmp/run2.csv"

# Run 1
su - ga -c "cd '$PROJECT_DIR' && python3 main.py" > /dev/null 2>&1
cp "$OUTPUT_CSV" "$RUN1_CSV"

# Run 2
su - ga -c "cd '$PROJECT_DIR' && python3 main.py" > /dev/null 2>&1
cp "$OUTPUT_CSV" "$RUN2_CSV"

# Check Row Count (Data Retention)
ROW_COUNT=$(wc -l < "$RUN1_CSV" || echo "0")
# Header is 1 line, so actual data rows = ROW_COUNT - 1
DATA_ROWS=$((ROW_COUNT - 1))

# Check Hashing Stability
# Extract email_hash column (assuming it's the last column or specific index, better to use python)
HASHES_MATCH=$(python3 -c "
import pandas as pd
try:
    df1 = pd.read_csv('$RUN1_CSV')
    df2 = pd.read_csv('$RUN2_CSV')
    if 'email_hash' not in df1.columns:
        print('missing_column')
    elif df1['email_hash'].equals(df2['email_hash']):
        print('true')
    else:
        print('false')
except Exception:
    print('error')
")

# Check IP Masking Pattern
# Should look like 192.168.1.xxx (3 dots, ends with xxx)
IP_MASK_CORRECT=$(python3 -c "
import pandas as pd
import re
try:
    df = pd.read_csv('$RUN1_CSV')
    # Check first 5 IPs
    sample = df['last_ip'].head(5).tolist()
    valid = all(re.match(r'^\d+\.\d+\.\d+\.xxx$', ip) for ip in sample)
    print('true' if valid else 'false')
except Exception:
    print('false')
")

# 4. JSON Export
cat > "$RESULT_FILE" << EOF
{
    "task_start": $TASK_START,
    "pytest_exit_code": $PYTEST_EXIT_CODE,
    "tests_passed": $TESTS_PASSED,
    "tests_failed": $TESTS_FAILED,
    "all_tests_pass": $ALL_TESTS_PASS,
    "row_count": $DATA_ROWS,
    "hashes_stable": "$HASHES_MATCH",
    "ip_mask_correct": "$IP_MASK_CORRECT",
    "pytest_output_snippet": $(echo "$PYTEST_OUTPUT" | tail -n 20 | jq -R -s '.')
}
EOF

# 5. Permission fix for copy_from_env
chmod 644 "$RESULT_FILE"
echo "Result exported to $RESULT_FILE"