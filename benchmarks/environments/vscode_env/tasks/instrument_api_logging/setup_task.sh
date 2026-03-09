#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Instrument API Logging Task ==="

WORKSPACE_DIR="/home/ga/workspace/api_logging"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Install Flask if not already installed
echo "Installing Flask..."
sudo -u ga python3 -m pip install --user flask --quiet 2>&1 || true

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
flask==3.0.0
EOF

# Create initial Flask app with minimal logging
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
from flask import Flask, request, jsonify
import random

app = Flask(__name__)

# Minimal, inconsistent logging
@app.route('/api/payment', methods=['POST'])
def payment():
    data = request.get_json()
    user_id = data.get('user_id')
    amount = data.get('amount')
    payment_token = data.get('payment_token')
    
    # Simulate occasional errors
    if random.random() < 0.02:
        print(f"ERROR: Payment failed for user {user_id}")
        return jsonify({'error': 'Payment processing failed'}), 500
    
    print(f"Payment: user={user_id}, amount={amount}")
    return jsonify({'status': 'success', 'transaction_id': f'tx_{user_id}_001'})

@app.route('/api/balance', methods=['GET'])
def balance():
    user_id = request.args.get('user_id')
    
    # No logging at all
    balance_value = random.randint(100, 10000)
    return jsonify({'user_id': user_id, 'balance': balance_value})

@app.route('/api/transaction', methods=['GET'])
def transaction():
    transaction_id = request.args.get('transaction_id')
    
    if not transaction_id:
        # Inconsistent error logging
        return jsonify({'error': 'Missing transaction_id'}), 400
    
    return jsonify({
        'transaction_id': transaction_id,
        'status': 'completed',
        'amount': 99.99
    })

@app.route('/health', methods=['GET'])
def health():
    return jsonify({'status': 'healthy'})

if __name__ == '__main__':
    app.run(debug=True, port=5000)
EOF

# Create a test script (optional, for agent to test)
cat > "$WORKSPACE_DIR/test_api.sh" << 'EOF'
#!/bin/bash
# Test script to verify API endpoints work

echo "Testing /api/payment..."
curl -X POST http://localhost:5000/api/payment \
  -H "Content-Type: application/json" \
  -d '{"user_id": "user123", "amount": 50.00, "payment_token": "tok_secret123"}'
echo ""

echo "Testing /api/balance..."
curl "http://localhost:5000/api/balance?user_id=user123"
echo ""

echo "Testing /api/transaction..."
curl "http://localhost:5000/api/transaction?transaction_id=tx_user123_001"
echo ""
EOF

chmod +x "$WORKSPACE_DIR/test_api.sh"

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/app.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Instrument API Logging Task Setup Complete ==="
echo "📝 Task: Add comprehensive logging to the Flask API"
echo ""
echo "Requirements:"
echo "  1. Configure logging with formatters and handlers"
echo "  2. Add request ID middleware (before_request + after_request)"
echo "  3. Instrument at least 2 of 3 endpoints with logging"
echo "  4. Create and apply timing decorator"
echo "  5. Protect sensitive data (password, token, credit_card, api_key)"
echo "  6. Save all changes (Ctrl+S)"
echo ""
echo "Workspace: $WORKSPACE_DIR"
echo "Main file: $WORKSPACE_DIR/app.py"