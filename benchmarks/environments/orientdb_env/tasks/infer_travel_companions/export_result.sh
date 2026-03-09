#!/bin/bash
echo "=== Exporting infer_travel_companions results ==="

source /workspace/scripts/task_utils.sh

# Capture final screenshot
take_screenshot /tmp/task_final.png

# We need to extract the graph state to JSON for verification.
# We will check:
# 1. Did the user create the reviews? (John->Review->Hotel and Maria->Review->Hotel on 2023-12-25)
# 2. Did the user create the PotentialCompanion class?
# 3. Does a PotentialCompanion edge exist between John and Maria?

TARGET_DATE="2023-12-25"
P1_EMAIL="john.smith@example.com"
P2_EMAIL="maria.garcia@example.com"
HOTEL_NAME="Hotel Artemide"

# Helper to run SQL and output clean JSON
run_query() {
    local sql="$1"
    # Using curl directly to control output format better
    curl -s -X POST \
        -u "root:GymAnything123!" \
        -H "Content-Type: application/json" \
        -d "{\"command\": \"$sql\"}" \
        "http://localhost:2480/command/demodb/sql"
}

# 1. Check for Reviews and Links
# Query: Find reviews on date, check if connected to specific Profile (in 'MadeReview') and Hotel (out 'HasReview')
# Note: In DemoDB schema: Profile -MadeReview-> Review -HasReview-> Hotel
# We'll use a complex query to get everything in one go.

echo "Querying graph topology..."

# Check John's Review
JOHN_REVIEW_JSON=$(run_query "SELECT @rid, Stars, Text FROM Reviews WHERE Date='${TARGET_DATE}' AND in('MadeReview').Email CONTAINS '${P1_EMAIL}' AND out('HasReview').Name CONTAINS '${HOTEL_NAME}'")

# Check Maria's Review
MARIA_REVIEW_JSON=$(run_query "SELECT @rid, Stars, Text FROM Reviews WHERE Date='${TARGET_DATE}' AND in('MadeReview').Email CONTAINS '${P2_EMAIL}' AND out('HasReview').Name CONTAINS '${HOTEL_NAME}'")

# 2. Check Class Existence
CLASS_CHECK=$(run_query "SELECT name FROM (SELECT expand(classes) FROM metadata:schema) WHERE name = 'PotentialCompanion'")

# 3. Check PotentialCompanion Edge
# We check both directions: John->Maria OR Maria->John
EDGE_CHECK=$(run_query "SELECT count(*) as cnt FROM PotentialCompanion WHERE (out.Email = '${P1_EMAIL}' AND in.Email = '${P2_EMAIL}') OR (out.Email = '${P2_EMAIL}' AND in.Email = '${P1_EMAIL}')")

# 4. Check for duplicates/self-loops (Anti-gaming/Quality)
# Count total edges vs unique pairs
EDGE_QUALITY=$(run_query "SELECT count(*) as total_edges FROM PotentialCompanion")

# Compile into a single JSON file
cat > /tmp/task_result.json <<EOF
{
    "john_review": $JOHN_REVIEW_JSON,
    "maria_review": $MARIA_REVIEW_JSON,
    "class_check": $CLASS_CHECK,
    "edge_check": $EDGE_CHECK,
    "edge_quality": $EDGE_QUALITY,
    "timestamp": $(date +%s)
}
EOF

echo "Export complete. Result saved to /tmp/task_result.json"
cat /tmp/task_result.json