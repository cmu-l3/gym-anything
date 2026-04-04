#!/bin/bash
# Setup script for create_visual_category_navigation
echo "=== Setting up Visual Category Navigation Task ==="

source /workspace/scripts/task_utils.sh

# 1. Ensure Services are Running
ensure_services_running 120

# 2. Setup Data: Ensure Vocabulary and Terms Exist
echo "Setting up taxonomy..."

# Check/Create Vocabulary
VOCAB_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM taxonomy_vocabulary WHERE vid='product_categories'")
if [ "$VOCAB_EXISTS" -eq 0 ] 2>/dev/null; then
    echo "Creating Product Categories vocabulary..."
    # We use drush php:eval for complex entity creation if simple SQL isn't enough, 
    # but for vocabulary SQL/config insert is hard. Using Drush is safer.
    drush_cmd php:eval '\Drupal\taxonomy\Entity\Vocabulary::create(["vid" => "product_categories", "name" => "Product Categories"])->save();'
fi

# Ensure Terms Exist
for term in "Headphones" "Keyboards" "Monitors"; do
    TERM_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM taxonomy_term_field_data WHERE vid='product_categories' AND name='$term'")
    if [ "$TERM_EXISTS" -eq 0 ] 2>/dev/null; then
        echo "Creating term: $term"
        drush_cmd php:eval "
        use Drupal\taxonomy\Entity\Term;
        Term::create([
            'vid' => 'product_categories',
            'name' => '$term',
        ])->save();"
    fi
done

# 3. Prepare Images
echo "Preparing source images..."
IMAGE_DIR="/home/ga/Downloads/category_images"
mkdir -p "$IMAGE_DIR"
chown ga:ga "$IMAGE_DIR"

# Generate images using ImageMagick (convert)
# Headphones (Blue)
convert -size 600x600 xc:lightblue -font DejaVu-Sans -pointsize 60 -fill black -gravity center -annotate +0+0 "Headphones" "$IMAGE_DIR/headphones.jpg"
# Keyboards (Green)
convert -size 600x600 xc:lightgreen -font DejaVu-Sans -pointsize 60 -fill black -gravity center -annotate +0+0 "Keyboards" "$IMAGE_DIR/keyboards.jpg"
# Monitors (Red)
convert -size 600x600 xc:lightcoral -font DejaVu-Sans -pointsize 60 -fill black -gravity center -annotate +0+0 "Monitors" "$IMAGE_DIR/monitors.jpg"

chown ga:ga "$IMAGE_DIR"/*.jpg

# 4. Record Initial State (to prevent pre-gaming)
echo "Recording initial state..."
date +%s > /tmp/task_start_timestamp

# Check if field already exists (should not)
FIELD_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name='field.storage.taxonomy_term.field_category_image'")
echo "$FIELD_EXISTS" > /tmp/initial_field_exists

# Check if view already exists
VIEW_EXISTS=$(drupal_db_query "SELECT COUNT(*) FROM config WHERE name='views.view.category_grid'")
echo "$VIEW_EXISTS" > /tmp/initial_view_exists

# 5. Launch Browser
echo "Launching Firefox..."
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/structure/taxonomy"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="