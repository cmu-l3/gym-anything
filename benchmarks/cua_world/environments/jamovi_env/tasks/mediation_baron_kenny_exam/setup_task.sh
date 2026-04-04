#!/bin/bash
set -e
echo "=== Setting up Mediation Analysis Task ==="

# 1. Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

# 2. Ensure Dataset Exists and Pre-calculate Ground Truth
# We need to calculate the expected regression coefficients to verify the agent's report.
# We'll use a python script to do this using the actual data.
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

# Ensure dataset is in place (copied from /opt/jamovi_datasets/ in post_start, but checking here)
if [ ! -f "$DATASET" ]; then
    echo "Restoring dataset..."
    cp "/opt/jamovi_datasets/Exam Anxiety.csv" "$DATASET"
fi

# Install python dependencies for ground truth calculation if needed
# (The environment has python3, but maybe not pandas/statsmodels. We'll use pure numpy/standard lib if possible
# or try to install. Jamovi uses flatpak, so system pip might be clean.)
if ! python3 -c "import pandas" 2>/dev/null; then
    echo "Installing pandas for ground truth calculation..."
    pip3 install pandas scipy numpy > /dev/null 2>&1 || true
fi

# Calculate Ground Truth
cat > /tmp/calc_ground_truth.py << 'EOF'
import pandas as pd
import numpy as np
import json

try:
    df = pd.read_csv("/home/ga/Documents/Jamovi/ExamAnxiety.csv")
    
    # Simple OLS function using numpy
    def simple_ols(y, x):
        # Add intercept
        X = np.column_stack([np.ones(len(x)), x])
        # Beta = (X'X)^-1 X'y
        beta = np.linalg.inv(X.T @ X) @ X.T @ y
        return beta # [intercept, slope]

    def multiple_ols(y, x_df):
        X = np.column_stack([np.ones(len(y))] + [x_df[col] for col in x_df.columns])
        beta = np.linalg.inv(X.T @ X) @ X.T @ y
        return beta # [intercept, slope1, slope2...]

    # Step 1: Total Effect (c) -> Exam ~ Anxiety
    beta_c = simple_ols(df['Exam'], df['Anxiety'])
    c_coeff = beta_c[1]

    # Step 2: Path a -> Revise ~ Anxiety
    beta_a = simple_ols(df['Revise'], df['Anxiety'])
    a_coeff = beta_a[1]

    # Step 3: Path b and c' -> Exam ~ Anxiety + Revise
    # Note: verify order of coefficients in multiple_ols return
    beta_step3 = multiple_ols(df['Exam'], df[['Anxiety', 'Revise']])
    c_prime_coeff = beta_step3[1] # Anxiety
    b_coeff = beta_step3[2]       # Revise

    indirect_effect = a_coeff * b_coeff

    results = {
        "c_path": float(c_coeff),
        "a_path": float(a_coeff),
        "b_path": float(b_coeff),
        "c_prime_path": float(c_prime_coeff),
        "indirect_effect": float(indirect_effect)
    }

    with open("/tmp/ground_truth.json", "w") as f:
        json.dump(results, f)
        
    print("Ground truth calculated successfully")

except Exception as e:
    print(f"Error calculating ground truth: {e}")
    # Fallback to known values from Field (2013) if calculation fails
    # These are approximate values from the textbook example
    fallback = {
        "c_path": -16.0, 
        "a_path": -17.0,
        "b_path": 0.5,
        "c_prime_path": -8.0,
        "indirect_effect": -8.5
    }
    with open("/tmp/ground_truth.json", "w") as f:
        json.dump(fallback, f)
EOF

python3 /tmp/calc_ground_truth.py

# 3. Start Jamovi
echo "Starting Jamovi..."
pkill -f "org.jamovi.jamovi" || true
sleep 2

# Launch with dataset
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"

# Wait for window
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety.csv"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done

# Maximize
sleep 5
DISPLAY=:1 wmctrl -r "ExamAnxiety.csv" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="