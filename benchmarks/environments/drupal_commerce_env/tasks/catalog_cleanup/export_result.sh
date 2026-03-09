#!/bin/bash
# Export script for Catalog Cleanup task
echo "=== Exporting Catalog Cleanup Result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Get Task Timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Dump Final Database State
# We use a custom SQL query to get exactly the data we need to verify all 4 requirements + collateral damage
echo "Querying final catalog state..."
drupal_db_query "
SELECT 
    p.product_id, 
    p.title, 
    p.status as product_status,
    v.variation_id,
    v.sku,
    v.price__number,
    p.changed as product_changed,
    v.changed as variation_changed
FROM commerce_product_field_data p
LEFT JOIN commerce_product__variations pv ON p.product_id = pv.entity_id
LEFT JOIN commerce_product_variation_field_data v ON pv.variations_target_id = v.variation_id
ORDER BY p.product_id ASC
" > /tmp/final_catalog_dump.txt

# 4. Generate JSON Result using Python
# This processes the SQL dump and the initial state to create a comprehensive result object
python3 -c '
import json
import time
import sys

# Load initial state
initial_products = []
try:
    with open("/tmp/initial_catalog_state.json", "r") as f:
        initial_products = json.load(f)
except:
    pass

# Parse final state from dump
final_products = []
try:
    with open("/tmp/final_catalog_dump.txt", "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 8:
                final_products.append({
                    "product_id": parts[0],
                    "title": parts[1],
                    "status": parts[2],
                    "variation_id": parts[3],
                    "sku": parts[4],
                    "price": parts[5],
                    "product_changed": parts[6],
                    "variation_changed": parts[7]
                })
except Exception as e:
    print(f"Error parsing final dump: {e}", file=sys.stderr)

# Identify specific target products by loose matching on initial state
# We map Product ID -> Logic Key (bose, anker, nintendo, lg)
target_ids = {}
for p in initial_products:
    title_lower = p["title"].lower()
    pid = p["product_id"]
    if "bose quietcomfort" in title_lower:
        target_ids["bose"] = pid
    elif "anker powercore" in title_lower:
        target_ids["anker"] = pid
    elif "nintendo switch" in title_lower:
        target_ids["nintendo"] = pid
    elif "ultrawide monitor" in title_lower:
        target_ids["lg"] = pid

# Prepare result dictionary
result = {
    "task_start": int("'"$TASK_START"'"),
    "task_end": int("'"$TASK_END"'"),
    "targets": {
        "bose": {"found": False},
        "anker": {"found": False},
        "nintendo": {"found": False},
        "lg": {"found": False}
    },
    "collateral_damage": [],
    "catalog_size": len(final_products)
}

# Analyze Final State
for p in final_products:
    pid = p["product_id"]
    
    # Check Bose
    if pid == target_ids.get("bose"):
        result["targets"]["bose"] = {
            "found": True,
            "status": p["status"],
            "title": p["title"],
            "last_changed": int(p["product_changed"])
        }
    
    # Check Anker
    elif pid == target_ids.get("anker"):
        result["targets"]["anker"] = {
            "found": True,
            "status": p["status"],
            "title": p["title"],
            "last_changed": int(p["product_changed"])
        }

    # Check Nintendo
    elif pid == target_ids.get("nintendo"):
        result["targets"]["nintendo"] = {
            "found": True,
            "status": p["status"],
            "title": p["title"],
            "price": p["price"],
            "sku": p["sku"],
            "last_changed": max(int(p["product_changed"]), int(p["variation_changed"]))
        }

    # Check LG (Looking for the product that WAS the LG monitor)
    # Note: If they changed the title incorrectly, we might miss it if we matched by title, 
    # but we are matching by ID established from initial state.
    elif pid == target_ids.get("lg"):
        result["targets"]["lg"] = {
            "found": True,
            "sku": p["sku"],
            "title": p["title"],
            "last_changed": max(int(p["product_changed"]), int(p["variation_changed"]))
        }

    # Check Collateral Damage (products that are NOT targets)
    else:
        # Find original state
        orig = next((x for x in initial_products if x["product_id"] == pid), None)
        if orig:
            # Check for unauthorized changes
            changes = []
            if p["status"] != orig["status"]: changes.append("status")
            if p["title"] != orig["title"]: changes.append("title")
            if float(p["price"]) != float(orig["price"]): changes.append("price")
            if p["sku"] != orig["sku"]: changes.append("sku")
            
            if changes:
                result["collateral_damage"].append({
                    "product_id": pid,
                    "title": p["title"],
                    "changes": changes
                })

# Fallback for LG SKU check: If they created a NEW variation instead of updating,
# we need to search the whole catalog for the new SKU
if not result["targets"]["lg"]["found"] or result["targets"]["lg"]["sku"] != "LG-34UW-V2":
    for p in final_products:
        if p["sku"].upper() == "LG-34UW-V2":
            # Found the target SKU on a product
            result["targets"]["lg"]["found_via_sku_search"] = True
            result["targets"]["lg"]["actual_sku_found"] = p["sku"]
            result["targets"]["lg"]["linked_product_id"] = p["product_id"]

# Save result
with open("/tmp/task_result.json", "w") as f:
    json.dump(result, f, indent=2)
'

# Handle permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result JSON saved."
cat /tmp/task_result.json
echo "=== Export Complete ==="