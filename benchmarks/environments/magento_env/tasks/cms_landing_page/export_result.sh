#!/bin/bash
# Export script for CMS Landing Page task

echo "=== Exporting CMS Landing Page Result ==="

source /workspace/scripts/task_utils.sh
take_screenshot /tmp/task_end_screenshot.png

INITIAL_BLOCK_COUNT=$(cat /tmp/initial_cms_block_count 2>/dev/null || echo "0")
INITIAL_PAGE_COUNT=$(cat /tmp/initial_cms_page_count 2>/dev/null || echo "0")

# ── Find the static block by identifier ──────────────────────────────────────
BLOCK_DATA=$(magento_query "SELECT block_id, title, identifier, is_active, CHAR_LENGTH(content) FROM cms_block WHERE LOWER(TRIM(identifier))='autumn-collection-featured' ORDER BY block_id DESC LIMIT 1" 2>/dev/null | tail -1)

BLOCK_ID=$(echo "$BLOCK_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
BLOCK_TITLE=$(echo "$BLOCK_DATA" | awk -F'\t' '{print $2}')
BLOCK_IDENTIFIER=$(echo "$BLOCK_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
BLOCK_ACTIVE=$(echo "$BLOCK_DATA" | awk -F'\t' '{print $4}' | tr -d '[:space:]')
BLOCK_CONTENT_LEN=$(echo "$BLOCK_DATA" | awk -F'\t' '{print $5}' | tr -d '[:space:]')

BLOCK_FOUND="false"
[ -n "$BLOCK_ID" ] && BLOCK_FOUND="true"
echo "Block: ID=$BLOCK_ID identifier=$BLOCK_IDENTIFIER active=$BLOCK_ACTIVE content_len=$BLOCK_CONTENT_LEN found=$BLOCK_FOUND"

# Check block content for HTML elements
BLOCK_HAS_HTML="false"
BLOCK_HAS_HEADING="false"
BLOCK_HAS_LIST="false"
if [ -n "$BLOCK_ID" ]; then
    BLOCK_CONTENT=$(magento_query "SELECT content FROM cms_block WHERE block_id=$BLOCK_ID" 2>/dev/null | tail -1 || echo "")

    if echo "$BLOCK_CONTENT" | grep -qi "<h[1-6]"; then
        BLOCK_HAS_HEADING="true"
    fi
    if echo "$BLOCK_CONTENT" | grep -qi "<ul\|<ol\|<li"; then
        BLOCK_HAS_LIST="true"
    fi
    if echo "$BLOCK_CONTENT" | grep -qi "<h[1-6]\|<p\|<div\|<span\|<ul\|<ol"; then
        BLOCK_HAS_HTML="true"
    fi
fi
echo "Block content checks: has_html=$BLOCK_HAS_HTML has_heading=$BLOCK_HAS_HEADING has_list=$BLOCK_HAS_LIST"

# ── Find the CMS page by identifier/url_key ───────────────────────────────────
PAGE_DATA=$(magento_query "SELECT page_id, title, identifier, meta_title, meta_description, meta_keywords, is_active, CHAR_LENGTH(content) FROM cms_page WHERE LOWER(TRIM(identifier))='autumn-collection-2024' ORDER BY page_id DESC LIMIT 1" 2>/dev/null | tail -1)

PAGE_ID=$(echo "$PAGE_DATA" | awk -F'\t' '{print $1}' | tr -d '[:space:]')
PAGE_TITLE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $2}')
PAGE_IDENTIFIER=$(echo "$PAGE_DATA" | awk -F'\t' '{print $3}' | tr -d '[:space:]')
PAGE_META_TITLE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $4}')
PAGE_META_DESC=$(echo "$PAGE_DATA" | awk -F'\t' '{print $5}')
PAGE_META_KEYWORDS=$(echo "$PAGE_DATA" | awk -F'\t' '{print $6}')
PAGE_ACTIVE=$(echo "$PAGE_DATA" | awk -F'\t' '{print $7}' | tr -d '[:space:]')
PAGE_CONTENT_LEN=$(echo "$PAGE_DATA" | awk -F'\t' '{print $8}' | tr -d '[:space:]')

PAGE_FOUND="false"
[ -n "$PAGE_ID" ] && PAGE_FOUND="true"
echo "Page: ID=$PAGE_ID identifier=$PAGE_IDENTIFIER active=$PAGE_ACTIVE content_len=$PAGE_CONTENT_LEN found=$PAGE_FOUND"

# Check page content for block directive
PAGE_HAS_BLOCK_DIRECTIVE="false"
PAGE_REFERENCES_CORRECT_BLOCK="false"
if [ -n "$PAGE_ID" ]; then
    PAGE_CONTENT=$(magento_query "SELECT content FROM cms_page WHERE page_id=$PAGE_ID" 2>/dev/null | tail -1 || echo "")

    if echo "$PAGE_CONTENT" | grep -qi "{{block"; then
        PAGE_HAS_BLOCK_DIRECTIVE="true"
    fi
    if echo "$PAGE_CONTENT" | grep -qi "autumn-collection-featured"; then
        PAGE_REFERENCES_CORRECT_BLOCK="true"
    fi
fi
echo "Page directives: has_block_directive=$PAGE_HAS_BLOCK_DIRECTIVE refs_correct_block=$PAGE_REFERENCES_CORRECT_BLOCK"

# Check meta title contains key phrase
PAGE_META_TITLE_OK="false"
if echo "$PAGE_META_TITLE" | grep -qi "autumn collection 2024"; then
    PAGE_META_TITLE_OK="true"
fi

# Check meta description contains key phrase
PAGE_META_DESC_OK="false"
if echo "$PAGE_META_DESC" | grep -qi "autumn 2024\|autumn collection"; then
    PAGE_META_DESC_OK="true"
fi

# Escape for JSON
BLOCK_TITLE_ESC=$(echo "$BLOCK_TITLE" | sed 's/"/\\"/g')
PAGE_TITLE_ESC=$(echo "$PAGE_TITLE" | sed 's/"/\\"/g')
PAGE_META_TITLE_ESC=$(echo "$PAGE_META_TITLE" | sed 's/"/\\"/g')
PAGE_META_DESC_ESC=$(echo "$PAGE_META_DESC" | sed 's/"/\\"/g' | head -c 200)

TEMP_JSON=$(mktemp /tmp/cms_landing_page_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "initial_block_count": ${INITIAL_BLOCK_COUNT:-0},
    "initial_page_count": ${INITIAL_PAGE_COUNT:-0},
    "block_found": $BLOCK_FOUND,
    "block_id": "${BLOCK_ID:-}",
    "block_title": "$BLOCK_TITLE_ESC",
    "block_identifier": "${BLOCK_IDENTIFIER:-}",
    "block_is_active": "${BLOCK_ACTIVE:-0}",
    "block_content_length": ${BLOCK_CONTENT_LEN:-0},
    "block_has_html": $BLOCK_HAS_HTML,
    "block_has_heading": $BLOCK_HAS_HEADING,
    "block_has_list": $BLOCK_HAS_LIST,
    "page_found": $PAGE_FOUND,
    "page_id": "${PAGE_ID:-}",
    "page_title": "$PAGE_TITLE_ESC",
    "page_identifier": "${PAGE_IDENTIFIER:-}",
    "page_meta_title": "$PAGE_META_TITLE_ESC",
    "page_meta_description": "$PAGE_META_DESC_ESC",
    "page_is_active": "${PAGE_ACTIVE:-0}",
    "page_content_length": ${PAGE_CONTENT_LEN:-0},
    "page_meta_title_ok": $PAGE_META_TITLE_OK,
    "page_meta_desc_ok": $PAGE_META_DESC_OK,
    "page_has_block_directive": $PAGE_HAS_BLOCK_DIRECTIVE,
    "page_references_correct_block": $PAGE_REFERENCES_CORRECT_BLOCK,
    "export_timestamp": "$(date -Iseconds)"
}
EOF

safe_write_json "$TEMP_JSON" /tmp/cms_landing_page_result.json
echo ""
cat /tmp/cms_landing_page_result.json
echo ""
echo "=== Export Complete ==="
