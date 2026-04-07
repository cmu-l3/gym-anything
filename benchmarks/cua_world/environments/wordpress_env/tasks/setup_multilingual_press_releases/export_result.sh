#!/bin/bash
echo "=== Exporting setup_multilingual_press_releases result ==="

source /workspace/scripts/task_utils.sh

take_screenshot /tmp/task_final.png

cd /var/www/html/wordpress

# Create a PHP script to extract Polylang data
cat > /tmp/check_polylang.php << 'PHPEOF'
<?php
error_reporting(0);

$result = [
    'polylang_active' => false,
    'languages' => [],
    'en_category_id' => null,
    'fr_category_id' => null,
    'fr_category_name' => '',
    'category_linked' => false,
    'en_post_id' => null,
    'fr_post_id' => null,
    'fr_post_title' => '',
    'fr_post_content' => '',
    'fr_post_status' => '',
    'post_linked' => false,
    'fr_post_category_id' => null,
    'fr_post_language' => null
];

if (function_exists('pll_get_post_translations')) {
    $result['polylang_active'] = true;
    
    // Check languages
    $terms = get_terms(['taxonomy' => 'language', 'hide_empty' => false]);
    if (!is_wp_error($terms)) {
        foreach ($terms as $term) {
            $result['languages'][] = $term->slug;
        }
    }
    
    // Check category
    $en_cat = get_term_by('name', 'Press Releases', 'category');
    if ($en_cat) {
        $result['en_category_id'] = $en_cat->term_id;
        $translations = pll_get_term_translations($en_cat->term_id);
        if (isset($translations['fr'])) {
            $result['fr_category_id'] = $translations['fr'];
            $result['category_linked'] = true;
            $fr_cat = get_term($translations['fr']);
            $result['fr_category_name'] = $fr_cat ? $fr_cat->name : '';
        }
    }
    
    if (!$result['fr_category_id']) {
        $fr_cat = get_term_by('name', 'Communiqués de presse', 'category');
        if ($fr_cat) {
            $result['fr_category_id'] = $fr_cat->term_id;
            $result['fr_category_name'] = $fr_cat->name;
        }
    }
    
    // Check post
    global $wpdb;
    $en_post_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_title = 'Acquisition of TechCorp Announced' AND post_type = 'post' AND post_status = 'publish' LIMIT 1");
    
    if ($en_post_id) {
        $result['en_post_id'] = $en_post_id;
        $translations = pll_get_post_translations($en_post_id);
        if (isset($translations['fr'])) {
            $result['fr_post_id'] = $translations['fr'];
            $result['post_linked'] = true;
        }
    }
    
    if (!$result['fr_post_id']) {
        $fr_post_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_title LIKE '%Annonce de l%acquisition de TechCorp%' AND post_type = 'post' LIMIT 1");
        if ($fr_post_id) {
            $result['fr_post_id'] = $fr_post_id;
        }
    }
    
    // Get fr post details
    if ($result['fr_post_id']) {
        $fr_post = get_post($result['fr_post_id']);
        $result['fr_post_title'] = $fr_post->post_title;
        $result['fr_post_content'] = $fr_post->post_content;
        $result['fr_post_status'] = $fr_post->post_status;
        $result['fr_post_language'] = pll_get_post_language($result['fr_post_id']);
        
        $cats = wp_get_post_categories($result['fr_post_id']);
        if (!empty($cats)) {
            $result['fr_post_category_id'] = $cats[0];
        }
    }
} else {
    // If not active, try to fetch the post anyway to see if agent created it
    global $wpdb;
    $fr_post_id = $wpdb->get_var("SELECT ID FROM {$wpdb->posts} WHERE post_title LIKE '%Annonce de l%acquisition de TechCorp%' AND post_type = 'post' LIMIT 1");
    if ($fr_post_id) {
        $result['fr_post_id'] = $fr_post_id;
        $fr_post = get_post($fr_post_id);
        $result['fr_post_title'] = $fr_post->post_title;
        $result['fr_post_content'] = $fr_post->post_content;
        $result['fr_post_status'] = $fr_post->post_status;
    }
}

$result['timestamp'] = date('c');

echo "\nJSON_START\n";
echo json_encode($result);
echo "\nJSON_END\n";
?>
PHPEOF

# Execute the PHP script
WP_EVAL_OUT=$(wp eval-file /tmp/check_polylang.php --allow-root 2>/dev/null)

# Extract JSON
JSON_DATA=$(echo "$WP_EVAL_OUT" | sed -n '/JSON_START/,/JSON_END/p' | grep -v 'JSON_START' | grep -v 'JSON_END')

if [ -z "$JSON_DATA" ]; then
    echo "Failed to extract JSON data from PHP script"
    # Fallback minimal JSON
    JSON_DATA="{\"polylang_active\": false, \"error\": \"Failed to parse output\"}"
fi

# Save to file
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
echo "$JSON_DATA" > "$TEMP_JSON"

# Move to final location
rm -f /tmp/setup_multilingual_press_releases_result.json 2>/dev/null || sudo rm -f /tmp/setup_multilingual_press_releases_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/setup_multilingual_press_releases_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/setup_multilingual_press_releases_result.json
chmod 666 /tmp/setup_multilingual_press_releases_result.json 2>/dev/null || sudo chmod 666 /tmp/setup_multilingual_press_releases_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/setup_multilingual_press_releases_result.json"
cat /tmp/setup_multilingual_press_releases_result.json
echo ""
echo "=== Export complete ==="