#!/bin/bash
# Setup script for Configure Bundle Promotion task
echo "=== Setting up Configure Bundle Promotion ==="

source /workspace/scripts/task_utils.sh

# Fallback definitions if task_utils missing
if ! type drupal_db_query &>/dev/null; then
    drupal_db_query() {
        docker exec drupal-mariadb mysql -u drupal -pdrupalpass drupal -N -e "$1" 2>/dev/null
    }
fi

# Ensure services are running
ensure_services_running 120

# 1. Verify required products exist
echo "Verifying product existence..."
DJI_CHECK=$(drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE sku='DJI-MINI3'")
ANKER_CHECK=$(drupal_db_query "SELECT variation_id FROM commerce_product_variation_field_data WHERE sku='ANKER-PC26800'")

if [ -z "$DJI_CHECK" ] || [ -z "$ANKER_CHECK" ]; then
    echo "Creating missing products..."
    cd /var/www/html/drupal
    /var/www/html/drupal/vendor/bin/drush php:eval '
    use Drupal\commerce_product\Entity\Product;
    use Drupal\commerce_product\Entity\ProductVariation;
    use Drupal\commerce_price\Price;

    function create_prod($sku, $title, $price) {
        $existing = \Drupal::entityTypeManager()->getStorage("commerce_product_variation")->loadByProperties(["sku" => $sku]);
        if (!$existing) {
            $variation = ProductVariation::create([
                "type" => "default",
                "sku" => $sku,
                "price" => new Price($price, "USD"),
                "status" => 1,
            ]);
            $variation->save();
            $product = Product::create([
                "type" => "default",
                "title" => $title,
                "variations" => [$variation],
                "stores" => [1],
                "status" => 1,
            ]);
            $product->save();
            echo "Created $sku\n";
        }
    }
    create_prod("DJI-MINI3", "DJI Mini 3 Pro", "759.00");
    create_prod("ANKER-PC26800", "Anker PowerCore 26800", "59.99");
    '
fi

# 2. Cleanup: Remove any existing promotion with this name to ensure fresh start
drupal_db_query "DELETE FROM commerce_promotion_field_data WHERE name LIKE '%Drone Power Bundle%'"
drupal_db_query "DELETE FROM commerce_promotion WHERE name LIKE '%Drone Power Bundle%'" # Base table

# 3. Record state
INITIAL_PROMO_COUNT=$(drupal_db_query "SELECT COUNT(*) FROM commerce_promotion_field_data")
echo "${INITIAL_PROMO_COUNT:-0}" > /tmp/initial_promo_count

date +%s > /tmp/task_start_timestamp

# 4. Prepare UI
ensure_drupal_shown 60
navigate_firefox_to "http://localhost/admin/commerce/promotions"
sleep 5

# Screenshot initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="