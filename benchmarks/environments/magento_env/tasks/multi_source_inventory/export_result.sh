#!/bin/bash
# Export script for MSI task

echo "=== Exporting MSI Task Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

# --- 1. Export Sources ---
echo "Exporting Sources..."
# We look specifically for the requested source codes
SOURCES_JSON=$(magento_query "SELECT source_code, name, enabled, country_id, region, city, postcode FROM inventory_source WHERE source_code IN ('east_coast_wh', 'west_coast_wh')" 2>/dev/null)

# Parse TSV to JSON structure for Python to handle easier, or just dump TSV
# Let's create a temporary python script to format the query output to JSON
cat << 'PYEOF' > /tmp/parse_sources.py
import sys
import json

lines = sys.stdin.readlines()
sources = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 7:
        sources.append({
            "source_code": parts[0],
            "name": parts[1],
            "enabled": parts[2],
            "country_id": parts[3],
            "region": parts[4],
            "city": parts[5],
            "postcode": parts[6]
        })
print(json.dumps(sources))
PYEOF

SOURCES_DATA=$(echo "$SOURCES_JSON" | python3 /tmp/parse_sources.py)
rm /tmp/parse_sources.py

# --- 2. Export Stock ---
echo "Exporting Stock..."
STOCK_DATA=$(magento_query "SELECT stock_id, name FROM inventory_stock WHERE name='US Regional Stock'" 2>/dev/null | tail -1)
STOCK_FOUND="false"
STOCK_ID=""
STOCK_NAME=""
if [ -n "$STOCK_DATA" ]; then
    STOCK_FOUND="true"
    STOCK_ID=$(echo "$STOCK_DATA" | awk -F'\t' '{print $1}')
    STOCK_NAME=$(echo "$STOCK_DATA" | awk -F'\t' '{print $2}')
fi

# --- 3. Export Stock-Source Links ---
echo "Exporting Stock Links..."
LINKS_LIST="[]"
if [ -n "$STOCK_ID" ]; then
    LINKS_JSON=$(magento_query "SELECT source_code, priority FROM inventory_source_stock_link WHERE stock_id=$STOCK_ID" 2>/dev/null)
    
    cat << 'PYEOF' > /tmp/parse_links.py
import sys
import json
lines = sys.stdin.readlines()
links = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 2:
        links.append({"source_code": parts[0], "priority": parts[1]})
print(json.dumps(links))
PYEOF
    LINKS_LIST=$(echo "$LINKS_JSON" | python3 /tmp/parse_links.py)
    rm /tmp/parse_links.py
fi

# --- 4. Export Inventory Items (Quantities) ---
echo "Exporting Inventory Items..."
# Check the specific SKUs and Sources
ITEMS_JSON=$(magento_query "SELECT source_code, sku, quantity, status FROM inventory_source_item WHERE source_code IN ('east_coast_wh', 'west_coast_wh') AND sku IN ('LAPTOP-001', 'PHONE-001', 'HEADPHONES-001')" 2>/dev/null)

cat << 'PYEOF' > /tmp/parse_items.py
import sys
import json
lines = sys.stdin.readlines()
items = []
for line in lines:
    parts = line.strip().split('\t')
    if len(parts) >= 4:
        items.append({
            "source_code": parts[0],
            "sku": parts[1],
            "quantity": parts[2],
            "status": parts[3]
        })
print(json.dumps(items))
PYEOF

ITEMS_LIST=$(echo "$ITEMS_JSON" | python3 /tmp/parse_items.py)
rm /tmp/parse_items.py

# --- 5. Compile Final Result JSON ---
TEMP_JSON=$(mktemp /tmp/msi_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "sources": $SOURCES_DATA,
    "stock_found": $STOCK_FOUND,
    "stock_name": "$STOCK_NAME",
    "stock_links": $LINKS_LIST,
    "inventory_items": $ITEMS_LIST,
    "timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/msi_result.json
echo ""
cat /tmp/msi_result.json
echo ""
echo "=== Export Complete ==="