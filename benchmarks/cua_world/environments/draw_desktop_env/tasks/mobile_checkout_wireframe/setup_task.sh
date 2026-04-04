#!/bin/bash
# Do NOT use set -e: draw.io startup commands may return non-zero

echo "=== Setting up mobile_checkout_wireframe task ==="

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

# Clean up any existing output files
rm -f /home/ga/Desktop/checkout_flow.drawio 2>/dev/null || true
rm -f /home/ga/Desktop/checkout_flow.png 2>/dev/null || true

# Create the Design Brief
cat > /home/ga/Desktop/design_brief.txt << 'EOF'
PROJECT: FreshCart Mobile App - Guest Checkout Flow
DATE: 2024-05-20
REQUESTED BY: Product Team

We need a low-fidelity wireframe for the new Guest Checkout flow. 
Please create a diagram with 3 screens showing the "Happy Path".

REQUIREMENTS:
1. Use a standard Smartphone frame for each screen (from Mockups or Mobile shape library).
2. Show the flow between screens using arrows.

SCREEN 1: "Your Cart"
- Header: "FreshCart"
- List Items:
  * "Gala Apples (3lb)" - $4.99
  * "Sourdough Bread" - $3.50
  * "Whole Milk" - $2.99
- Summary Section: "Total: $11.48"
- Primary Action: Button labeled "Proceed to Checkout"

SCREEN 2: "Payment Method"
- Header: "Secure Payment"
- Fields:
  * "Card Number" (placeholder text)
  * "Expiry Date"
  * "CVV"
- Section: "Delivery Address" (dropdown or text box)
- Primary Action: Button labeled "Pay Now"

SCREEN 3: "Order Success"
- Icon: A large checkmark or success circle
- Main Text: "Order Placed Successfully!"
- Subtext: "Arriving in 35-45 minutes"
- Primary Action: Button labeled "Track Order"
EOF

chown ga:ga /home/ga/Desktop/design_brief.txt
chmod 644 /home/ga/Desktop/design_brief.txt
echo "Design brief created at /home/ga/Desktop/design_brief.txt"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Launch draw.io (startup dialog will appear)
echo "Launching draw.io..."
su - ga -c "DISPLAY=:1 DRAWIO_DISABLE_UPDATE=true $DRAWIO_BIN --no-sandbox --disable-update > /tmp/drawio_mobile.log 2>&1 &"

# Wait for draw.io window
echo "Waiting for draw.io window..."
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "draw.io"; then
        echo "draw.io window detected after ${i} seconds"
        break
    fi
    sleep 1
done

sleep 5

# Maximize the window
DISPLAY=:1 wmctrl -r "draw.io" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss startup dialog (creates blank diagram)
echo "Dismissing startup dialog..."
DISPLAY=:1 xdotool key Escape
sleep 2

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="