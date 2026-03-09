#!/bin/bash
# Setup script for Email Newsletter Campaign task

echo "=== Setting up Email Newsletter Campaign Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Record initial counts for anti-gaming
echo "Recording initial counts..."
INITIAL_TEMPLATE_COUNT=$(magento_query "SELECT COUNT(*) FROM newsletter_template" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")
INITIAL_SUBSCRIBER_COUNT=$(magento_query "SELECT COUNT(*) FROM newsletter_subscriber WHERE subscriber_status=1" 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

echo "$INITIAL_TEMPLATE_COUNT" > /tmp/initial_template_count
echo "$INITIAL_SUBSCRIBER_COUNT" > /tmp/initial_subscriber_count

# Seed the 5 required customers
echo "Seeding required customers..."
php -r "
use Magento\Framework\App\Bootstrap;
require '/var/www/html/magento/app/bootstrap.php';
$bootstrap = Bootstrap::create(BP, $_SERVER);
$obj = $bootstrap->getObjectManager();
$state = $obj->get('Magento\Framework\App\State');
$state->setAreaCode('frontend');

$customerRepo = $obj->get('Magento\Customer\Api\CustomerRepositoryInterface');
$customerFactory = $obj->get('Magento\Customer\Data\CustomerInterfaceFactory');
$encryptor = $obj->get('Magento\Framework\Encryption\EncryptorInterface');

$customers = [
    ['alice.johnson@example.com', 'Alice', 'Johnson'],
    ['bob.smith@example.com', 'Bob', 'Smith'],
    ['carol.williams@example.com', 'Carol', 'Williams'],
    ['david.brown@example.com', 'David', 'Brown'],
    ['emma.davis@example.com', 'Emma', 'Davis']
];

foreach ($customers as $data) {
    try {
        $customer = $customerFactory->create();
        $customer->setWebsiteId(1);
        $customer->setEmail($data[0]);
        $customer->setFirstname($data[1]);
        $customer->setLastname($data[2]);
        $customer = $customerRepo->save($customer, $encryptor->getHash('Customer123!', true));
        echo 'Created/Updated customer: ' . $data[0] . PHP_EOL;
    } catch (\Exception $e) {
        // Ignore if already exists, that's fine
        echo 'Customer exists or error: ' . $data[0] . PHP_EOL;
    }
}
" 2>/dev/null

# Ensure Firefox is running and logged in
echo "Ensuring Firefox is running..."
MAGENTO_ADMIN_URL="http://localhost/admin"

if ! pgrep -f firefox > /dev/null; then
    echo "Starting Firefox..."
    su - ga -c "DISPLAY=:1 firefox '$MAGENTO_ADMIN_URL' > /tmp/firefox_task.log 2>&1 &"
    sleep 8
fi

# Wait for Firefox window
if ! wait_for_window "firefox\|mozilla\|Magento" 30; then
    echo "WARNING: Firefox window not detected"
fi

# Focus Firefox window
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    focus_window "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
    sleep 2
fi

# Check login state
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
echo "Navigate to:"
echo "1. Stores > Configuration > Customers > Newsletter"
echo "2. Marketing > Communications > Newsletter Templates"
echo "3. Customers > All Customers"