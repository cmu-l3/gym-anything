#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debug ML Model API Task ==="

# Record task start time
date +%s > /tmp/task_start_time

# Install required packages
echo "Installing Python dependencies..."
sudo -u ga bash -c "pip3 install scikit-learn fastapi uvicorn httpx pytest pandas numpy joblib --no-warn-script-location"

# Setup Workspace
WORKSPACE_DIR="/home/ga/workspace/ml_api"
sudo -u ga mkdir -p "$WORKSPACE_DIR"
cd "$WORKSPACE_DIR"
sudo -u ga mkdir -p api artifacts data scripts tests

# ─────────────────────────────────────────────────────────────
# 1. Generate Dummy Data and Train Original Model
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/scripts/train_model.py" << 'PYEOF'
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import StandardScaler
import joblib
import os

# 1. Generate Dummy Data
np.random.seed(42)
n = 500
data = {
    'age': np.random.randint(20, 90, n),
    'bmi': np.random.uniform(18.0, 40.0, n),
    'blood_type': np.random.choice(['A', 'B', 'AB', 'O'], n),
    'heart_rate': np.random.randint(60, 110, n),
    'readmission': np.random.randint(0, 2, n)
}
df = pd.DataFrame(data)
df.to_csv('/home/ga/workspace/ml_api/data/patients.csv', index=False)

# 2. Preprocessing
# One-Hot Encode categorical feature
df_encoded = pd.get_dummies(df, columns=['blood_type'])

# Ensure exact column order for model
expected_cols = ['age', 'bmi', 'heart_rate', 'blood_type_A', 'blood_type_AB', 'blood_type_B', 'blood_type_O']
for c in expected_cols:
    if c not in df_encoded.columns:
        df_encoded[c] = 0
X = df_encoded[expected_cols]
y = df['readmission']

# Scale numerical features
scaler = StandardScaler()
X.loc[:, ['age', 'bmi', 'heart_rate']] = scaler.fit_transform(X[['age', 'bmi', 'heart_rate']])

# 3. Train Model
model = RandomForestClassifier(n_estimators=10, max_depth=3, random_state=42)
model.fit(X, y)

# 4. Save Artifacts
joblib.dump(model, '/home/ga/workspace/ml_api/artifacts/model.pkl')
joblib.dump(scaler, '/home/ga/workspace/ml_api/artifacts/scaler.pkl')
PYEOF

sudo -u ga python3 "$WORKSPACE_DIR/scripts/train_model.py"

# ─────────────────────────────────────────────────────────────
# 2. Write Buggy API Files
# ─────────────────────────────────────────────────────────────

cat > "$WORKSPACE_DIR/api/schemas.py" << 'PYEOF'
from pydantic import BaseModel

class PatientRecord(BaseModel):
    age: int
    bmi: int  # BUG 1: Truncates float values to integers
    blood_type: str
    heart_rate: int

class PredictionResponse(BaseModel):
    probability: float
    risk_class: int
PYEOF

cat > "$WORKSPACE_DIR/api/preprocessing.py" << 'PYEOF'
import numpy as np
import pandas as pd

def preprocess_payload(payload: dict) -> np.ndarray:
    """Convert API payload to numpy array for model prediction."""
    df = pd.DataFrame([payload])
    
    # Numeric features
    # BUG 3: Missing StandardScaler transformation entirely
    features_numeric = df[['age', 'bmi', 'heart_rate']].values[0]
    
    # Categorical feature
    # BUG 4: Uses arbitrary integer mapping instead of One-Hot Encoding
    blood_type_map = {'A': 0, 'B': 1, 'AB': 2, 'O': 3}
    bt_encoded = blood_type_map.get(df['blood_type'].iloc[0], 0)
    
    # Combine
    final_features = np.concatenate([features_numeric, [bt_encoded]])
    
    # BUG 2: Reshapes to a column vector instead of a row vector
    return final_features.reshape(-1, 1)
PYEOF

cat > "$WORKSPACE_DIR/api/app.py" << 'PYEOF'
from fastapi import FastAPI, HTTPException
import joblib
from api.schemas import PatientRecord, PredictionResponse
from api.preprocessing import preprocess_payload

app = FastAPI(title="Readmission Risk API")

@app.post("/predict", response_model=PredictionResponse)
def predict_risk(patient: PatientRecord):
    try:
        # BUG 5: Model loaded from disk on EVERY request (memory leak / slow)
        model = joblib.load('artifacts/model.pkl')
        
        # Preprocess
        X = preprocess_payload(patient.model_dump())
        
        # Predict
        prob = model.predict_proba(X)[0][1]
        risk_class = int(prob > 0.5)
        
        return PredictionResponse(probability=prob, risk_class=risk_class)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
PYEOF

# ─────────────────────────────────────────────────────────────
# 3. Write Test Suite
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/tests/test_api.py" << 'PYEOF'
from fastapi.testclient import TestClient
from api.app import app

client = TestClient(app)

def test_prediction_endpoint():
    payload = {
        "age": 65,
        "bmi": 28.5,
        "blood_type": "O",
        "heart_rate": 85
    }
    response = client.post("/predict", json=payload)
    assert response.status_code == 200, f"API failed: {response.text}"
    
    data = response.json()
    assert "probability" in data
    assert "risk_class" in data

def test_bmi_float_preservation():
    # BMI of 29.9 should not be truncated
    payload = {"age": 40, "bmi": 29.9, "blood_type": "A", "heart_rate": 70}
    response = client.post("/predict", json=payload)
    assert response.status_code == 200
PYEOF

chown -R ga:ga "$WORKSPACE_DIR"

# Launch VS Code
echo "Launching VS Code..."
su - ga -c "DISPLAY=:1 code $WORKSPACE_DIR"
sleep 5

# Focus and Maximize
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "Visual Studio Code" 2>/dev/null || true

# Take Initial Screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="