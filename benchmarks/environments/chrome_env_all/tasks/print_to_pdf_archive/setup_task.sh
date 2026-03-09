#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Print-to-PDF Archive Task Setup ==="
echo "Task: Print webpage receipt to PDF with headers/footers disabled"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the receipt HTML file
echo "Creating receipt HTML..."
RECEIPT_DIR="/home/ga/Documents"
mkdir -p "$RECEIPT_DIR"

cat > "$RECEIPT_DIR/order_confirmation.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Order Confirmation #ORD-2025-1847</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            max-width: 800px;
            margin: 40px auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 30px;
            text-align: center;
            border-radius: 8px 8px 0 0;
            margin: -40px -40px 30px -40px;
        }
        .header h1 {
            margin: 0;
            font-size: 28px;
        }
        .header p {
            margin: 10px 0 0 0;
            font-size: 16px;
            opacity: 0.9;
        }
        .section {
            margin: 25px 0;
        }
        .section-title {
            font-size: 18px;
            font-weight: 600;
            color: #333;
            margin-bottom: 15px;
            padding-bottom: 8px;
            border-bottom: 2px solid #667eea;
        }
        .info-row {
            display: flex;
            justify-content: space-between;
            padding: 12px 0;
            border-bottom: 1px solid #eee;
        }
        .info-row:last-child {
            border-bottom: none;
        }
        .info-label {
            color: #666;
            font-weight: 500;
        }
        .info-value {
            color: #333;
            font-weight: 600;
        }
        .items-table {
            width: 100%;
            border-collapse: collapse;
            margin: 15px 0;
        }
        .items-table th {
            background: #f8f9fa;
            padding: 12px;
            text-align: left;
            font-weight: 600;
            color: #333;
            border-bottom: 2px solid #dee2e6;
        }
        .items-table td {
            padding: 12px;
            border-bottom: 1px solid #eee;
        }
        .total-row {
            background: #f8f9fa;
            font-weight: 700;
            font-size: 18px;
        }
        .total-row td {
            padding: 15px 12px;
            border-bottom: none;
        }
        .notice {
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            padding: 15px;
            margin-top: 25px;
            border-radius: 4px;
        }
        .notice strong {
            color: #856404;
        }
        .footer {
            text-align: center;
            color: #666;
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #eee;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>✓ Order Confirmed</h1>
            <p>Thank you for your purchase!</p>
        </div>
        
        <div class="section">
            <div class="section-title">Order Information</div>
            <div class="info-row">
                <span class="info-label">Order Number:</span>
                <span class="info-value">ORD-2025-1847</span>
            </div>
            <div class="info-row">
                <span class="info-label">Order Date:</span>
                <span class="info-value">January 15, 2025</span>
            </div>
            <div class="info-row">
                <span class="info-label">Customer Name:</span>
                <span class="info-value">Sarah Johnson</span>
            </div>
            <div class="info-row">
                <span class="info-label">Email:</span>
                <span class="info-value">sarah.johnson@email.com</span>
            </div>
            <div class="info-row">
                <span class="info-label">Payment Method:</span>
                <span class="info-value">Visa ending in 4532</span>
            </div>
        </div>
        
        <div class="section">
            <div class="section-title">Items Ordered</div>
            <table class="items-table">
                <thead>
                    <tr>
                        <th>Item Description</th>
                        <th style="text-align: center;">Qty</th>
                        <th style="text-align: right;">Unit Price</th>
                        <th style="text-align: right;">Total</th>
                    </tr>
                </thead>
                <tbody>
                    <tr>
                        <td>Wireless Bluetooth Headphones - Premium Noise Cancelling</td>
                        <td style="text-align: center;">1</td>
                        <td style="text-align: right;">$129.99</td>
                        <td style="text-align: right;">$129.99</td>
                    </tr>
                    <tr>
                        <td>USB-C to HDMI Adapter Cable (6ft)</td>
                        <td style="text-align: center;">2</td>
                        <td style="text-align: right;">$18.99</td>
                        <td style="text-align: right;">$37.98</td>
                    </tr>
                    <tr>
                        <td>Laptop Stand - Adjustable Ergonomic Design</td>
                        <td style="text-align: center;">1</td>
                        <td style="text-align: right;">$45.50</td>
                        <td style="text-align: right;">$45.50</td>
                    </tr>
                    <tr>
                        <td>Wireless Mouse - Optical with Side Buttons</td>
                        <td style="text-align: center;">1</td>
                        <td style="text-align: right;">$24.99</td>
                        <td style="text-align: right;">$24.99</td>
                    </tr>
                    <tr>
                        <td colspan="3" style="text-align: right; font-weight: 600;">Subtotal:</td>
                        <td style="text-align: right; font-weight: 600;">$238.46</td>
                    </tr>
                    <tr>
                        <td colspan="3" style="text-align: right;">Shipping & Handling:</td>
                        <td style="text-align: right;">$8.95</td>
                    </tr>
                    <tr>
                        <td colspan="3" style="text-align: right;">Tax (8.5%):</td>
                        <td style="text-align: right;">$20.27</td>
                    </tr>
                    <tr class="total-row">
                        <td colspan="3" style="text-align: right;">ORDER TOTAL:</td>
                        <td style="text-align: right;">$267.68</td>
                    </tr>
                </tbody>
            </table>
        </div>
        
        <div class="section">
            <div class="section-title">Shipping Address</div>
            <div class="info-row">
                <span class="info-value">
                    Sarah Johnson<br>
                    1428 Elm Street, Apt 5B<br>
                    Springfield, IL 62701<br>
                    United States
                </span>
            </div>
        </div>
        
        <div class="notice">
            <strong>Important:</strong> Please save this confirmation for your records. 
            Your order will be shipped within 2-3 business days. You will receive a 
            tracking number via email once your items have been dispatched.
        </div>
        
        <div class="footer">
            <p>Questions about your order? Contact us at support@example-store.com</p>
            <p>Order ID: ORD-2025-1847 | Transaction ID: TXN-89475-KL</p>
        </div>
    </div>
</body>
</html>
EOF

chown ga:ga "$RECEIPT_DIR/order_confirmation.html"
echo "✓ Receipt HTML created at: $RECEIPT_DIR/order_confirmation.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh about:blank" &
    sleep 5
else
    echo "Chrome is already running"
fi

# Wait for Chrome to be fully ready
sleep 2

# IMPORTANT: Click at center to select desktop (multi-desktop environments)
# This ensures we're on the first desktop where Chrome is running
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Chrome window using wmctrl
export DISPLAY=:1
wid=$(wmctrl -l | grep -i 'Google Chrome\|Chromium' | head -1 | awk '{print $1}')
if [ -z "$wid" ]; then
    echo "Warning: Could not find Chrome window"
else
    echo "Focusing Chrome window: $wid"
    wmctrl -i -a $wid || true
    sleep 1
fi

# Navigate to the receipt
RECEIPT_URL="file:///home/ga/Documents/order_confirmation.html"
echo "Navigating to: $RECEIPT_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/order_confirmation.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 3

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

echo "=== Setup complete ==="
echo "Chrome is displaying the order confirmation receipt"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+P to open print dialog"
echo "  2. Select 'Save as PDF' as destination"
echo "  3. Click 'More settings' to expand options"
echo "  4. DISABLE 'Headers and footers' toggle (CRITICAL)"
echo "  5. Click 'Save' to generate PDF"
echo ""
echo "The key requirement is DISABLING headers/footers to avoid URL/date artifacts"