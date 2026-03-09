#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Form Recovery / Autofill Profile Setup Task ==="
echo "Task: Create comprehensive autofill profile to prevent form data loss"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Wait for environment to be ready
sleep 2

# Create test form HTML file for agent to optionally test autofill
echo "Creating test form HTML for autofill verification..."
FORM_DIR="/home/ga/Documents"
mkdir -p "$FORM_DIR"

cat > "$FORM_DIR/autofill_test_form.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Autofill Test Form</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
        }
        .form-container {
            background: white;
            padding: 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 10px;
        }
        .subtitle {
            color: #666;
            margin-bottom: 30px;
            font-size: 14px;
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            color: #555;
            font-weight: 500;
        }
        input {
            width: 100%;
            padding: 10px;
            border: 1px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
            box-sizing: border-box;
        }
        input:focus {
            outline: none;
            border-color: #4CAF50;
        }
        .form-row {
            display: grid;
            grid-template-columns: 1fr 1fr;
            gap: 15px;
        }
        button {
            background-color: #4CAF50;
            color: white;
            padding: 12px 30px;
            border: none;
            border-radius: 4px;
            font-size: 16px;
            cursor: pointer;
            margin-top: 10px;
        }
        button:hover {
            background-color: #45a049;
        }
        .info-box {
            background-color: #e3f2fd;
            border-left: 4px solid #2196F3;
            padding: 15px;
            margin-bottom: 20px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="form-container">
        <h1>Job Application Form</h1>
        <p class="subtitle">Please fill out all fields to complete your application</p>
        
        <div class="info-box">
            <strong>Note:</strong> This form demonstrates autofill functionality. 
            If you've set up Chrome autofill, click on any field to see suggestions.
        </div>

        <form id="applicationForm">
            <div class="form-group">
                <label for="firstName">First Name *</label>
                <input type="text" id="firstName" name="given-name" 
                       autocomplete="given-name" required placeholder="John">
            </div>

            <div class="form-group">
                <label for="lastName">Last Name *</label>
                <input type="text" id="lastName" name="family-name" 
                       autocomplete="family-name" required placeholder="Smith">
            </div>

            <div class="form-group">
                <label for="email">Email Address *</label>
                <input type="email" id="email" name="email" 
                       autocomplete="email" required placeholder="john.smith@example.com">
            </div>

            <div class="form-group">
                <label for="phone">Phone Number *</label>
                <input type="tel" id="phone" name="tel" 
                       autocomplete="tel" required placeholder="(555) 123-4567">
            </div>

            <div class="form-group">
                <label for="address">Street Address *</label>
                <input type="text" id="address" name="address-line1" 
                       autocomplete="address-line1" required placeholder="123 Main Street">
            </div>

            <div class="form-group">
                <label for="address2">Apartment, Suite, etc.</label>
                <input type="text" id="address2" name="address-line2" 
                       autocomplete="address-line2" placeholder="Apt 4B">
            </div>

            <div class="form-row">
                <div class="form-group">
                    <label for="city">City *</label>
                    <input type="text" id="city" name="address-level2" 
                           autocomplete="address-level2" required placeholder="Springfield">
                </div>

                <div class="form-group">
                    <label for="state">State *</label>
                    <input type="text" id="state" name="address-level1" 
                           autocomplete="address-level1" required placeholder="CA">
                </div>
            </div>

            <div class="form-row">
                <div class="form-group">
                    <label for="zip">ZIP Code *</label>
                    <input type="text" id="zip" name="postal-code" 
                           autocomplete="postal-code" required placeholder="90210">
                </div>

                <div class="form-group">
                    <label for="country">Country *</label>
                    <input type="text" id="country" name="country" 
                           autocomplete="country" required placeholder="United States">
                </div>
            </div>

            <div class="form-group">
                <label for="company">Company Name</label>
                <input type="text" id="company" name="organization" 
                       autocomplete="organization" placeholder="Acme Corporation">
            </div>

            <button type="submit">Submit Application</button>
        </form>
    </div>

    <script>
        document.getElementById('applicationForm').addEventListener('submit', function(e) {
            e.preventDefault();
            alert('Form submitted! In a real scenario, this data would be sent to the server.');
        });
    </script>
</body>
</html>
EOF

chown ga:ga "$FORM_DIR/autofill_test_form.html"
echo "✓ Test form created at: $FORM_DIR/autofill_test_form.html"

# Ensure Chrome is properly focused and ready
echo "Setting up Chrome for task..."

# Check if Chrome is running
if ! pgrep -f "chrome.*remote-debugging-port" > /dev/null; then
    echo "Chrome not running, starting it..."
    su - ga -c "DISPLAY=:1 /home/ga/launch_chrome.sh https://www.google.com" &
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

# Navigate to starting URL (Google as neutral starting point)
echo "Navigating to: https://www.google.com"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'https://www.google.com'" || true
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
echo ""
echo "SCENARIO: User spent 25 minutes filling out a job application form."
echo "Session timed out and all data was lost. User is frustrated!"
echo ""
echo "TASK: Set up Chrome autofill to prevent this from happening again."
echo ""
echo "Agent should:"
echo "  1. Navigate to chrome://settings/addresses (or Settings > Autofill and passwords > Addresses)"
echo "  2. Click 'Add' to create a new address/autofill profile"
echo "  3. Fill in comprehensive information:"
echo "     - Name (first, last)"
echo "     - Email address"
echo "     - Phone number"
echo "     - Street address, City, State, ZIP, Country"
echo "     - Optional: Company name"
echo "  4. Click 'Save' to store the profile"
echo "  5. Ensure 'Save and fill addresses' is enabled"
echo "  6. Optionally: Test by navigating to file:///home/ga/Documents/autofill_test_form.html"
echo ""
echo "This will prevent future form data loss by auto-filling forms with one click!"