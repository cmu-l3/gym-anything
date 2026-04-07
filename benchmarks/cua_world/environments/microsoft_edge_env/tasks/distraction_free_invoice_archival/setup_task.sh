#!/bin/bash
# setup_task.sh - Pre-task hook for Distraction-Free Invoice Archival
# Installs dependencies, generates the messy invoice HTML, and launches Edge.

set -e

echo "=== Setting up Distraction-Free Invoice Archival task ==="

# 1. Install poppler-utils for pdftotext (used in export_result.sh for verification)
#    We do this in setup so it doesn't eat into task time/timeout
echo "Installing verification tools..."
sudo apt-get update -qq > /dev/null
sudo apt-get install -y -qq poppler-utils > /dev/null

# 2. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# 3. Create the "Messy" Invoice HTML
mkdir -p /workspace/assets
cat > /workspace/assets/vendor_invoice.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>Vendor Portal - Invoice #8492</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 0; background-color: #f4f4f4; }
        
        /* The Clutter - Agent must remove these */
        #marketing-banner {
            background-color: #ff4444; color: white; padding: 15px; text-align: center;
            font-weight: bold; font-size: 18px; border-bottom: 3px solid #cc0000;
        }
        #chat-widget {
            position: fixed; bottom: 20px; right: 20px; width: 200px; height: 50px;
            background-color: #0078d4; color: white; border-radius: 25px;
            display: flex; align-items: center; justify-content: center;
            box-shadow: 0 4px 8px rgba(0,0,0,0.2); cursor: pointer; z-index: 1000;
            font-weight: bold;
        }
        #cookie-consent {
            position: fixed; bottom: 0; left: 0; width: 100%; padding: 15px;
            background-color: #333; color: white; text-align: center; font-size: 14px;
            z-index: 999;
        }

        /* The Invoice (Target Content) */
        .container {
            max-width: 800px; margin: 40px auto; background: white; padding: 40px;
            box-shadow: 0 0 10px rgba(0,0,0,0.1); min-height: 800px;
        }
        .header { display: flex; justify-content: space-between; border-bottom: 2px solid #ddd; padding-bottom: 20px; margin-bottom: 20px; }
        .logo { font-size: 24px; font-weight: bold; color: #333; }
        .details { text-align: right; }
        table { width: 100%; border-collapse: collapse; margin-top: 30px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f9f9f9; }
        .total-row { font-weight: bold; font-size: 18px; }
        
        /* Print Styles - Intentionally broken to force manual cleanup */
        @media print {
            body { -webkit-print-color-adjust: exact; }
        }
    </style>
</head>
<body>

    <!-- OBSTRUCTION 1: Top Banner -->
    <div id="marketing-banner">
        FLASH SALE: 50% OFF RENEWALS! ENDS TONIGHT!
    </div>

    <div class="container">
        <div class="header">
            <div class="logo">Acme Cloud Services</div>
            <div class="details">
                <p><strong>Invoice #8492</strong></p>
                <p>Date: Oct 24, 2024</p>
                <p>Due: Upon Receipt</p>
            </div>
        </div>

        <div class="bill-to">
            <h3>Bill To:</h3>
            <p>Global Analytics Inc.</p>
            <p>123 Enterprise Way</p>
            <p>Seattle, WA 98101</p>
        </div>

        <table>
            <thead>
                <tr>
                    <th>Description</th>
                    <th>Quantity</th>
                    <th>Rate</th>
                    <th>Amount</th>
                </tr>
            </thead>
            <tbody>
                <tr>
                    <td>Enterprise Cloud Hosting (Oct)</td>
                    <td>1</td>
                    <td>$850.00</td>
                    <td>$850.00</td>
                </tr>
                <tr>
                    <td>Dedicated SQL Instance</td>
                    <td>1</td>
                    <td>$250.00</td>
                    <td>$250.00</td>
                </tr>
                <tr>
                    <td>Load Balancer Service</td>
                    <td>2</td>
                    <td>$45.00</td>
                    <td>$90.00</td>
                </tr>
                <tr>
                    <td>Premium Support SLA</td>
                    <td>1</td>
                    <td>$50.50</td>
                    <td>$50.50</td>
                </tr>
            </tbody>
            <tfoot>
                <tr class="total-row">
                    <td colspan="3" style="text-align: right;">Grand Total:</td>
                    <td>$1,240.50</td>
                </tr>
            </tfoot>
        </table>

        <div style="margin-top: 50px; font-size: 12px; color: #777;">
            <p>Thank you for your business. Please remit payment within 30 days.</p>
            <p>Questions? Contact billing@acmecloud.com</p>
        </div>
    </div>

    <!-- OBSTRUCTION 2: Chat Widget -->
    <div id="chat-widget">
        Need Help? Chat with Agent
    </div>

    <!-- OBSTRUCTION 3: Cookie Footer -->
    <div id="cookie-consent">
        We use cookies to improve your experience. <button>Accept</button>
    </div>

</body>
</html>
EOF

# 4. Clean up any previous attempts
rm -rf /home/ga/Documents/Invoices
pkill -f microsoft-edge || true

# 5. Launch Edge (Maximized)
echo "Launching Microsoft Edge..."
su - ga -c "DISPLAY=:1 microsoft-edge \
    --no-first-run \
    --no-default-browser-check \
    --disable-sync \
    --disable-features=TranslateUI \
    --start-maximized \
    about:blank > /dev/null 2>&1 &"

# Wait for Edge to start
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "Edge"; then
        echo "Edge started."
        break
    fi
    sleep 1
done

# Focus Edge
DISPLAY=:1 wmctrl -a "Edge" 2>/dev/null || true

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="