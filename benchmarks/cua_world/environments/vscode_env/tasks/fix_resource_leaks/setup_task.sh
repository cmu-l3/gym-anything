#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Resource Leaks Task ==="

WORKSPACE_DIR="/home/ga/workspace/flask_api"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create app.py with file logging leak
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
"""
Flask REST API - Main Application
Issue: File opened for logging but never closed
"""
from flask import Flask, request, jsonify
import os

app = Flask(__name__)

def setup_logging():
    """Initialize application logging"""
    log_dir = '/tmp/logs'
    os.makedirs(log_dir, exist_ok=True)
    
    # RESOURCE LEAK: File opened but never closed
    log_file = open(os.path.join(log_dir, 'app.log'), 'a')
    log_file.write('Application started\n')
    log_file.flush()
    # Missing: log_file.close() or using 'with' statement
    
    return True

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({'status': 'healthy'})

@app.route('/api/data', methods=['POST'])
def process_data():
    """Process incoming data"""
    data = request.json
    return jsonify({'received': len(data)})

if __name__ == '__main__':
    setup_logging()
    app.run(host='0.0.0.0', port=5000)
EOF

# Create db.py with connection leak in error path
cat > "$WORKSPACE_DIR/db.py" << 'EOF'
"""
Database Connection Handler
Issue: Connection not closed in error path
"""
import psycopg2
from psycopg2 import OperationalError

class DatabaseManager:
    def __init__(self, connection_string):
        self.connection_string = connection_string
    
    def execute_query(self, query, params=None):
        """
        Execute a database query
        RESOURCE LEAK: Connection not closed if query fails
        """
        # RESOURCE LEAK: Connection created but not properly cleaned up
        conn = psycopg2.connect(self.connection_string)
        cursor = conn.cursor()
        
        try:
            cursor.execute(query, params)
            results = cursor.fetchall()
            conn.commit()
            cursor.close()
            conn.close()  # Only closed in success path!
            return results
        except Exception as e:
            # ERROR PATH: Connection is NOT closed here!
            print(f"Query failed: {e}")
            raise
        # Missing: finally block with conn.close()
    
    def get_user_count(self):
        """Get total user count"""
        query = "SELECT COUNT(*) FROM users"
        result = self.execute_query(query)
        return result[0][0] if result else 0

def create_connection(db_name):
    """Create database connection - another potential leak"""
    connection_string = f"dbname={db_name} user=postgres password=secret"
    return DatabaseManager(connection_string)
EOF

# Create file_processor.py with temporary file leak
cat > "$WORKSPACE_DIR/file_processor.py" << 'EOF'
"""
File Upload Processor
Issue: Temporary file not closed after use
"""
import tempfile
import os
import hashlib

def validate_upload(file_data, max_size_mb=10):
    """
    Validate uploaded file
    RESOURCE LEAK: Temporary file opened but never closed
    """
    max_size = max_size_mb * 1024 * 1024
    
    if len(file_data) > max_size:
        return False, "File too large"
    
    # RESOURCE LEAK: Temporary file opened but not closed
    tmp = tempfile.NamedTemporaryFile(mode='wb', delete=False)
    tmp.write(file_data)
    tmp.flush()
    # Missing: tmp.close() or using 'with' statement
    
    # Calculate checksum
    file_hash = hashlib.sha256(file_data).hexdigest()
    
    # Clean up file (but file handle still open!)
    os.unlink(tmp.name)
    
    return True, file_hash

def process_uploaded_file(file_path):
    """Process an uploaded file"""
    with open(file_path, 'rb') as f:
        data = f.read()
    
    is_valid, result = validate_upload(data)
    return result

def save_upload(file_data, destination):
    """Save uploaded file to destination"""
    with open(destination, 'wb') as f:
        f.write(file_data)
    return True
EOF

# Create report_generator.py with HTTP response leak
cat > "$WORKSPACE_DIR/report_generator.py" << 'EOF'
"""
Report Generation Service
Issue: HTTP response stream not properly closed
"""
import requests
import json

def fetch_report_data(api_url):
    """
    Fetch data from external API for report generation
    RESOURCE LEAK: Response not closed
    """
    headers = {
        'Authorization': 'Bearer token123',
        'Content-Type': 'application/json'
    }
    
    # RESOURCE LEAK: Response object not closed
    response = requests.get(api_url, headers=headers, timeout=30)
    
    if response.status_code != 200:
        print(f"API request failed: {response.status_code}")
        return None
    
    data = response.json()
    # Missing: response.close() or using 'with' statement
    
    return data

def generate_pdf_report(report_id):
    """Generate PDF report from data"""
    api_url = f"https://api.example.com/reports/{report_id}"
    
    data = fetch_report_data(api_url)
    if not data:
        return None
    
    # Generate report (simplified)
    report = {
        'id': report_id,
        'data': data,
        'status': 'generated'
    }
    
    return report

def download_external_resource(url):
    """Download external resource"""
    # RESOURCE LEAK: Another response not closed
    resp = requests.get(url, stream=True)
    content = resp.content
    # Missing: resp.close()
    return content

def check_api_health(endpoint):
    """Check if external API is healthy"""
    try:
        # This one is also a leak!
        r = requests.get(endpoint, timeout=5)
        return r.status_code == 200
    except:
        return False
EOF

# Create backup.py with multiple file leaks in loop
cat > "$WORKSPACE_DIR/backup.py" << 'EOF'
"""
Backup Utility Script
Issue: Multiple files opened in loop without closing
"""
import os
import json
import shutil
from datetime import datetime

def backup_configuration_files(source_dir, backup_dir):
    """
    Backup configuration files
    RESOURCE LEAK: Files opened in loop but never closed
    """
    os.makedirs(backup_dir, exist_ok=True)
    
    config_files = ['config.json', 'settings.json', 'secrets.json']
    backup_manifest = []
    
    # RESOURCE LEAK: Multiple files opened without closing
    for config_file in config_files:
        source_path = os.path.join(source_dir, config_file)
        
        if os.path.exists(source_path):
            # LEAK: File opened but never closed
            f = open(source_path, 'r')
            content = f.read()
            # Missing: f.close()
            
            timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
            backup_filename = f"{config_file}.{timestamp}.bak"
            backup_path = os.path.join(backup_dir, backup_filename)
            
            # LEAK: Another file opened but never closed
            backup_file = open(backup_path, 'w')
            backup_file.write(content)
            backup_file.flush()
            # Missing: backup_file.close()
            
            backup_manifest.append({
                'original': config_file,
                'backup': backup_filename,
                'timestamp': timestamp
            })
    
    # Write manifest (this one also leaks!)
    manifest_path = os.path.join(backup_dir, 'manifest.json')
    manifest_file = open(manifest_path, 'w')
    json.dump(backup_manifest, manifest_file, indent=2)
    # Missing: manifest_file.close()
    
    return len(backup_manifest)

def restore_from_backup(backup_dir, target_dir):
    """Restore configuration from backup"""
    manifest_path = os.path.join(backup_dir, 'manifest.json')
    
    # This is correct - using 'with' statement
    with open(manifest_path, 'r') as f:
        manifest = json.load(f)
    
    for entry in manifest:
        backup_file = os.path.join(backup_dir, entry['backup'])
        target_file = os.path.join(target_dir, entry['original'])
        shutil.copy2(backup_file, target_file)
    
    return True
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create some dummy config files for backup.py context
sudo -u ga mkdir -p "$WORKSPACE_DIR/config_source"
echo '{"key": "value1"}' > "$WORKSPACE_DIR/config_source/config.json"
echo '{"setting": "value2"}' > "$WORKSPACE_DIR/config_source/settings.json"
echo '{"secret": "value3"}' > "$WORKSPACE_DIR/config_source/secrets.json"

# Open VSCode with the workspace
echo "Opening VSCode with Flask API project..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

echo "=== Fix Resource Leaks Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Use Find in Files (Ctrl+Shift+F) to search for: open(, requests.get(, psycopg2.connect("
echo "  2. Navigate to each file and identify resource leaks"
echo "  3. Refactor to use 'with' statements or add explicit .close() in finally blocks"
echo "  4. Fix at least 4 out of 5 leaks"
echo "  5. Save all files (Ctrl+K S)"
echo ""
echo "Files with leaks:"
echo "  - app.py (line ~23): File logging without close"
echo "  - db.py (line ~45): DB connection not closed in error path"
echo "  - file_processor.py (line ~67): Temporary file not closed"
echo "  - report_generator.py (line ~89): HTTP response not closed"
echo "  - backup.py (lines ~112-118): Multiple files in loop not closed"