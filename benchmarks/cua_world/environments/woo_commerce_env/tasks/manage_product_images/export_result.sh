#!/bin/bash
# Export script for Manage Product Images task

echo "=== Exporting Manage Product Images Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record export time
EXPORT_TIME=$(date +%s)
START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Verify database connectivity
if ! check_db_connection; then
    echo '{"error": "database_unreachable"}' > /tmp/task_result.json
    exit 1
fi

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# 1. Get Product Data
echo "Fetching product data..."
PRODUCT_INFO=$(wc_query "SELECT p.ID, p.post_modified, p.post_status 
    FROM wp_posts p 
    JOIN wp_postmeta pm ON p.ID = pm.post_id 
    WHERE pm.meta_key='_sku' AND pm.meta_value='WBH-001' LIMIT 1")

PRODUCT_FOUND="false"
PRODUCT_ID=""
POST_MODIFIED=""
POST_STATUS=""
MAIN_IMAGE_ID=""
GALLERY_IDS=""
MAIN_IMAGE_FILE=""
GALLERY_FILES_JSON="[]"

if [ -n "$PRODUCT_INFO" ]; then
    PRODUCT_FOUND="true"
    PRODUCT_ID=$(echo "$PRODUCT_INFO" | cut -f1)
    POST_MODIFIED=$(echo "$PRODUCT_INFO" | cut -f2)
    POST_STATUS=$(echo "$PRODUCT_INFO" | cut -f3)

    # 2. Get Main Image ID (_thumbnail_id)
    MAIN_IMAGE_ID=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_thumbnail_id' LIMIT 1")

    # 3. Get Gallery IDs (_product_image_gallery)
    GALLERY_IDS=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$PRODUCT_ID AND meta_key='_product_image_gallery' LIMIT 1")

    # 4. Resolve Main Image Filename
    if [ -n "$MAIN_IMAGE_ID" ]; then
        MAIN_IMAGE_FILE=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$MAIN_IMAGE_ID AND meta_key='_wp_attached_file' LIMIT 1")
        # Extract just the filename from path (e.g., "2023/10/image.jpg" -> "image.jpg")
        MAIN_IMAGE_FILE=$(basename "$MAIN_IMAGE_FILE")
    fi

    # 5. Resolve Gallery Filenames
    if [ -n "$GALLERY_IDS" ]; then
        # GALLERY_IDS is comma separated (e.g., "102,103")
        # We need to loop or use IN clause. Using simple loop for bash safety.
        IFS=',' read -ra ADDR <<< "$GALLERY_IDS"
        
        GALLERY_FILES_JSON="["
        FIRST=true
        for img_id in "${ADDR[@]}"; do
            [ -z "$img_id" ] && continue
            
            f_path=$(wc_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$img_id AND meta_key='_wp_attached_file' LIMIT 1")
            f_name=$(basename "$f_path")
            f_date=$(wc_query "SELECT post_date FROM wp_posts WHERE ID=$img_id LIMIT 1")
            
            # Convert DB date to timestamp
            f_ts=$(date -d "$f_date" +%s 2>/dev/null || echo "0")
            
            if [ "$FIRST" = true ]; then
                FIRST=false
            else
                GALLERY_FILES_JSON="$GALLERY_FILES_JSON,"
            fi
            GALLERY_FILES_JSON="$GALLERY_FILES_JSON {\"id\": \"$img_id\", \"filename\": \"$f_name\", \"timestamp\": $f_ts}"
        done
        GALLERY_FILES_JSON="$GALLERY_FILES_JSON]"
    fi
fi

# Convert product modified time to timestamp for comparison
MODIFIED_TS=$(date -d "$POST_MODIFIED" +%s 2>/dev/null || echo "0")

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/img_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $START_TIME,
    "product_found": $PRODUCT_FOUND,
    "product_id": "$PRODUCT_ID",
    "product_status": "$POST_STATUS",
    "last_modified_timestamp": $MODIFIED_TS,
    "main_image": {
        "id": "$MAIN_IMAGE_ID",
        "filename": "$MAIN_IMAGE_FILE"
    },
    "gallery_images": $GALLERY_FILES_JSON,
    "export_timestamp": $EXPORT_TIME
}
EOF

# Move to standard output location
safe_write_json "$TEMP_JSON" /tmp/task_result.json

echo "Export complete. Result:"
cat /tmp/task_result.json