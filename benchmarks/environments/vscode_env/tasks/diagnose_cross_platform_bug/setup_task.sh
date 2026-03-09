#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Diagnose Cross-Platform Bug Task ==="

WORKSPACE_DIR="/home/ga/workspace/webapp"
sudo -u ga mkdir -p "$WORKSPACE_DIR"/{static/css,templates,secrets}

echo "Creating Django project structure..."

# Create manage.py
cat > "$WORKSPACE_DIR/manage.py" << 'EOF'
#!/usr/bin/env python3
"""Django's command-line utility for administrative tasks."""
import os
import sys

if __name__ == "__main__":
    os.environ.setdefault("DJANGO_SETTINGS_MODULE", "settings")
    try:
        from django.core.management import execute_from_command_line
    except ImportError as exc:
        raise ImportError(
            "Couldn't import Django. Are you sure it's installed?"
        ) from exc
    execute_from_command_line(sys.argv)
EOF
chmod +x "$WORKSPACE_DIR/manage.py"

# Create models.py (lowercase filename - CORRECT)
cat > "$WORKSPACE_DIR/models.py" << 'EOF'
"""Database models for the webapp."""
from django.db import models

class User(models.Model):
    """User model representing registered users."""
    username = models.CharField(max_length=100)
    email = models.EmailField()
    created_at = models.DateTimeField(auto_now_add=True)
    is_active = models.BooleanField(default=True)
    
    def __str__(self):
        return self.username
    
    class Meta:
        ordering = ['-created_at']
        verbose_name = 'User'
        verbose_name_plural = 'Users'
EOF

# Create views.py with CASE MISMATCH BUG
cat > "$WORKSPACE_DIR/views.py" << 'EOF'
"""Views for the webapp."""
from django.shortcuts import render, get_object_or_404
from django.http import HttpResponse
from Models import User  # ❌ BUG: Should be lowercase 'models' (line 4)

def home(request):
    """Display home page with all users."""
    users = User.objects.all()
    return render(request, 'index.html', {'users': users})

def user_detail(request, user_id):
    """Display details for a specific user."""
    user = get_object_or_404(User, pk=user_id)
    return render(request, 'user_detail.html', {'user': user})

def about(request):
    """Display about page."""
    return render(request, 'about.html')
EOF

# Create settings.py with HARDCODED PATH BUG
cat > "$WORKSPACE_DIR/settings.py" << 'EOF'
"""Django settings for webapp project."""
import os

BASE_DIR = os.path.dirname(os.path.abspath(__file__))

# SECURITY WARNING: keep the secret key used in production secret!
# ❌ BUG: Hardcoded absolute path specific to Sam's Mac (line 9)
SECRET_KEY_FILE = '/Users/sam/workspace/webapp/secrets/django_secret.txt'
# Should be: SECRET_KEY_FILE = os.path.join(BASE_DIR, 'secrets', 'django_secret.txt')

try:
    with open(SECRET_KEY_FILE, 'r') as f:
        SECRET_KEY = f.read().strip()
except FileNotFoundError:
    SECRET_KEY = 'django-insecure-fallback-key-for-development'

# SECURITY WARNING: don't run with debug turned on in production!
DEBUG = True

ALLOWED_HOSTS = ['localhost', '127.0.0.1']

# Application definition
INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
]

ROOT_URLCONF = 'urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [os.path.join(BASE_DIR, 'templates')],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
            ],
        },
    },
]

# Static files (CSS, JavaScript, Images)
STATIC_URL = '/static/'
STATICFILES_DIRS = [os.path.join(BASE_DIR, 'static')]

# Database
DATABASES = {
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': os.path.join(BASE_DIR, 'db.sqlite3'),
    }
}
EOF

# Create urls.py
cat > "$WORKSPACE_DIR/urls.py" << 'EOF'
"""URL Configuration for webapp."""
from django.urls import path
from views import home, user_detail, about

urlpatterns = [
    path('', home, name='home'),
    path('user/<int:user_id>/', user_detail, name='user_detail'),
    path('about/', about, name='about'),
]
EOF

# Create utils.py (helper file)
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
"""Utility functions for the webapp."""
from datetime import datetime

def format_date(date):
    """Format date object to string."""
    return date.strftime('%Y-%m-%d %H:%M:%S')

def validate_email(email):
    """Basic email validation."""
    return '@' in email and '.' in email.split('@')[1]

def sanitize_username(username):
    """Remove special characters from username."""
    return ''.join(c for c in username if c.isalnum() or c in ['_', '-'])
EOF

# Create templates/index.html with CASE MISMATCH BUG in static path
cat > "$WORKSPACE_DIR/templates/index.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>User Dashboard - WebApp</title>
    <!-- ❌ BUG: Uses 'CSS' (uppercase) but actual directory is 'css' (lowercase) - line 7 -->
    <link rel="stylesheet" href="/static/CSS/main.css">
</head>
<body>
    <header class="main-header">
        <h1>User Dashboard</h1>
        <nav>
            <a href="/">Home</a>
            <a href="/about/">About</a>
        </nav>
    </header>
    <main class="content">
        <section class="user-list">
            <h2>Registered Users</h2>
            {% if users %}
                {% for user in users %}
                <div class="user-card">
                    <h3>{{ user.username }}</h3>
                    <p class="email">{{ user.email }}</p>
                    <p class="date">Joined: {{ user.created_at|date:"Y-m-d" }}</p>
                    <a href="/user/{{ user.id }}/" class="btn">View Profile</a>
                </div>
                {% endfor %}
            {% else %}
                <p class="no-users">No users registered yet.</p>
            {% endif %}
        </section>
    </main>
    <footer>
        <p>&copy; 2024 WebApp. All rights reserved.</p>
    </footer>
</body>
</html>
EOF

# Create templates/about.html
cat > "$WORKSPACE_DIR/templates/about.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <title>About - WebApp</title>
    <link rel="stylesheet" href="/static/css/main.css">
</head>
<body>
    <header class="main-header">
        <h1>About WebApp</h1>
        <nav>
            <a href="/">Home</a>
            <a href="/about/">About</a>
        </nav>
    </header>
    <main class="content">
        <h2>About This Application</h2>
        <p>This is a Django web application for managing users.</p>
    </main>
</body>
</html>
EOF

# Create static/css/main.css (lowercase directory - CORRECT)
cat > "$WORKSPACE_DIR/static/css/main.css" << 'EOF'
/* Main stylesheet for WebApp */

* {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
}

body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
    line-height: 1.6;
    color: #333;
    background-color: #f4f4f4;
    padding: 20px;
}

.main-header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 2rem;
    margin-bottom: 2rem;
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
}

.main-header h1 {
    margin-bottom: 1rem;
}

.main-header nav a {
    color: white;
    text-decoration: none;
    margin-right: 1.5rem;
    font-weight: 500;
    transition: opacity 0.3s;
}

.main-header nav a:hover {
    opacity: 0.8;
}

.content {
    max-width: 1200px;
    margin: 0 auto;
}

.user-list {
    background: white;
    padding: 2rem;
    border-radius: 8px;
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}

.user-card {
    background: #f9f9f9;
    padding: 1.5rem;
    margin: 1rem 0;
    border-radius: 6px;
    border-left: 4px solid #667eea;
    transition: transform 0.2s, box-shadow 0.2s;
}

.user-card:hover {
    transform: translateY(-2px);
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.15);
}

.user-card h3 {
    color: #667eea;
    margin-bottom: 0.5rem;
}

.user-card .email {
    color: #666;
    margin-bottom: 0.25rem;
}

.user-card .date {
    color: #999;
    font-size: 0.9rem;
    margin-bottom: 1rem;
}

.btn {
    display: inline-block;
    background: #667eea;
    color: white;
    padding: 0.5rem 1rem;
    text-decoration: none;
    border-radius: 4px;
    transition: background 0.3s;
}

.btn:hover {
    background: #5568d3;
}

.no-users {
    color: #666;
    font-style: italic;
}

footer {
    text-align: center;
    margin-top: 3rem;
    padding: 1rem;
    color: #666;
}
EOF

# Create secret file (so path would work if it wasn't hardcoded)
echo "django-insecure-s3cr3t-k3y-f0r-d3v3l0pm3nt-0nly-d0-n0t-us3-1n-pr0d" > "$WORKSPACE_DIR/secrets/django_secret.txt"

# Create README explaining the scenario
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Cross-Platform Bug Investigation Task

## 🐛 The Problem

This Django application works perfectly on Sam's MacBook Pro but crashes immediately on Jordan's Ubuntu machine with:
