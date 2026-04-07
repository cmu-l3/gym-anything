#!/bin/bash
echo "=== Setting up Multi-Band CMD Photometry Task ==="

source /workspace/scripts/task_utils.sh

# Create project directories
PROJECT_DIR="/home/ga/AstroImages/m12_cmd"
RESULTS_DIR="$PROJECT_DIR/results"
rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR" "$RESULTS_DIR"

# Copy M12 data from cached location
M12_CACHE="/opt/fits_samples/m12"
if [ -d "$M12_CACHE" ]; then
    echo "Copying M12 data from cache..."
    cp "$M12_CACHE/Vcomb.fits" "$PROJECT_DIR/" 2>/dev/null || echo "WARNING: Vcomb.fits not found"
    cp "$M12_CACHE/Bcomb.fits" "$PROJECT_DIR/" 2>/dev/null || echo "WARNING: Bcomb.fits not found"
    cp "$M12_CACHE/m12_B_V.xls" "$PROJECT_DIR/" 2>/dev/null || echo "WARNING: m12_B_V.xls not found"
else
    echo "M12 cache not found at $M12_CACHE, attempting download..."
    M12_BASE="https://esahubble.org/static/projects/fits_liberator/datasets/m12"
    cd "$PROJECT_DIR"
    for f in Vcomb Bcomb; do
        wget -q --timeout=60 "${M12_BASE}/${f}.zip" -O "${f}.zip" 2>&1
        if [ -f "${f}.zip" ]; then
            unzip -o "${f}.zip" && rm -f "${f}.zip"
        fi
    done
    wget -q --timeout=60 "${M12_BASE}/m12_B_V.xls" -O m12_B_V.xls 2>&1
fi

# Verify required files exist
for f in Vcomb.fits Bcomb.fits m12_B_V.xls; do
    if [ ! -f "$PROJECT_DIR/$f" ]; then
        echo "ERROR: Required file $f not found"
    else
        echo "OK: $f ($(stat -c%s "$PROJECT_DIR/$f") bytes)"
    fi
done

# Build catalog: parse XLS (B,V,B-V only) + detect star positions from FITS
# The XLS has no pixel coordinates, so we detect stars in the image and match
# by magnitude to assign positions. This is deterministic: same XLS + same FITS
# = same catalog every time.
python3 << 'PYEOF'
import json, os, sys
import numpy as np
from astropy.io import fits

PROJECT_DIR = "/home/ga/AstroImages/m12_cmd"
gt = {}

catalog_csv_path = os.path.join(PROJECT_DIR, "m12_catalog.csv")
xls_path = os.path.join(PROJECT_DIR, "m12_B_V.xls")

# ================================================================
# Step 1: Parse XLS catalog (3 columns: B, V, B-V)
# ================================================================
catalog = []
xls_parsed = False

# Strategy 1: xlrd
if os.path.exists(xls_path) and not xls_parsed:
    try:
        import xlrd
        wb = xlrd.open_workbook(xls_path)
        ws = wb.sheet_by_index(0)
        for r in range(1, ws.nrows):
            try:
                b_mag = float(ws.cell_value(r, 0))
                v_mag = float(ws.cell_value(r, 1))
                bv = float(ws.cell_value(r, 2))
                catalog.append({'B': b_mag, 'V': v_mag, 'BV': bv})
            except (ValueError, TypeError):
                continue
        if len(catalog) >= 10:
            xls_parsed = True
            print(f"XLS parsed via xlrd: {len(catalog)} stars")
    except Exception as e:
        print(f"xlrd failed: {e}")

# Strategy 2: pandas
if os.path.exists(xls_path) and not xls_parsed:
    try:
        import pandas as pd
        df = pd.read_excel(xls_path)
        for _, row in df.iterrows():
            try:
                vals = [float(v) for v in row.values[:3]]
                catalog.append({'B': vals[0], 'V': vals[1], 'BV': vals[2]})
            except (ValueError, TypeError):
                continue
        if len(catalog) >= 10:
            xls_parsed = True
            print(f"XLS parsed via pandas: {len(catalog)} stars")
    except Exception as e:
        print(f"pandas failed: {e}")

# Strategy 3: HTML table
if os.path.exists(xls_path) and not xls_parsed:
    try:
        import pandas as pd
        dfs = pd.read_html(xls_path)
        if dfs:
            for _, row in dfs[0].iterrows():
                try:
                    vals = [float(v) for v in row.values[:3]]
                    catalog.append({'B': vals[0], 'V': vals[1], 'BV': vals[2]})
                except (ValueError, TypeError):
                    continue
        if len(catalog) >= 10:
            xls_parsed = True
            print(f"XLS parsed via HTML: {len(catalog)} stars")
    except Exception as e:
        print(f"HTML parse failed: {e}")

# Strategy 4: raw text
if os.path.exists(xls_path) and not xls_parsed:
    try:
        with open(xls_path, 'r', errors='replace') as f:
            for line in f:
                parts = line.strip().split()
                if len(parts) >= 3:
                    try:
                        b, v, bv = float(parts[0]), float(parts[1]), float(parts[2])
                        if 5 < v < 30:
                            catalog.append({'B': b, 'V': v, 'BV': bv})
                    except ValueError:
                        continue
        if len(catalog) >= 10:
            xls_parsed = True
            print(f"XLS parsed via raw text: {len(catalog)} stars")
    except Exception as e:
        print(f"raw text failed: {e}")

if not xls_parsed or len(catalog) < 10:
    print("FATAL: Could not parse m12_B_V.xls")
    sys.exit(1)

catalog.sort(key=lambda s: s['V'])
print(f"Catalog V range: [{catalog[0]['V']:.2f}, {catalog[-1]['V']:.2f}]")

# ================================================================
# Step 2: Detect stars from FITS images (pure numpy, no scipy)
# ================================================================
v_path = os.path.join(PROJECT_DIR, "Vcomb.fits")
b_path = os.path.join(PROJECT_DIR, "Bcomb.fits")

if not os.path.exists(v_path) or not os.path.exists(b_path):
    print("FATAL: FITS files missing")
    sys.exit(1)

with fits.open(v_path) as hdul:
    v_data = hdul[0].data.astype(np.float64)
with fits.open(b_path) as hdul:
    b_data = hdul[0].data.astype(np.float64)
H, W = v_data.shape
print(f"Image: {H}x{W}")

# Box-smooth for peak detection
from numpy.lib.stride_tricks import sliding_window_view
padded = np.pad(v_data, 2, mode='reflect')
smoothed = np.mean(sliding_window_view(padded, (5, 5)), axis=(-1, -2))

bg_median = np.median(v_data)
bg_std = np.std(v_data[v_data < np.percentile(v_data, 90)])
threshold = bg_median + 10.0 * bg_std
print(f"Detection threshold: {threshold:.2f}")

# Find local maxima
margin = 30
peaks = []
for y in range(margin, H - margin):
    for x in range(margin, W - margin):
        val = smoothed[y, x]
        if val < threshold:
            continue
        patch = smoothed[y-3:y+4, x-3:x+4]
        if val < np.max(patch):
            continue
        # Centroid
        sub = np.clip(v_data[y-2:y+3, x-2:x+3] - bg_median, 0, None)
        total = np.sum(sub)
        if total <= 0:
            continue
        yc = y + np.sum(sub * np.arange(-2, 3)[:, None]) / total
        xc = x + np.sum(sub * np.arange(-2, 3)[None, :]) / total
        peaks.append((float(xc), float(yc), float(val)))

# Deduplicate (merge within 5 pixels)
peaks.sort(key=lambda s: -s[2])
unique = []
for x, y, v in peaks:
    if not any((x-fx)**2 + (y-fy)**2 < 25 for fx, fy, _ in unique):
        unique.append((x, y, v))
print(f"Detected {len(unique)} unique peaks")

# Aperture photometry
detected = []
for cx, cy, _ in unique[:500]:
    yi, xi = int(round(cy)), int(round(cx))
    ylo, yhi = max(0, yi-25), min(H, yi+26)
    xlo, xhi = max(0, xi-25), min(W, xi+26)
    ycoords = np.arange(ylo, yhi)[:, None]
    xcoords = np.arange(xlo, xhi)[None, :]
    dist = np.sqrt((xcoords - cx)**2 + (ycoords - cy)**2)
    aper = dist <= 8
    sky = (dist >= 15) & (dist <= 25)
    if np.sum(sky) < 10 or np.sum(aper) < 5:
        continue
    v_sub = v_data[ylo:yhi, xlo:xhi]
    b_sub = b_data[ylo:yhi, xlo:xhi]
    v_sky = np.median(v_sub[sky])
    b_sky = np.median(b_sub[sky])
    v_flux = float(np.sum(v_sub[aper]) - v_sky * np.sum(aper))
    b_flux = float(np.sum(b_sub[aper]) - b_sky * np.sum(aper))
    if v_flux > 0 and b_flux > 0:
        detected.append({
            'x': cx, 'y': cy,
            'v_inst': -2.5 * np.log10(v_flux),
            'b_inst': -2.5 * np.log10(b_flux)
        })

detected.sort(key=lambda s: s['v_inst'])
print(f"Measured {len(detected)} stars")

# ================================================================
# Step 3: Match catalog to detected stars by magnitude
# ================================================================
N = min(len(catalog), len(detected), 20)
zp_v = float(np.median([catalog[i]['V'] - detected[i]['v_inst'] for i in range(N)]))
print(f"ZP_V estimate: {zp_v:.3f}")

matched = []
used = set()
for cs in catalog:
    best_i, best_d = -1, 999.0
    for di, ds in enumerate(detected):
        if di in used:
            continue
        d = abs(cs['V'] - (ds['v_inst'] + zp_v))
        if d < best_d:
            best_d, best_i = d, di
    if best_i >= 0 and best_d < 0.5:
        matched.append({
            'x': detected[best_i]['x'],
            'y': detected[best_i]['y'],
            'V': cs['V'], 'B': cs['B'], 'BV': cs['BV']
        })
        used.add(best_i)

print(f"Matched: {len(matched)}/{len(catalog)} catalog stars to image positions")

# ================================================================
# Step 4: Write catalog CSV and ground truth
# ================================================================
with open(catalog_csv_path, 'w') as f:
    f.write("star_id,x_pixel,y_pixel,V_mag,B_mag,BV_color\n")
    for i, m in enumerate(matched):
        f.write(f"{i+1},{m['x']:.2f},{m['y']:.2f},{m['V']:.4f},{m['B']:.4f},{m['BV']:.4f}\n")
print(f"Catalog written: {len(matched)} stars")

# Ground truth
v_mags = [m['V'] for m in matched]
b_mags = [m['B'] for m in matched]
bv_colors = [m['BV'] for m in matched]

gt['num_catalog_stars'] = len(matched)
gt['catalog_v_min'] = float(min(v_mags))
gt['catalog_v_max'] = float(max(v_mags))
gt['catalog_v_median'] = float(np.median(v_mags))
gt['catalog_b_min'] = float(min(b_mags))
gt['catalog_b_max'] = float(max(b_mags))
gt['catalog_bv_min'] = float(min(bv_colors))
gt['catalog_bv_max'] = float(max(bv_colors))
gt['catalog_bv_median'] = float(np.median(bv_colors))
gt['catalog_bv_mean'] = float(np.mean(bv_colors))
gt['catalog_bv_std'] = float(np.std(bv_colors))
gt['catalog_csv_created'] = True
gt['zp_v_setup'] = zp_v
gt[f'Vcomb.fits_shape'] = [H, W]
gt[f'Vcomb.fits_mean'] = float(np.mean(v_data))
gt[f'Bcomb.fits_shape'] = list(b_data.shape)
gt[f'Bcomb.fits_mean'] = float(np.mean(b_data))

with open('/tmp/cmd_ground_truth.json', 'w') as f:
    json.dump(gt, f, indent=2)

print(f"\nGround truth saved. V range: [{gt['catalog_v_min']:.2f}, {gt['catalog_v_max']:.2f}]")
print(f"B-V range: [{gt['catalog_bv_min']:.2f}, {gt['catalog_bv_max']:.2f}]")
PYEOF

# Check if catalog was created successfully
if [ $? -ne 0 ]; then
    echo "ERROR: Catalog creation failed"
fi

CATALOG_LINES=$(wc -l < "$PROJECT_DIR/m12_catalog.csv")
echo "Catalog has $CATALOG_LINES lines (including header)"

# Set ownership
chown -R ga:ga "$PROJECT_DIR"

# Record initial state
date +%s > /tmp/task_start_timestamp
echo "0" > /tmp/initial_results_count

# Launch AstroImageJ
launch_astroimagej 120

# Take initial screenshot
sleep 3
take_screenshot /tmp/task_start_screenshot.png

echo "=== Setup Complete ==="
echo "Project directory: $PROJECT_DIR"
echo "V-band image: $PROJECT_DIR/Vcomb.fits"
echo "B-band image: $PROJECT_DIR/Bcomb.fits"
echo "Reference catalog: $PROJECT_DIR/m12_catalog.csv"
echo "Results output: $RESULTS_DIR/"
