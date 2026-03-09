#!/bin/bash
echo "=== Exporting Product Catalog Reorganization Result ==="

source /workspace/scripts/task_utils.sh

if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/product_catalog_reorg_result.json
    exit 1
fi

take_screenshot /tmp/product_catalog_reorg_end_screenshot.png

TASK_START=$(cat /tmp/product_catalog_reorg_start_ts 2>/dev/null || echo "0")

# ================================================================
# Check parent category 'Outdoor & Recreation'
# ================================================================
PARENT_CAT_ID=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)='outdoor & recreation' LIMIT 1" 2>/dev/null)
PARENT_CAT_EXISTS="false"
[ -n "$PARENT_CAT_ID" ] && PARENT_CAT_EXISTS="true"

# ================================================================
# Check subcategories
# ================================================================
check_subcategory() {
    local cat_name="$1"
    local parent_id="$2"
    local cat_id=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_cat' AND LOWER(t.name)=LOWER('$cat_name') LIMIT 1" 2>/dev/null)

    if [ -z "$cat_id" ]; then
        echo "NOT_FOUND||"
        return
    fi

    # Check if parent is correct
    local actual_parent=$(wc_query "SELECT tt.parent FROM wp_term_taxonomy tt WHERE tt.term_id=$cat_id AND tt.taxonomy='product_cat' LIMIT 1" 2>/dev/null)
    local parent_term_id=""
    if [ -n "$parent_id" ]; then
        parent_term_id=$(wc_query "SELECT tt.term_taxonomy_id FROM wp_term_taxonomy tt WHERE tt.term_id=$parent_id AND tt.taxonomy='product_cat' LIMIT 1" 2>/dev/null)
    fi

    # WooCommerce uses term_id as parent in wp_term_taxonomy
    local is_child="false"
    if [ -n "$actual_parent" ] && [ -n "$parent_id" ] && [ "$actual_parent" = "$parent_id" ]; then
        is_child="true"
    fi

    echo "$cat_id|$is_child|$actual_parent"
}

CAMPING_RESULT=$(check_subcategory "Camping Gear" "$PARENT_CAT_ID")
CAMPING_ID=$(echo "$CAMPING_RESULT" | cut -d'|' -f1)
CAMPING_IS_CHILD=$(echo "$CAMPING_RESULT" | cut -d'|' -f2)
[ -z "$CAMPING_IS_CHILD" ] && CAMPING_IS_CHILD="false"

FITNESS_RESULT=$(check_subcategory "Fitness Equipment" "$PARENT_CAT_ID")
FITNESS_ID=$(echo "$FITNESS_RESULT" | cut -d'|' -f1)
FITNESS_IS_CHILD=$(echo "$FITNESS_RESULT" | cut -d'|' -f2)
[ -z "$FITNESS_IS_CHILD" ] && FITNESS_IS_CHILD="false"

CAMPING_EXISTS="false"
[ -n "$CAMPING_ID" ] && [ "$CAMPING_ID" != "NOT_FOUND" ] && CAMPING_EXISTS="true"
FITNESS_EXISTS="false"
[ -n "$FITNESS_ID" ] && [ "$FITNESS_ID" != "NOT_FOUND" ] && FITNESS_EXISTS="true"

echo "Categories: parent=$PARENT_CAT_ID, camping=$CAMPING_ID (child=$CAMPING_IS_CHILD), fitness=$FITNESS_ID (child=$FITNESS_IS_CHILD)"

# ================================================================
# Check product category assignments
# ================================================================
check_product_in_category() {
    local sku="$1"
    local cat_id="$2"
    local product_id=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$sku' LIMIT 1" 2>/dev/null)
    if [ -z "$product_id" ] || [ -z "$cat_id" ] || [ "$cat_id" = "NOT_FOUND" ]; then
        echo "false"
        return
    fi
    local tt_id=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$cat_id AND taxonomy='product_cat' LIMIT 1" 2>/dev/null)
    if [ -z "$tt_id" ]; then
        echo "false"
        return
    fi
    local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$product_id AND term_taxonomy_id=$tt_id" 2>/dev/null)
    [ "$count" -gt 0 ] 2>/dev/null && echo "true" || echo "false"
}

PCH_IN_CAMPING=$(check_product_in_category "PCH-DUO" "$CAMPING_ID")
YMP_IN_FITNESS=$(check_product_in_category "YMP-001" "$FITNESS_ID")
RBS_IN_FITNESS=$(check_product_in_category "RBS-005" "$FITNESS_ID")

echo "Assignments: PCH in Camping=$PCH_IN_CAMPING, YMP in Fitness=$YMP_IN_FITNESS, RBS in Fitness=$RBS_IN_FITNESS"

# ================================================================
# Check tags
# ================================================================
check_tag_on_product() {
    local tag_name="$1"
    local sku="$2"
    local product_id=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$sku' LIMIT 1" 2>/dev/null)
    local tag_id=$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_tag' AND LOWER(t.name)=LOWER('$tag_name') LIMIT 1" 2>/dev/null)
    if [ -z "$product_id" ] || [ -z "$tag_id" ]; then
        echo "false"
        return
    fi
    local tt_id=$(wc_query "SELECT term_taxonomy_id FROM wp_term_taxonomy WHERE term_id=$tag_id AND taxonomy='product_tag' LIMIT 1" 2>/dev/null)
    if [ -z "$tt_id" ]; then
        echo "false"
        return
    fi
    local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$product_id AND term_taxonomy_id=$tt_id" 2>/dev/null)
    [ "$count" -gt 0 ] 2>/dev/null && echo "true" || echo "false"
}

# Check tag existence
BESTSELLER_EXISTS="false"
ECOFRIENDLY_EXISTS="false"
GIFTIDEA_EXISTS="false"
[ -n "$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_tag' AND LOWER(t.name)='bestseller' LIMIT 1" 2>/dev/null)" ] && BESTSELLER_EXISTS="true"
[ -n "$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_tag' AND LOWER(t.name)='eco-friendly' LIMIT 1" 2>/dev/null)" ] && ECOFRIENDLY_EXISTS="true"
[ -n "$(wc_query "SELECT t.term_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='product_tag' AND LOWER(t.name)='gift-idea' LIMIT 1" 2>/dev/null)" ] && GIFTIDEA_EXISTS="true"

# Check tag assignments
BS_WBH=$(check_tag_on_product "bestseller" "WBH-001")
BS_YMP=$(check_tag_on_product "bestseller" "YMP-001")
EF_OCT=$(check_tag_on_product "eco-friendly" "OCT-BLK-M")
EF_BCB=$(check_tag_on_product "eco-friendly" "BCB-SET2")
GI_LED=$(check_tag_on_product "gift-idea" "LED-DL-01")
GI_CPP=$(check_tag_on_product "gift-idea" "CPP-SET3")

echo "Tags: bestseller=$BESTSELLER_EXISTS, eco-friendly=$ECOFRIENDLY_EXISTS, gift-idea=$GIFTIDEA_EXISTS"
echo "Tag assignments: bs-wbh=$BS_WBH, bs-ymp=$BS_YMP, ef-oct=$EF_OCT, ef-bcb=$EF_BCB, gi-led=$GI_LED, gi-cpp=$GI_CPP"

# ================================================================
# Check featured products
# ================================================================
check_featured() {
    local sku="$1"
    local product_id=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='$sku' LIMIT 1" 2>/dev/null)
    if [ -z "$product_id" ]; then
        echo "false"
        return
    fi
    local featured_tt=$(wc_query "SELECT tt.term_taxonomy_id FROM wp_terms t JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE t.slug='featured' AND tt.taxonomy='product_visibility' LIMIT 1" 2>/dev/null)
    if [ -z "$featured_tt" ]; then
        echo "false"
        return
    fi
    local count=$(wc_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$product_id AND term_taxonomy_id=$featured_tt" 2>/dev/null)
    [ "$count" -gt 0 ] 2>/dev/null && echo "true" || echo "false"
}

WBH_FEATURED=$(check_featured "WBH-001")
YMP_FEATURED=$(check_featured "YMP-001")

echo "Featured: WBH=$WBH_FEATURED, YMP=$YMP_FEATURED"

# ================================================================
# Check short description
# ================================================================
PCH_PRODUCT_ID=$(wc_query "SELECT post_id FROM wp_postmeta WHERE meta_key='_sku' AND meta_value='PCH-DUO' LIMIT 1" 2>/dev/null)
PCH_SHORT_DESC=""
if [ -n "$PCH_PRODUCT_ID" ]; then
    PCH_SHORT_DESC=$(wc_query "SELECT post_excerpt FROM wp_posts WHERE ID=$PCH_PRODUCT_ID LIMIT 1" 2>/dev/null)
fi

PCH_SHORT_DESC_ESC=$(json_escape "$PCH_SHORT_DESC")
echo "PCH short description: $PCH_SHORT_DESC"

# ================================================================
# Write result JSON
# ================================================================
TEMP_JSON=$(mktemp /tmp/product_catalog_reorg_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "parent_category_exists": $PARENT_CAT_EXISTS,
    "parent_category_id": "$PARENT_CAT_ID",
    "camping_gear": {
        "exists": $CAMPING_EXISTS,
        "id": "$CAMPING_ID",
        "is_child_of_parent": $CAMPING_IS_CHILD
    },
    "fitness_equipment": {
        "exists": $FITNESS_EXISTS,
        "id": "$FITNESS_ID",
        "is_child_of_parent": $FITNESS_IS_CHILD
    },
    "category_assignments": {
        "pch_in_camping": $PCH_IN_CAMPING,
        "ymp_in_fitness": $YMP_IN_FITNESS,
        "rbs_in_fitness": $RBS_IN_FITNESS
    },
    "tags": {
        "bestseller_exists": $BESTSELLER_EXISTS,
        "ecofriendly_exists": $ECOFRIENDLY_EXISTS,
        "giftidea_exists": $GIFTIDEA_EXISTS
    },
    "tag_assignments": {
        "bestseller_wbh": $BS_WBH,
        "bestseller_ymp": $BS_YMP,
        "ecofriendly_oct": $EF_OCT,
        "ecofriendly_bcb": $EF_BCB,
        "giftidea_led": $GI_LED,
        "giftidea_cpp": $GI_CPP
    },
    "featured": {
        "wbh_featured": $WBH_FEATURED,
        "ymp_featured": $YMP_FEATURED
    },
    "short_description": "$PCH_SHORT_DESC_ESC",
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/product_catalog_reorg_result.json

echo ""
cat /tmp/product_catalog_reorg_result.json
echo ""
echo "=== Export Complete ==="
