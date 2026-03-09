#!/bin/bash
echo "=== Exporting create_sub_server result ==="

source /workspace/scripts/task_utils.sh

# 1. Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Gather Task Metrics
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)
INITIAL_COUNT=$(cat /tmp/initial_domain_count.txt 2>/dev/null || echo "0")
CURRENT_COUNT=$(virtualmin list-domains --name-only 2>/dev/null | wc -l)

# 3. Verify Domain State via CLI (Ground Truth)
DOMAIN="blog.greenwidgets.test"
DOMAIN_EXISTS="false"
PARENT_DOMAIN=""
FEATURES_WEB="false"
FEATURES_DNS="false"
FEATURES_MYSQL="false"
DESCRIPTION=""
DOC_ROOT_EXISTS="false"

if virtualmin_domain_exists "$DOMAIN"; then
    DOMAIN_EXISTS="true"
    
    # Get domain info
    INFO=$(virtualmin list-domains --domain "$DOMAIN" --multiline 2>/dev/null)
    
    # Check parent
    PARENT_DOMAIN=$(echo "$INFO" | grep -i "Parent domain:" | awk -F': ' '{print $2}' | xargs)
    
    # Check features
    if echo "$INFO" | grep -qi "Web virtual server: Yes"; then FEATURES_WEB="true"; fi
    if echo "$INFO" | grep -qi "DNS domain: Yes"; then FEATURES_DNS="true"; fi
    if echo "$INFO" | grep -qi "MySQL database: Yes"; then FEATURES_MYSQL="true"; fi
    
    # Check description
    DESCRIPTION=$(echo "$INFO" | grep -i "Description:" | awk -F': ' '{print $2}' | xargs)
    
    # Check Document Root
    DOC_ROOT=$(echo "$INFO" | grep -i "HTML directory:" | awk -F': ' '{print $2}' | xargs)
    if [ -n "$DOC_ROOT" ] && [ -d "$DOC_ROOT" ]; then
        DOC_ROOT_EXISTS="true"
    fi
fi

# 4. Check MySQL Database specifically (Double check)
MYSQL_DB_EXISTS="false"
# Sub-server DBs usually named like 'blog' or 'greenwidgets_blog'
if [ "$FEATURES_MYSQL" = "true" ]; then
    # List databases for this domain
    DBS=$(virtualmin list-databases --domain "$DOMAIN" --name-only 2>/dev/null)
    if [ -n "$DBS" ]; then
        MYSQL_DB_EXISTS="true"
    fi
fi

# 5. Create JSON Result
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "initial_domain_count": $INITIAL_COUNT,
    "current_domain_count": $CURRENT_COUNT,
    "domain_exists": $DOMAIN_EXISTS,
    "parent_domain": "$PARENT_DOMAIN",
    "features": {
        "web": $FEATURES_WEB,
        "dns": $FEATURES_DNS,
        "mysql": $FEATURES_MYSQL,
        "mysql_db_confirmed": $MYSQL_DB_EXISTS
    },
    "description": "$DESCRIPTION",
    "doc_root_exists": $DOC_ROOT_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export complete ==="
cat /tmp/task_result.json