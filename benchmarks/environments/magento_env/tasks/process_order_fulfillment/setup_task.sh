#!/bin/bash
# Setup script for Process Order Fulfillment task

echo "=== Setting up Process Order Fulfillment Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Ensure Magento services are running
echo "Checking Magento services..."
if ! docker ps | grep -q "magento-mariadb"; then
    echo "Starting Docker services..."
    cd /home/ga/magento && docker-compose up -d
    sleep 10
fi

# 2. Check/Create the target order (#000000001)
echo "Checking for order #000000001..."
ORDER_EXISTS=$(magento_query "SELECT entity_id FROM sales_order WHERE increment_id='000000001'" 2>/dev/null | tail -1)

if [ -z "$ORDER_EXISTS" ]; then
    echo "Creating pending order #000000001..."
    
    # PHP script to create a simple order programmatically
    # This ensures a clean state for the agent
    cat > /tmp/create_order.php << 'PHPEOF'
<?php
use Magento\Framework\App\Bootstrap;
require '/var/www/html/magento/app/bootstrap.php';

$bootstrap = Bootstrap::create(BP, $_SERVER);
$obj = $bootstrap->getObjectManager();

$state = $obj->get('Magento\Framework\App\State');
$state->setAreaCode('adminhtml');

$storeId = 1;
$quote = $obj->create('Magento\Quote\Model\Quote');
$quote->setStoreId($storeId);

// Create guest customer
$customer = $obj->create('Magento\Customer\Model\Customer');
$customer->setWebsiteId(1);
$customer->loadByEmail('guest@example.com');
if (!$customer->getId()) {
    $customer->setWebsiteId(1)
             ->setStoreId(1)
             ->setFirstname('John')
             ->setLastname('Guest')
             ->setEmail('guest@example.com')
             ->setPassword('Guest123!');
    $customer->save();
}
$quote->assignCustomer($customer);

// Add product
$product = $obj->create('Magento\Catalog\Model\Product')->load(1); // Assuming ID 1 exists from seeded data
if (!$product->getId()) {
    // Fallback: get any product
    $productCollection = $obj->create('Magento\Catalog\Model\ResourceModel\Product\Collection');
    $productCollection->setPageSize(1);
    $product = $productCollection->getFirstItem();
}
$quote->addProduct($product, 1);

// Set Address
$addressData = [
    'firstname' => 'John',
    'lastname' => 'Doe',
    'street' => '123 Main St',
    'city' => 'New York',
    'country_id' => 'US',
    'region' => 'NY',
    'postcode' => '10001',
    'telephone' => '1234567890',
    'save_in_address_book' => 1
];
$billingAddr = $quote->getBillingAddress()->addData($addressData);
$shippingAddr = $quote->getShippingAddress()->addData($addressData);

// Set Shipping & Payment
$shippingAddr->setCollectShippingRates(true)
             ->setCollectShippingRates(true)
             ->setShippingMethod('flatrate_flatrate');
$quote->setPaymentMethod('checkmo');
$quote->setInventoryProcessed(false);
$quote->save();

// Set Payment
$quote->getPayment()->importData(['method' => 'checkmo']);
$quote->collectTotals()->save();

// Convert to Order
$order = $obj->create('Magento\Quote\Model\QuoteManagement')->submit($quote);
$order->setIncrementId('000000001');
$order->save();

echo "Order created: " . $order->getIncrementId() . "\n";
PHPEOF

    # Execute PHP script
    php /tmp/create_order.php
    
    # Reset order ID in DB to be exactly 000000001 if the PHP script didn't force it correctly
    # (Magento might ignore setIncrementId if sequence is active, so we force it via SQL)
    LAST_ID=$(magento_query "SELECT entity_id FROM sales_order ORDER BY entity_id DESC LIMIT 1" 2>/dev/null | tail -1)
    if [ -n "$LAST_ID" ]; then
        magento_query "UPDATE sales_order SET increment_id='000000001' WHERE entity_id=$LAST_ID"
    fi
    echo "Order #000000001 ensured."
else
    echo "Order #000000001 already exists."
    # Optional: Reset status to pending if it was completed
    magento_query "UPDATE sales_order SET status='pending', state='new', total_invoiced=0, total_paid=0 WHERE increment_id='000000001'"
    ORDER_ID=$(magento_query "SELECT entity_id FROM sales_order WHERE increment_id='000000001'" 2>/dev/null | tail -1)
    # Clear invoices and shipments for a clean retry
    magento_query "DELETE FROM sales_invoice WHERE order_id=$ORDER_ID"
    magento_query "DELETE FROM sales_shipment WHERE order_id=$ORDER_ID"
    echo "Order #000000001 reset to pending state."
fi

# 3. Record initial counts for anti-gaming verification
INITIAL_INVOICE_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_invoice" 2>/dev/null | tail -1)
INITIAL_SHIPMENT_COUNT=$(magento_query "SELECT COUNT(*) FROM sales_shipment" 2>/dev/null | tail -1)

echo "${INITIAL_INVOICE_COUNT:-0}" > /tmp/initial_invoice_count.txt
echo "${INITIAL_SHIPMENT_COUNT:-0}" > /tmp/initial_shipment_count.txt

# 4. Prepare Browser
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin/sales/order/"

if ! pgrep -f firefox > /dev/null; then
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# 5. Handle Login if needed
WINDOW_TITLE=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "firefox\|mozilla" | head -1)
if echo "$WINDOW_TITLE" | grep -qi "admin" && ! echo "$WINDOW_TITLE" | grep -qi "dashboard"; then
    echo "Attempting login..."
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
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="