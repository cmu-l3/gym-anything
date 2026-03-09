#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Feature Flag Implementation Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_app"
TASK_ASSETS="/workspace/tasks/implement_feature_flag/assets"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create assets directory if it doesn't exist
mkdir -p "$TASK_ASSETS"

# Create app.py
cat > "$TASK_ASSETS/app.py" << 'EOF'
"""
Flask payment application - needs feature flag implementation
"""
from flask import Flask, request, jsonify
import logging
from payment_processor import process_payment_legacy, process_payment_stripe

app = Flask(__name__)
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@app.route('/checkout', methods=['POST'])
def checkout():
    """
    Process checkout payment
    TODO: Implement feature flag to switch between legacy and Stripe payment processors
    """
    data = request.get_json()
    amount = data.get('amount', 0)
    
    # Currently only uses legacy processor
    # Need to implement feature flag logic here
    result = process_payment_legacy(amount)
    
    return jsonify(result)

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "healthy"})

if __name__ == '__main__':
    app.run(debug=True, port=5000)
EOF

# Create payment_processor.py
cat > "$TASK_ASSETS/payment_processor.py" << 'EOF'
"""
Payment processing functions
"""
import time

def process_payment_legacy(amount):
    """Legacy payment processor"""
    time.sleep(0.1)  # Simulate processing
    return {
        "success": True,
        "processor": "legacy",
        "amount": amount,
        "transaction_id": f"LEGACY-{int(time.time())}"
    }

def process_payment_stripe(amount):
    """New Stripe payment processor"""
    time.sleep(0.1)  # Simulate processing
    return {
        "success": True,
        "processor": "stripe",
        "amount": amount,
        "transaction_id": f"STRIPE-{int(time.time())}"
    }
EOF

# Create .env.example
cat > "$TASK_ASSETS/.env.example" << 'EOF'
# Environment variables template
# Copy to .env and configure

# Feature Flags
# USE_STRIPE_PAYMENT=false
EOF

# Create requirements.txt
cat > "$TASK_ASSETS/requirements.txt" << 'EOF'
flask==2.3.0
python-dotenv==1.0.0
EOF

# Copy files to workspace
sudo -u ga cp "$TASK_ASSETS/app.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/payment_processor.py" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/.env.example" "$WORKSPACE_DIR/"
sudo -u ga cp "$TASK_ASSETS/requirements.txt" "$WORKSPACE_DIR/"

# Set ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create a README for the task
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment App - Feature Flag Implementation

## Your Task

Implement a feature flag system to control the Stripe payment integration.

### Steps:
1. Create a `.env` file (copy from .env.example)
2. Add `USE_STRIPE_PAYMENT=false` to the .env file
3. Modify `app.py` to:
   - Load environment variables using python-dotenv
   - Read the USE_STRIPE_PAYMENT flag
   - Conditionally use Stripe or legacy processor based on flag
   - Add logging to track which processor is used

### Files:
- `app.py` - Main Flask application (MODIFY THIS)
- `payment_processor.py` - Payment functions (already implemented)
- `.env.example` - Environment template (COPY TO .env)
- `requirements.txt` - Dependencies (already available)

### Expected Result:
The /checkout endpoint should work with both payment processors depending on the feature flag value.
EOF

sudo chown ga:ga "$WORKSPACE_DIR/README.md"

# Ensure VSCode is running and open the workspace
echo "Opening VSCode workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' --new-window" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open relevant files in VSCode
sleep 2
echo "Opening task files..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/app.py'" 2>/dev/null &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/payment_processor.py'" 2>/dev/null &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/.env.example'" 2>/dev/null &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/README.md'" 2>/dev/null &

echo "=== Feature Flag Implementation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .env file with USE_STRIPE_PAYMENT variable"
echo "  2. Modify app.py to read environment variable"
echo "  3. Implement conditional logic in /checkout endpoint"
echo "  4. Add logging to track which processor is used"
echo "  5. Ensure both code paths work correctly"
echo ""
echo "📂 Workspace: $WORKSPACE_DIR"
echo "📄 Files to modify: app.py, .env (create new)"