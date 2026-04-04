#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Scope Feature Request Task ==="

WORKSPACE_DIR="/home/ga/workspace/analytics_platform"

# Clean up if exists
if [ -d "$WORKSPACE_DIR" ]; then
    sudo rm -rf "$WORKSPACE_DIR"
fi

sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create project structure
sudo -u ga mkdir -p app/routes app/services app/templates tests

echo "Creating Python application files..."

# Create __init__.py files
sudo -u ga touch app/__init__.py
sudo -u ga touch app/routes/__init__.py

# Create models.py
cat > "$WORKSPACE_DIR/app/models.py" << 'EOF'
"""
Data models for analytics platform
"""
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()

class Dataset(db.Model):
    """Uploaded dataset metadata"""
    id = db.Column(db.Integer, primary_key=True)
    filename = db.Column(db.String(255), nullable=False)
    uploaded_at = db.Column(db.DateTime, nullable=False)
    user_id = db.Column(db.Integer, db.ForeignKey('user.id'))
    row_count = db.Column(db.Integer)
    
    data_points = db.relationship('DataPoint', backref='dataset', lazy=True)


class DataPoint(db.Model):
    """Individual data record from CSV"""
    id = db.Column(db.Integer, primary_key=True)
    timestamp = db.Column(db.DateTime, nullable=False)
    user_email = db.Column(db.String(255), nullable=False)
    value = db.Column(db.Float, nullable=False)
    category = db.Column(db.String(100))
    dataset_id = db.Column(db.Integer, db.ForeignKey('dataset.id'))
    
    def __repr__(self):
        return f'<DataPoint {self.id}: {self.user_email} @ {self.timestamp}>'


class User(db.Model):
    """Platform user"""
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False)
    name = db.Column(db.String(255))
    created_at = db.Column(db.DateTime, nullable=False)
    
    datasets = db.relationship('Dataset', backref='owner', lazy=True)
EOF

# Create csv_parser.py
cat > "$WORKSPACE_DIR/app/services/csv_parser.py" << 'EOF'
"""
CSV parsing service
Handles uploaded CSV files and converts to internal data format
"""
import csv
import io
from datetime import datetime

def parse_csv(file_content):
    """
    Parse CSV file content and return list of data dicts
    
    Args:
        file_content: String content of CSV file
        
    Returns:
        List of dicts with keys: timestamp, user_email, value, category
    """
    reader = csv.DictReader(io.StringIO(file_content))
    data = []
    
    for row_num, row in enumerate(reader, start=1):
        # TODO: Add validation here!
        # Currently just extracts fields with no checks
        data_point = {
            'timestamp': row.get('timestamp'),
            'user_email': row.get('email'),
            'value': row.get('value'),
            'category': row.get('category', 'uncategorized')
        }
        data.append(data_point)
    
    return data


def validate_csv_structure(file_content):
    """
    Basic structure validation (very minimal currently)
    """
    # TODO: Implement proper validation
    if not file_content or len(file_content) < 10:
        raise ValueError("File is empty or too small")
    
    return True
EOF

# Create upload.py route
cat > "$WORKSPACE_DIR/app/routes/upload.py" << 'EOF'
"""
File upload routes
"""
from flask import Blueprint, request, jsonify, render_template
from werkzeug.utils import secure_filename
from datetime import datetime
import logging

from app.services.csv_parser import parse_csv
from app.services.storage import save_dataset
from app.services.notifications import send_upload_notification

logger = logging.getLogger(__name__)

upload_bp = Blueprint('upload', __name__)


@upload_bp.route('/upload/csv', methods=['POST'])
def upload_csv():
    """
    Handle CSV file upload
    
    Expected: multipart/form-data with 'csv_file' field
    Returns: JSON with dataset_id and row count
    """
    if 'csv_file' not in request.files:
        return jsonify({'error': 'No file provided'}), 400
    
    file = request.files['csv_file']
    
    if file.filename == '':
        return jsonify({'error': 'Empty filename'}), 400
    
    if not file.filename.endswith('.csv'):
        return jsonify({'error': 'File must be CSV'}), 400
    
    try:
        # Read file content
        content = file.read().decode('utf-8')
        
        # Parse CSV (NO VALIDATION!)
        data = parse_csv(content)
        
        # Save to database
        dataset_id = save_dataset(
            data, 
            secure_filename(file.filename),
            request.user.id if hasattr(request, 'user') else None
        )
        
        # Send notification
        send_upload_notification(dataset_id, len(data))
        
        logger.info(f"CSV uploaded successfully: dataset_id={dataset_id}, rows={len(data)}")
        
        return jsonify({
            'success': True,
            'dataset_id': dataset_id,
            'rows': len(data),
            'message': 'File uploaded successfully'
        }), 200
        
    except Exception as e:
        logger.error(f"Upload failed: {str(e)}")
        return jsonify({'error': 'Upload failed', 'details': str(e)}), 500


@upload_bp.route('/upload', methods=['GET'])
def upload_form():
    """Render upload form"""
    return render_template('upload.html')
EOF

# Create storage.py
cat > "$WORKSPACE_DIR/app/services/storage.py" << 'EOF'
"""
Data storage service
"""
from app.models import db, Dataset, DataPoint
from datetime import datetime

def save_dataset(data_points, filename, user_id=None):
    """
    Save parsed data to database
    
    Args:
        data_points: List of data point dicts
        filename: Original filename
        user_id: Optional user ID
        
    Returns:
        dataset_id: ID of created dataset
    """
    # Create dataset record
    dataset = Dataset(
        filename=filename,
        uploaded_at=datetime.utcnow(),
        user_id=user_id,
        row_count=len(data_points)
    )
    db.session.add(dataset)
    db.session.flush()  # Get dataset ID
    
    # Create data point records
    for point_data in data_points:
        point = DataPoint(
            timestamp=datetime.fromisoformat(point_data['timestamp']),
            user_email=point_data['user_email'],
            value=float(point_data['value']),
            category=point_data.get('category'),
            dataset_id=dataset.id
        )
        db.session.add(point)
    
    db.session.commit()
    
    return dataset.id
EOF

# Create notifications.py
cat > "$WORKSPACE_DIR/app/services/notifications.py" << 'EOF'
"""
Notification service
"""
import logging

logger = logging.getLogger(__name__)

def send_upload_notification(dataset_id, row_count):
    """Send email notification about successful upload"""
    logger.info(f"Notification: Dataset {dataset_id} uploaded with {row_count} rows")
    # In real app, would send actual email
    pass
EOF

# Create api.py
cat > "$WORKSPACE_DIR/app/routes/api.py" << 'EOF'
"""
REST API routes for data access
"""
from flask import Blueprint, jsonify, request
from app.models import Dataset, DataPoint

api_bp = Blueprint('api', __name__)


@api_bp.route('/api/datasets', methods=['GET'])
def list_datasets():
    """List all datasets"""
    datasets = Dataset.query.all()
    return jsonify([{
        'id': d.id,
        'filename': d.filename,
        'uploaded_at': d.uploaded_at.isoformat(),
        'row_count': d.row_count
    } for d in datasets])


@api_bp.route('/api/datasets/<int:dataset_id>', methods=['GET'])
def get_dataset(dataset_id):
    """Get dataset details"""
    dataset = Dataset.query.get_or_404(dataset_id)
    data_points = DataPoint.query.filter_by(dataset_id=dataset_id).limit(100).all()
    
    return jsonify({
        'id': dataset.id,
        'filename': dataset.filename,
        'uploaded_at': dataset.uploaded_at.isoformat(),
        'row_count': dataset.row_count,
        'sample_data': [{
            'timestamp': dp.timestamp.isoformat(),
            'user_email': dp.user_email,
            'value': dp.value,
            'category': dp.category
        } for dp in data_points]
    })
EOF

# Create requirements.txt
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
Flask==2.3.0
Flask-SQLAlchemy==3.0.0
python-dotenv==1.0.0
gunicorn==21.0.0
psycopg2-binary==2.9.0
EOF

# Create config.py
cat > "$WORKSPACE_DIR/config.py" << 'EOF'
"""
Application configuration
"""
import os

class Config:
    SECRET_KEY = os.environ.get('SECRET_KEY', 'dev-secret-key')
    SQLALCHEMY_DATABASE_URI = os.environ.get('DATABASE_URL', 'postgresql://localhost/analytics')
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    MAX_CONTENT_LENGTH = 16 * 1024 * 1024  # 16MB max file size
EOF

# Create README.md
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# Analytics Platform

SaaS analytics platform with CSV data import functionality.

## Features
- CSV file upload
- Data visualization dashboard
- REST API for data access
- User management

## Architecture

The application follows a standard Flask structure:
- `app/models.py` - SQLAlchemy data models
- `app/routes/` - HTTP route handlers
- `app/services/` - Business logic services
- `app/templates/` - HTML templates

## CSV Import Flow

1. User uploads CSV via `/upload/csv` endpoint
2. `upload.py` receives file and calls `parse_csv()`
3. `csv_parser.py` reads CSV and extracts data
4. `storage.py` saves data to database
5. `notifications.py` sends confirmation email

**Current Issue**: No validation is performed on uploaded data!

## Setup
