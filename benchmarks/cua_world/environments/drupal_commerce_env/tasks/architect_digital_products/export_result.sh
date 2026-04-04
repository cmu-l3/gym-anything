#!/bin/bash
# Export script for architect_digital_products
echo "=== Exporting architect_digital_products results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# We need to verify configuration. In Drupal 8+, config is stored in the database 'config' table.
# We will query this table to check for existence of required entities.

# Helper to read config blob (serialized PHP)
# We will dump the blobs to a temp file and parse with Python in the script to avoid complex bash regex on binary-ish data.

# 1. Check Taxonomy Vocabulary
VOCAB_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'taxonomy.vocabulary.file_formats'")

# 2. Check Taxonomy Terms
# Terms are content, stored in taxonomy_term_field_data
# We check if terms with the expected VID exist
TERMS_JSON=$(drupal_db_query "SELECT JSON_ARRAYAGG(name) FROM taxonomy_term_field_data WHERE vid = 'file_formats'")

# 3. Check Variation Type
VARIATION_TYPE_CONFIG=$(drupal_db_query "SELECT data FROM config WHERE name = 'commerce_product.commerce_product_variation_type.digital_variation'")
if [ -z "$VARIATION_TYPE_CONFIG" ]; then
    VARIATION_EXISTS="false"
else
    VARIATION_EXISTS="true"
fi

# 4. Check Product Type
PRODUCT_TYPE_CONFIG=$(drupal_db_query "SELECT data FROM config WHERE name = 'commerce_product.commerce_product_type.digital_product'")
if [ -z "$PRODUCT_TYPE_CONFIG" ]; then
    PRODUCT_TYPE_EXISTS="false"
else
    PRODUCT_TYPE_EXISTS="true"
fi

# 5. Check Fields
# Field storage and instance config
FIELD_FILE_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product_variation.digital_variation.field_download_file'")
FIELD_FORMAT_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name = 'field.field.commerce_product_variation.digital_variation.field_file_format'")

# 6. Analyze blobs with Python to check specific settings (like 'shippable' or 'variationType')
# We write the hex-encoded blobs to files or pass them to python
# Since we might not have direct hex dump access easily, we'll try to grep the raw output in Python if possible,
# or just assume if the config exists it's likely correct, but we should try to be specific.
# NOTE: MariaDB 'data' column in 'config' table is a blob. `drupal_db_query` uses `mysql -N -e` which outputs text.
# Binary data might be messy.
# Safer strategy: Check for the presence of the config entry (Primary) and specific substrings in the string representation if possible.
# Drupal config export is typically YAML-like text if exported, but in DB it's serialized PHP.

# Let's save the raw config data to a file for Python to analyze
# We use Python to fetch the data cleanly to handle binary/serialized format
cat > /tmp/analyze_config.py << 'PYEOF'
import sys
import pymysql
import phpserialize
import json
import re

# Connect to DB (using hardcoded creds from env setup)
connection = pymysql.connect(host='127.0.0.1',
                             user='drupal',
                             password='drupalpass',
                             database='drupal',
                             cursorclass=pymysql.cursors.DictCursor)

results = {
    "variation_shippable": True, # Default to true (bad)
    "product_uses_variation": False,
    "file_field_type": None,
    "format_field_target": None
}

try:
    with connection.cursor() as cursor:
        # Check Variation Type traits (Serialized PHP)
        cursor.execute("SELECT data FROM config WHERE name = 'commerce_product.commerce_product_variation_type.digital_variation'")
        row = cursor.fetchone()
        if row:
            data = row['data'] # This is bytes
            # Simple string check on the bytes is often enough for serialized data
            # "traits";a:1:{s:16:"commerce_shipping";a:0:{}} -> Shippable
            # If shippable is UNCHECKED, the trait shouldn't be there or configuration is empty?
            # Actually, usually it appears in the 'traits' array.
            # Let's look for 'commerce_shipping' in the data.
            try:
                # Basic check: if 'commerce_shipping' is present in the traits array key
                # In Drupal Commerce, the trait id is 'commerce_shipping'.
                # If we uncheck it, it should strictly NOT be in the enabled traits.
                # However, exact serialized string matching is brittle.
                s_data = str(data)
                if b'commerce_shipping' in data:
                    results['variation_shippable'] = True
                else:
                    results['variation_shippable'] = False
            except:
                pass

        # Check Product Type linkage
        cursor.execute("SELECT data FROM config WHERE name = 'commerce_product.commerce_product_type.digital_product'")
        row = cursor.fetchone()
        if row:
            data = row['data']
            if b'digital_variation' in data:
                results['product_uses_variation'] = True

        # Check Field Types (Field Storage config)
        # field.storage.commerce_product_variation.field_download_file
        cursor.execute("SELECT data FROM config WHERE name = 'field.storage.commerce_product_variation.field_download_file'")
        row = cursor.fetchone()
        if row:
             if b'file' in row['data']:
                 results['file_field_type'] = 'file'

        # field.storage.commerce_product_variation.field_file_format
        cursor.execute("SELECT data FROM config WHERE name = 'field.storage.commerce_product_variation.field_file_format'")
        row = cursor.fetchone()
        if row:
             if b'entity_reference' in row['data']:
                 results['format_field_type'] = 'entity_reference'

except Exception as e:
    results['error'] = str(e)

print(json.dumps(results))
PYEOF

# Run the python analysis script inside the container (or where python/pymysql is installed)
# The setup script installs python3-pymysql, so this should run.
ANALYSIS_JSON=$(python3 /tmp/analyze_config.py 2>/dev/null || echo "{}")

# Assemble final JSON
cat > /tmp/task_result.json << EOF
{
    "vocab_exists": $([ "$VOCAB_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "terms_found": ${TERMS_JSON:-"[]"},
    "variation_exists": $VARIATION_EXISTS,
    "product_type_exists": $PRODUCT_TYPE_EXISTS,
    "field_file_exists": $([ "$FIELD_FILE_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "field_format_exists": $([ "$FIELD_FORMAT_EXISTS" -gt 0 ] && echo "true" || echo "false"),
    "config_analysis": $ANALYSIS_JSON,
    "timestamp": $(date +%s)
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="