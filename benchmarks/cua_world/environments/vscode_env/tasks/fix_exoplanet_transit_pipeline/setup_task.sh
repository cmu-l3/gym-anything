#!/bin/bash
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up Exoplanet Pipeline Task ==="

WORKSPACE_DIR="/home/ga/workspace/exoplanet_pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/data"
sudo -u ga mkdir -p "$WORKSPACE_DIR/pipeline"
sudo -u ga mkdir -p "$WORKSPACE_DIR/tests"
sudo -u ga mkdir -p "$WORKSPACE_DIR/results"

# ─────────────────────────────────────────────────────────────
# 1. Generate Realistic Astrophysical Data (Domain Generator)
# ─────────────────────────────────────────────────────────────
echo "Generating physical Kepler-8b light curve data..."
cat > "/tmp/generate_lightcurve.py" << 'PYGEN'
import numpy as np
import pandas as pd
import os

np.random.seed(42)

# Kepler-8b true parameters
PERIOD = 3.5225
T0 = 1.25
DEPTH = 0.0102  # ~10200 ppm
DURATION = 0.15 # days

# Generate 90 days of observation (Kepler long cadence ~30 mins)
time = np.arange(0, 90, 30 / (24 * 60))
flux = np.ones_like(time) * 50000  # Baseline raw electron count
flux_err = np.sqrt(flux)           # Poisson shot noise

# Inject transits (U-shaped dips)
phases = ((time - T0) / PERIOD) % 1.0
phases[phases > 0.5] -= 1.0
transit_mask = np.abs(phases) < (DURATION / (2 * PERIOD))
flux[transit_mask] *= (1.0 - DEPTH)

# Add stellar variability (low frequency sine waves)
trend = 1000 * np.sin(2 * np.pi * time / 15.0) + 500 * np.cos(2 * np.pi * time / 7.0)
flux += trend

# Add Gaussian noise
flux += np.random.normal(0, flux_err)

# Add cosmic ray spikes (positive outliers only)
spike_indices = np.random.choice(len(time), size=50, replace=False)
flux[spike_indices] += np.random.uniform(2000, 8000, size=50)

df = pd.DataFrame({'time': time, 'flux': flux, 'flux_err': flux_err})
df.to_csv('/home/ga/workspace/exoplanet_pipeline/data/kepler8b_lightcurve.csv', index=False)
PYGEN

sudo -u ga python3 /tmp/generate_lightcurve.py
rm /tmp/generate_lightcurve.py

# ─────────────────────────────────────────────────────────────
# 2. Pipeline Modules (with injected bugs)
# ─────────────────────────────────────────────────────────────

# Bug 1: Normalizes by median(flux_err) instead of median(flux)
cat > "$WORKSPACE_DIR/pipeline/data_loader.py" << 'EOF'
import pandas as pd
import numpy as np

def load_and_normalize(filepath):
    """Load light curve and normalize flux to ~1.0"""
    df = pd.read_csv(filepath)
    # BUG: Normalizing by the error instead of the flux
    median_flux = np.median(df['flux_err']) 
    
    df['normalized_flux'] = df['flux'] / median_flux
    df['normalized_err'] = df['flux_err'] / median_flux
    return df
EOF

# Bug 2: Savgol filter requires an odd window length
cat > "$WORKSPACE_DIR/pipeline/detrender.py" << 'EOF'
import numpy as np
from scipy.signal import savgol_filter

def remove_stellar_trend(time, flux, window_days=3.0):
    """Remove low-frequency stellar variability using a Savitzky-Golay filter."""
    cadence_days = np.median(np.diff(time))
    window_length = int(window_days / cadence_days)
    
    # BUG: window_length might be even, causing savgol_filter to crash.
    # Must enforce window_length to be an odd integer.
    
    trend = savgol_filter(flux, window_length, polyorder=2)
    detrended_flux = flux - trend + 1.0
    return detrended_flux, trend
EOF

# Bug 3: Absolute value rejects BOTH cosmic rays (+) and transit dips (-)
cat > "$WORKSPACE_DIR/pipeline/outlier_rejection.py" << 'EOF'
import numpy as np

def remove_cosmic_rays(time, flux, threshold_sigma=3.0):
    """Remove positive flux outliers (cosmic rays) while preserving transits."""
    trend = np.median(flux)
    std = np.std(flux)
    
    # BUG: np.abs() removes deep transit dips (which are negative outliers).
    # We only want to remove positive outliers (flux - trend > threshold).
    outlier_mask = np.abs(flux - trend) > (threshold_sigma * std)
    
    clean_time = time[~outlier_mask]
    clean_flux = flux[~outlier_mask]
    return clean_time, clean_flux
EOF

# Bug 4: Box-Least Squares searches linear period space instead of linear frequency space
cat > "$WORKSPACE_DIR/pipeline/transit_search.py" << 'EOF'
import numpy as np

def run_bls_search(time, flux, min_period=1.0, max_period=10.0):
    """Find the most likely transit period using Box-Least Squares logic."""
    # BUG: A linear grid in period space misses narrow resonances.
    # We must search a linear grid in frequency space (1/period).
    periods = np.linspace(min_period, max_period, 10000)
    
    best_power = -np.inf
    best_period = None
    
    # Simplified BLS calculation for the pipeline
    for p in periods:
        phase = (time % p) / p
        transit_mask = (phase > 0.45) & (phase < 0.55)
        if np.sum(transit_mask) == 0:
            continue
            
        dip = 1.0 - np.mean(flux[transit_mask])
        power = dip * np.sqrt(np.sum(transit_mask))
        
        if power > best_power:
            best_power = power
            best_period = p
            
    return best_period
EOF

# Bug 5: Phase folding does not subtract the epoch (t0)
cat > "$WORKSPACE_DIR/pipeline/phase_folder.py" << 'EOF'
import numpy as np

def fold_lightcurve(time, flux, period, t0):
    """Fold the light curve on the given period, centered on transit epoch t0."""
    # BUG: Formula fails to align transits to phase 0.0 because t0 is ignored.
    # Should be: ((time - t0) / period) % 1.0
    phase = (time / period) % 1.0
    
    # Shift phase to [-0.5, 0.5]
    phase[phase > 0.5] -= 1.0
    
    # Sort by phase
    sort_idx = np.argsort(phase)
    return phase[sort_idx], flux[sort_idx]
EOF

# ─────────────────────────────────────────────────────────────
# 3. Execution & Tests
# ─────────────────────────────────────────────────────────────
cat > "$WORKSPACE_DIR/run_pipeline.py" << 'EOF'
import json
import numpy as np
from pipeline.data_loader import load_and_normalize
from pipeline.detrender import remove_stellar_trend
from pipeline.outlier_rejection import remove_cosmic_rays
from pipeline.transit_search import run_bls_search
from pipeline.phase_folder import fold_lightcurve

def main():
    print("Running Exoplanet Transit Pipeline...")
    # 1. Load Data
    df = load_and_normalize('data/kepler8b_lightcurve.csv')
    time, flux = df['time'].values, df['normalized_flux'].values
    
    # 2. Detrend
    flux, _ = remove_stellar_trend(time, flux)
    
    # 3. Reject Outliers
    time, flux = remove_cosmic_rays(time, flux)
    
    # 4. Search for Transit
    best_period = run_bls_search(time, flux)
    print(f"Detected Period: {best_period:.4f} days")
    
    # Calculate depth
    phase, folded_flux = fold_lightcurve(time, flux, best_period, 1.25)
    transit_mask = np.abs(phase) < 0.02
    transit_depth_ppm = (1.0 - np.mean(folded_flux[transit_mask])) * 1e6
    print(f"Detected Depth: {transit_depth_ppm:.0f} ppm")
    
    # Save Results
    results = {
        "target": "Kepler-8b",
        "period_days": round(float(best_period), 4),
        "transit_depth_ppm": round(float(transit_depth_ppm), 0)
    }
    
    with open('results/planet_parameters.json', 'w') as f:
        json.dump(results, f, indent=4)
    print("Results saved to results/planet_parameters.json")

if __name__ == "__main__":
    main()
EOF

cat > "$WORKSPACE_DIR/tests/test_pipeline.py" << 'EOF'
import numpy as np
import pytest
import os
import sys
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

from pipeline.data_loader import load_and_normalize
from pipeline.detrender import remove_stellar_trend
from pipeline.outlier_rejection import remove_cosmic_rays
from pipeline.transit_search import run_bls_search
from pipeline.phase_folder import fold_lightcurve

def test_data_loader():
    df = load_and_normalize('data/kepler8b_lightcurve.csv')
    assert np.median(df['normalized_flux']) > 0.9
    assert np.median(df['normalized_flux']) < 1.1

def test_detrender():
    # Provide an array length that results in an even window length naturally
    time = np.linspace(0, 10, 1000)
    flux = np.ones(1000)
    # Should not crash
    detrended, _ = remove_stellar_trend(time, flux, window_days=1.0)
    assert len(detrended) == 1000

def test_outlier_rejection():
    time = np.arange(10)
    flux = np.ones(10)
    flux[2] = 100.0  # Cosmic ray (+)
    flux[7] = 0.5    # Transit dip (-)
    
    clean_t, clean_f = remove_cosmic_rays(time, flux, threshold_sigma=2.0)
    assert 2 not in clean_t  # Cosmic ray removed
    assert 7 in clean_t      # Transit dip preserved

def test_phase_folder():
    time = np.array([1.25, 4.7725, 8.295]) # exact transit times
    period = 3.5225
    t0 = 1.25
    phase, _ = fold_lightcurve(time, np.ones(3), period, t0)
    # All should fold to exactly phase 0
    assert np.allclose(phase, 0.0, atol=1e-5)
EOF

# Ensure all files are owned by ga
chown -R ga:ga "$WORKSPACE_DIR"

# ─────────────────────────────────────────────────────────────
# 4. Launch VS Code
# ─────────────────────────────────────────────────────────────
echo "Starting VS Code..."
date +%s > /tmp/task_start_time.txt

sudo -u ga DISPLAY=:1 code "$WORKSPACE_DIR"

# Wait for VS Code to open
wait_for_window "Visual Studio Code" 30

focus_vscode_window
DISPLAY=:1 wmctrl -r "Visual Studio Code" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take an initial screenshot for evidence
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Exoplanet Task Setup Complete ==="