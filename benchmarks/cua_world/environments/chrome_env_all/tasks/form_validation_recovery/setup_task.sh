#!/usr/bin/env bash
# set -euo pipefail

echo "=== Chrome Form Validation and Error Recovery Task Setup ==="
echo "Task: Trigger validation errors, observe feedback, correct errors, submit successfully"

# Install required utilities
# apt-get update -qq
# apt-get install -y -qq xdotool wmctrl curl jq python3 python3-pip || true

# Ensure Python HTTP server is available
pip3 install -q --upgrade pip 2>/dev/null || true

# Wait for environment to be ready
sleep 2

# Create the test form HTML file with validation
echo "Creating test form with validation..."
FORM_DIR="/home/ga/Documents/test_forms"
mkdir -p "$FORM_DIR"

cat > "$FORM_DIR/registration_form.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>User Registration Form</title>
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
        }
        .form-group {
            margin-bottom: 20px;
        }
        label {
            display: block;
            margin-bottom: 5px;
            color: #333;
            font-weight: bold;
        }
        input[type="text"],
        input[type="email"],
        input[type="tel"],
        input[type="password"] {
            width: 100%;
            padding: 10px;
            border: 2px solid #ddd;
            border-radius: 4px;
            font-size: 14px;
            box-sizing: border-box;
        }
        input.error {
            border-color: #d32f2f;
        }
        input.valid {
            border-color: #4caf50;
        }
        .error-message {
            color: #d32f2f;
            font-size: 12px;
            margin-top: 5px;
            display: none;
        }
        .error-message.show {
            display: block;
        }
        .hint {
            color: #666;
            font-size: 12px;
            margin-top: 3px;
        }
        button {
            background-color: #2196F3;
            color: white;
            padding: 12px 30px;
            border: none;
            border-radius: 4px;
            font-size: 16px;
            cursor: pointer;
            width: 100%;
            margin-top: 10px;
        }
        button:hover {
            background-color: #1976D2;
        }
        .required {
            color: #d32f2f;
        }
    </style>
</head>
<body>
    <div class="form-container">
        <h1>User Registration</h1>
        <p class="subtitle">Please fill out all required fields</p>
        
        <form id="registrationForm" novalidate>
            <div class="form-group">
                <label for="fullName">Full Name <span class="required">*</span></label>
                <input type="text" id="fullName" name="fullName" required>
                <div class="error-message" id="nameError">Please enter your full name (at least 3 characters)</div>
            </div>

            <div class="form-group">
                <label for="email">Email Address <span class="required">*</span></label>
                <input type="email" id="email" name="email" required>
                <div class="error-message" id="emailError">Please enter a valid email address (e.g., user@example.com)</div>
            </div>

            <div class="form-group">
                <label for="phone">Phone Number <span class="required">*</span></label>
                <input type="tel" id="phone" name="phone" required>
                <div class="hint">Format: (XXX) XXX-XXXX</div>
                <div class="error-message" id="phoneError">Please enter a valid phone number in format (XXX) XXX-XXXX</div>
            </div>

            <div class="form-group">
                <label for="password">Password <span class="required">*</span></label>
                <input type="password" id="password" name="password" required>
                <div class="hint">Must be at least 8 characters, include uppercase, lowercase, number, and special character</div>
                <div class="error-message" id="passwordError">Password must be at least 8 characters and contain uppercase, lowercase, number, and special character (!@#$%^&*)</div>
            </div>

            <button type="submit">Submit Registration</button>
        </form>
    </div>

    <script>
        const form = document.getElementById('registrationForm');
        const fullName = document.getElementById('fullName');
        const email = document.getElementById('email');
        const phone = document.getElementById('phone');
        const password = document.getElementById('password');

        // Validation functions
        function validateName(value) {
            return value.trim().length >= 3;
        }

        function validateEmail(value) {
            const emailRegex = /^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$/;
            return emailRegex.test(value);
        }

        function validatePhone(value) {
            const phoneRegex = /^\(\d{3}\)\s?\d{3}-\d{4}$/;
            return phoneRegex.test(value);
        }

        function validatePassword(value) {
            const minLength = value.length >= 8;
            const hasUpper = /[A-Z]/.test(value);
            const hasLower = /[a-z]/.test(value);
            const hasNumber = /[0-9]/.test(value);
            const hasSpecial = /[!@#$%^&*(),.?":{}|<>]/.test(value);
            return minLength && hasUpper && hasLower && hasNumber && hasSpecial;
        }

        function showError(input, errorElement) {
            input.classList.add('error');
            input.classList.remove('valid');
            errorElement.classList.add('show');
        }

        function clearError(input, errorElement) {
            input.classList.remove('error');
            input.classList.add('valid');
            errorElement.classList.remove('show');
        }

        function validateField(input, validator, errorElement) {
            if (validator(input.value)) {
                clearError(input, errorElement);
                return true;
            } else {
                showError(input, errorElement);
                return false;
            }
        }

        // Real-time validation on blur
        fullName.addEventListener('blur', () => {
            validateField(fullName, validateName, document.getElementById('nameError'));
        });

        email.addEventListener('blur', () => {
            validateField(email, validateEmail, document.getElementById('emailError'));
        });

        phone.addEventListener('blur', () => {
            validateField(phone, validatePhone, document.getElementById('phoneError'));
        });

        password.addEventListener('blur', () => {
            validateField(password, validatePassword, document.getElementById('passwordError'));
        });

        // Form submission
        form.addEventListener('submit', (e) => {
            e.preventDefault();

            // Validate all fields
            const nameValid = validateField(fullName, validateName, document.getElementById('nameError'));
            const emailValid = validateField(email, validateEmail, document.getElementById('emailError'));
            const phoneValid = validateField(phone, validatePhone, document.getElementById('phoneError'));
            const passwordValid = validateField(password, validatePassword, document.getElementById('passwordError'));

            // If all valid, redirect to success page
            if (nameValid && emailValid && phoneValid && passwordValid) {
                // Store submitted values in sessionStorage for verification
                sessionStorage.setItem('formSubmitted', 'true');
                sessionStorage.setItem('submittedEmail', email.value);
                sessionStorage.setItem('submittedPhone', phone.value);
                sessionStorage.setItem('submittedName', fullName.value);
                
                // Redirect to success page
                window.location.href = 'success.html';
            } else {
                // Scroll to first error
                const firstError = document.querySelector('.error');
                if (firstError) {
                    firstError.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            }
        });
    </script>
</body>
</html>
EOF

# Create success page
cat > "$FORM_DIR/success.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Registration Successful</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            max-width: 600px;
            margin: 50px auto;
            padding: 20px;
            background-color: #f5f5f5;
            text-align: center;
        }
        .success-container {
            background: white;
            padding: 50px 30px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }
        .success-icon {
            font-size: 64px;
            color: #4caf50;
            margin-bottom: 20px;
        }
        h1 {
            color: #4caf50;
            margin-bottom: 10px;
        }
        p {
            color: #666;
            font-size: 16px;
            line-height: 1.6;
        }
        .submitted-info {
            background: #f5f5f5;
            padding: 20px;
            margin-top: 30px;
            border-radius: 4px;
            text-align: left;
        }
        .info-label {
            font-weight: bold;
            color: #333;
        }
    </style>
</head>
<body>
    <div class="success-container" id="successContainer">
        <div class="success-icon">✓</div>
        <h1 id="successMessage">Registration Successful!</h1>
        <p>Thank you for completing the registration form. Your information has been submitted successfully.</p>
        <div class="submitted-info" id="submittedInfo"></div>
    </div>

    <script>
        // Display submitted information from sessionStorage
        const formSubmitted = sessionStorage.getItem('formSubmitted');
        if (formSubmitted === 'true') {
            const name = sessionStorage.getItem('submittedName');
            const email = sessionStorage.getItem('submittedEmail');
            const phone = sessionStorage.getItem('submittedPhone');
            
            const infoDiv = document.getElementById('submittedInfo');
            infoDiv.innerHTML = `
                <p><span class="info-label">Name:</span> ${name || 'N/A'}</p>
                <p><span class="info-label">Email:</span> ${email || 'N/A'}</p>
                <p><span class="info-label">Phone:</span> ${phone || 'N/A'}</p>
            `;
        }
    </script>
</body>
</html>
EOF

chown -R ga:ga "$FORM_DIR"
echo "✓ Test form created at: $FORM_DIR/registration_form.html"

# Start a simple HTTP server to serve the form (avoid file:// protocol issues)
echo "Starting HTTP server for form..."
pkill -f "python3.*http.server.*8765" || true
sleep 1

# Start HTTP server on port 8765 in background
su - ga -c "cd $FORM_DIR && nohup python3 -m http.server 8765 > /tmp/http_server.log 2>&1 &"
sleep 2

# Verify HTTP server is running
if curl -s http://localhost:8765/registration_form.html > /dev/null 2>&1; then
    echo "✓ HTTP server is running on port 8765"
else
    echo "⚠ Warning: HTTP server may not be responding"
fi

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

# Navigate to the test form
FORM_URL="http://localhost:8765/registration_form.html"
echo "Navigating to: $FORM_URL"
su - ga -c "DISPLAY=:1 xdotool search --class chrome | head -1 | xargs -I {} xdotool windowactivate --sync {}" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool key --clearmodifiers ctrl+l" || true
sleep 0.5
su - ga -c "DISPLAY=:1 xdotool type --clearmodifiers --delay 50 'http://localhost:8765/registration_form.html'" || true
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
echo "Chrome should be displaying the registration form"
echo "Agent should now:"
echo "  1. Fill form with INVALID data (e.g., bad email, short password)"
echo "  2. Click Submit and observe validation errors"
echo "  3. Correct each error based on error messages"
echo "  4. Submit again successfully"
echo "Expected validation rules:"
echo "  - Email: valid format (user@example.com)"
echo "  - Phone: (XXX) XXX-XXXX format"
echo "  - Password: 8+ chars, upper, lower, number, special char"
echo "  - Name: 3+ characters"