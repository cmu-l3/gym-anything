<?php
use Drupal\commerce_store\Entity\Store;
use Drupal\commerce_store\Entity\StoreType;
use Drupal\commerce_product\Entity\Product;
use Drupal\commerce_product\Entity\ProductVariation;
use Drupal\commerce_price\Price;

// Create the default store first (required before products can be assigned)
$stores = \Drupal::entityTypeManager()->getStorage('commerce_store')->loadMultiple();
if (empty($stores)) {
    // Ensure 'online' store type exists
    $store_type = StoreType::load('online');
    if (!$store_type) {
        $store_type = StoreType::create([
            'id' => 'online',
            'label' => 'Online',
            'description' => 'An online store type.',
        ]);
        $store_type->save();
        echo "Created 'online' store type\n";
    }

    $store = Store::create([
        'type' => 'online',
        'uid' => 1,
        'name' => 'Urban Electronics',
        'mail' => 'store@urbanelectronics.com',
        'address' => [
            'country_code' => 'US',
            'address_line1' => '456 Market Street',
            'locality' => 'San Francisco',
            'administrative_area' => 'CA',
            'postal_code' => '94105',
        ],
        'default_currency' => 'USD',
        'is_default' => TRUE,
    ]);
    $store->save();
    echo "Created store: " . $store->getName() . " (ID: " . $store->id() . ")\n";
} else {
    echo "Store already exists\n";
}

$products = [
  ["title" => "Sony WH-1000XM5 Wireless Headphones", "sku" => "SONY-WH1000XM5", "price" => "348.00", "body" => "Industry-leading noise cancellation with Auto NC Optimizer. Crystal-clear hands-free calling with 4 beamforming microphones. Up to 30-hour battery life with quick charging."],
  ["title" => "Apple MacBook Air M2 13-inch", "sku" => "APPLE-MBA-M2-13", "price" => "1099.00", "body" => "Supercharged by M2 chip. 13.6-inch Liquid Retina display. Up to 18 hours of battery life. 8GB unified memory. 256GB SSD storage."],
  ["title" => "Samsung 65-inch 4K QLED Smart TV", "sku" => "SAMSUNG-QN65Q80C", "price" => "997.99", "body" => "Quantum HDR+ with 100% Color Volume. Neural Quantum Processor 4K. Direct Full Array backlighting. Object Tracking Sound."],
  ["title" => "Bose QuietComfort Ultra Earbuds", "sku" => "BOSE-QCUE", "price" => "299.00", "body" => "World-class noise cancellation. Immersive spatial audio with Bose Immersive Audio. CustomTune sound calibration. Up to 6 hours battery."],
  ["title" => "Logitech MX Master 3S Wireless Mouse", "sku" => "LOGI-MXM3S", "price" => "99.99", "body" => "8K DPI any-surface tracking. Quiet Clicks. MagSpeed electromagnetic scroll wheel. USB-C quick charging."],
  ["title" => "Dell UltraSharp 27 4K USB-C Hub Monitor", "sku" => "DELL-U2723QE", "price" => "619.99", "body" => "27-inch 4K UHD IPS Black panel. USB-C hub with 90W power delivery. 98% DCI-P3 color coverage."],
  ["title" => "Anker PowerCore 26800mAh Portable Charger", "sku" => "ANKER-PC26800", "price" => "65.99", "body" => "Ultra-high 26800mAh capacity. Dual input ports for fast recharging. Triple USB output. PowerIQ technology."],
  ["title" => "Keychron Q1 Pro Mechanical Keyboard", "sku" => "KEYCHRON-Q1PRO", "price" => "199.00", "body" => "75% layout QMK/VIA compatible wireless mechanical keyboard. Full aluminum CNC machined body. Gasket mount design."],
  ["title" => "WD Black SN850X 2TB NVMe SSD", "sku" => "WD-SN850X-2TB", "price" => "149.99", "body" => "PCIe Gen4 NVMe SSD. Up to 7300 MB/s read speed. Game Mode 2.0 with predictive loading. Optimized for PS5 and PC gaming."],
  ["title" => "Razer DeathAdder V3 Gaming Mouse", "sku" => "RAZER-DAV3", "price" => "89.99", "body" => "Focus Pro 30K optical sensor. Up to 90-hour battery life. HyperSpeed Wireless. Ultra-lightweight at 63g."],
  ["title" => "CalDigit TS4 Thunderbolt 4 Dock", "sku" => "CALDIGIT-TS4", "price" => "399.99", "body" => "18 ports including 3x Thunderbolt 4. 98W laptop charging. 2.5GbE Ethernet. SD and microSD card readers."],
  ["title" => "Corsair Vengeance DDR5 32GB RAM Kit", "sku" => "CORSAIR-DDR5-32G", "price" => "94.99", "body" => "DDR5-5600 MHz speed. 2x16GB kit. Intel XMP 3.0 optimized. Tight CL36 latency."],
];

foreach ($products as $p) {
  $variation = ProductVariation::create([
    "type" => "default",
    "sku" => $p["sku"],
    "price" => new Price($p["price"], "USD"),
    "status" => 1,
  ]);
  $variation->save();

  $product = Product::create([
    "type" => "default",
    "title" => $p["title"],
    "body" => ["value" => $p["body"], "format" => "basic_html"],
    "stores" => [1],
    "variations" => [$variation],
    "status" => 1,
  ]);
  $product->save();
  echo "Created: " . $p["title"] . " ($" . $p["price"] . ")\n";
}
