#!/bin/bash
# Export script for library_hierarchy_queries
# Verifies file existence, content keywords, and compares output against ground truth

echo "=== Exporting Library Hierarchy Task Results ==="

source /workspace/scripts/task_utils.sh

# Record end state
take_screenshot /tmp/task_final.png

QUERY_FILE="/home/ga/Desktop/hierarchy_queries.sql"
OUTPUT_FILE="/home/ga/Desktop/hierarchy_output.txt"
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Check Files
[ -f "$QUERY_FILE" ] && Q_EXISTS=true || Q_EXISTS=false
[ -f "$OUTPUT_FILE" ] && O_EXISTS=true || O_EXISTS=false
Q_SIZE=$(stat -c%s "$QUERY_FILE" 2>/dev/null || echo 0)
O_SIZE=$(stat -c%s "$OUTPUT_FILE" 2>/dev/null || echo 0)

# 2. Check SQL Keywords (Process Verification)
HAS_CONNECT_BY=false
HAS_SYS_PATH=false
HAS_RECURSIVE=false
HAS_WITH=false

if [ "$Q_EXISTS" = "true" ]; then
    grep -qi "CONNECT BY" "$QUERY_FILE" && HAS_CONNECT_BY=true
    grep -qi "SYS_CONNECT_BY_PATH" "$QUERY_FILE" && HAS_SYS_PATH=true
    grep -qi "WITH" "$QUERY_FILE" && HAS_WITH=true
    # "RECURSIVE" isn't strictly a keyword in Oracle syntax (it's implicit in WITH clause for 11gR2+, 
    # but the task asked for "Recursive CTE"). Oracle uses `WITH name (cols) AS ...`
    # We'll check for WITH.
fi

# 3. Generate Ground Truth Data
# We run specific validation queries to get the "correct answers" that should be in the agent's output.
echo "Generating ground truth..."

python3 << 'PYEOF'
import oracledb
import json

result = {
    "files": {
        "query_file_exists": "${Q_EXISTS}" == "true",
        "output_file_exists": "${O_EXISTS}" == "true",
        "query_file_size": int("${Q_SIZE}"),
        "output_file_size": int("${O_SIZE}")
    },
    "keywords": {
        "connect_by": "${HAS_CONNECT_BY}" == "true",
        "sys_connect_by_path": "${HAS_SYS_PATH}" == "true",
        "with_cte": "${HAS_WITH}" == "true"
    },
    "ground_truth": {},
    "agent_output_content": ""
}

try:
    # Load agent output content for analysis
    output_path = "${OUTPUT_FILE}"
    if result["files"]["output_file_exists"]:
        with open(output_path, 'r', errors='ignore') as f:
            result["agent_output_content"] = f.read()

    # Connect to DB for ground truth
    conn = oracledb.connect(user="hr", password="hr123", dsn="localhost:1521/XEPDB1")
    cursor = conn.cursor()

    # GT 1: Check if Category 005 exists and get its name (for Path check)
    cursor.execute("SELECT category_name FROM library_categories WHERE category_code = '005'")
    row = cursor.fetchone()
    result["ground_truth"]["cat_005_name"] = row[0] if row else "Unknown"

    # GT 2: Check item count for Main Class 500 (Science)
    # The count should include 500 + 510 + 520 + 530 + 512 + 515 + 523
    # Items: 'The Science Book' (500) + 'Abstract Algebra' (512) + 'Linear...' (512) + 'Calculus' (515) + 'Mars' (523)
    # Total = 1 + 2 + 1 + 1 = 5 items in 500 tree.
    # Let's run the actual query to be sure.
    cursor.execute("""
        SELECT COUNT(*)
        FROM library_items i
        JOIN library_categories c ON i.category_id = c.category_id
        WHERE c.category_id IN (
            SELECT category_id FROM library_categories
            START WITH category_code = '500'
            CONNECT BY PRIOR category_id = parent_id
        )
    """)
    result["ground_truth"]["count_500"] = cursor.fetchone()[0]

    # GT 3: Check empty leaf
    # 004 was created as empty leaf.
    cursor.execute("""
        SELECT category_code
        FROM library_categories c
        WHERE NOT EXISTS (
            SELECT 1 FROM library_categories child WHERE child.parent_id = c.category_id
        )
        AND NOT EXISTS (
            SELECT 1 FROM library_items i WHERE i.category_id = c.category_id
        )
        AND category_code = '004'
    """)
    row = cursor.fetchone()
    result["ground_truth"]["empty_leaf_code"] = row[0] if row else None

    # GT 4: Max Depth Employee (Recursive CTE ground truth)
    # In HR schema: King(1) -> Kochhar(2) -> Higgins(3) -> Gietz(4) is a standard deep chain.
    cursor.execute("""
        SELECT MAX(LEVEL) FROM employees
        START WITH manager_id IS NULL
        CONNECT BY PRIOR employee_id = manager_id
    """)
    result["ground_truth"]["max_emp_depth"] = cursor.fetchone()[0]

    conn.close()

except Exception as e:
    result["error"] = str(e)

with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)

PYEOF

# Clean up
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="
cat /tmp/task_result.json