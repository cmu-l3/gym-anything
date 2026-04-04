#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up FastAPI Debug Configuration Task ==="

WORKSPACE_DIR="/home/ga/workspace/fastapi_project"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create FastAPI application
cat > "$WORKSPACE_DIR/app.py" << 'EOF'
from fastapi import FastAPI
import os
import argparse
import yaml

app = FastAPI()

@app.get("/")
def read_root():
    db_url = os.getenv("DATABASE_URL", "not_set")
    return {"message": "Hello FastAPI", "database": db_url}

@app.get("/health")
def health_check():
    return {"status": "healthy"}

@app.get("/debug")
def debug_endpoint():
    # Good location for breakpoint testing
    x = 42
    y = x * 2
    result = {"x": x, "y": y, "sum": x + y}
    return result

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="FastAPI Debug Demo")
    parser.add_argument("--config", required=True, help="Path to config file")
    parser.add_argument("--port", type=int, default=8000, help="Port to run on")
    args = parser.parse_args()
    
    # Load config
    with open(args.config, 'r') as f:
        config = yaml.safe_load(f)
    
    print(f"Loaded config: {config}")
    print(f"Running on port {args.port}")
    
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=args.port)
EOF

# Create config file
cat > "$WORKSPACE_DIR/config.yaml" << 'EOF'
app_name: "FastAPI Debug Demo"
environment: "development"
debug: true
log_level: "INFO"
EOF

# Create requirements
cat > "$WORKSPACE_DIR/requirements.txt" << 'EOF'
fastapi==0.104.1
uvicorn[standard]==0.24.0
pyyaml==6.0.1
EOF

# Create README with instructions
cat > "$WORKSPACE_DIR/README.md" << 'EOF'
# FastAPI Debug Demo

## Task
Create a debug configuration in `.vscode/launch.json` that allows debugging this FastAPI app.

## Requirements
- Configuration name: "FastAPI Debug"
- Environment variable: DATABASE_URL=postgresql://localhost/testdb
- Arguments: --config config.yaml --port 8080
- Python interpreter: .venv/bin/python

## How to create
1. Create `.vscode/` folder
2. Create `launch.json` file
3. Add debug configuration with all requirements above

You can use Command Palette (Ctrl+Shift+P) → "Debug: Open launch.json" for a template.
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Create virtual environment and install dependencies
echo "Creating virtual environment..."
cd "$WORKSPACE_DIR"
sudo -u ga python3 -m venv .venv
sudo -u ga bash -c "source .venv/bin/activate && pip install --quiet --upgrade pip && pip install --quiet -r requirements.txt"

echo "Virtual environment created and dependencies installed"

# Open VSCode with the workspace
echo "Opening VSCode..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

sleep 2
focus_vscode_window

# Open README to show instructions
sleep 2
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR/README.md'" || true
sleep 1

echo "=== FastAPI Debug Configuration Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create .vscode/launch.json in the workspace"
echo "  2. Add a debug configuration named 'FastAPI Debug'"
echo "  3. Include environment variable: DATABASE_URL=postgresql://localhost/testdb"
echo "  4. Include arguments: --config config.yaml --port 8080"
echo "  5. Set Python interpreter to .venv/bin/python"
echo ""
echo "Workspace: $WORKSPACE_DIR"