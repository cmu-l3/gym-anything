#!/bin/bash
set -e
echo "=== Setting up Docker Image Versioning Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Wait for Docker
wait_for_docker 60

PROJECT_DIR="/home/ga/projects/acme-payment-service"

# 1. Clean previous state
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

# 2. Initialize Git Repo with History
echo "Initializing git repository..."
git init
git config user.email "dev@acme.corp"
git config user.name "Acme Developer"
# Don't fail if branch rename fails (git version diffs)
git checkout -b main 2>/dev/null || true

# 3. Create Application Code (Crash on missing ENV)
cat > app.py << 'EOF'
import os
import sys
from flask import Flask, jsonify

app = Flask(__name__)

@app.route('/version')
def version():
    # These ENVs are required
    try:
        revision = os.environ['APP_REVISION']
        branch = os.environ.get('APP_BRANCH', 'unknown')
        build_date = os.environ['APP_BUILD_DATE']
    except KeyError as e:
        # App logic should handle this, but we crash if critical vars missing to prove the point
        return jsonify({"error": f"Missing env {str(e)}"}), 500
        
    return jsonify({
        "service": "payment-service",
        "revision": revision,
        "branch": branch,
        "build_date": build_date
    })

if __name__ == '__main__':
    # Startup check
    required = ['APP_REVISION', 'APP_BUILD_DATE', 'APP_BRANCH']
    missing = [v for v in required if v not in os.environ]
    if missing:
        print(f"CRITICAL: Missing environment variables: {', '.join(missing)}", file=sys.stderr)
        print("Application cannot start without version metadata.", file=sys.stderr)
        sys.exit(1)
        
    print("Version metadata found. Starting service...", file=sys.stderr)
    app.run(host='0.0.0.0', port=5000)
EOF

cat > requirements.txt << 'EOF'
flask==3.0.0
EOF

# 4. Create Naive Dockerfile
cat > Dockerfile << 'EOF'
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

# TODO: Add ARGs, ENVs, and LABELs here
# The application requires APP_REVISION, APP_BRANCH, and APP_BUILD_DATE

EXPOSE 5000
CMD ["python", "app.py"]
EOF

# 5. Create Naive Build Script
cat > build.sh << 'EOF'
#!/bin/bash
# TODO: Extract git info and pass as build args
echo "Building Acme Payment Service..."
docker build -t acme-payment:latest .
EOF
chmod +x build.sh

# 6. Commit to create valid git history
echo "flask==3.0.0" > requirements.txt
git add .
git commit -m "Initial commit: Service scaffolding"
git tag v0.1.0

# Add some history
echo "# update" >> app.py
git commit -am "Fix: minor bug in logic"
echo "# another update" >> app.py
git commit -am "Feat: added logging stub"

chown -R ga:ga "$PROJECT_DIR"

# 7. Record Task Start Time
date +%s > /tmp/task_start_time.txt
echo "Setup complete. Current HEAD: $(git rev-parse HEAD)"

# 8. Launch Terminal
su - ga -c "DISPLAY=:1 gnome-terminal --maximize -- bash -c 'cd $PROJECT_DIR && echo \"Task Ready: Fix the Docker build pipeline.\"; echo; ls -la; exec bash'" > /tmp/terminal.log 2>&1 &

sleep 3
take_screenshot /tmp/task_initial.png
echo "=== Setup complete ==="