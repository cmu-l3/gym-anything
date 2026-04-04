#!/bin/bash
# Setup script for local_s3_minio_integration task

echo "=== Setting up local_s3_minio_integration task ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Docker Desktop is running
if ! docker_desktop_running; then
    echo "Starting Docker Desktop..."
    su - ga -c "DISPLAY=:1 XDG_RUNTIME_DIR=/run/user/1000 /opt/docker-desktop/bin/docker-desktop > /tmp/docker-desktop.log 2>&1 &"
    sleep 10
fi

# Wait for Docker daemon
wait_for_docker_daemon 60

# Project setup
PROJECT_DIR="/home/ga/s3-project"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"

# 1. Create the Flask Application
cat > "$PROJECT_DIR/app.py" << 'PYEOF'
import os
import boto3
from flask import Flask, request, jsonify
from botocore.exceptions import NoCredentialsError, ClientError

app = Flask(__name__)

# Configuration
S3_ENDPOINT = os.environ.get('S3_ENDPOINT_URL')
ACCESS_KEY = os.environ.get('AWS_ACCESS_KEY_ID')
SECRET_KEY = os.environ.get('AWS_SECRET_ACCESS_KEY')
BUCKET_NAME = 'company-assets'

def get_s3_client():
    if not S3_ENDPOINT:
        # Default to AWS real endpoint (will fail without real creds)
        return boto3.client('s3')
    
    return boto3.client('s3',
        endpoint_url=S3_ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        region_name='us-east-1'
    )

@app.route('/')
def index():
    return f"S3 Uploader App. Target Bucket: {BUCKET_NAME}"

@app.route('/health')
def health():
    try:
        s3 = get_s3_client()
        # Just check if we can list buckets to verify connection
        s3.list_buckets()
        return jsonify({"status": "healthy", "s3_connection": "ok"})
    except Exception as e:
        return jsonify({"status": "unhealthy", "error": str(e)}), 500

@app.route('/upload', methods=['POST'])
def upload_file():
    if 'file' not in request.files:
        return jsonify({"error": "No file part"}), 400
    
    file = request.files['file']
    if file.filename == '':
        return jsonify({"error": "No selected file"}), 400

    try:
        s3 = get_s3_client()
        s3.upload_fileobj(file, BUCKET_NAME, file.filename)
        return jsonify({"message": f"Successfully uploaded {file.filename}"}), 200
    except ClientError as e:
        return jsonify({"error": str(e)}), 500
    except Exception as e:
        return jsonify({"error": f"Unexpected error: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
PYEOF

# 2. Create requirements.txt
cat > "$PROJECT_DIR/requirements.txt" << 'TXTEOF'
flask==3.0.0
boto3==1.34.0
TXTEOF

# 3. Create Dockerfile for Web App
cat > "$PROJECT_DIR/Dockerfile" << 'DOCKERFILE'
FROM python:3.9-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .
CMD ["python", "app.py"]
DOCKERFILE

# 4. Create initial (incomplete) docker-compose.yml
# Intentionally missing MinIO and env vars
cat > "$PROJECT_DIR/docker-compose.yml" << 'YMLEOF'
version: '3.8'

services:
  web:
    build: .
    ports:
      - "5000:5000"
    # TODO: Add environment variables for S3 connection
    # environment:
    #   - S3_ENDPOINT_URL=...
    
  # TODO: Add MinIO service here
  # TODO: Add mechanism to create 'company-assets' bucket on startup

YMLEOF

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Pre-pull images to save time
echo "Pre-pulling images..."
docker pull minio/minio:latest >/dev/null 2>&1 &
docker pull python:3.9-slim >/dev/null 2>&1 &
# Don't wait, let them pull in background

# Focus Docker Desktop window for the agent
focus_docker_desktop

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="