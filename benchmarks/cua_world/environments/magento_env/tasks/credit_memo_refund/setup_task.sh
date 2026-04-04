#!/bin/bash
# Setup script for Credit Memo Refund task
set -e

echo "=== Setting up Credit Memo Refund Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create a PHP script to generate the order programmatically
#    This ensures a clean state with a specific order ready for refunding.
cat > /var/www/html/magento/create_order.php << 'PHPEOF'
<?php
use Magento\Framework\App\Bootstrap;
require __DIR__ . '/app/bootstrap.php';

$bootstrap = Bootstrap::create(BP, $_SERVER);
$obj = $bootstrap->getObjectManager();

$state = $obj->get(Magento\Framework\App\State::class);
$state->setAreaCode('adminhtml');

$storeManager = $obj->get(Magento\Store\Model\StoreManagerInterface::class);
$store = $storeManager->getStore();
$websiteId = $storeManager->getStore()->getWebsiteId();

// 1. Create Customer
$customerFactory = $obj->get(Magento\Customer\Model\CustomerFactory::class);
$customer = $customerFactory->create();
$customer->setWebsiteId($websiteId);
$customer->loadByEmail('john.smith@example.com');

if (!$customer->getId()) {
    $customer->setEmail('john.smith@example.com');
    $customer->setFirstname('John');
    $customer->setLastname('Smith');
    $customer->setPassword('Customer123!');
    $customer->save();
    echo "Customer created: John Smith\n";
} else {
    echo "Customer exists: John Smith\n";
}

// 2. Create Quote/Order
$quote = $obj->get(Magento\Quote\Model\QuoteFactory::class)->create();
$quote->setStore($store);
$quote->setCurrency();
$quote->assignCustomer($customer);

// Add Products
$productRepository = $obj->get(Magento\Catalog\Api\ProductRepositoryInterface::class);

// Add Laptop (Qty 1)
try {
    $laptop = $productRepository->get('LAPTOP-001');
    $quote->addProduct($laptop, 1);
} catch (\Exception $e) {
    echo "Error adding laptop: " . $e->getMessage() . "\n";
}

// Add Headphones (Qty 2)
try {
    $headphones = $productRepository->get('HEADPHONES-001');
    $quote->addProduct($headphones, 2);
} catch (\Exception $e) {
    echo "Error adding headphones: " . $e->getMessage() . "\n";
}

// Set Address
$addressData = [
    'firstname' => 'John',
    'lastname' => 'Smith',
    'street' => '123 Tech Blvd',
    'city' => 'San Jose',
    'country_id' => 'US',
    'region' => 'California',
    'region_id' => 12,
    'postcode' => '95110',
    'telephone' => '555-0123',
    'save_in_address_book' => 1
];

$billingAddress = $quote->getBillingAddress()->addData($addressData);
$shippingAddress = $quote->getShippingAddress()->addData($addressData);

// Set Shipping Method
$shippingAddress->setCollectShippingRates(true)
    ->collectShippingRates()
    ->setShippingMethod('flatrate_flatrate');

// Set Payment Method
$quote->setPaymentMethod('checkmo');
$quote->setInventoryProcessed(false);

// Save Quote
$quote->save();
$quote->getPayment()->importData(['method' => 'checkmo']);
$quote->collectTotals()->save();

// Convert to Order
$quoteManagement = $obj->get(Magento\Quote\Model\QuoteManagement::class);
$order = $quoteManagement->submit($quote);
echo "Order created: #" . $order->getIncrementId() . "\n";

// 3. Invoice the Order (Status -> Processing)
if ($order->canInvoice()) {
    $invoice = $obj->get(Magento\Sales\Model\Service\InvoiceService::class)->prepareInvoice($order);
    $invoice->register();
    $invoice->save();
    
    $transaction = $obj->get(Magento\Framework\DB\Transaction::class)
        ->addObject($invoice)
        ->addObject($invoice->getOrder());
    $transaction->save();
    
    echo "Order invoiced. Status: " . $order->getStatus() . "\n";
}
PHPEOF

# Execute the PHP script
echo "Executing order creation script..."
php /var/www/html/magento/create_order.php
rm -f /var/www/html/magento/create_order.php

# Record initial credit memo count
echo "Recording initial credit memo count..."
INITIAL_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_creditmemo" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
echo "$INITIAL_COUNT" > /tmp/initial_creditmemo_count
echo "Initial credit memos: $INITIAL_COUNT"

# Ensure Firefox is running
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 10
fi

# Wait for window
if ! wait_for_window "firefox\|mozilla\|Magento" 60; then
    echo "WARNING: Firefox window not detected"
fi

# Focus window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Handle login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting auto-login..."
    sleep 2
    DISPLAY=:1 xdotool mousemove 960 540 click 1
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool key ctrl+a
    DISPLAY=:1 xdotool type --clearmodifiers "admin"
    sleep 0.5
    DISPLAY=:1 xdotool key Tab
    sleep 0.3
    DISPLAY=:1 xdotool type --clearmodifiers "Admin1234!"
    sleep 0.5
    DISPLAY=:1 xdotool key Return
    sleep 10
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="