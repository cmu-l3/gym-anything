#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Split-Editor Workflow Task ==="

WORKSPACE_DIR="/home/ga/workspace/contact_form"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create starter HTML file with old identifiers
cat > "$WORKSPACE_DIR/form.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Contact Form</title>
    <link rel="stylesheet" href="styles.css">
</head>
<body>
    <form class="old-form" action="#" method="POST">
        <h2>Contact Us</h2>
        <div class="form-group">
            <label for="name">Name:</label>
            <input type="text" id="name" name="name" placeholder="Your Name" required>
        </div>
        <div class="form-group">
            <label for="email">Email:</label>
            <input type="email" id="email" name="email" placeholder="your.email@example.com" required>
        </div>
        <div class="form-group">
            <label for="message">Message:</label>
            <textarea id="message" name="message" rows="4" placeholder="Your message..." required></textarea>
        </div>
        <button type="submit" id="oldSubmit">Send Message</button>
    </form>
    <script src="script.js"></script>
</body>
</html>
EOF

# Create minimal starter CSS file
cat > "$WORKSPACE_DIR/styles.css" << 'EOF'
/* TODO: Add styles for .contact-form and #submitBtn */
body {
    font-family: Arial, sans-serif;
    background-color: #f4f4f4;
    margin: 0;
    padding: 20px;
}

.form-group {
    margin-bottom: 15px;
}

label {
    display: block;
    margin-bottom: 5px;
    font-weight: bold;
}

input[type="text"],
input[type="email"],
textarea {
    width: 100%;
    padding: 8px;
    border: 1px solid #ddd;
    border-radius: 4px;
    box-sizing: border-box;
}
EOF

# Create starter JavaScript file with old identifier
cat > "$WORKSPACE_DIR/script.js" << 'EOF'
// Form validation script
// TODO: Update to use new button ID
document.addEventListener('DOMContentLoaded', function() {
    const submitButton = document.getElementById('oldSubmit');
    const form = document.querySelector('.old-form');
    
    if (submitButton) {
        submitButton.addEventListener('click', function(e) {
            e.preventDefault();
            
            // Simple validation
            const nameInput = document.getElementById('name');
            const emailInput = document.getElementById('email');
            const messageInput = document.getElementById('message');
            
            if (!nameInput.value.trim()) {
                alert('Please enter your name');
                return;
            }
            
            if (!emailInput.value.trim()) {
                alert('Please enter your email');
                return;
            }
            
            if (!messageInput.value.trim()) {
                alert('Please enter a message');
                return;
            }
            
            alert('Form submitted successfully!');
            form.reset();
        });
    }
});
EOF

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

echo "Created starter files with inconsistent naming:"
echo "  - form.html (class='old-form', id='oldSubmit')"
echo "  - styles.css (minimal styling, needs .contact-form and #submitBtn)"
echo "  - script.js (targets 'oldSubmit')"

# Open VSCode to the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Split-Editor Workflow Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Open all three files: form.html, styles.css, script.js"
echo "  2. Arrange in split-editor layout (View → Split Editor Right/Down)"
echo "  3. Update HTML: change 'old-form' → 'contact-form', 'oldSubmit' → 'submitBtn'"
echo "  4. Update CSS: add .contact-form, #submitBtn, #submitBtn:hover selectors"
echo "  5. Update JavaScript: change getElementById('oldSubmit') → getElementById('submitBtn')"
echo "  6. Save all files (Ctrl+S in each)"
echo ""
echo "Workspace: $WORKSPACE_DIR"