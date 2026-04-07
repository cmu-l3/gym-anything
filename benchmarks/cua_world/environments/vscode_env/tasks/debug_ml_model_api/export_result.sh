#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Exporting ML Model API Result ==="

WORKSPACE_DIR="/home/ga/workspace/ml_api"
RESULT_FILE="/tmp/ml_api_result.json"

# Save open files in VSCode
focus_vscode_window 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+shift+s 2>/dev/null || true
sleep 1
safe_xdotool ga :1 key --delay 200 ctrl+k ctrl+s 2>/dev/null || true
sleep 2

take_screenshot /tmp/task_final.png

# Write a python script to run behavioral checks and static analysis
cat > /tmp/run_tests.py << 'EOF'
import sys
import json
import traceback
import ast
import os

os.chdir('/home/ga/workspace/ml_api')
sys.path.append("/home/ga/workspace/ml_api")

result = {
    "api_files": {},
    "bmi_float_preserved": False,
    "shape_correct": False,
    "preprocessing_correct": False,
    "model_loaded_globally": False,
    "errors": []
}

# 1. Export source files
for fpath in ["api/app.py", "api/schemas.py", "api/preprocessing.py"]:
    try:
        with open(f"/home/ga/workspace/ml_api/{fpath}") as f:
            result["api_files"][fpath] = f.read()
    except Exception as e:
        result["errors"].append(f"Failed to read {fpath}: {e}")

# 2. AST Check for Performance/Memory bug
try:
    app_code = result["api_files"].get("api/app.py", "")
    tree = ast.parse(app_code)
    has_load_inside = False
    
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef):
            is_route = False
            for dec in node.decorator_list:
                if isinstance(dec, ast.Call) and getattr(dec.func, 'attr', '') in ['post', 'get', 'put']:
                    is_route = True
            
            if is_route:
                for child in ast.walk(node):
                    if isinstance(child, ast.Call):
                        func_name = getattr(child.func, 'attr', getattr(child.func, 'id', ''))
                        if func_name in ['load', 'read_pickle']:
                            has_load_inside = True
                            
    result["model_loaded_globally"] = not has_load_inside
except Exception as e:
    result["errors"].append(f"AST check failed: {e}")

# 3. Behavioral Tests
try:
    from api.schemas import PatientRecord
    
    # Check BMI preservation
    patient = PatientRecord(age=40, bmi=29.9, blood_type="A", heart_rate=70)
    if isinstance(patient.bmi, float) and patient.bmi == 29.9:
        result["bmi_float_preserved"] = True
except Exception as e:
    result["errors"].append(f"Import schemas failed: {e}")

try:
    from fastapi.testclient import TestClient
    from api.app import app
    client = TestClient(app)
    
    # Known payload
    payload = {"age": 55, "bmi": 32.5, "blood_type": "B", "heart_rate": 88}
    
    # Calculate expected output using ground truth logic
    import joblib
    import pandas as pd
    model = joblib.load('/home/ga/workspace/ml_api/artifacts/model.pkl')
    scaler = joblib.load('/home/ga/workspace/ml_api/artifacts/scaler.pkl')
    
    df = pd.DataFrame([payload])
    df_encoded = pd.get_dummies(df, columns=['blood_type'])
    expected_cols = ['age', 'bmi', 'heart_rate', 'blood_type_A', 'blood_type_AB', 'blood_type_B', 'blood_type_O']
    for c in expected_cols:
        if c not in df_encoded.columns:
            df_encoded[c] = 0
    df_encoded = df_encoded[expected_cols]
    df_encoded[['age', 'bmi', 'heart_rate']] = scaler.transform(df_encoded[['age', 'bmi', 'heart_rate']])
    
    expected_prob = model.predict_proba(df_encoded)[0][1]
    
    # Query API
    resp = client.post("/predict", json=payload)
    if resp.status_code == 200:
        result["shape_correct"] = True  # It survived the shape error
        actual_prob = resp.json().get("probability", -1)
        
        # Float matching precision
        if abs(actual_prob - expected_prob) < 1e-4:
            result["preprocessing_correct"] = True
    else:
        result["errors"].append(f"API Error: {resp.text}")
        
except Exception as e:
    result["errors"].append(f"Behavioral test failed: {e}\n{traceback.format_exc()}")

with open("/tmp/ml_api_result.json", "w") as f:
    json.dump(result, f)
EOF

sudo -u ga python3 /tmp/run_tests.py

# Check modification timestamps
TASK_START=$(cat /tmp/task_start_time 2>/dev/null || echo "0")
APP_MTIME=$(stat -c %Y "$WORKSPACE_DIR/api/app.py" 2>/dev/null || echo 0)
PREP_MTIME=$(stat -c %Y "$WORKSPACE_DIR/api/preprocessing.py" 2>/dev/null || echo 0)
SCH_MTIME=$(stat -c %Y "$WORKSPACE_DIR/api/schemas.py" 2>/dev/null || echo 0)

MODIFIED="false"
if [ "$APP_MTIME" -gt "$TASK_START" ] || [ "$PREP_MTIME" -gt "$TASK_START" ] || [ "$SCH_MTIME" -gt "$TASK_START" ]; then
    MODIFIED="true"
fi

# Inject modified boolean into JSON
python3 -c "
import json
with open('/tmp/ml_api_result.json', 'r') as f:
    d = json.load(f)
d['files_modified'] = $MODIFIED == 'true'
with open('/tmp/ml_api_result.json', 'w') as f:
    json.dump(d, f)
"

echo "=== Export Complete ==="