#!/bin/bash
echo "=== Exporting Store Configuration and Multi-Order Fulfillment Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/store_config_multi_order_result.json
    exit 1
fi

take_screenshot /tmp/store_config_multi_order_end_screenshot.png

TASK_START=$(cat /tmp/store_config_multi_order_start_ts 2>/dev/null || echo "0")
INITIAL_ORDER_COUNT=$(cat /tmp/store_config_multi_order_initial_count 2>/dev/null || echo "0")
EXISTING_ORDER_IDS=$(cat /tmp/store_config_multi_order_existing_ids 2>/dev/null | tr -d '[:space:]')

# ================================================================
# Check COD payment method
# ================================================================
cd /var/www/html/wordpress 2>/dev/null || true
COD_SETTINGS=$(wp option get woocommerce_cod_settings --format=json --allow-root 2>/dev/null || echo "{}")
COD_ENABLED="false"
COD_TITLE=""
COD_DESCRIPTION=""

# Parse COD settings using Python for reliability
COD_INFO=$(python3 << 'PYEOF'
import json, sys
try:
    raw = sys.stdin.read()
    data = json.loads(raw)
    enabled = data.get("enabled", "no")
    title = data.get("title", "")
    desc = data.get("description", "")
    print(f"{enabled}\t{title}\t{desc}")
except:
    print("no\t\t")
PYEOF
<<< "$COD_SETTINGS")

COD_ENABLED_VAL=$(echo "$COD_INFO" | cut -f1)
COD_TITLE=$(echo "$COD_INFO" | cut -f2)
COD_DESCRIPTION=$(echo "$COD_INFO" | cut -f3)

[ "$COD_ENABLED_VAL" = "yes" ] && COD_ENABLED="true"

echo "COD: enabled=$COD_ENABLED, title=$COD_TITLE, desc=$COD_DESCRIPTION"

# ================================================================
# Check shipping class
# ================================================================
SHIPPING_CLASS_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_shipping_class' AND (LOWER(t.name)='oversized items' OR t.slug='oversized-items') LIMIT 1" 2>/dev/null)
SHIPPING_CLASS_EXISTS="false"
SHIPPING_CLASS_SLUG=""
SHIPPING_CLASS_DESC=""

if [ -n "$SHIPPING_CLASS_ID" ]; then
    SHIPPING_CLASS_EXISTS="true"
    SHIPPING_CLASS_SLUG=$(wc_query "SELECT t.slug FROM wp_terms t WHERE t.term_id=$SHIPPING_CLASS_ID LIMIT 1" 2>/dev/null)
    SHIPPING_CLASS_DESC=$(wc_query "SELECT tt.description FROM wp_term_taxonomy tt WHERE tt.term_id=$SHIPPING_CLASS_ID AND tt.taxonomy='product_shipping_class' LIMIT 1" 2>/dev/null)
fi

echo "Shipping class: exists=$SHIPPING_CLASS_EXISTS, slug=$SHIPPING_CLASS_SLUG"

# Check shipping class assignment to products
check_shipping_class() {
    local sku="$1"
    local class_id="$2"
    local product_id=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$sku' LIMIT 1" 2>/dev/null)
    if [ -z "$product_id" ] || [ -z "$class_id" ]; then
        echo "false"
        return
    fi
    local tt_id=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$class_id AND taxonomy='product_shipping_class' LIMIT 1" 2>/dev/null)
    if [ -z "$tt_id" ]; then
        echo "false"
        return
    fi
    local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$product_id AND term_taxonomy_id=$tt_id" 2>/dev/null)
    [ "$count" -gt 0 ] 2>/dev/null && echo "true" || echo "false"
}

PCH_HAS_CLASS=$(check_shipping_class "PCH-DUO" "$SHIPPING_CLASS_ID")
CPP_HAS_CLASS=$(check_shipping_class "CPP-SET3" "$SHIPPING_CLASS_ID")

echo "Shipping class assignments: PCH=$PCH_HAS_CLASS, CPP=$CPP_HAS_CLASS"

# ================================================================
# Check orders
# ================================================================
CURRENT_ORDER_COUNT=$(get_order_count 2>/dev/null || echo "0")

EXCLUDE_CLAUSE=""
if [ -n "$EXISTING_ORDER_IDS" ] && [ "$EXISTING_ORDER_IDS" != "NULL" ]; then
    EXCLUDE_CLAUSE="AND p.ID NOT IN ($EXISTING_ORDER_IDS)"
fi

# Function to find and extract order details
extract_order() {
    local customer_email="$1"
    local order_id=$(wc_query "SELECT p.ID
        FROM wp_posts p
        JOIN wp_postmeta pm ON p.ID = pm.post_id AND pm.meta_key = '_customer_user'
        JOIN wp_users u ON pm.meta_value = u.ID
        WHERE p.post_type = 'shop_order'
        AND p.post_status != 'auto-draft'
        AND LOWER(u.user_email) = LOWER('$customer_email')
        $EXCLUDE_CLAUSE
        ORDER BY p.ID DESC LIMIT 1" 2>/dev/null)

    if [ -z "$order_id" ]; then
        echo "|||||||[]"
        return
    fi

    local status=$(wc_query "SELECT post_status FROM wp_posts WHERE ID=$order_id" 2>/dev/null)
    local total=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$order_id AND meta_key='_order_total' LIMIT 1" 2>/dev/null)
    local cust_id=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$order_id AND meta_key='_customer_user' LIMIT 1" 2>/dev/null)
    local cust_email=$(wc_query "SELECT user_email FROM wp_users WHERE ID=$cust_id LIMIT 1" 2>/dev/null)

    # Get order note (most recent private note)
    local note=$(wc_query "SELECT comment_content FROM wp_comments WHERE comment_post_ID=$order_id AND comment_type='order_note' AND comment_agent='system' ORDER BY comment_ID DESC LIMIT 1" 2>/dev/null)
    # Fallback: any order note
    if [ -z "$note" ]; then
        note=$(wc_query "SELECT comment_content FROM wp_comments WHERE comment_post_ID=$order_id AND comment_type='order_note' ORDER BY comment_ID DESC LIMIT 1" 2>/dev/null)
    fi

    # Get line items
    local items_json="["
    local first=true
    local items_raw=$(wc_query "SELECT oi.order_item_name,
        MAX(CASE WHEN oim.meta_key='_qty' THEN oim.meta_value END) as qty,
        MAX(CASE WHEN oim.meta_key='_product_id' THEN oim.meta_value END) as pid
        FROM wp_woocommerce_order_items oi
        JOIN wp_woocommerce_order_itemmeta oim ON oi.order_item_id = oim.order_item_id
        WHERE oi.order_id=$order_id AND oi.order_item_type='line_item'
        GROUP BY oi.order_item_id" 2>/dev/null)

    while IFS=$'\t' read -r iname iqty ipid; do
        [ -z "$iname" ] && continue
        local isku=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$ipid AND meta_key='_sku' LIMIT 1" 2>/dev/null)
        local iname_esc=$(json_escape "$iname")
        if [ "$first" = true ]; then first=false; else items_json="$items_json,"; fi
        items_json="$items_json{\"name\":\"$iname_esc\",\"quantity\":\"$iqty\",\"sku\":\"$isku\"}"
    done <<< "$items_raw"
    items_json="$items_json]"

    local note_esc=$(json_escape "$note")
    local cust_email_esc=$(json_escape "$cust_email")

    echo "$order_id|$status|$total|$cust_email_esc|$note_esc|$items_json"
}

# Extract Order A (Mike Wilson)
ORDER_A_RAW=$(extract_order "mike.wilson@example.com")
ORDER_A_ID=$(echo "$ORDER_A_RAW" | cut -d'|' -f1)
ORDER_A_STATUS=$(echo "$ORDER_A_RAW" | cut -d'|' -f2)
ORDER_A_TOTAL=$(echo "$ORDER_A_RAW" | cut -d'|' -f3)
ORDER_A_EMAIL=$(echo "$ORDER_A_RAW" | cut -d'|' -f4)
ORDER_A_NOTE=$(echo "$ORDER_A_RAW" | cut -d'|' -f5)
ORDER_A_ITEMS=$(echo "$ORDER_A_RAW" | cut -d'|' -f6)

ORDER_A_FOUND="false"
[ -n "$ORDER_A_ID" ] && ORDER_A_FOUND="true"

# Extract Order B (John Doe)
ORDER_B_RAW=$(extract_order "john.doe@example.com")
ORDER_B_ID=$(echo "$ORDER_B_RAW" | cut -d'|' -f1)
ORDER_B_STATUS=$(echo "$ORDER_B_RAW" | cut -d'|' -f2)
ORDER_B_TOTAL=$(echo "$ORDER_B_RAW" | cut -d'|' -f3)
ORDER_B_EMAIL=$(echo "$ORDER_B_RAW" | cut -d'|' -f4)
ORDER_B_NOTE=$(echo "$ORDER_B_RAW" | cut -d'|' -f5)
ORDER_B_ITEMS=$(echo "$ORDER_B_RAW" | cut -d'|' -f6)

ORDER_B_FOUND="false"
[ -n "$ORDER_B_ID" ] && ORDER_B_FOUND="true"

echo "Order A: ID=$ORDER_A_ID, Status=$ORDER_A_STATUS, Customer=$ORDER_A_EMAIL"
echo "Order B: ID=$ORDER_B_ID, Status=$ORDER_B_STATUS, Customer=$ORDER_B_EMAIL"

COD_TITLE_ESC=$(json_escape "$COD_TITLE")
COD_DESCRIPTION_ESC=$(json_escape "$COD_DESCRIPTION")
SHIPPING_CLASS_DESC_ESC=$(json_escape "$SHIPPING_CLASS_DESC")

TEMP_JSON=$(mktemp /tmp/store_config_multi_order_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "initial_order_count": $INITIAL_ORDER_COUNT,
    "current_order_count": $CURRENT_ORDER_COUNT,
    "cod": {
        "enabled": $COD_ENABLED,
        "title": "$COD_TITLE_ESC",
        "description": "$COD_DESCRIPTION_ESC"
    },
    "shipping_class": {
        "exists": $SHIPPING_CLASS_EXISTS,
        "slug": "$SHIPPING_CLASS_SLUG",
        "description": "$SHIPPING_CLASS_DESC_ESC",
        "pch_assigned": $PCH_HAS_CLASS,
        "cpp_assigned": $CPP_HAS_CLASS
    },
    "order_a": {
        "found": $ORDER_A_FOUND,
        "id": "$ORDER_A_ID",
        "status": "$ORDER_A_STATUS",
        "total": "$ORDER_A_TOTAL",
        "customer_email": "$ORDER_A_EMAIL",
        "note": "$ORDER_A_NOTE",
        "line_items": ${ORDER_A_ITEMS:-[]}
    },
    "order_b": {
        "found": $ORDER_B_FOUND,
        "id": "$ORDER_B_ID",
        "status": "$ORDER_B_STATUS",
        "total": "$ORDER_B_TOTAL",
        "customer_email": "$ORDER_B_EMAIL",
        "note": "$ORDER_B_NOTE",
        "line_items": ${ORDER_B_ITEMS:-[]}
    },
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/store_config_multi_order_result.json

echo ""
cat /tmp/store_config_multi_order_result.json
echo ""
echo "=== Export Complete ==="
