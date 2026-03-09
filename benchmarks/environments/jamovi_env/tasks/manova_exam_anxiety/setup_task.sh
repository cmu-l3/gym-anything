#!/bin/bash
set -e
echo "=== Setting up MANOVA Exam Anxiety task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure dependencies for ground truth calculation are present
# (Jamovi environment is Ubuntu-based)
if ! python3 -c "import pandas, scipy" 2>/dev/null; then
    echo "Installing python dependencies for ground truth calculation..."
    apt-get update && apt-get install -y python3-pandas python3-scipy || pip3 install pandas scipy
fi

# ==============================================================================
# Compute Ground Truth (MANOVA stats)
# We calculate the expected stats using Python to verify the agent's report later.
# ==============================================================================
mkdir -p /var/lib/jamovi_ground_truth

cat > /tmp/calc_ground_truth.py << 'PYEOF'
import pandas as pd
import numpy as np
from scipy import stats
import json

try:
    # Load Data
    df = pd.read_csv('/home/ga/Documents/Jamovi/ExamAnxiety.csv')
    
    # Filter only relevant columns and drop NAs if any
    dvs = ['Exam', 'Anxiety', 'Revise']
    iv = 'Gender'
    df = df[dvs + [iv]].dropna()
    
    # Organize data matrices
    groups = df[iv].unique()
    Y = df[dvs].values
    N = len(df)
    p = len(dvs)
    k = len(groups)
    
    # -------------------------------------------------------
    # 1. Univariate F-tests (One-way ANOVA for each DV)
    # -------------------------------------------------------
    univariate_results = {}
    for dv in dvs:
        group_data = [df[df[iv] == g][dv].values for g in groups]
        F, p_val = stats.f_oneway(*group_data)
        univariate_results[dv] = {"F": float(F), "p": float(p_val)}

    # -------------------------------------------------------
    # 2. Multivariate (Pillai's Trace)
    # Calculation via eigen decomposition of SSCP matrices
    # -------------------------------------------------------
    # Total Mean
    grand_mean = Y.mean(axis=0)
    
    # Total Sum of Squares and Cross Products (T)
    T = np.zeros((p, p))
    for i in range(N):
        diff = Y[i, :] - grand_mean
        T += np.outer(diff, diff)
        
    # Within-group SSCP (E) aka Residual
    E = np.zeros((p, p))
    for g in groups:
        sub_Y = df[df[iv] == g][dvs].values
        sub_mean = sub_Y.mean(axis=0)
        for i in range(len(sub_Y)):
            diff = sub_Y[i, :] - sub_mean
            E += np.outer(diff, diff)
            
    # Hypothesis SSCP (H) = T - E
    H = T - E
    
    # Pillai's Trace = trace(H * (H+E)^-1)
    # V = tr(H(H+E)^-1)
    HE_inv = np.linalg.inv(H + E)
    matrix_pillai = np.dot(H, HE_inv)
    pillai_trace = np.trace(matrix_pillai)
    
    # Approximate F for Pillai's
    # For s = min(p, k-1). Here k=2 (Male,Female), so s=1.
    # When s=1, Pillai's F is exact.
    s = min(p, k - 1)
    m = (abs(p - (k - 1)) - 1) / 2
    n_param = (N - k - p - 1) / 2
    
    df1 = s * (2 * m + s + 1)
    df2 = s * (2 * n_param + s + 1)
    
    # Standard formula
    # F = ( (2n + s + 1) / (2m + s + 1) ) * ( V / (s - V) )
    approx_F = ((2 * n_param + s + 1) / (2 * m + s + 1)) * (pillai_trace / (s - pillai_trace))
    
    # p-value
    p_multivariate = 1 - stats.f.cdf(approx_F, df1, df2)

    # -------------------------------------------------------
    # 3. Box's M (Simplified Check)
    # Box's M is complex to implement from scratch reliably 
    # without statsmodels.multivariate. 
    # We will just verify the agent reports a value.
    # -------------------------------------------------------

    result = {
        "pillai_trace": float(pillai_trace),
        "multivariate_F": float(approx_F),
        "multivariate_p": float(p_multivariate),
        "df1": int(df1),
        "df2": int(df2),
        "univariate": univariate_results
    }
    
    print(json.dumps(result, indent=2))
    
except Exception as e:
    print(json.dumps({"error": str(e)}))
PYEOF

python3 /tmp/calc_ground_truth.py > /var/lib/jamovi_ground_truth/manova_expected.json
chmod 644 /var/lib/jamovi_ground_truth/manova_expected.json
echo "Ground truth computed:"
cat /var/lib/jamovi_ground_truth/manova_expected.json

# ==============================================================================
# Launch Jamovi
# ==============================================================================
DATASET="/home/ga/Documents/Jamovi/ExamAnxiety.csv"

# Ensure dataset exists (it should be there from environment setup)
if [ ! -f "$DATASET" ]; then
    echo "ERROR: Dataset $DATASET not found!"
    exit 1
fi

echo "Launching Jamovi with dataset..."
# Use setsid to detach, passing arguments to the launcher script
su - ga -c "setsid /usr/local/bin/launch-jamovi '$DATASET' > /tmp/jamovi.log 2>&1 &"

# Wait for Jamovi to appear
echo "Waiting for Jamovi window..."
for i in {1..60}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ExamAnxiety"; then
        echo "Jamovi window detected"
        break
    fi
    sleep 1
done
sleep 5

# Maximize the window (finding it by the filename in title)
DISPLAY=:1 wmctrl -r "ExamAnxiety" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ExamAnxiety" 2>/dev/null || true

# Dismiss any potential first-run dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="