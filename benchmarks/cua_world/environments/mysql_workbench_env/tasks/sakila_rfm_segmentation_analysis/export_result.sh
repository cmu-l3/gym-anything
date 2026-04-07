#!/bin/bash
# Export script for Sakila RFM Segmentation Task
# Validates the database state and export file without giving the agent the answer key

echo "=== Exporting RFM Analysis Results ==="

source /workspace/scripts/task_utils.sh

# Capture final state
if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
take_screenshot /tmp/task_final.png

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
EXPORT_PATH="/home/ga/Documents/exports/churn_risk_customers.csv"

# ------------------------------------------------------------------
# 1. DATABASE VALIDATION
# ------------------------------------------------------------------

# Check table existence
TABLE_EXISTS=$(mysql -u root -p'GymAnything#2024' -N -e "
    SELECT COUNT(*) FROM information_schema.tables 
    WHERE table_schema='sakila' AND table_name='customer_rfm_scores';
" 2>/dev/null)
TABLE_EXISTS=${TABLE_EXISTS:-0}

ROW_COUNT=0
METRICS_MATCH_COUNT=0
R_SCORE_LOGIC_MATCH=0
F_SCORE_LOGIC_MATCH=0
M_SCORE_LOGIC_MATCH=0

if [ "$TABLE_EXISTS" -eq 1 ]; then
    ROW_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "SELECT COUNT(*) FROM customer_rfm_scores;" 2>/dev/null)
    
    # GROUND TRUTH VALIDATION QUERY
    # We calculate the expected values and join with the agent's table to verify correctness.
    # Tolerances: Monetary +/- 0.1, Recency exact, Frequency exact.
    
    echo "Validating metrics and scoring logic..."
    
    # Create a temporary verification table with correct values
    mysql -u root -p'GymAnything#2024' sakila -e "
        CREATE TEMPORARY TABLE ground_truth_rfm AS
        WITH base_metrics AS (
            SELECT 
                c.customer_id,
                DATEDIFF('2006-02-14 23:59:59', MAX(r.rental_date)) as recency,
                COUNT(r.rental_id) as frequency,
                SUM(p.amount) as monetary
            FROM customer c
            JOIN rental r ON c.customer_id = r.customer_id
            JOIN payment p ON c.customer_id = p.customer_id
            GROUP BY c.customer_id
        ),
        scored AS (
            SELECT *,
                NTILE(5) OVER (ORDER BY recency DESC, customer_id ASC) as r_score, -- Low days = High score (5)
                NTILE(5) OVER (ORDER BY frequency ASC, customer_id ASC) as f_score, -- High count = High score (5)
                NTILE(5) OVER (ORDER BY monetary ASC, customer_id ASC) as m_score   -- High val = High score (5)
            FROM base_metrics
        )
        SELECT * FROM scored;
    " 2>/dev/null

    # Metric Accuracy Check
    METRICS_MATCH_COUNT=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*)
        FROM customer_rfm_scores a
        JOIN ground_truth_rfm g ON a.customer_id = g.customer_id
        WHERE 
            a.recency_days = g.recency
            AND a.frequency_count = g.frequency
            AND ABS(a.monetary_total - g.monetary) < 0.1;
    " 2>/dev/null)

    # Scoring Logic Check - R Score (Directionality is key)
    # R_Score should be 5 for LOW recency days.
    # Check if agent's r_score matches our ground truth (which uses DESC sort for 5=Recent)
    R_SCORE_LOGIC_MATCH=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*)
        FROM customer_rfm_scores a
        JOIN ground_truth_rfm g ON a.customer_id = g.customer_id
        WHERE a.r_score = g.r_score;
    " 2>/dev/null)

    # Scoring Logic Check - F Score
    F_SCORE_LOGIC_MATCH=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*)
        FROM customer_rfm_scores a
        JOIN ground_truth_rfm g ON a.customer_id = g.customer_id
        WHERE a.f_score = g.f_score;
    " 2>/dev/null)

    # Scoring Logic Check - M Score
    M_SCORE_LOGIC_MATCH=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
        SELECT COUNT(*)
        FROM customer_rfm_scores a
        JOIN ground_truth_rfm g ON a.customer_id = g.customer_id
        WHERE a.m_score = g.m_score;
    " 2>/dev/null)
    
    # Cleanup temp table (optional, happens on disconnect anyway)
fi

# ------------------------------------------------------------------
# 2. EXPORT FILE VALIDATION
# ------------------------------------------------------------------

FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
VALID_ROWS=0
CORRECT_SEGMENT_ROWS=0

if [ -f "$EXPORT_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$EXPORT_PATH" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$EXPORT_PATH" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Check content roughly
    LINE_COUNT=$(wc -l < "$EXPORT_PATH" || echo "0")
    if [ "$LINE_COUNT" -gt 1 ]; then
        VALID_ROWS=$((LINE_COUNT - 1))
        
        # Verify the segment logic via DB validation of the CSV content
        # We'll create a temp table, load CSV, and compare
        # Since LOAD DATA INFILE has permission issues often in constrained envs, we'll python check it later or do a spot check here.
        
        # Simple bash check: do the rows in CSV satisfy the criteria based on Ground Truth?
        # Extract IDs from CSV
        CSV_IDS=$(tail -n +2 "$EXPORT_PATH" | cut -d',' -f1 | tr -d '"' | tr '\n' ',' | sed 's/,$//')
        
        if [ -n "$CSV_IDS" ]; then
            # Query Ground Truth to see if these IDs are actually Churn Risks
            # Risk: R <= 2 AND (F >= 4 OR M >= 4)
            CORRECT_SEGMENT_ROWS=$(mysql -u root -p'GymAnything#2024' sakila -N -e "
                WITH base_metrics AS (
                    SELECT 
                        c.customer_id,
                        DATEDIFF('2006-02-14 23:59:59', MAX(r.rental_date)) as recency,
                        COUNT(r.rental_id) as frequency,
                        SUM(p.amount) as monetary
                    FROM customer c
                    JOIN rental r ON c.customer_id = r.customer_id
                    JOIN payment p ON c.customer_id = p.customer_id
                    GROUP BY c.customer_id
                ),
                scored AS (
                    SELECT *,
                        NTILE(5) OVER (ORDER BY recency DESC, customer_id ASC) as r_score,
                        NTILE(5) OVER (ORDER BY frequency ASC, customer_id ASC) as f_score,
                        NTILE(5) OVER (ORDER BY monetary ASC, customer_id ASC) as m_score
                    FROM base_metrics
                )
                SELECT COUNT(*) FROM scored 
                WHERE customer_id IN ($CSV_IDS)
                AND (r_score <= 2 AND (f_score >= 4 OR m_score >= 4));
            " 2>/dev/null)
        fi
    fi
fi

# App status
APP_RUNNING=$(pgrep -f "mysql-workbench" > /dev/null && echo "true" || echo "false")

# ------------------------------------------------------------------
# 3. JSON OUTPUT
# ------------------------------------------------------------------

# Create secure temp file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "table_exists": $([ "$TABLE_EXISTS" -eq 1 ] && echo "true" || echo "false"),
    "row_count": ${ROW_COUNT:-0},
    "metrics_match_count": ${METRICS_MATCH_COUNT:-0},
    "r_score_logic_match": ${R_SCORE_LOGIC_MATCH:-0},
    "f_score_logic_match": ${F_SCORE_LOGIC_MATCH:-0},
    "m_score_logic_match": ${M_SCORE_LOGIC_MATCH:-0},
    "file_exists": $FILE_EXISTS,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "csv_row_count": $VALID_ROWS,
    "correct_segment_rows": ${CORRECT_SEGMENT_ROWS:-0},
    "app_running": $APP_RUNNING
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Results exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="