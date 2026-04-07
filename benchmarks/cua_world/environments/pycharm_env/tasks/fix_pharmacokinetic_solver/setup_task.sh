#!/bin/bash
echo "=== Setting up fix_pharmacokinetic_solver ==="

# Source utility functions
. /workspace/scripts/task_utils.sh 2>/dev/null || true

TASK_NAME="fix_pharmacokinetic_solver"
PROJECT_DIR="/home/ga/PycharmProjects/pk_tools"

# Clean previous run
rm -rf "$PROJECT_DIR" 2>/dev/null || true
rm -f /tmp/${TASK_NAME}_* 2>/dev/null || true

# Record start time
date +%s > /tmp/task_start_time.txt

# Create project structure
mkdir -p "$PROJECT_DIR/pk_tools"
mkdir -p "$PROJECT_DIR/tests"
mkdir -p "$PROJECT_DIR/data"
mkdir -p "$PROJECT_DIR/output"

# --- 1. Requirements ---
cat > "$PROJECT_DIR/requirements.txt" << 'EOF'
numpy>=1.24.0
pandas>=2.0.0
pytest>=7.3.0
matplotlib>=3.7.0
EOF

# --- 2. Source Code (With Bugs) ---

# pk_tools/__init__.py
touch "$PROJECT_DIR/pk_tools/__init__.py"

# pk_tools/model.py (BUG 1: kel calculation)
cat > "$PROJECT_DIR/pk_tools/model.py" << 'EOF'
"""
Pharmacokinetic Model Definitions.
Implements one-compartment IV bolus models.
"""
import numpy as np

def calculate_kel(half_life: float) -> float:
    """
    Calculate elimination rate constant (kel) from half-life.
    
    Args:
        half_life: Drug half-life in hours.
        
    Returns:
        Elimination rate constant (1/hr).
    """
    if half_life <= 0:
        raise ValueError("Half-life must be positive")
    
    # BUG: Mathematical error.
    # Correct formula: ln(2) / half_life (~0.693 / half_life)
    # Current implementation: 0.693 * half_life
    return 0.693 * half_life

def concentration_at_time(dose: float, vd: float, kel: float, t: float) -> float:
    """
    Calculate concentration at time t after a single bolus dose.
    C(t) = (Dose / Vd) * e^(-kel * t)
    """
    if t < 0:
        return 0.0
    return (dose / vd) * np.exp(-kel * t)
EOF

# pk_tools/simulation.py (BUG 2: Accumulation logic)
cat > "$PROJECT_DIR/pk_tools/simulation.py" << 'EOF'
"""
Time-series simulation for multi-dose regimens.
"""
import numpy as np
from .model import concentration_at_time

def simulate_regimen(doses: list, interval: float, vd: float, kel: float, duration: float, dt: float = 0.1):
    """
    Simulate concentration over time for a multi-dose regimen.
    
    Args:
        doses: List of dose amounts (mg).
        interval: Dosing interval (hours).
        vd: Volume of distribution (L).
        kel: Elimination rate constant (1/hr).
        duration: Total simulation duration (hours).
        dt: Time step (hours).
        
    Returns:
        tuple: (time_array, concentration_array)
    """
    n_steps = int(duration / dt) + 1
    time_array = np.linspace(0, duration, n_steps)
    conc_array = np.zeros(n_steps)
    
    # Calculate concentrations by superposition logic or state accumulation
    # Here we use a state update loop
    
    current_conc = 0.0
    next_dose_index = 0
    next_dose_time = 0.0
    
    for i in range(1, n_steps):
        t = time_array[i]
        dt_actual = t - time_array[i-1]
        
        # Decay from previous step
        current_conc = current_conc * np.exp(-kel * dt_actual)
        
        # Check if it's time for a dose
        # Allow a small epsilon for float comparison
        if next_dose_index < len(doses) and abs(t - next_dose_time) < (dt / 2.0):
            dose = doses[next_dose_index]
            
            # BUG: Logic error.
            # Should add new concentration to residual: current_conc += dose / vd
            # Current implementation overwrites it, ignoring accumulation.
            current_conc = dose / vd
            
            next_dose_index += 1
            next_dose_time += interval
            
        conc_array[i] = current_conc
        
    # Set t=0 value
    if len(doses) > 0:
        conc_array[0] = doses[0] / vd
        
    return time_array, conc_array
EOF

# pk_tools/analysis.py (BUG 3: AUC Fencepost error)
cat > "$PROJECT_DIR/pk_tools/analysis.py" << 'EOF'
"""
PK Parameter Analysis (AUC, Clearance, etc.)
"""
import numpy as np

def calculate_auc(time: np.ndarray, concentration: np.ndarray) -> float:
    """
    Calculate Area Under the Curve (AUC) using the Trapezoidal Rule.
    
    Args:
        time: Array of time points (hr).
        concentration: Array of concentration points (mg/L).
        
    Returns:
        AUC (mg*hr/L).
    """
    auc = 0.0
    
    # BUG: Fencepost error / IndexOutOfBounds
    # Loops to len(time), but accesses i+1.
    # Should be range(len(time) - 1).
    for i in range(len(time)):
        dt = time[i+1] - time[i]
        avg_c = (concentration[i] + concentration[i+1]) / 2.0
        auc += avg_c * dt
        
    return auc

def check_therapeutic_range(concentration: np.ndarray, min_c: float, max_c: float) -> dict:
    """Check time spent within therapeutic window."""
    in_range = (concentration >= min_c) & (concentration <= max_c)
    time_in_range = np.sum(in_range) # Approximate as sum of points (assuming uniform dt mostly)
    # Note: This is a simplification for the analysis module
    return {
        "is_safe": np.max(concentration) <= max_c,
        "is_effective": np.min(concentration[concentration > 0]) >= min_c
    }
EOF

# --- 3. Tests ---

# tests/conftest.py
cat > "$PROJECT_DIR/tests/conftest.py" << 'EOF'
import pytest
import numpy as np

@pytest.fixture
def standard_patient():
    return {
        "vd": 50.0,    # 50 Liters
        "half_life": 6.0 # 6 hours
    }
EOF

# tests/test_model.py
cat > "$PROJECT_DIR/tests/test_model.py" << 'EOF'
import pytest
import numpy as np
from pk_tools.model import calculate_kel, concentration_at_time

def test_kel_calculation():
    """Test relationship between half-life and elimination rate."""
    t_half = 10.0
    # kel = ln(2) / t_half = 0.693147 / 10 = 0.06931
    expected = np.log(2) / t_half
    result = calculate_kel(t_half)
    
    # Allow small tolerance
    assert abs(result - expected) < 0.001, \
        f"Calculated kel {result} does not match expected {expected} for half-life {t_half}"

def test_concentration_decay():
    """Test simple exponential decay."""
    dose = 1000.0
    vd = 100.0
    kel = 0.1
    t = 10.0
    
    # C(10) = (1000/100) * e^(-0.1 * 10) = 10 * 0.3678 = 3.678
    expected = 10.0 * np.exp(-1.0)
    result = concentration_at_time(dose, vd, kel, t)
    assert abs(result - expected) < 0.001
EOF

# tests/test_simulation.py
cat > "$PROJECT_DIR/tests/test_simulation.py" << 'EOF'
import pytest
import numpy as np
from pk_tools.simulation import simulate_regimen

def test_steady_state_accumulation():
    """
    Test that drug accumulates over multiple doses.
    If we dose every half-life, the second peak should be 1.5x the first peak.
    """
    vd = 10.0
    kel = 0.1  # t_half approx 6.93 hrs
    doses = [100.0, 100.0]
    interval = 10.0 # Dosing interval
    duration = 20.0
    
    t, c = simulate_regimen(doses, interval, vd, kel, duration, dt=0.1)
    
    # Find peaks (approximate)
    # Peak 1 at t=0
    peak1 = c[0]
    assert abs(peak1 - 10.0) < 0.1
    
    # Peak 2 at t=10
    # At t=10 just before dose 2: C = 10 * exp(-0.1 * 10) = 10 * 0.367 = 3.67
    # Dose 2 adds 10.0. New peak should be ~13.67
    idx_dose2 = int(10.0 / 0.1)
    # Search around the expected dose time for local max
    peak2 = np.max(c[idx_dose2-2:idx_dose2+5])
    
    # Bug check: If accumulation is broken, peak2 will be ~10.0 (same as peak1)
    assert peak2 > 12.0, f"Drug did not accumulate. Peak 2 {peak2} should be > 12.0"

def test_single_dose_profile():
    doses = [100.0]
    t, c = simulate_regimen(doses, 24, 10, 0.1, 10, dt=0.1)
    assert len(t) == len(c)
    assert c[0] == 10.0
    assert c[-1] < 10.0
EOF

# tests/test_analysis.py
cat > "$PROJECT_DIR/tests/test_analysis.py" << 'EOF'
import pytest
import numpy as np
from pk_tools.analysis import calculate_auc

def test_auc_calculation():
    """Test Trapezoidal rule implementation."""
    # Simple rectangle/triangle case
    # t = [0, 1, 2]
    # c = [2, 2, 2] -> Area = 2 * 2 = 4
    t = np.array([0.0, 1.0, 2.0])
    c = np.array([2.0, 2.0, 2.0])
    
    try:
        auc = calculate_auc(t, c)
    except IndexError:
        pytest.fail("calculate_auc raised IndexError (Check loop bounds)")
        
    assert abs(auc - 4.0) < 0.001

def test_auc_linear_decay():
    # t = [0, 10], c = [10, 0] -> Triangle area = 0.5 * 10 * 10 = 50
    t = np.array([0.0, 10.0])
    c = np.array([10.0, 0.0])
    auc = calculate_auc(t, c)
    assert abs(auc - 50.0) < 0.001
EOF

# --- 4. Data and Scripts ---

# Randomize patient data for anti-gaming
WEIGHT=$(( 60 + RANDOM % 40 )) # 60-100 kg
AGE=$(( 30 + RANDOM % 40 ))
CREATININE=$(( 80 + RANDOM % 40 )) # umol/L
DOSE_AMOUNT=$(( 500 + (RANDOM % 4) * 250 )) # 500, 750, 1000, 1250
cat > "$PROJECT_DIR/data/patient_732.json" << EOF
{
    "patient_id": "732",
    "weight_kg": $WEIGHT,
    "age": $AGE,
    "sex": "M",
    "serum_creatinine": $CREATININE,
    "regimen": {
        "drug": "Vancomycin",
        "dose_mg": $DOSE_AMOUNT,
        "interval_hrs": 12,
        "num_doses": 4
    }
}
EOF

# Store hidden ground truth parameters for export verification
echo "{\"weight\": $WEIGHT, \"dose\": $DOSE_AMOUNT}" > /tmp/ground_truth_params.json

# script for agent to run
cat > "$PROJECT_DIR/generate_report.py" << 'EOF'
import json
import pandas as pd
import numpy as np
from pk_tools.model import calculate_kel
from pk_tools.simulation import simulate_regimen
from pk_tools.analysis import calculate_auc

def estimate_parameters(patient_data):
    # Simplified population PK parameters
    # Vd approx 0.7 L/kg
    vd = 0.7 * patient_data['weight_kg']
    
    # Half life based on creatinine (simplified)
    # Higher creatinine = worse kidney function = longer half life
    cr = patient_data['serum_creatinine']
    t_half = 6.0 * (cr / 80.0) 
    
    return vd, t_half

def main():
    print("Loading patient data...")
    with open('data/patient_732.json', 'r') as f:
        data = json.load(f)
        
    print(f"Estimating parameters for Patient {data['patient_id']}...")
    vd, t_half = estimate_parameters(data)
    kel = calculate_kel(t_half)
    
    print(f"  Vd: {vd:.1f} L")
    print(f"  Half-life: {t_half:.1f} hr")
    print(f"  Kel: {kel:.4f} 1/hr")
    
    regimen = data['regimen']
    doses = [regimen['dose_mg']] * regimen['num_doses']
    
    print("Running simulation...")
    t, c = simulate_regimen(
        doses=doses,
        interval=regimen['interval_hrs'],
        vd=vd,
        kel=kel,
        duration=48.0
    )
    
    auc = calculate_auc(t, c)
    print(f"Simulation Complete. Total AUC (0-48h): {auc:.1f}")
    
    df = pd.DataFrame({'time_hr': t, 'concentration_mg_L': c})
    output_path = 'output/patient_732_sim.csv'
    df.to_csv(output_path, index=False)
    print(f"Report saved to {output_path}")

if __name__ == "__main__":
    main()
EOF

# Set permissions
chown -R ga:ga "$PROJECT_DIR"

# Launch PyCharm
source /workspace/scripts/task_utils.sh
setup_pycharm_project "$PROJECT_DIR"

# Take screenshot
take_screenshot /tmp/task_initial.png
EOF