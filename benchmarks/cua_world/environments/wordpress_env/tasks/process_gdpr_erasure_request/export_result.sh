#!/bin/bash
# Export script for process_gdpr_erasure_request task

echo "=== Exporting process_gdpr_erasure_request result ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# 1. Check Export Zip
EXPORT_EXISTS="false"
EXPORT_VALID="false"
ZIP_PATH="/home/ga/legal_holds/alex_rebel_export.zip"

if [ -f "$ZIP_PATH" ]; then
    EXPORT_EXISTS="true"
    echo "Export zip found at expected location."
    
    # Check if the zip contains WordPress export data with the user's email
    if unzip -p "$ZIP_PATH" 2>/dev/null | grep -qi "alex.rebel@example.com"; then
        EXPORT_VALID="true"
        echo "Export zip content validated."
    else
        echo "WARNING: Export zip does not contain valid data for the target user."
    fi
else
    echo "Export zip NOT found at $ZIP_PATH."
fi

# 2. Check User Deletion
USER_COUNT=$(wp_db_query "SELECT COUNT(*) FROM wp_users WHERE user_login='alex_rebel'")
USER_DELETED="false"
if [ "$USER_COUNT" -eq "0" ]; then
    USER_DELETED="true"
    echo "User 'alex_rebel' successfully deleted."
else
    echo "User 'alex_rebel' still exists."
fi

# 3. Check Post Reassignment
POSTS_EXIST="true"
POSTS_REASSIGNED="true"

for PID in $(cat /tmp/alex_post_1) $(cat /tmp/alex_post_2) $(cat /tmp/alex_post_3); do
    AUTHOR=$(wp_db_query "SELECT post_author FROM wp_posts WHERE ID=$PID")
    if [ -z "$AUTHOR" ]; then
        POSTS_EXIST="false"
        POSTS_REASSIGNED="false"
        echo "Post $PID was deleted!"
    elif [ "$AUTHOR" != "1" ]; then
        POSTS_REASSIGNED="false"
        echo "Post $PID was not reassigned to admin (Current author: $AUTHOR)."
    fi
done

if [ "$POSTS_REASSIGNED" = "true" ]; then
    echo "Posts successfully reassigned to admin."
fi

# 4. Check Comment Anonymization
COMMENTS_ANONYMIZED="true"

for CID in $(cat /tmp/alex_comment_1) $(cat /tmp/alex_comment_2) $(cat /tmp/alex_comment_3); do
    C_AUTHOR=$(wp_db_query "SELECT comment_author FROM wp_comments WHERE comment_ID=$CID")
    C_EMAIL=$(wp_db_query "SELECT comment_author_email FROM wp_comments WHERE comment_ID=$CID")
    
    if [ "$C_AUTHOR" != "Anonymous" ] || [ "$C_EMAIL" != "" ]; then
        COMMENTS_ANONYMIZED="false"
        echo "Comment $CID was not fully anonymized (Author: '$C_AUTHOR', Email: '$C_EMAIL')."
    fi
done

if [ "$COMMENTS_ANONYMIZED" = "true" ]; then
    echo "Comments successfully anonymized."
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/gdpr_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "export_exists": $EXPORT_EXISTS,
    "export_valid": $EXPORT_VALID,
    "user_deleted": $USER_DELETED,
    "posts_exist": $POSTS_EXIST,
    "posts_reassigned": $POSTS_REASSIGNED,
    "comments_anonymized": $COMMENTS_ANONYMIZED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Safely move json to accessible location
rm -f /tmp/gdpr_task_result.json 2>/dev/null || sudo rm -f /tmp/gdpr_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/gdpr_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/gdpr_task_result.json
chmod 666 /tmp/gdpr_task_result.json 2>/dev/null || sudo chmod 666 /tmp/gdpr_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo ""
echo "Result saved to /tmp/gdpr_task_result.json"
cat /tmp/gdpr_task_result.json
echo ""
echo "=== Export complete ==="