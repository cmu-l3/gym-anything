#!/bin/bash
# Export script for Enrich Product Fields task
echo "=== Exporting enrich_product_fields Result ==="

source /workspace/scripts/task_utils.sh

# Fallback DB query
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
    json_escape() {
        local str="$1"
        echo "$str" | sed 's/\\/\\\\/g; s/"/\\"/g; s/\t/\\t/g' | tr -d '\n' | tr -d '\r'
    }
fi

take_screenshot /tmp/task_end_screenshot.png

# 1. Check Taxonomy Vocabulary 'brands'
VOCAB_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM taxonomy_vocabulary WHERE vid = 'brands'")
VOCAB_EXISTS=${VOCAB_EXISTS:-0}

# 2. Check Terms in 'brands' vocabulary
# Get list of term names
TERMS_JSON="[]"
if [ "$VOCAB_EXISTS" -gt 0 ]; then
    TERMS=$(drupal_db_query "SELECT name FROM taxonomy_term_field_data WHERE vid = 'brands'")
    # Convert newline separated list to JSON array
    TERMS_JSON=$(echo "$TERMS" | jq -R -s -c 'split("\n")[:-1]')
fi

# 3. Check Fields Configuration
# Check if field config exists in the config table
FIELD_BRAND_CONFIG=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product.default.field_brand'")
FIELD_WEIGHT_CONFIG=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product.default.field_weight'")

FIELD_BRAND_EXISTS="false"
[ "$FIELD_BRAND_CONFIG" -gt 0 ] && FIELD_BRAND_EXISTS="true"

FIELD_WEIGHT_EXISTS="false"
[ "$FIELD_WEIGHT_CONFIG" -gt 0 ] && FIELD_WEIGHT_EXISTS="true"

# 4. Check Product Data
# We need to construct a JSON object with the data for the specific products
# We'll use python to execute the complex query and format JSON to avoid bash string hell
PYTHON_SCRIPT="
import pymysql
import json
import sys

try:
    conn = pymysql.connect(
        host='127.0.0.1', 
        user='drupal', 
        password='drupalpass', 
        database='drupal',
        port=3306
    )
    cursor = conn.cursor()
    
    products = [
        'Sony WH-1000XM5 Wireless Headphones', # Full titles from seed data
        'Apple AirPods Pro (2nd Gen)',
        'Samsung Galaxy Buds2 Pro',
        'Logitech MX Master 3S',
        'Bose QuietComfort 45'
    ]
    
    # Map friendly names to actual DB titles (fuzzy match)
    results = {}
    
    for p_name in products:
        # Find product ID
        cursor.execute(\"SELECT product_id, title FROM commerce_product_field_data WHERE title LIKE %s LIMIT 1\", ('%' + p_name.split()[0] + '%',))
        row = cursor.fetchone()
        
        if row:
            pid = row[0]
            real_title = row[1]
            p_data = {'title': real_title, 'brand': None, 'weight': None}
            
            # Check Brand (if table exists)
            try:
                cursor.execute(\"\"\"
                    SELECT t.name 
                    FROM commerce_product__field_brand b
                    JOIN taxonomy_term_field_data t ON b.field_brand_target_id = t.tid
                    WHERE b.entity_id = %s
                \"\"\", (pid,))
                brand_row = cursor.fetchone()
                if brand_row:
                    p_data['brand'] = brand_row[0]
            except:
                pass # Table might not exist
                
            # Check Weight (if table exists)
            try:
                cursor.execute(\"SELECT field_weight_value FROM commerce_product__field_weight WHERE entity_id = %s\", (pid,))
                weight_row = cursor.fetchone()
                if weight_row:
                    p_data['weight'] = float(weight_row[0])
            except:
                pass
                
            results[real_title] = p_data
            
    print(json.dumps(results))
    
except Exception as e:
    print(json.dumps({'error': str(e)}))
"

# Install python dependencies if missing (setup script should have handled this, but safety check)
if ! python3 -c "import pymysql" 2>/dev/null; then
    pip3 install pymysql >/dev/null 2>&1
fi

PRODUCT_DATA_JSON=$(python3 -c "$PYTHON_SCRIPT")

# Write full result
cat > /tmp/enrich_product_fields_result.json << EOF
{
    "vocab_exists": $VOCAB_EXISTS,
    "terms_found": $TERMS_JSON,
    "field_brand_exists": $FIELD_BRAND_EXISTS,
    "field_weight_exists": $FIELD_WEIGHT_EXISTS,
    "product_data": $PRODUCT_DATA_JSON,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure readable
chmod 666 /tmp/enrich_product_fields_result.json 2>/dev/null || true

echo "Result JSON generated:"
cat /tmp/enrich_product_fields_result.json
echo "=== Export Complete ==="