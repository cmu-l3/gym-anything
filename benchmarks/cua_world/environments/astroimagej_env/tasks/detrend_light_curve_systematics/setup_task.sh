#!/bin/bash
echo "=== Setting up Detrend Light Curve Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Create directories
WORK_DIR="/home/ga/AstroImages/time_series"
OUT_DIR="$WORK_DIR/output"
rm -rf "$WORK_DIR"
mkdir -p "$OUT_DIR"

# Generate realistic WASP-12b time-series photometry data with an airmass systematic
# (Using Python to generate highly realistic parameters modeled after the real dataset)
python3 << 'PYEOF'
import numpy as np
import json
import os
import scipy.stats

# Realistic WASP-12b observation parameters
n_points = 186
# JD range matching ~5 hours of observation
jd_norm = np.linspace(7393.55, 7393.85, n_points)

# Airmass is typically a parabola reaching a minimum at transit center/meridian crossing
# We simulate a rising airmass as the star sets
airmass = 1.02 + 8.0 * (jd_norm - 7393.65)**2

# Base flux
flux = np.ones(n_points)

# Add planetary transit (Mandel-Agol simplified to a box for UI testing)
mid_transit = 7393.70
duration = 0.11
transit_mask = np.abs(jd_norm - mid_transit) < (duration / 2)
flux[transit_mask] -= 0.0142  # ~1.4% transit depth

# Add airmass systematic (Linear detrend model: c0 + c1 * AIRMASS)
true_c1 = -0.0385
flux += true_c1 * (airmass - 1.0)

# Add realistic photometric scatter (red/white noise)
np.random.seed(42)
flux += np.random.normal(0, 0.0012, n_points)

# Save to TSV (AstroImageJ standard format)
tsv_path = "/home/ga/AstroImages/time_series/wasp12b_raw_photometry.tsv"
with open(tsv_path, "w") as f:
    f.write("J.D.-2400000\tAIRMASS\trel_flux_T1\n")
    for i in range(n_points):
        f.write(f"{jd_norm[i]:.6f}\t{airmass[i]:.5f}\t{flux[i]:.6f}\n")

# Calculate Ground Truth using standard linear regression on the out-of-transit baseline
oot_mask = ~transit_mask
slope, intercept, r_value, p_value, std_err = scipy.stats.linregress(airmass[oot_mask], flux[oot_mask])

# Save ground truth for the verifier
gt = {
    "c1_expected": float(slope),
    "c0_expected": float(intercept),
    "num_points": n_points
}
with open("/tmp/ground_truth.json", "w") as f:
    json.dump(gt, f)

print(f"Generated realistic photometry with expected c1 coefficient: {slope:.5f}")
PYEOF

chown -R ga:ga "$WORK_DIR"

# Launch AstroImageJ
echo "Launching AstroImageJ..."
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true
sleep 2

AIJ_PATH=""
for path in "/usr/local/bin/aij" "/opt/astroimagej/astroimagej/bin/AstroImageJ"; do
    if [ -x "$path" ]; then
        AIJ_PATH="$path"
        break
    fi
done

su - ga -c "DISPLAY=:1 _JAVA_OPTIONS='-Xmx4g' '$AIJ_PATH' > /tmp/astroimagej_ga.log 2>&1" &

# Wait for UI and maximize
sleep 8
for i in {1..20}; do
    WID=$(DISPLAY=:1 wmctrl -l | grep -i "AstroImageJ" | awk '{print $1}' | head -1)
    if [ -n "$WID" ]; then
        DISPLAY=:1 wmctrl -ir "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="