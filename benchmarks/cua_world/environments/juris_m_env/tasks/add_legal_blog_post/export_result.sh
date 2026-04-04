#!/bin/bash
echo "=== Exporting add_legal_blog_post Result ==="
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Timestamps
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Find DB
JURISM_DB=$(get_jurism_db)
if [ -z "$JURISM_DB" ]; then
    echo "ERROR: Cannot find Jurism database"
    echo '{"error": "Jurism database not found", "passed": false}' > /tmp/add_legal_blog_post_result.json
    exit 1
fi

# 1. Check for Collection "Web Research"
COLL_ID=$(sqlite3 "$JURISM_DB" "SELECT collectionID FROM collections WHERE collectionName='Web Research' LIMIT 1" 2>/dev/null || echo "")
COLL_EXISTS="false"
if [ -n "$COLL_ID" ]; then
    COLL_EXISTS="true"
fi

# 2. Check for Item in that Collection
ITEM_ID=""
ITEM_EXISTS="false"
TITLE_MATCH="false"
AUTHOR_MATCH="false"
BLOG_MATCH="false"
DATE_MATCH="false"
URL_MATCH="false"
TAG_MATCH="false"
ITEM_TYPE=""
ACTUAL_TITLE=""
ACTUAL_URL=""

if [ "$COLL_EXISTS" = "true" ]; then
    # Get items in this collection
    # We look for the one that might be our blog post
    # Strategy: Find any item in this collection, then check its fields
    
    # Get list of itemIDs in collection (excluding notes/attachments)
    ITEM_IDS=$(sqlite3 "$JURISM_DB" "SELECT itemID FROM collectionItems WHERE collectionID=$COLL_ID AND itemID IN (SELECT itemID FROM items WHERE itemTypeID NOT IN (1,3,31))" 2>/dev/null)
    
    for iid in $ITEM_IDS; do
        # Check title (fieldID=1)
        VAL=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$iid AND fieldID=1 LIMIT 1" 2>/dev/null)
        if [[ "$VAL" == *"Court to decide"* ]] || [[ "$VAL" == *"testers"* ]]; then
            ITEM_ID="$iid"
            ITEM_EXISTS="true"
            ACTUAL_TITLE="$VAL"
            if [[ "$VAL" == *"Court to decide whether 'testers' have standing to sue under ADA"* ]]; then
                TITLE_MATCH="true"
            fi
            
            # Check Item Type (typename)
            TYPE_ID=$(sqlite3 "$JURISM_DB" "SELECT itemTypeID FROM items WHERE itemID=$iid" 2>/dev/null)
            ITEM_TYPE=$(sqlite3 "$JURISM_DB" "SELECT typeName FROM itemTypes WHERE itemTypeID=$TYPE_ID" 2>/dev/null)
            
            # Check Blog Title (Publication Title - fieldID=12 or 7 usually, let's check widely)
            # For blogPost, publicationTitle is usually fieldID 12 (publicationTitle) or 7 (publicationTitle generic)
            # We'll search fields for "SCOTUSblog"
            BLOG_VAL=$(sqlite3 "$JURISM_DB" "SELECT COUNT(*) FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$iid AND value='SCOTUSblog'" 2>/dev/null)
            if [ "$BLOG_VAL" -gt 0 ]; then BLOG_MATCH="true"; fi

            # Check Date (fieldID=8)
            DATE_VAL=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$iid AND fieldID=8 LIMIT 1" 2>/dev/null)
            if [[ "$DATE_VAL" == *"2023-03-27"* ]]; then DATE_MATCH="true"; fi

            # Check URL (fieldID=13)
            URL_VAL=$(sqlite3 "$JURISM_DB" "SELECT value FROM itemData JOIN itemDataValues ON itemData.valueID=itemDataValues.valueID WHERE itemID=$iid AND fieldID=13 LIMIT 1" 2>/dev/null)
            ACTUAL_URL="$URL_VAL"
            if [[ "$URL_VAL" == *"scotusblog.com/2023/03/court-to-decide"* ]]; then URL_MATCH="true"; fi

            # Check Author (Howe)
            AUTHOR_VAL=$(sqlite3 "$JURISM_DB" "SELECT lastName FROM creators JOIN itemCreators ON creators.creatorID=itemCreators.creatorID WHERE itemCreators.itemID=$iid AND lastName='Howe' LIMIT 1" 2>/dev/null)
            if [ -n "$AUTHOR_VAL" ]; then AUTHOR_MATCH="true"; fi
            
            # Check Tag
            TAG_VAL=$(sqlite3 "$JURISM_DB" "SELECT name FROM tags JOIN itemTags ON tags.tagID=itemTags.tagID WHERE itemTags.itemID=$iid AND name='standing' LIMIT 1" 2>/dev/null)
            if [ -n "$TAG_VAL" ]; then TAG_MATCH="true"; fi
            
            # Found the candidate, stop looking
            break
        fi
    done
fi

# Escape JSON strings
ACTUAL_TITLE_ESC=$(echo "$ACTUAL_TITLE" | sed 's/"/\\"/g')
ACTUAL_URL_ESC=$(echo "$ACTUAL_URL" | sed 's/"/\\"/g')

# Create JSON
cat > /tmp/add_legal_blog_post_result.json << EOF
{
    "task_start_timestamp": $TASK_START,
    "task_end_timestamp": $TASK_END,
    "collection_exists": $COLL_EXISTS,
    "item_exists_in_collection": $ITEM_EXISTS,
    "item_type": "$ITEM_TYPE",
    "title_match": $TITLE_MATCH,
    "actual_title": "$ACTUAL_TITLE_ESC",
    "author_match": $AUTHOR_MATCH,
    "blog_title_match": $BLOG_MATCH,
    "date_match": $DATE_MATCH,
    "url_match": $URL_MATCH,
    "actual_url": "$ACTUAL_URL_ESC",
    "tag_match": $TAG_MATCH,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/add_legal_blog_post_result.json 2>/dev/null || true
echo "Result saved to /tmp/add_legal_blog_post_result.json"
cat /tmp/add_legal_blog_post_result.json
echo "=== Export Complete ==="