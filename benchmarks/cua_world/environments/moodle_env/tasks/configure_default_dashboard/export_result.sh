#!/bin/bash
# Export script for Configure Default Dashboard task

echo "=== Exporting Configure Default Dashboard Result ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_end_screenshot.png

# User ID to check for reset
USER_ID=$(cat /tmp/jsmith_id.txt 2>/dev/null || echo "0")

# We use a PHP script to reliably extract block configuration
# SQL is difficult because 'configdata' is base64 encoded serialized PHP object
cat > /tmp/check_dashboard.php << 'PHP_EOF'
<?php
define('CLI_SCRIPT', true);
require('/var/www/html/moodle/config.php');

$result = [
    'online_users_found' => false,
    'timeline_found' => false,
    'support_block_found' => false,
    'support_block_title_correct' => false,
    'support_block_content_correct' => false,
    'user_custom_dashboard_exists' => false,
    'found_blocks' => []
];

// 1. Get the Default Dashboard page definition
// In mdl_my_pages, the system default has userid=NULL and private=0
$mypage = $DB->get_record('my_pages', array('userid' => null, 'private' => 0, 'name' => 'dashboard'));

if ($mypage) {
    // Get the context for this page
    // Moodle 4.0+ context logic for my_pages
    $context = context_system::instance(); 
    
    // We need to find block instances. 
    // They are linked to the 'my_pages' entry via pagetypepattern and subpagepattern usually,
    // OR via parentcontextid.
    
    // Attempt 1: Look for context related to this page instance
    // NOTE: In Moodle 4.x, blocks on default dashboard are often attached to context_system 
    // but with specific pagetypepattern 'my-index' and subpagepattern matching the ID.
    
    // Let's search mdl_block_instances directly for the page ID match
    $sql = "SELECT bi.* 
            FROM {block_instances} bi
            WHERE bi.pagetypepattern = 'my-index'
            AND bi.subpagepattern = ?";
            
    $blocks = $DB->get_records_sql($sql, array($mypage->id));
    
    foreach ($blocks as $block) {
        $blockname = $block->blockname;
        $result['found_blocks'][] = $blockname;
        
        if ($blockname === 'online_users') {
            $result['online_users_found'] = true;
        }
        
        if ($blockname === 'timeline') {
            $result['timeline_found'] = true;
        }
        
        if ($blockname === 'html') {
            // Decode config data
            $config = unserialize(base64_decode($block->configdata));
            if ($config) {
                // Check Title
                if (isset($config->title) && stripos($config->title, 'Student Support') !== false) {
                    $result['support_block_found'] = true;
                    $result['support_block_title_correct'] = true;
                }
                
                // Check Content
                if (isset($config->text)) {
                    // Normalize text (strip tags) to check content
                    $clean_text = strip_tags($config->text);
                    if (stripos($clean_text, 'helpdesk@university.edu') !== false) {
                        $result['support_block_content_correct'] = true;
                        // If title was generic but content matches, we count it as found
                        $result['support_block_found'] = true;
                    }
                }
            }
        }
    }
}

// 2. Check if user jsmith still has a custom dashboard
// If reset worked, this record should be gone
$userid = (int) $argv[1];
if ($userid > 0) {
    $custom = $DB->get_record('my_pages', array('userid' => $userid, 'name' => 'dashboard'));
    if ($custom) {
        $result['user_custom_dashboard_exists'] = true;
    }
}

echo json_encode($result);
PHP_EOF

# Run the PHP script
echo "Running verification PHP script..."
PHP_OUTPUT=$(sudo -u www-data php /tmp/check_dashboard.php "$USER_ID")

# Save output to JSON file
echo "$PHP_OUTPUT" > /tmp/configure_default_dashboard_result.json

# Ensure permissions
chmod 666 /tmp/configure_default_dashboard_result.json

echo "Result JSON:"
cat /tmp/configure_default_dashboard_result.json
echo ""

echo "=== Export Complete ==="