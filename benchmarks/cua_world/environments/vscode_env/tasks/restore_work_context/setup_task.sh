#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Restore Work Context Task ==="

PROJECT_DIR="/home/ga/projects/user-auth-service"

# Clean up any existing project directory
sudo -u ga rm -rf "$PROJECT_DIR"
sudo -u ga mkdir -p "$PROJECT_DIR"

# Create project structure
sudo -u ga mkdir -p "$PROJECT_DIR/app/routes"
sudo -u ga mkdir -p "$PROJECT_DIR/app/services"
sudo -u ga mkdir -p "$PROJECT_DIR/app/models"
sudo -u ga mkdir -p "$PROJECT_DIR/app/utils"
sudo -u ga mkdir -p "$PROJECT_DIR/tests"

# Create target file 1: app/routes/auth.py
cat > "$PROJECT_DIR/app/routes/auth.py" << 'EOF'
from flask import Blueprint, request, jsonify
from app.services.email_service import send_password_reset_email
from app.models.user import User

auth_bp = Blueprint('auth', __name__)

@auth_bp.route('/login', methods=['POST'])
def login():
    """Handle user login"""
    email = request.json.get('email')
    password = request.json.get('password')
    
    user = User.query.filter_by(email=email).first()
    if user and user.check_password(password):
        return jsonify({'success': True, 'token': 'dummy_token'}), 200
    return jsonify({'error': 'Invalid credentials'}), 401

@auth_bp.route('/reset-password', methods=['POST'])
def request_password_reset():
    """Handle password reset request - INCOMPLETE"""
    email = request.json.get('email')
    # TODO: Finish implementing this function
    # Need to: generate token, send email, return response
    pass
EOF

# Create target file 2: app/services/email_service.py
cat > "$PROJECT_DIR/app/services/email_service.py" << 'EOF'
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
import os

def send_password_reset_email(user_email, reset_token):
    """Send password reset email with token"""
    # Email configuration
    smtp_server = os.getenv('SMTP_SERVER', 'smtp.gmail.com')
    smtp_port = int(os.getenv('SMTP_PORT', '587'))
    sender_email = os.getenv('SENDER_EMAIL', 'noreply@example.com')
    
    # Create email message
    message = MIMEMultipart('alternative')
    message['Subject'] = 'Password Reset Request'
    message['From'] = sender_email
    message['To'] = user_email
    
    # TODO: Implement email sending logic
    # HTML body with reset link
    html = f"""
    <html>
      <body>
        <p>Click the link below to reset your password:</p>
        <a href="https://example.com/reset/{reset_token}">Reset Password</a>
      </body>
    </html>
    """
    
    part = MIMEText(html, 'html')
    message.attach(part)
    
    # TODO: Connect to SMTP server and send
    pass
EOF

# Create target file 3: app/models/user.py
cat > "$PROJECT_DIR/app/models/user.py" << 'EOF'
from datetime import datetime
from werkzeug.security import generate_password_hash, check_password_hash
import secrets

class User:
    """User model for authentication"""
    
    def __init__(self, email, password_hash=None):
        self.email = email
        self.password_hash = password_hash
        self.created_at = datetime.utcnow()
        self.reset_token = None
        self.reset_token_expires = None
    
    def set_password(self, password):
        """Hash and set user password"""
        self.password_hash = generate_password_hash(password)
    
    def check_password(self, password):
        """Verify password against hash"""
        return check_password_hash(self.password_hash, password)
    
    def generate_reset_token(self):
        """Generate password reset token"""
        # TODO: Add password reset token methods
        self.reset_token = secrets.token_urlsafe(32)
        return self.reset_token
    
    def verify_reset_token(self, token):
        """Verify reset token is valid"""
        # TODO: Implement token verification
        pass
EOF

# Create additional project files for realism
cat > "$PROJECT_DIR/app/__init__.py" << 'EOF'
from flask import Flask

def create_app():
    app = Flask(__name__)
    app.config['SECRET_KEY'] = 'dev-secret-key'
    
    from app.routes.auth import auth_bp
    app.register_blueprint(auth_bp, url_prefix='/auth')
    
    return app
EOF

cat > "$PROJECT_DIR/app/routes/__init__.py" << 'EOF'
# Routes package
EOF

cat > "$PROJECT_DIR/app/services/__init__.py" << 'EOF'
# Services package
EOF

cat > "$PROJECT_DIR/app/models/__init__.py" << 'EOF'
# Models package
EOF

cat > "$PROJECT_DIR/app/routes/users.py" << 'EOF'
from flask import Blueprint, jsonify

users_bp = Blueprint('users', __name__)

@users_bp.route('/profile', methods=['GET'])
def get_profile():
    return jsonify({'user': 'profile_data'}), 200
EOF

cat > "$PROJECT_DIR/app/services/token_service.py" << 'EOF'
import jwt
import os
from datetime import datetime, timedelta

def generate_auth_token(user_id):
    """Generate JWT auth token"""
    secret = os.getenv('JWT_SECRET', 'secret')
    payload = {
        'user_id': user_id,
        'exp': datetime.utcnow() + timedelta(days=1)
    }
    return jwt.encode(payload, secret, algorithm='HS256')
EOF

cat > "$PROJECT_DIR/app/models/session.py" << 'EOF'
from datetime import datetime

class Session:
    """User session model"""
    def __init__(self, user_id, token):
        self.user_id = user_id
        self.token = token
        self.created_at = datetime.utcnow()
EOF

cat > "$PROJECT_DIR/app/utils/validators.py" << 'EOF'
import re

def validate_email(email):
    """Validate email format"""
    pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
    return re.match(pattern, email) is not None

def validate_password_strength(password):
    """Check password meets minimum requirements"""
    if len(password) < 8:
        return False
    if not re.search(r'[A-Z]', password):
        return False
    if not re.search(r'[a-z]', password):
        return False
    if not re.search(r'[0-9]', password):
        return False
    return True
EOF

cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
Flask==2.3.0
Werkzeug==2.3.0
PyJWT==2.8.0
python-dotenv==1.0.0
EOF

cat > "$PROJECT_DIR/config.py" << 'EOF'
import os

class Config:
    SECRET_KEY = os.getenv('SECRET_KEY', 'dev-secret-key')
    SQLALCHEMY_DATABASE_URI = os.getenv('DATABASE_URL', 'sqlite:///app.db')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    JWT_SECRET = os.getenv('JWT_SECRET', 'jwt-secret')
EOF

cat > "$PROJECT_DIR/README.md" << 'EOF'
# User Authentication Service

Flask-based authentication service with login, registration, and password reset functionality.

## Features

- User registration and login
- Password hashing with Werkzeug
- JWT token-based authentication
- Password reset via email
- Input validation

## Setup
