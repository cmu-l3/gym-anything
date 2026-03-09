#!/bin/bash
echo "=== Exporting denormalize_latest_review result ==="
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
export PATH=$PATH:$JAVA_HOME/bin
source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Verification Data Collection ---

# 1. Get Hotels Schema to verify property existence and type
echo "Fetching Hotels schema..."
SCHEMA_INFO=$(curl -s -u "${ORIENTDB_AUTH}" "${ORIENTDB_URL}/database/demodb" 2>/dev/null)

# 2. Get the 'LatestReview' data for a specific test hotel (Hotel Artemide)
echo "Fetching actual updated data for Hotel Artemide..."
ACTUAL_DATA=$(orientdb_query "demodb" "SELECT LatestReview FROM Hotels WHERE Name='Hotel Artemide'")

# 3. Get the Ground Truth raw reviews for Hotel Artemide to calculate expected value
# We use a MATCH query to find connected reviews regardless of edge direction (using -HasReview-)
echo "Fetching ground truth reviews..."
GROUND_TRUTH_REVIEWS=$(orientdb_query "demodb" "MATCH {class: Hotels, as: h, where: (Name='Hotel Artemide')} -HasReview- {class: Reviews, as: r} RETURN r.Stars as stars, r.Text as text, r.Date as date ORDER BY date DESC")

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Use Python to assemble the JSON to avoid bash quoting hell
python3 -c "
import json
import sys
import os

try:
    # Load raw data
    schema_raw = '''$SCHEMA_INFO'''
    actual_raw = '''$ACTUAL_DATA'''
    gt_raw = '''$GROUND_TRUTH_REVIEWS'''
    
    schema = json.loads(schema_raw) if schema_raw else {}
    actual = json.loads(actual_raw) if actual_raw else {}
    gt = json.loads(gt_raw) if gt_raw else {}
    
    # Process Schema
    hotels_class = next((c for c in schema.get('classes', []) if c['name'] == 'Hotels'), {})
    properties = hotels_class.get('properties', [])
    latest_review_prop = next((p for p in properties if p['name'] == 'LatestReview'), None)
    
    prop_exists = latest_review_prop is not None
    prop_type = latest_review_prop.get('type') if latest_review_prop else None
    
    # Process Actual Data
    actual_result = actual.get('result', [])
    actual_val = actual_result[0].get('LatestReview') if actual_result else None
    
    # Process Ground Truth
    gt_result = gt.get('result', [])
    # GT is sorted by Date DESC in query, so first is latest
    expected_val = None
    if gt_result:
        top = gt_result[0]
        # Normalize keys (API might return lowercase or camelCase depending on projection)
        expected_val = {
            'stars': top.get('stars'),
            'text': top.get('text'),
            'date': top.get('date')
        }

    output = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'schema_check': {
            'property_exists': prop_exists,
            'property_type': prop_type
        },
        'data_check': {
            'actual_value': actual_val,
            'expected_value': expected_val,
            'test_hotel': 'Hotel Artemide'
        },
        'screenshot_path': '/tmp/task_final.png'
    }
    
    print(json.dumps(output, indent=2))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))

" > "$TEMP_JSON"

# Save to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="