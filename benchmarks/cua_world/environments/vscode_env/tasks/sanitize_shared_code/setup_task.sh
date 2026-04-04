#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Sanitize Shared Code Task ==="

WORKSPACE_DIR="/home/ga/workspace/flask_demo"
TASK_DIR="/workspace/tasks/sanitize_shared_code"

# Clean up any existing workspace
sudo rm -rf "$WORKSPACE_DIR"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create Flask app with embedded secrets
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
from flask import Flask, request
import psycopg2
import stripe
import boto3

app = Flask(__name__)

# Database connection - TODO: move to env vars
DB_PASSWORD = "MyS3cr3tP@ssw0rd2024!"
DATABASE_URL = f"postgresql://admin:{DB_PASSWORD}@localhost/mydb"

# Stripe API key for payments
stripe.api_key = "sk_live_51K7xYzIqPqHMN8vwxQ0hB3mY9"

# AWS credentials for S3 uploads
AWS_ACCESS_KEY = "AKIAIOSFODNN7EXAMPLE"
AWS_SECRET_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"

s3_client = boto3.client(
    's3',
    aws_access_key_id=AWS_ACCESS_KEY,
    aws_secret_access_key=AWS_SECRET_KEY
)

@app.route('/api/users')
def get_users():
    # Connect to database
    conn = psycopg2.connect(DATABASE_URL)
    cursor = conn.cursor()
    cursor.execute("SELECT * FROM users")
    return {"users": cursor.fetchall()}

@app.route('/api/charge', methods=['POST'])
def charge_card():
    amount = request.json.get('amount')
    # Create charge using Stripe
    charge = stripe.Charge.create(
        amount=amount,
        currency='usd',
        source=request.json.get('token')
    )
    return {"success": True, "charge_id": charge.id}

if __name__ == '__main__':
    app.run(debug=True)
EOF

# Create config file with more secrets
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
# Configuration file for Flask demo
# WARNING: Contains sensitive data - do NOT commit!

import os

class Config:
    SECRET_KEY = "flask-secret-key-change-in-production-xyz789"
    SQLALCHEMY_DATABASE_URI = "postgresql://admin:MyS3cr3tP@ssw0rd2024!@localhost/mydb"
    
    # External API keys
    STRIPE_PUBLIC_KEY = "pk_live_51K7xYzIqPqHMN8vwAbCdEfGh"
    STRIPE_SECRET_KEY = "sk_live_51K7xYzIqPqHMN8vwxQ0hB3mY9"
    
    # AWS for file uploads
    AWS_ACCESS_KEY_ID = "AKIAIOSFODNN7EXAMPLE"
    AWS_SECRET_ACCESS_KEY = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
    AWS_BUCKET_NAME = "my-production-bucket"
    
    # Email service (SendGrid)
    SENDGRID_API_KEY = "SG.xYz123AbC456DeF789.1234567890abcdefghijklmnopqrstuvwxyz"
    
    # JWT secret for authentication
    JWT_SECRET = "super-secret-jwt-token-12345"
EOF

# Create test file (developers often forget to sanitize these!)
cat > "$WORKSPACE_DIR/test_app.py" << 'EOF'
import unittest
from app import app

class TestApp(unittest.TestCase):
    def setUp(self):
        self.app = app.test_client()
        # Using production Stripe key for testing (bad practice!)
        # Key: sk_live_51K7xYzIqPqHMN8vwxQ0hB3mY9
    
    def test_users_endpoint(self):
        response = self.app.get('/api/users')
        self.assertEqual(response.status_code, 200)

if __name__ == '__main__':
    unittest.main()
EOF

# Create requirements file
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
Flask==2.3.0
psycopg2-binary==2.9.6
stripe==5.4.0
boto3==1.26.137
sendgrid==6.10.0
PyJWT==2.6.0
EOF

# Create README
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Flask Demo Application

A simple Flask app demonstrating payments and file uploads.

## Setup

1. Install dependencies: `pip install -r requirements.txt`
2. Configure environment variables (see config.py)
3. Run: `python app.py`

## Features

- User management with PostgreSQL
- Payment processing with Stripe
- File uploads to AWS S3
- Email notifications via SendGrid
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with workspace
echo "Opening VSCode with flask_demo workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open the main files for viewing
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/app.py'" &
sleep 1
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/config.py'" &
sleep 1

echo "=== Sanitize Shared Code Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Review app.py, config.py, test_app.py for hardcoded secrets"
echo "  2. Use Find and Replace (Ctrl+Shift+H) to replace ALL secrets with placeholders"
echo "  3. Secrets to remove:"
echo "     - Database password: MyS3cr3tP@ssw0rd2024!"
echo "     - Stripe keys (sk_live_*, pk_live_*)"
echo "     - AWS keys (AKIA*, wJalrXUtnFEMI*)"
echo "     - SendGrid key (SG.*)"
echo "     - Flask SECRET_KEY"
echo "     - JWT secret"
echo "  4. Create SECRETS_REMOVED.md documenting what you removed"
echo "  5. Ensure code syntax remains valid"
echo ""
echo "Workspace: $WORKSPACE_DIR"