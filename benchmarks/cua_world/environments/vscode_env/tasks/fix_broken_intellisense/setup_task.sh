#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Fix Broken IntelliSense Task ==="

WORKSPACE_DIR="/home/ga/workspace/ml_project"
VENV_DIR="$WORKSPACE_DIR/venv"

# Create workspace directory
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"

# Create Python virtual environment as user ga
echo "Creating Python virtual environment..."
sudo -u ga python3 -m venv "$VENV_DIR"

# Install required packages in venv
echo "Installing packages in virtual environment..."
sudo -u ga bash -c "source '$VENV_DIR/bin/activate' && pip install --quiet numpy pandas scikit-learn matplotlib"

# Verify packages were installed
echo "Verifying package installation..."
sudo -u ga bash -c "source '$VENV_DIR/bin/activate' && pip list | grep -E '(numpy|pandas|scikit)'" || echo "Warning: Package verification failed"

# Create Python files with imports that will show errors with wrong interpreter
cat > "$WORKSPACE_DIR/data_analysis.py" << 'EOF'
import numpy as np
import pandas as pd
from sklearn.linear_model import LinearRegression
import matplotlib.pyplot as plt

def load_data(filepath):
    """Load dataset from CSV file"""
    data = pd.read_csv(filepath)
    return data

def preprocess_data(df):
    """Clean and prepare data for modeling"""
    df = df.dropna()
    df = df.reset_index(drop=True)
    return df

def train_model(X, y):
    """Train linear regression model"""
    model = LinearRegression()
    model.fit(X, y)
    return model

def plot_results(y_true, y_pred):
    """Plot actual vs predicted values"""
    plt.figure(figsize=(10, 6))
    plt.scatter(y_true, y_pred, alpha=0.5)
    plt.xlabel('Actual Values')
    plt.ylabel('Predicted Values')
    plt.title('Model Predictions')
    plt.savefig('results.png')

if __name__ == "__main__":
    print("ML pipeline ready")
EOF

# Create a second file to make workspace more realistic
cat > "$WORKSPACE_DIR/utils.py" << 'EOF'
import numpy as np
from typing import List, Tuple

def calculate_statistics(data: np.ndarray) -> dict:
    """Calculate basic statistics for dataset"""
    return {
        'mean': np.mean(data),
        'std': np.std(data),
        'min': np.min(data),
        'max': np.max(data)
    }

def normalize_data(data: np.ndarray) -> np.ndarray:
    """Normalize data to 0-1 range"""
    return (data - np.min(data)) / (np.max(data) - np.min(data))
EOF

# Create .vscode directory with WRONG interpreter configuration (this is the bug)
sudo -u ga mkdir -p "$WORKSPACE_DIR/.vscode"

# Point to global Python instead of venv - THIS BREAKS INTELLISENSE
cat > "$WORKSPACE_DIR/.vscode/settings.json" << 'EOF'
{
    "python.defaultInterpreterPath": "/usr/bin/python3",
    "python.linting.enabled": true,
    "python.linting.pylintEnabled": false,
    "editor.fontSize": 14
}
EOF

# Set proper ownership
sudo chown -R ga:ga "$WORKSPACE_DIR"

# Ensure Python extension is installed (but with wrong interpreter, IntelliSense won't work)
echo "Ensuring Python extensions are installed..."
sudo -u ga bash -c "DISPLAY=:1 code --install-extension ms-python.python --force" 2>&1 || echo "Python extension may already be installed"
sudo -u ga bash -c "DISPLAY=:1 code --install-extension ms-python.vscode-pylance --force" 2>&1 || echo "Pylance extension may already be installed"

# Give extensions time to install
sleep 3

# Open VSCode with the workspace
echo "Opening VSCode with workspace..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/data_analysis.py' --reuse-window" &
wait_for_vscode 25
wait_for_window "Visual Studio Code" 35

# Click center to focus desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

# Focus VSCode window
focus_vscode_window
sleep 2

echo "=== Fix Broken IntelliSense Task Setup Complete ==="
echo ""
echo "🔴 PROBLEM: Python IntelliSense is broken!"
echo "   - Import statements show red errors"
echo "   - Autocomplete doesn't work"
echo "   - Go-to-definition fails"
echo "   - Code runs fine (packages are installed in venv)"
echo ""
echo "🎯 TASK: Fix IntelliSense by selecting correct Python interpreter"
echo ""
echo "📝 Instructions:"
echo "  1. Notice imports in data_analysis.py have red squiggly underlines"
echo "  2. Press Ctrl+Shift+P to open Command Palette"
echo "  3. Type: 'Python: Select Interpreter'"
echo "  4. Select the venv interpreter: ./venv/bin/python or ~/workspace/ml_project/venv/bin/python"
echo "  5. Reload window if needed: Ctrl+Shift+P → 'Developer: Reload Window'"
echo "  6. Verify imports no longer show errors"
echo ""
echo "📂 Workspace: $WORKSPACE_DIR"
echo "🐍 Virtual environment: $VENV_DIR"
echo "❌ Current interpreter (WRONG): /usr/bin/python3"
echo "✅ Correct interpreter: $VENV_DIR/bin/python"