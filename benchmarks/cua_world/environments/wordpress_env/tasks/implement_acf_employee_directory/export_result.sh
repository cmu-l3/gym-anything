#!/bin/bash
# Export script for implement_acf_employee_directory task

echo "=== Exporting ACF Employee Directory Result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# 1. Check if ACF plugin is active
ACF_ACTIVE="false"
if wp plugin is-active advanced-custom-fields --allow-root 2>/dev/null; then
    ACF_ACTIVE="true"
fi
echo "ACF Active: $ACF_ACTIVE"

# 2. Extract Team Category ID
TEAM_CAT_ID=$(wp_db_query "SELECT t.term_id FROM wp_terms t INNER JOIN wp_term_taxonomy tt ON t.term_id = tt.term_id WHERE tt.taxonomy='category' AND LOWER(TRIM(t.name)) = 'team' LIMIT 1" 2>/dev/null)

# Helper function to get post data
get_employee_data() {
    local emp_name="$1"
    
    local exists="false"
    local in_category="false"
    local job_title=""
    local department=""
    local office_extension=""
    local acf_hidden_job=""
    local acf_hidden_dept=""
    local acf_hidden_ext=""
    
    # Find published post
    local post_id=$(wp_db_query "SELECT ID FROM wp_posts WHERE LOWER(TRIM(post_title)) = LOWER(TRIM('$emp_name')) AND post_type='post' AND post_status='publish' ORDER BY ID DESC LIMIT 1" 2>/dev/null)
    
    if [ -n "$post_id" ]; then
        exists="true"
        
        # Check category
        if [ -n "$TEAM_CAT_ID" ]; then
            local cat_check=$(wp_db_query "SELECT COUNT(*) FROM wp_term_relationships WHERE object_id=$post_id AND term_taxonomy_id=$TEAM_CAT_ID" 2>/dev/null)
            if [ "$cat_check" -gt 0 ]; then
                in_category="true"
            fi
        fi
        
        # Get standard meta values (what the user typed)
        job_title=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='job_title' LIMIT 1" 2>/dev/null)
        department=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='department' LIMIT 1" 2>/dev/null)
        office_extension=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='office_extension' LIMIT 1" 2>/dev/null)
        
        # Get hidden ACF reference keys (starts with underscore). ACF uses these to map values to field objects.
        # This proves the data was saved via ACF UI and not native WP custom fields.
        acf_hidden_job=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_job_title' LIMIT 1" 2>/dev/null)
        acf_hidden_dept=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_department' LIMIT 1" 2>/dev/null)
        acf_hidden_ext=$(wp_db_query "SELECT meta_value FROM wp_postmeta WHERE post_id=$post_id AND meta_key='_office_extension' LIMIT 1" 2>/dev/null)
    fi
    
    # Safe escape for JSON
    job_title=$(json_escape "$job_title")
    department=$(json_escape "$department")
    office_extension=$(json_escape "$office_extension")
    acf_hidden_job=$(json_escape "$acf_hidden_job")
    acf_hidden_dept=$(json_escape "$acf_hidden_dept")
    acf_hidden_ext=$(json_escape "$acf_hidden_ext")
    
    echo "{\"exists\": $exists, \"in_category\": $in_category, \"job_title\": \"$job_title\", \"department\": \"$department\", \"office_extension\": \"$office_extension\", \"acf_hidden_job\": \"$acf_hidden_job\", \"acf_hidden_dept\": \"$acf_hidden_dept\", \"acf_hidden_ext\": \"$acf_hidden_ext\"}"
}

# 3. Gather Data
EMP1_DATA=$(get_employee_data "Emily Chen")
EMP2_DATA=$(get_employee_data "Marcus Johnson")

# 4. Construct JSON
TEMP_JSON=$(mktemp /tmp/acf_result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "acf_active": $ACF_ACTIVE,
    "emp1": $EMP1_DATA,
    "emp2": $EMP2_DATA,
    "timestamp": "$(date -Iseconds)"
}
EOF

rm -f /tmp/acf_task_result.json 2>/dev/null || sudo rm -f /tmp/acf_task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/acf_task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/acf_task_result.json
chmod 666 /tmp/acf_task_result.json 2>/dev/null || sudo chmod 666 /tmp/acf_task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/acf_task_result.json