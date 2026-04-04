<?php
use Drupal\commerce_promotion\Entity\Promotion;
use Drupal\commerce_promotion\Entity\Coupon;
use Drupal\commerce_price\Price;

// 10% off welcome promotion
$promo1 = Promotion::create([
  "name" => "Welcome 10% Off",
  "display_name" => "10% Welcome Discount",
  "order_types" => ["default"],
  "stores" => [1],
  "offer" => [
    "target_plugin_id" => "order_percentage_off",
    "target_plugin_configuration" => [
      "percentage" => "0.10",
    ],
  ],
  "status" => 1,
  "require_coupon" => TRUE,
]);
$promo1->save();

$coupon1 = Coupon::create([
  "code" => "WELCOME10",
  "usage_limit" => 100,
  "status" => 1,
]);
$coupon1->save();
$promo1->get("coupons")->appendItem($coupon1);
$promo1->save();
echo "Created: Welcome 10% Off (coupon: WELCOME10)\n";

// $25 off orders over $200
$promo2 = Promotion::create([
  "name" => "Save \$25 on Orders Over \$200",
  "display_name" => "\$25 Off Orders Over \$200",
  "order_types" => ["default"],
  "stores" => [1],
  "offer" => [
    "target_plugin_id" => "order_fixed_amount_off",
    "target_plugin_configuration" => [
      "amount" => [
        "number" => "25.00",
        "currency_code" => "USD",
      ],
    ],
  ],
  "conditions" => [
    [
      "target_plugin_id" => "order_total_price",
      "target_plugin_configuration" => [
        "operator" => ">=",
        "amount" => [
          "number" => "200.00",
          "currency_code" => "USD",
        ],
      ],
    ],
  ],
  "status" => 1,
  "require_coupon" => TRUE,
]);
$promo2->save();

$coupon2 = Coupon::create([
  "code" => "SAVE25",
  "usage_limit" => 200,
  "status" => 1,
]);
$coupon2->save();
$promo2->get("coupons")->appendItem($coupon2);
$promo2->save();
echo "Created: Save \$25 on Orders Over \$200 (coupon: SAVE25)\n";

// 15% off electronics (automatic, disabled)
$promo3 = Promotion::create([
  "name" => "Electronics 15% Off",
  "display_name" => "15% Off Electronics",
  "order_types" => ["default"],
  "stores" => [1],
  "offer" => [
    "target_plugin_id" => "order_percentage_off",
    "target_plugin_configuration" => [
      "percentage" => "0.15",
    ],
  ],
  "status" => 0,
  "require_coupon" => FALSE,
]);
$promo3->save();
echo "Created: Electronics 15% Off (automatic, disabled)\n";
