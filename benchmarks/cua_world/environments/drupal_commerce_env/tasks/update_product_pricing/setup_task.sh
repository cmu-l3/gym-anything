#!/bin/bash
# Setup script for Update Product Pricing task
echo "=== Setting up update_product_pricing ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure services are running
ensure_services_running 120

# Helper to ensure a product exists with specific state using Drush
# We use Drush php:eval for reliability over raw SQL inserts
ensure_product() {
    local title="$1"
    local sku="$2"
    local price="$3"
    local status="$4"
    local desc="$5"

    echo "Ensuring product '$title' ($sku) exists..."

    cd /var/www/html/drupal
    
    # PHP script to load/create and update product
    cat <<EOF > /tmp/update_product_$sku.php
use Drupal\commerce_product\Entity\Product;
use Drupal\commerce_product\Entity\ProductVariation;

\$sku = '$sku';
\$target_price = new \Drupal\commerce_price\Price('$price', 'USD');
\$target_status = $status;

// Find variation by SKU
\$variations = \Drupal::entityTypeManager()
  ->getStorage('commerce_product_variation')
  ->loadByProperties(['sku' => \$sku]);

if (!empty(\$variations)) {
  \$variation = reset(\$variations);
  \$variation->setPrice(\$target_price);
  \$variation->save();
  echo "Updated variation $sku price to $price\n";
  
  // Update parent product status
  \$product = \$variation->getProduct();
  if (\$product) {
    \$product->set('status', \$target_status);
    \$product->setTitle("$title");
    \$product->save();
    echo "Updated product status to $status\n";
  }
} else {
  // Create new if missing
  \$variation = ProductVariation::create([
    'type' => 'default',
    'sku' => \$sku,
    'price' => \$target_price,
    'title' => "$title",
  ]);
  \$variation->save();
  
  \$product = Product::create([
    'uid' => 1,
    'type' => 'default',
    'title' => "$title",
    'stores' => [1],
    'variations' => [\$variation],
    'body' => ['value' => "$desc", 'format' => 'basic_html'],
    'status' => \$target_status,
  ]);
  \$product->save();
  echo "Created new product $sku\n";
}
EOF
    
    vendor/bin/drush php:script /tmp/update_product_$sku.php
    rm /tmp/update_product_$sku.php
}

# 1. Reset products to INITIAL state
# Sony: $348.00, Published
ensure_product "Sony WH-1000XM5 Wireless Headphones" "SONY-WH1000XM5" "348.00" "1" "Industry-leading noise canceling headphones."

# Logitech: $99.99, Published
ensure_product "Logitech MX Master 3S" "LOGI-MXM3S" "99.99" "1" "Performance wireless mouse."

# Bose: $329.00, Published (Must be published initially so agent can unpublish it)
ensure_product "Bose QuietComfort 45" "BOSE-QC45" "329.00" "1" "Iconic quiet. Comfort. and sound."

# Clear cache to ensure UI reflects DB
cd /var/www/html/drupal && vendor/bin/drush cr

# Record initial state for anti-gaming verification
echo "Recording initial database state..."

# Function to get price by SKU
get_price() {
    drupal_db_query "SELECT price__number FROM commerce_product_variation_field_data WHERE sku='$1'"
}

# Function to get status by SKU (via product)
get_status() {
    drupal_db_query "SELECT p.status FROM commerce_product_field_data p JOIN commerce_product__variations pv ON p.product_id = pv.entity_id JOIN commerce_product_variation_field_data v ON pv.variations_target_id = v.variation_id WHERE v.sku='$1'"
}

INITIAL_SONY_PRICE=$(get_price "SONY-WH1000XM5")
INITIAL_LOGI_PRICE=$(get_price "LOGI-MXM3S")
INITIAL_BOSE_PRICE=$(get_price "BOSE-QC45")
INITIAL_BOSE_STATUS=$(get_status "BOSE-QC45")
INITIAL_TOTAL_PUBLISHED=$(drupal_db_query "SELECT COUNT(*) FROM commerce_product_field_data WHERE status=1")

cat > /tmp/initial_state.json <<EOF
{
  "sony_price": "${INITIAL_SONY_PRICE:-0}",
  "logi_price": "${INITIAL_LOGI_PRICE:-0}",
  "bose_price": "${INITIAL_BOSE_PRICE:-0}",
  "bose_status": "${INITIAL_BOSE_STATUS:-0}",
  "total_published": ${INITIAL_TOTAL_PUBLISHED:-0},
  "timestamp": $(date +%s)
}
EOF

echo "Initial state recorded:"
cat /tmp/initial_state.json

# Navigate to Product List
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/products"
sleep 5

# Maximize
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Take screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="