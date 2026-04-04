#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sanitize Hardcoded Secrets Task ==="

WORKSPACE_DIR="/home/ga/workspace/payment_service"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Python files with hardcoded secrets (INSECURE - for training purposes only!)
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
import os
from db_connector import get_db_connection
from payment_handler import process_payment

# Application configuration
STRIPE_API_KEY = "sk_live_51HxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxY"
DEBUG_MODE = True

def main():
    conn = get_db_connection()
    result = process_payment(amount=100.00, currency="usd")
    print(f"Payment processed: {result}")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/db_connector.py" << 'EOF'
import psycopg2

# Database credentials
DB_HOST = "prod-db.example.com"
DB_PORT = 5432
DB_NAME = "payments"
DB_USER = "admin"
DB_PASSWORD = "P@ssw0rd!2024_SecureDB_Prod"

def get_db_connection():
    """Establish database connection"""
    conn = psycopg2.connect(
        host=DB_HOST,
        port=DB_PORT,
        database=DB_NAME,
        user=DB_USER,
        password=DB_PASSWORD
    )
    return conn
EOF

cat > "$WORKSPACE_DIR/payment_handler.py" << 'EOF'
import boto3

# AWS Configuration for invoice storage
AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
AWS_REGION = "us-east-1"
S3_BUCKET = "payment-invoices-prod"

def process_payment(amount, currency):
    """Process payment and store invoice"""
    # Payment logic here
    s3_client = boto3.client(
        's3',
        aws_access_key_id=AWS_ACCESS_KEY_ID,
        aws_secret_access_key=AWS_SECRET_ACCESS_KEY,
        region_name=AWS_REGION
    )
    # Store invoice logic...
    return {"status": "success", "amount": amount}
EOF

cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
stripe==7.0.0
psycopg2-binary==2.9.9
boto3==1.34.0
python-dotenv==1.0.0
EOF

# Create .gitignore without .env (agent needs to add it)
cat > "$WORKSPACE_DIR/.gitignore" << 'EOF'
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.venv/
venv/
*.log
EOF

# Create a README to provide context
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Payment Service

## ⚠️ SECURITY ISSUE DETECTED

This codebase currently has **hardcoded production secrets** in the source files!

**Files with secrets:**
- `app.py` - Stripe API key
- `db_connector.py` - Database password
- `payment_handler.py` - AWS credentials

**Action required:** Move all secrets to `.env` file before committing to Git!
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Initialize Git repository
cd "$WORKSPACE_DIR"
sudo -u ga git init
sudo -u ga git config user.name "GA User"
sudo -u ga git config user.email "ga@localhost"
sudo -u ga git add .
sudo -u ga git commit -m "Initial commit with payment integration (contains secrets - DO NOT PUSH!)"

echo "⚠️  Git repository initialized with hardcoded secrets in commit!"

# Install python-dotenv in case it's not available
sudo -u ga pip3 install python-dotenv --quiet 2>/dev/null || true

# Open VSCode with the workspace and README visible
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/README.md'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Sanitize Hardcoded Secrets Task Setup Complete ==="
echo ""
echo "⚠️  CRITICAL SECURITY ISSUE ⚠️"
echo "Production secrets are hardcoded in source files!"
echo ""
echo "📝 Instructions:"
echo "  1. Use Search (Ctrl+Shift+F) to find all hardcoded secrets"
echo "  2. Create .env file with all secrets (4 total)"
echo "  3. Update source files to use os.getenv() instead of hardcoded values"
echo "  4. Add .env to .gitignore"
echo "  5. Verify no secrets are staged for commit"
echo ""
echo "Workspace: $WORKSPACE_DIR"