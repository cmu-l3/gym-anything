#!/bin/bash
set -e

echo "=== Setting up create_related_products_view ==="

source /workspace/scripts/task_utils.sh

date +%s > /tmp/create_related_products_view_start_ts

ensure_services_running

COUNT=$($DRUSH php:eval "echo \\Drupal\\commerce_product\\Entity\\Product::query()->count();" 2>/dev/null || echo "0")
if [ "$COUNT" -lt "5" ]; then
  echo "Creating fallback products for related-products task..."
  $DRUSH php:eval '
    use Drupal\commerce_product\Entity\Product;
    use Drupal\commerce_product\Entity\ProductVariation;
    use Drupal\commerce_price\Price;

    $store = \Drupal\commerce_store\Entity\Store::load(1);
    if (!$store) {
      $store = \Drupal\commerce_store\Entity\Store::create([
        "type" => "online",
        "uid" => 1,
        "name" => "Default Store",
        "mail" => "admin@example.com",
        "default_currency" => "USD"
      ]);
      $store->save();
    }

    for ($i = 1; $i <= 5; $i++) {
      $sku = "TEST-" . $i;
      if (!\Drupal\commerce_product\Entity\ProductVariation::loadBySku($sku)) {
        $variation = ProductVariation::create([
          "type" => "default",
          "sku" => $sku,
          "price" => new Price("10.00", "USD")
        ]);
        $variation->save();
        $product = Product::create([
          "type" => "default",
          "title" => "Test Product " . $i,
          "stores" => [$store],
          "variations" => [$variation]
        ]);
        $product->save();
      }
    }
  ' 2>&1
fi

if ! pgrep -f "firefox" > /dev/null; then
  su - ga -c "DISPLAY=:1 firefox > /tmp/firefox_related_products.log 2>&1 &"
  sleep 5
fi

ensure_drupal_shown

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
  DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

navigate_firefox_to "http://localhost/admin/structure/views"
take_screenshot /tmp/create_related_products_view_start.png

echo "=== Setup complete ==="
