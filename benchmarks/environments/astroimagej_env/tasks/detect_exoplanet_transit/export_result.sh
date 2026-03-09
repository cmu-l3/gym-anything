#!/bin/bash
# Export script for WASP-12b Exoplanet Transit Detection task
# Extracts analysis results from AstroImageJ for verification
#
# Key output locations checked:
# - /home/ga/AstroImages/WASP-12b/*Measurements*.xls (AIJ default save location)
# - /home/ga/AstroImages/results/*.tbl
# - /home/ga/*.xls, /home/ga/*.tbl (if saved to home)

source /workspace/scripts/task_utils.sh 2>/dev/null || true

echo "=== Exporting WASP-12b Transit Detection Results ==="

# Take final screenshot
FINAL_SCREENSHOT="/tmp/aij_final_screenshot.png"
take_screenshot "$FINAL_SCREENSHOT" 2>/dev/null || DISPLAY=:1 scrot "$FINAL_SCREENSHOT" 2>/dev/null || true
echo "Final screenshot saved to $FINAL_SCREENSHOT"

# ============================================================
# Get window list (reliable signal)
# ============================================================
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")
echo "Windows: $WINDOWS_LIST"

# ============================================================
# Detect what's running/visible
# ============================================================
LIGHTCURVE_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "plot\|Multi-plot\|Measurements\|curve"; then
    LIGHTCURVE_WINDOW="true"
    echo "Light curve/plot window detected"
fi

MULTIAP_WINDOW="false"
if echo "$WINDOWS_LIST" | grep -qi "Multi-Aperture\|Aperture"; then
    MULTIAP_WINDOW="true"
    echo "Multi-aperture window detected"
fi

TRANSIT_WINDOW="false"
IMAGE_LOADED="false"
NUM_SLICES=0
if echo "$WINDOWS_LIST" | grep -qi "wasp\|\.fits\|stack"; then
    TRANSIT_WINDOW="true"
    IMAGE_LOADED="true"
    echo "Image/stack window detected"

    # Check if virtual stack (V) indicator present
    if echo "$WINDOWS_LIST" | grep -q "(V)"; then
        # Count actual FITS files
        FITS_COUNT=$(ls -1 /home/ga/AstroImages/WASP-12b/*.fits 2>/dev/null | wc -l || echo "0")
        NUM_SLICES=$FITS_COUNT
        echo "Virtual stack with $NUM_SLICES slices"
    fi
fi

# ============================================================
# Find measurement files (THE KEY CHECK)
# AstroImageJ saves measurements as .xls or .tbl files
# ============================================================
echo ""
echo "=== Searching for measurement files ==="

SEARCH_DIRS="/home/ga/AstroImages/WASP-12b /home/ga/AstroImages/results /home/ga /home/ga/Desktop"

MEASUREMENT_FILE=""
MEASUREMENT_FILES_FOUND=""

# Search for AstroImageJ measurement files
for dir in $SEARCH_DIRS; do
    if [ -d "$dir" ]; then
        # Look for .xls files (AIJ default format)
        found=$(find "$dir" -maxdepth 2 -type f \( \
            -name "*Measurements*.xls" -o \
            -name "*Measurements*.tbl" -o \
            -name "*Measurements*.csv" -o \
            -name "*_T1*.xls" -o \
            -name "*photometry*.txt" -o \
            -name "*lightcurve*.txt" \
        \) 2>/dev/null | head -5)

        if [ -n "$found" ]; then
            echo "Found in $dir:"
            echo "$found"
            MEASUREMENT_FILES_FOUND="$MEASUREMENT_FILES_FOUND $found"

            # Use first file found for parsing
            if [ -z "$MEASUREMENT_FILE" ]; then
                MEASUREMENT_FILE=$(echo "$found" | head -1)
            fi
        fi
    fi
done

# Also check for any .xls or .tbl files created during the task
BASELINE_TIME="/tmp/initial_results_count"
if [ -f "$BASELINE_TIME" ]; then
    NEW_FILES=$(find /home/ga -maxdepth 3 -type f \( -name "*.xls" -o -name "*.tbl" \) -newer "$BASELINE_TIME" 2>/dev/null)
    if [ -n "$NEW_FILES" ]; then
        echo "New files since task start:"
        echo "$NEW_FILES"
        MEASUREMENT_FILES_FOUND="$MEASUREMENT_FILES_FOUND $NEW_FILES"
        if [ -z "$MEASUREMENT_FILE" ]; then
            MEASUREMENT_FILE=$(echo "$NEW_FILES" | head -1)
        fi
    fi
fi

# ============================================================
# Parse measurement file for transit parameters
# ============================================================
TRANSIT_DEPTH=""
MID_TRANSIT=""
DURATION=""
PLANET_RADIUS=""
NUM_MEASUREMENTS=0
NUM_APERTURES=0
NUM_COMPARISON_STARS=0
HAS_TIME_COL="false"
HAS_FLUX_COL="false"

if [ -n "$MEASUREMENT_FILE" ] && [ -f "$MEASUREMENT_FILE" ]; then
    echo ""
    echo "=== Parsing measurement file: $MEASUREMENT_FILE ==="

    # Count lines (measurements)
    NUM_MEASUREMENTS=$(wc -l < "$MEASUREMENT_FILE" 2>/dev/null || echo "0")
    NUM_MEASUREMENTS=$((NUM_MEASUREMENTS - 1))  # Subtract header
    if [ "$NUM_MEASUREMENTS" -lt 0 ]; then NUM_MEASUREMENTS=0; fi
    echo "Number of data points: $NUM_MEASUREMENTS"

    # Check for required columns
    HEADER=$(head -1 "$MEASUREMENT_FILE" 2>/dev/null || echo "")

    if echo "$HEADER" | grep -qiE "J\.D\.|JD|BJD"; then
        HAS_TIME_COL="true"
        echo "Time column found"
    fi

    if echo "$HEADER" | grep -qiE "rel_flux|Source-Sky|tot_C_cnts"; then
        HAS_FLUX_COL="true"
        echo "Flux column found"
    fi

    # Count apertures (T1, C2, C3, etc. in column names)
    NUM_APERTURES=$(echo "$HEADER" | grep -oE "rel_flux_[TC][0-9]+" | wc -l || echo "0")
    NUM_COMPARISON_STARS=$(echo "$HEADER" | grep -oE "rel_flux_C[0-9]+" | wc -l || echo "0")
    echo "Apertures: $NUM_APERTURES, Comparison stars: $NUM_COMPARISON_STARS"

    # Parse transit parameters if we have time and flux data
    if [ "$HAS_TIME_COL" = "true" ] && [ "$HAS_FLUX_COL" = "true" ] && [ "$NUM_MEASUREMENTS" -gt 20 ]; then
        echo "Extracting transit parameters..."

        python3 << 'PYEOF'
import sys
import os

measurement_file = os.environ.get('MEASUREMENT_FILE', '')
if not measurement_file or not os.path.exists(measurement_file):
    sys.exit(0)

try:
    import numpy as np

    # Read file
    with open(measurement_file, 'r') as f:
        lines = f.readlines()

    if len(lines) < 10:
        print("Not enough data")
        sys.exit(0)

    # Find header (first line with column names)
    header = lines[0].strip().split('\t') if '\t' in lines[0] else lines[0].strip().split()

    # Find time and flux columns
    time_col = -1
    flux_col = -1

    for i, h in enumerate(header):
        h_lower = h.lower()
        # Time column (JD, BJD, etc.)
        if 'j.d.' in h_lower or 'jd' in h_lower or 'bjd' in h_lower:
            time_col = i
        # Flux column (rel_flux_T1 is the target relative flux)
        if 'rel_flux_t1' in h_lower:
            flux_col = i

    if time_col < 0:
        print("No time column found")
        sys.exit(0)

    if flux_col < 0:
        # Try Source-Sky_T1 as alternative
        for i, h in enumerate(header):
            if 'source-sky_t1' in h.lower() or 'source_t1' in h.lower():
                flux_col = i
                break

    if flux_col < 0:
        print("No flux column found")
        sys.exit(0)

    print(f"Using columns: time={time_col} ({header[time_col]}), flux={flux_col} ({header[flux_col]})")

    # Parse data
    times = []
    fluxes = []

    for line in lines[1:]:
        parts = line.strip().split('\t') if '\t' in line else line.strip().split()
        if len(parts) > max(time_col, flux_col):
            try:
                t = float(parts[time_col])
                f = float(parts[flux_col])
                if f > 0:  # Valid flux
                    times.append(t)
                    fluxes.append(f)
            except (ValueError, IndexError):
                pass

    if len(times) < 20:
        print(f"Only {len(times)} valid data points")
        sys.exit(0)

    times = np.array(times)
    fluxes = np.array(fluxes)

    # Normalize flux
    median_flux = np.median(fluxes)
    fluxes_norm = fluxes / median_flux

    # Estimate transit depth
    # Baseline: median of top 30% of flux values
    sorted_flux = np.sort(fluxes_norm)
    baseline = np.median(sorted_flux[-int(len(sorted_flux)*0.3):])
    # Bottom: median of bottom 20%
    bottom = np.median(sorted_flux[:int(len(sorted_flux)*0.2)])

    depth_frac = (baseline - bottom) / baseline
    depth_percent = depth_frac * 100

    # Mid-transit time (minimum flux)
    mid_idx = np.argmin(fluxes_norm)
    mid_transit = times[mid_idx]

    # Convert reduced JD if needed
    if mid_transit < 100000:
        mid_transit += 2400000

    # Transit duration estimate
    threshold = baseline - 0.5 * (baseline - bottom)
    in_transit = fluxes_norm < threshold
    if np.any(in_transit):
        transit_times = times[in_transit]
        duration_days = transit_times.max() - transit_times.min()
        duration_hours = duration_days * 24
    else:
        duration_hours = 0

    # Calculate planet radius
    # Rp = Rs * sqrt(depth), Rs = 1.599 R_sun
    RS_SUN = 1.599
    R_SUN_TO_R_JUP = 9.73
    rp_rjup = RS_SUN * np.sqrt(max(depth_frac, 0)) * R_SUN_TO_R_JUP

    # Write results
    import json
    result = {
        "transit_depth_percent": round(depth_percent, 3),
        "mid_transit_bjd": round(mid_transit, 4),
        "duration_hours": round(duration_hours, 2),
        "planet_radius_rjup": round(rp_rjup, 2),
        "num_data_points": len(times)
    }

    with open("/tmp/transit_params.json", "w") as f:
        json.dump(result, f, indent=2)

    print(f"Transit depth: {depth_percent:.3f}%")
    print(f"Mid-transit: BJD {mid_transit:.4f}")
    print(f"Duration: {duration_hours:.2f} hours")
    print(f"Planet radius: {rp_rjup:.2f} R_Jupiter")

except Exception as e:
    print(f"Parse error: {e}")
    import traceback
    traceback.print_exc()
PYEOF

        # Read extracted parameters
        if [ -f "/tmp/transit_params.json" ]; then
            TRANSIT_DEPTH=$(python3 -c "import json; print(json.load(open('/tmp/transit_params.json')).get('transit_depth_percent', ''))" 2>/dev/null || echo "")
            MID_TRANSIT=$(python3 -c "import json; print(json.load(open('/tmp/transit_params.json')).get('mid_transit_bjd', ''))" 2>/dev/null || echo "")
            DURATION=$(python3 -c "import json; print(json.load(open('/tmp/transit_params.json')).get('duration_hours', ''))" 2>/dev/null || echo "")
            PLANET_RADIUS=$(python3 -c "import json; print(json.load(open('/tmp/transit_params.json')).get('planet_radius_rjup', ''))" 2>/dev/null || echo "")
        fi
    fi
fi

# ============================================================
# Check for light curve plot files
# ============================================================
LIGHTCURVE_FILE=""
for dir in $SEARCH_DIRS; do
    found=$(find "$dir" -maxdepth 2 -type f \( \
        -name "*plot*.png" -o \
        -name "*curve*.png" -o \
        -name "*Multi-plot*.png" -o \
        -name "*lightcurve*.png" \
    \) 2>/dev/null | head -1)

    if [ -n "$found" ]; then
        LIGHTCURVE_FILE="$found"
        echo "Found light curve plot: $LIGHTCURVE_FILE"
        break
    fi
done

# ============================================================
# Check for agent report with planet radius
# ============================================================
if [ -z "$PLANET_RADIUS" ]; then
    for dir in /home/ga /home/ga/Desktop /home/ga/AstroImages/results; do
        found=$(find "$dir" -maxdepth 2 -type f -name "*.txt" -newer /tmp/initial_results_count 2>/dev/null | head -5)
        for f in $found; do
            if grep -qiE "planet.*radius|R_J|Jupiter" "$f" 2>/dev/null; then
                extracted=$(grep -oP '\d+\.\d+\s*(R_?J|Jupiter)' "$f" 2>/dev/null | head -1 | grep -oP '\d+\.\d+')
                if [ -n "$extracted" ]; then
                    PLANET_RADIUS="$extracted"
                    echo "Found planet radius in report: $PLANET_RADIUS R_J"
                    break 2
                fi
            fi
        done
    done
fi

# ============================================================
# Cleanup: Close AstroImageJ
# ============================================================
pkill -f "astroimagej\|aij\|AstroImageJ" 2>/dev/null || true

# ============================================================
# Create final result JSON
# ============================================================
MEASUREMENT_FILES_STR=$(echo "$MEASUREMENT_FILES_FOUND" | tr ' \n' '|' | sed 's/|$//')

cat > /tmp/task_result.json << EOF
{
    "measurement_file_found": $([ -n "$MEASUREMENT_FILE" ] && echo "true" || echo "false"),
    "measurement_file_path": "$MEASUREMENT_FILE",
    "num_measurements": $NUM_MEASUREMENTS,
    "num_apertures": $NUM_APERTURES,
    "num_comparison_stars": $NUM_COMPARISON_STARS,
    "has_time_column": $HAS_TIME_COL,
    "has_flux_column": $HAS_FLUX_COL,
    "num_slices": $NUM_SLICES,
    "image_loaded": $IMAGE_LOADED,
    "transit_depth_percent": "$TRANSIT_DEPTH",
    "mid_transit_bjd": "$MID_TRANSIT",
    "duration_hours": "$DURATION",
    "planet_radius_rjup": "$PLANET_RADIUS",
    "lightcurve_window_found": $LIGHTCURVE_WINDOW,
    "lightcurve_file": "$LIGHTCURVE_FILE",
    "multiap_window_found": $MULTIAP_WINDOW,
    "transit_window_found": $TRANSIT_WINDOW,
    "screenshot_path": "$FINAL_SCREENSHOT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|')",
    "measurement_files_searched": "$MEASUREMENT_FILES_STR",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 /tmp/task_result.json 2>/dev/null || true

echo ""
echo "=== Export Result ==="
cat /tmp/task_result.json
echo ""
echo "=== Export Complete ==="
