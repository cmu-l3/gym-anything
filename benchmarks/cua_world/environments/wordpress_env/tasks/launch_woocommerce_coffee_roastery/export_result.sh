#!/bin/bash
# Export script for launch_woocommerce_coffee_roastery task (post_task hook)
# Collects WooCommerce store state: settings, categories, attributes,
# products (including variable product variations), shipping, tax, coupons.

echo "=== Exporting launch_woocommerce_coffee_roastery result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# ============================================================
# Use Python for structured data extraction
# ============================================================
cat << 'PYEOF' > /tmp/export_store_data.py
import subprocess
import json
import re
import time
import sys

def run_cmd(cmd):
    """Run a shell command, return stdout. Empty string on error."""
    try:
        res = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=30)
        return res.stdout.strip()
    except Exception:
        return ""

def wp_cli(args_str):
    return run_cmd(f"wp {args_str} --allow-root --path=/var/www/html/wordpress 2>/dev/null")

def wp_db(query):
    escaped = query.replace("\\", "\\\\").replace("'", "'\\''")
    return run_cmd(
        f"docker exec wordpress-mariadb mysql -u wordpress -pwordpresspass wordpress -N -e '{escaped}' 2>/dev/null"
    )

def parse_php_value(serialized, key):
    """Extract a string value from PHP serialized data by key name.
    Parses the alternating key-value structure to avoid false matches
    when the key name also appears as a value of another field."""
    # Extract all serialized string tokens in order
    tokens = re.findall(r's:\d+:"([^"]*)"', serialized)
    # Tokens alternate: key, value, key, value, ...
    for i in range(0, len(tokens) - 1, 2):
        if tokens[i] == key:
            return tokens[i + 1]
    return ""

result = {}

# ================================================================
# 1. WooCommerce plugin status
# ================================================================
try:
    res = subprocess.run(
        ["wp", "plugin", "is-active", "woocommerce", "--allow-root",
         "--path=/var/www/html/wordpress"],
        capture_output=True, timeout=15
    )
    result["woocommerce_active"] = (res.returncode == 0)
except Exception:
    result["woocommerce_active"] = False

# ================================================================
# 2. Store settings
# ================================================================
result["store_settings"] = {
    "currency": wp_cli("option get woocommerce_currency"),
    "address": wp_cli("option get woocommerce_store_address"),
    "city": wp_cli("option get woocommerce_store_city"),
    "postcode": wp_cli("option get woocommerce_store_postcode"),
    "country": wp_cli("option get woocommerce_default_country"),
    "calc_taxes": wp_cli("option get woocommerce_calc_taxes"),
}

# ================================================================
# 3. Tax rates
# ================================================================
tax_rates = []
tax_rows = wp_db(
    "SELECT tax_rate_id, tax_rate_country, tax_rate_state, tax_rate, tax_rate_name "
    "FROM wp_woocommerce_tax_rates"
)
if tax_rows:
    for line in tax_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 5:
            tax_rates.append({
                "id": parts[0],
                "country": parts[1],
                "state": parts[2],
                "rate": parts[3],
                "name": parts[4]
            })
result["tax_rates"] = tax_rates

# ================================================================
# 4. Product categories with hierarchy
# ================================================================
categories = []
cat_rows = wp_db(
    "SELECT t.name, t.slug, tt.parent, tt.term_id "
    "FROM wp_terms t "
    "INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id "
    "WHERE tt.taxonomy = 'product_cat' "
    "AND t.name != 'Uncategorized' "
    "ORDER BY tt.parent, t.name"
)
if cat_rows:
    for line in cat_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 4:
            categories.append({
                "name": parts[0],
                "slug": parts[1],
                "parent_id": parts[2],
                "term_id": parts[3]
            })
# Resolve parent names for readability
term_to_name = {c["term_id"]: c["name"] for c in categories}
for c in categories:
    pid = c["parent_id"]
    c["parent_name"] = term_to_name.get(pid, "") if pid != "0" else ""
result["categories"] = categories

# ================================================================
# 5. Product attributes and terms
# ================================================================
attributes = []
attr_rows = wp_db(
    "SELECT attribute_id, attribute_name, attribute_label "
    "FROM wp_woocommerce_attribute_taxonomies"
)
if attr_rows:
    for line in attr_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            taxonomy = "pa_" + parts[1]
            term_rows = wp_db(
                f"SELECT t.name FROM wp_terms t "
                f"INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id "
                f"WHERE tt.taxonomy = '{taxonomy}'"
            )
            terms = [t.strip() for t in term_rows.split("\n") if t.strip()] if term_rows else []
            attributes.append({
                "id": parts[0],
                "slug": parts[1],
                "label": parts[2],
                "terms": terms
            })
result["attributes"] = attributes

# ================================================================
# 6. Products (simple and variable with variations)
# ================================================================
products = []
product_rows = wp_db(
    "SELECT p.ID, p.post_title, p.post_status "
    "FROM wp_posts p "
    "WHERE p.post_type = 'product' AND p.post_status = 'publish' "
    "ORDER BY p.ID"
)
if product_rows:
    for line in product_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            pid = parts[0]

            # Determine product type from product_type taxonomy
            ptype = wp_db(
                f"SELECT t.name FROM wp_terms t "
                f"INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id "
                f"INNER JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id "
                f"WHERE tr.object_id = {pid} AND tt.taxonomy = 'product_type'"
            ).strip()
            if not ptype:
                ptype = "simple"

            # Get categories assigned to this product
            pcats = wp_db(
                f"SELECT t.name FROM wp_terms t "
                f"INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id "
                f"INNER JOIN wp_term_relationships tr ON tt.term_taxonomy_id = tr.term_taxonomy_id "
                f"WHERE tr.object_id = {pid} AND tt.taxonomy = 'product_cat'"
            )
            cat_list = [c.strip() for c in pcats.split("\n") if c.strip()] if pcats else []

            # Get SKU and regular price
            sku = wp_db(f"SELECT meta_value FROM wp_postmeta WHERE post_id={pid} AND meta_key='_sku'")
            price = wp_db(f"SELECT meta_value FROM wp_postmeta WHERE post_id={pid} AND meta_key='_regular_price'")

            product = {
                "id": pid,
                "name": parts[1],
                "status": parts[2],
                "type": ptype,
                "categories": cat_list,
                "sku": sku if sku else "",
                "regular_price": price if price else "",
            }

            # If variable, get variations
            if ptype == "variable":
                var_rows = wp_db(
                    f"SELECT v.ID FROM wp_posts v "
                    f"WHERE v.post_parent = {pid} AND v.post_type = 'product_variation' "
                    f"ORDER BY v.ID"
                )
                variations = []
                if var_rows:
                    for vline in var_rows.strip().split("\n"):
                        vid = vline.strip()
                        if vid:
                            vprice = wp_db(
                                f"SELECT meta_value FROM wp_postmeta "
                                f"WHERE post_id={vid} AND meta_key='_regular_price'"
                            )
                            vsku = wp_db(
                                f"SELECT meta_value FROM wp_postmeta "
                                f"WHERE post_id={vid} AND meta_key='_sku'"
                            )
                            bag_size = wp_db(
                                f"SELECT meta_value FROM wp_postmeta "
                                f"WHERE post_id={vid} AND meta_key='attribute_pa_bag-size'"
                            )
                            variations.append({
                                "id": vid,
                                "price": vprice if vprice else "",
                                "sku": vsku if vsku else "",
                                "bag_size": bag_size if bag_size else ""
                            })
                product["variations"] = variations

            products.append(product)

result["products"] = products

# ================================================================
# 7. Shipping zones with methods and locations
# ================================================================
shipping_zones = []
zone_rows = wp_db("SELECT zone_id, zone_name FROM wp_woocommerce_shipping_zones")
if zone_rows:
    for line in zone_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 2:
            zone_id = parts[0]

            # Get methods for this zone
            method_rows = wp_db(
                f"SELECT instance_id, method_id, is_enabled "
                f"FROM wp_woocommerce_shipping_zone_methods "
                f"WHERE zone_id={zone_id}"
            )
            methods = []
            if method_rows:
                for mline in method_rows.strip().split("\n"):
                    mparts = mline.split("\t")
                    if len(mparts) >= 3:
                        instance_id = mparts[0]
                        method_type = mparts[1]
                        enabled = mparts[2]

                        # Get method settings from wp_options
                        settings_raw = wp_db(
                            f"SELECT option_value FROM wp_options "
                            f"WHERE option_name='woocommerce_{method_type}_{instance_id}_settings'"
                        )

                        method_info = {
                            "method_id": method_type,
                            "instance_id": instance_id,
                            "enabled": enabled,
                        }

                        # Parse key settings from PHP serialized data
                        if settings_raw:
                            if method_type == "flat_rate":
                                method_info["cost"] = parse_php_value(settings_raw, "cost")
                            elif method_type == "free_shipping":
                                method_info["requires"] = parse_php_value(settings_raw, "requires")
                                method_info["min_amount"] = parse_php_value(settings_raw, "min_amount")

                        methods.append(method_info)

            # Get locations for this zone
            loc_rows = wp_db(
                f"SELECT location_code, location_type "
                f"FROM wp_woocommerce_shipping_zone_locations "
                f"WHERE zone_id={zone_id}"
            )
            locations = []
            if loc_rows:
                for lline in loc_rows.strip().split("\n"):
                    lparts = lline.split("\t")
                    if len(lparts) >= 2:
                        locations.append({
                            "code": lparts[0],
                            "type": lparts[1]
                        })

            shipping_zones.append({
                "zone_id": zone_id,
                "zone_name": parts[1],
                "methods": methods,
                "locations": locations
            })

result["shipping_zones"] = shipping_zones

# ================================================================
# 8. Coupons
# ================================================================
coupons = []
coupon_rows = wp_db(
    "SELECT p.ID, p.post_title, p.post_status "
    "FROM wp_posts p "
    "WHERE p.post_type = 'shop_coupon' "
    "ORDER BY p.ID"
)
if coupon_rows:
    for line in coupon_rows.strip().split("\n"):
        parts = line.split("\t")
        if len(parts) >= 3:
            cid = parts[0]
            discount_type = wp_db(
                f"SELECT meta_value FROM wp_postmeta WHERE post_id={cid} AND meta_key='discount_type'"
            )
            amount = wp_db(
                f"SELECT meta_value FROM wp_postmeta WHERE post_id={cid} AND meta_key='coupon_amount'"
            )
            usage_limit = wp_db(
                f"SELECT meta_value FROM wp_postmeta WHERE post_id={cid} AND meta_key='usage_limit'"
            )
            date_expires = wp_db(
                f"SELECT meta_value FROM wp_postmeta WHERE post_id={cid} AND meta_key='date_expires'"
            )
            coupons.append({
                "id": cid,
                "code": parts[1],
                "status": parts[2],
                "discount_type": discount_type if discount_type else "",
                "amount": amount if amount else "",
                "usage_limit": usage_limit if usage_limit else "",
                "date_expires": date_expires if date_expires else ""
            })

result["coupons"] = coupons

# ================================================================
# Timestamp
# ================================================================
result["timestamp"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")

# ================================================================
# Write result
# ================================================================
output_path = "/tmp/launch_woocommerce_coffee_roastery_result.json"
with open(output_path, "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2))
PYEOF

python3 /tmp/export_store_data.py

chmod 666 /tmp/launch_woocommerce_coffee_roastery_result.json 2>/dev/null || \
    sudo chmod 666 /tmp/launch_woocommerce_coffee_roastery_result.json 2>/dev/null || true

echo ""
echo "Result saved to /tmp/launch_woocommerce_coffee_roastery_result.json"
echo "=== Export complete ==="
