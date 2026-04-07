#!/bin/bash
echo "=== Exporting add_lab_test_dictionary result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot showing end state
take_screenshot /tmp/task_final.png

# Read initial anti-gaming baseline counts
INITIAL_NAME_COUNT=$(cat /tmp/initial_name_count 2>/dev/null || echo "0")
INITIAL_CODE_COUNT=$(cat /tmp/initial_code_count 2>/dev/null || echo "0")

echo "Analyzing final database state..."

# Determine final occurrences across the entire database dump (robust to schema variations)
FINAL_NAME_COUNT=$(mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null | grep -i "Helicobacter pylori" | wc -l | tr -d ' ')
FINAL_CODE_COUNT=$(mysqldump -u freemed -pfreemed freemed --no-create-info --skip-extended-insert 2>/dev/null | grep -i "UBT-HP" | wc -l | tr -d ' ')

# Determine exactly which table the record was inserted into (Structural Integrity Check)
FOUND_IN_TABLE=""
for table in $(mysql -u freemed -pfreemed freemed -N -e "SHOW TABLES;"); do
    COUNT=$(mysqldump -u freemed -pfreemed freemed $table --no-create-info --skip-extended-insert 2>/dev/null | grep -i "Helicobacter pylori" | wc -l | tr -d ' ')
    if [ "$COUNT" -gt 0 ]; then
        FOUND_IN_TABLE="$table"
        break
    fi
done

echo "Result Name Count: $FINAL_NAME_COUNT"
echo "Result Code Count: $FINAL_CODE_COUNT"
echo "Found in Table: $FOUND_IN_TABLE"

# Export data to JSON for verifier evaluation
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_name_count": $INITIAL_NAME_COUNT,
    "final_name_count": $FINAL_NAME_COUNT,
    "initial_code_count": $INITIAL_CODE_COUNT,
    "final_code_count": $FINAL_CODE_COUNT,
    "found_in_table": "$FOUND_IN_TABLE",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure safe file permissions for copy_from_env
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="