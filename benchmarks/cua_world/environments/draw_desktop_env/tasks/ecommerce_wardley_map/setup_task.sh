#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up ecommerce_wardley_map task ==="

# Find draw.io binary
DRAWIO_BIN=""
if command -v drawio &>/dev/null; then
    DRAWIO_BIN="drawio"
elif [ -f /opt/drawio/drawio ]; then
    DRAWIO_BIN="/opt/drawio/drawio"
elif [ -f /usr/bin/drawio ]; then
    DRAWIO_BIN="/usr/bin/drawio"
fi

if [ -z "$DRAWIO_BIN" ]; then
    echo "ERROR: draw.io binary not found!"
    exit 1
fi

# Clean up previous run
rm -f /home/ga/Desktop/marketplace_wardley_map.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/marketplace_wardley_map.png 2>/dev/null || true
rm -f /home/ga/Desktop/marketplace_strategy.txt 2>/dev/null || true

# Create the Strategy Document
cat > /home/ga/Desktop/marketplace_strategy.txt << 'EOF'
STRATEGIC ANALYSIS: ONLINE MARKETPLACE PLATFORM
===============================================

OBJECTIVE:
Map the current technology stack to identify build-vs-buy opportunities.

AXIS DEFINITIONS:
Y-Axis (Value Chain): Top = Visible to User; Bottom = Invisible/Infrastructure
X-Axis (Evolution): Genesis -> Custom Built -> Product (+rental) -> Commodity (+utility)

COMPONENT LIST & POSITIONING:

1. HIGH VISIBILITY (Direct User Interaction)
   - Customer (Anchor): Commodity (The market exists)
   - Buyer Experience (Web/Mobile App): Product (Standard interfaces)
   - Seller Experience (Portal): Product (Standard interfaces)

2. MID-HIGH VISIBILITY (Core Features)
   - Search & Discovery: Product (Standard search patterns)
   - Product Listings: Product (Standard catalog management)
   - Checkout Flow: Product (Standard cart/checkout)
   - Seller Dashboard: Custom Built (Unique analytics/workflow for our niche)
   - Ratings & Reviews: Product (Standard feature)

3. MID-LOW VISIBILITY (Backend Services)
   - Recommendation Engine: Custom Built (Our key differentiator)
   - Fraud Detection: Custom Built (Specific to our vertical's risks)
   - Order Management: Product (Standard OMS logic)
   - Payment Processing: Commodity (Stripe/PayPal - do not build)
   - Notification Service: Product (Email/SMS gateways)

4. LOW VISIBILITY (Infrastructure/Utilities)
   - Data Analytics: Product (Data warehouse tools)
   - Compute Infrastructure: Commodity (AWS EC2/Kubernetes)
   - Object Storage: Commodity (S3)
   - CDN (Content Delivery Network): Commodity (CloudFront)
   - Identity & Auth: Commodity (Auth0/Cognito)

DEPENDENCY MAP (A -> B means A depends on B):
   - Customer -> Buyer Experience
   - Customer -> Seller Experience
   - Buyer Experience -> Search & Discovery
   - Buyer Experience -> Checkout Flow
   - Buyer Experience -> Ratings & Reviews
   - Seller Experience -> Seller Dashboard
   - Seller Experience -> Product Listings
   - Search & Discovery -> Recommendation Engine
   - Search & Discovery -> Product Listings
   - Checkout Flow -> Payment Processing
   - Checkout Flow -> Order Management
   - Order Management -> Notification Service
   - Recommendation Engine -> Data Analytics
   - Fraud Detection -> Data Analytics
   - Fraud Detection -> Payment Processing
   - (All Mid-Tier Services) -> Compute Infrastructure
   - (All Mid-Tier Services) -> Identity & Auth
   - Product Listings -> Object Storage
   - Object Storage -> CDN

STRATEGIC MOVES (Recommendations):
1. Invest R&D in Recommendation Engine (Custom) to drive conversion.
2. Outsource Payment Processing and Identity to Utility providers (Commodity).
3. Migrate custom Seller Dashboard to standard components where possible to reduce maintenance.
EOF

chown ga:ga /home/ga/Desktop/marketplace_strategy.txt
chmod 644 /home/ga/Desktop/marketplace_strategy.txt

# Record start time
date +%s > /tmp/task_start_timestamp

# Launch draw.io
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_launch.log 2>&1 &"

# Wait for window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected"
        break
    fi
    sleep 1
done

sleep 5

# Maximize
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="