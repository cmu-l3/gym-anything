#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Save Page as PDF Task Setup ==="
echo "Task: Save customer support chat webpage as PDF for record-keeping"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Install PDF processing libraries
pip3 install -q PyPDF2 pypdf pillow 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the sample support chat HTML file
echo "Creating sample customer support chat page..."
CONTENT_DIR="/home/ga/Documents"
mkdir -p "$CONTENT_DIR"

cat > "$CONTENT_DIR/support_chat_transcript.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Customer Support Chat Transcript - Reference #CS-2024-8472</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Arial, sans-serif;
            line-height: 1.6;
            max-width: 900px;
            margin: 0 auto;
            padding: 20px;
            background: #f5f5f5;
        }
        .container {
            background: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            padding: 30px;
        }
        .header {
            background: #1a73e8;
            color: white;
            padding: 20px;
            border-radius: 8px 8px 0 0;
            margin: -30px -30px 20px -30px;
        }
        .header h1 {
            margin: 0 0 10px 0;
            font-size: 24px;
        }
        .ref-number {
            font-size: 18px;
            font-weight: bold;
            color: #fff3cd;
            margin: 5px 0;
        }
        .metadata {
            color: #e8eaed;
            font-size: 14px;
        }
        .message {
            margin: 15px 0;
            padding: 15px;
            border-radius: 8px;
        }
        .customer {
            background: #e8f5e9;
            border-left: 4px solid #4caf50;
        }
        .agent {
            background: #e3f2fd;
            border-left: 4px solid #2196f3;
        }
        .timestamp {
            color: #666;
            font-size: 12px;
            margin-bottom: 5px;
        }
        .speaker {
            font-weight: bold;
            margin-bottom: 5px;
        }
        .highlight {
            background: #fff9c4;
            padding: 2px 4px;
            border-radius: 3px;
        }
        .warning-box {
            margin-top: 30px;
            padding: 15px;
            background: #fff3cd;
            border-left: 4px solid #ffc107;
            border-radius: 4px;
        }
        .warning-box strong {
            color: #856404;
        }
        .resolution-info {
            margin-top: 20px;
            padding: 15px;
            background: #d4edda;
            border-left: 4px solid #28a745;
            border-radius: 4px;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎧 Customer Support Chat Transcript</h1>
            <p class="ref-number">Reference Number: CS-2024-8472</p>
            <p class="metadata">Date: January 15, 2024 | Support Agent: Sarah Mitchell | Duration: 8 minutes</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:23:18</div>
            <div class="speaker">You (Customer):</div>
            <p>Hi, I need help urgently. I was charged twice for my last order #ORD-5839. My bank statement shows two charges of $47.99 on January 12th. This is causing an overdraft issue for me.</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:24:02</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>Hello! I'm very sorry to hear about the duplicate charge. I completely understand how frustrating this must be, especially with the overdraft concern. Let me pull up your account and investigate this right away.</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:25:47</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>Thank you for your patience. I've reviewed your account and order history. I can confirm that order #ORD-5839 placed on January 12th at 11:42 AM was indeed charged twice due to a payment processing error on our end. This was completely our mistake.</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:26:15</div>
            <div class="speaker">You (Customer):</div>
            <p>Okay, thank you for confirming that. How quickly can this be refunded? I really need this resolved ASAP because of the overdraft fees.</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:27:33</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>I'm processing a full refund of $47.99 for you right now. The refund has been submitted to your original payment method (Visa ending in 4892). You should typically see this reflected in <span class="highlight">3-5 business days</span>, though it may appear as early as tomorrow depending on your bank.</p>
            <p>Additionally, since this was our error and caused you inconvenience, I'm also applying a <span class="highlight">$15 courtesy credit</span> to your account that you can use on your next purchase.</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:28:09</div>
            <div class="speaker">You (Customer):</div>
            <p>That's great, thank you! Can I get a confirmation number for this refund? I want to have it saved in case I need to follow up with my bank about the overdraft fees.</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:29:21</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>Absolutely! Your refund confirmation details are:</p>
            <ul>
                <li><strong>Refund Confirmation Number:</strong> <span class="highlight">REF-2024-9382-A47</span></li>
                <li><strong>Refund Amount:</strong> $47.99</li>
                <li><strong>Original Transaction:</strong> ORD-5839</li>
                <li><strong>Refund Date Processed:</strong> January 15, 2024 at 14:29 EST</li>
                <li><strong>Expected Credit:</strong> January 18-20, 2024</li>
                <li><strong>Account Credit Applied:</strong> $15.00 (available immediately)</li>
            </ul>
            <p>I'm also sending you a confirmation email to your registered email address (j.smith@email.com) with all these details.</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:30:05</div>
            <div class="speaker">You (Customer):</div>
            <p>Perfect! If my bank charges me overdraft fees because of this, can you help with that too?</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:31:12</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>Yes, we can certainly help with that. If you do incur any overdraft fees directly related to this duplicate charge, please:</p>
            <ol>
                <li>Contact your bank first and request an overdraft fee waiver (many banks will waive it if you explain the situation)</li>
                <li>If they won't waive it, get documentation of the fee</li>
                <li>Reply to the confirmation email I'm sending you with that documentation</li>
                <li>Reference this case number: <span class="highlight">CS-2024-8472</span></li>
            </ol>
            <p>We'll reimburse you for any legitimate overdraft fees caused by our error, up to $35 per occurrence.</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:31:58</div>
            <div class="speaker">You (Customer):</div>
            <p>Thank you so much Sarah! You've been extremely helpful. I really appreciate you taking care of this so quickly.</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:32:34</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>You're very welcome! I'm glad I could help resolve this for you. Again, I sincerely apologize for the inconvenience this caused. If you have any questions or concerns when the refund processes, please don't hesitate to reach out. This chat transcript has been saved to your account, and you can access it anytime from your order history page.</p>
            <p>Is there anything else I can help you with today?</p>
        </div>

        <div class="message customer">
            <div class="timestamp">14:33:01</div>
            <div class="speaker">You (Customer):</div>
            <p>No, that's everything. Thanks again!</p>
        </div>

        <div class="message agent">
            <div class="timestamp">14:33:15</div>
            <div class="speaker">Sarah Mitchell (Support Agent):</div>
            <p>Wonderful! Have a great rest of your day! 😊</p>
        </div>

        <div class="resolution-info">
            <strong>✓ Issue Resolved</strong><br>
            Resolution: Duplicate charge refunded, courtesy credit applied, overdraft fee reimbursement process explained<br>
            Resolution Time: 8 minutes<br>
            Customer Satisfaction: Awaiting survey response
        </div>

        <div class="warning-box">
            <strong>⚠️ IMPORTANT:</strong> This chat transcript will be automatically deleted from our servers 30 days after the case is closed. 
            <strong>Please save this page as a PDF for your permanent records.</strong> You may need this documentation for:
            <ul style="margin: 10px 0 0 0;">
                <li>Dispute resolution with your bank</li>
                <li>Overdraft fee reimbursement claims</li>
                <li>Tax records or expense tracking</li>
                <li>Future reference if additional issues arise</li>
            </ul>
        </div>
    </div>

    <script>
        // Add print hint after page loads
        window.addEventListener('load', function() {
            console.log('Support chat transcript loaded. Save this page as PDF (Ctrl+P) for your records.');
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$CONTENT_DIR/support_chat_transcript.html"
echo "✓ Customer support chat page created at: $CONTENT_DIR/support_chat_transcript.html"

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

# Navigate to the support chat page
CHAT_URL="file:///home/ga/Documents/support_chat_transcript.html"
echo "Navigating to: $CHAT_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'file:///home/ga/Documents/support_chat_transcript.html'" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers Return" || true
sleep 4

# Final focus to ensure Chrome is active
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate {}" || true
sleep 1

# Verify Chrome is ready via CDP
if curl -s http://localhost:9222/json > /dev/null 2>&1; then
    echo "✓ Chrome CDP is accessible"
    # Verify the page loaded
    ACTIVE_URL=$(curl -s http://localhost:9222/json 2>/dev/null | jq -r '[.[] | select(.type == "page")][0].url // ""')
    if [[ "$ACTIVE_URL" == *"support_chat_transcript.html"* ]]; then
        echo "✓ Support chat page loaded successfully"
    else
        echo "⚠ Warning: Expected page not loaded. Current URL: $ACTIVE_URL"
    fi
else
    echo "⚠ Warning: Chrome CDP not responding"
fi

# Clear Downloads folder to ensure clean state
echo "Clearing Downloads folder for clean test..."
rm -f /home/ga/Downloads/*.pdf 2>/dev/null || true

echo "=== Setup complete ==="
echo "Chrome is displaying the customer support chat transcript"
echo ""
echo "Agent should now:"
echo "  1. Press Ctrl+P to open the print dialog"
echo "  2. Select 'Save as PDF' as the destination"
echo "  3. Click Save button"
echo "  4. Choose a descriptive filename (e.g., 'support_chat_CS-2024-8472' or similar)"
echo "  5. Save the PDF to the Downloads folder"
echo ""
echo "This simulates documenting an important support conversation for future reference."