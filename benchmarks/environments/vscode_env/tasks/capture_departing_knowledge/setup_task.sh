#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Capture Departing Knowledge Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_api"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create payment processor module with minimal comments
cat > "$WORKSPACE_DIR/payment_processor.py" << 'EOF'
import hashlib
import requests
from datetime import datetime, timedelta

GATEWAY_URL = "https://payments.example.com/api/v2"
TIMEOUT_SECONDS = 30

def process_payment(amount, currency, card_token, idempotency_key):
    if currency != "USD":
        amount = convert_currency(amount, currency, "USD")
    
    payload = {
        "amount_cents": int(amount * 100),
        "currency": "USD",
        "card_token": card_token,
        "idempotency_key": idempotency_key,
        "signature": generate_signature(amount, idempotency_key)
    }
    
    response = requests.post(
        f"{GATEWAY_URL}/charge",
        json=payload,
        timeout=TIMEOUT_SECONDS
    )
    
    if response.status_code == 429:
        return {"status": "retry_later", "retry_after": 60}
    
    return response.json()

def convert_currency(amount, from_curr, to_curr):
    rates = fetch_exchange_rates()
    return amount * rates.get(from_curr, 1.0) / rates.get(to_curr, 1.0)

def generate_signature(amount, idempotency_key):
    secret = get_secret_key()
    data = f"{amount}:{idempotency_key}:{secret}"
    return hashlib.sha256(data.encode()).hexdigest()

def fetch_exchange_rates():
    # Cached for 1 hour
    return {"USD": 1.0, "EUR": 0.85, "GBP": 0.73}

def get_secret_key():
    return "sk_live_1234567890abcdef"

def handle_webhook(payload, signature_header):
    expected_sig = generate_webhook_signature(payload)
    if signature_header != expected_sig:
        return {"error": "Invalid signature"}
    
    event_type = payload.get("type")
    if event_type == "payment.succeeded":
        update_order_status(payload["payment_id"], "paid")
    elif event_type == "payment.failed":
        notify_customer(payload["payment_id"], "failed")
    
    return {"status": "processed"}

def generate_webhook_signature(payload):
    secret = get_webhook_secret()
    return hashlib.sha256(f"{payload}:{secret}".encode()).hexdigest()

def get_webhook_secret():
    return "whsec_9876543210fedcba"

def update_order_status(payment_id, status):
    pass

def notify_customer(payment_id, status):
    pass
EOF

# Create knowledge transfer transcript
cat > "$WORKSPACE_DIR/knowledge_transfer.md" << 'EOF'
# Payment System Knowledge Transfer - Maya's Notes

## Critical Things You MUST Know

### The Idempotency Key Thing
The gateway requires idempotency keys, but here's the catch: they expire after 24 hours on THEIR end, but we cache them for 48 hours. This causes weird duplicate charge bugs if a customer retries a failed payment after 24 hours. We've never fixed it because it's rare and the fix is complex.

**TODO**: Implement idempotency key expiration after 23 hours

### Currency Conversion Gotcha
We ALWAYS convert to USD before sending to the gateway, even if the gateway supports the original currency. Why? Because we had a bug in 2021 where the gateway's EUR exchange rate was stale for 3 days and we lost $12k in margin. Converting ourselves gives us control.

**WARNING**: Never trust gateway currency conversion rates

### The 429 Retry Logic
When we get rate limited (429 status), we return `retry_later` with a 60-second delay. This is NOT what the gateway suggests - they say to use exponential backoff. But our frontend team hard-coded 60 seconds everywhere, so changing it would break the UI. Technical debt we live with.

### Webhook Signature Validation
The webhook signature validation is CRITICAL. We had a security incident in 2020 where someone spoofed webhooks. The current implementation is correct, but if you ever change it, GET SECURITY TO REVIEW.

The signature uses SHA256, not HMAC, because that's what the gateway v2 API uses. Gateway v3 (which we should migrate to) uses HMAC-SHA256.

### Exchange Rate Caching
Exchange rates are cached for 1 hour. This is a business decision - Finance wanted longer (lower API costs) but Product wanted shorter (more accurate). 1 hour was the compromise. Don't change without checking with both teams.

### Secret Key Management
Oh god, the secrets. I know they're hardcoded. We have a ticket to move them to environment variables (JIRA-4582) but it's been deprioritized for 18 months. The keys are also in the deployment configs, so it's not AS bad as it looks, but still not great.

### Related Files
- `webhook_handler.py` - Has the retry logic for failed webhooks
- `refund_logic.py` - Partial refunds have a completely different flow
- `fraud_checker.py` - Runs BEFORE payment processing, can block transactions

### External Resources
- Gateway API docs: https://docs.payments.example.com/v2
- Our runbook: https://wiki.company.com/payments
- On-call rotation: payments-oncall@company.com
- Gateway support: support@payments.example.com (response time: 4-6 hours)

### Common Issues
1. **Random 500 errors**: Gateway has intermittent issues on Wednesdays 2-3am PST for maintenance
2. **Webhook delays**: Can be delayed up to 30 minutes during high load
3. **Test cards**: Use 4242424242424242 for testing, but it behaves differently than real cards for 3DS
EOF

# Create minimal related files
cat > "$WORKSPACE_DIR/webhook_handler.py" << 'EOF'
def retry_failed_webhooks():
    # Stub implementation
    pass
EOF

cat > "$WORKSPACE_DIR/refund_logic.py" << 'EOF'
def process_refund(payment_id, amount):
    # Stub implementation
    pass
EOF

cat > "$WORKSPACE_DIR/fraud_checker.py" << 'EOF'
def check_fraud_score(card_token, amount):
    # Stub implementation
    return 0.0
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/knowledge_transfer.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Capture Departing Knowledge Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Read knowledge_transfer.md (currently open)"
echo "  2. Open payment_processor.py"
echo "  3. Add docstrings to functions (at least 5)"
echo "  4. Add inline comments explaining WHY (at least 8)"
echo "  5. Add WARNING comments (at least 2)"
echo "  6. Add TODO comments (at least 1)"
echo "  7. Create PAYMENT_SYSTEM_GUIDE.md with:"
echo "     - Common gotchas section"
echo "     - References to 3+ related files"
echo "     - External resource links"
echo "     - Contact/troubleshooting info"
echo "  8. Save all files (Ctrl+S)"