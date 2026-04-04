#!/bin/bash
echo "=== Exporting Solar Suitability Analysis Result ==="

source /workspace/scripts/task_utils.sh

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Define paths
RESULT_FILE="/home/ga/GIS_Data/exports/solar_candidates.tif"
INPUT_DEM="/home/ga/GIS_Data/elevation.tif"
OUTPUT_JSON="/tmp/task_result.json"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 3. Check file existence and metadata
FILE_EXISTS="false"
FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"
VALID_FORMAT="false"
ANALYSIS_RESULT="{}"

if [ -f "$RESULT_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$RESULT_FILE")
    FILE_MTIME=$(stat -c%Y "$RESULT_FILE")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi

    # 4. Analyze Raster Content using Python
    # We calculate ground truth slope/aspect on the fly and compare
    echo "Analyzing raster content..."
    ANALYSIS_RESULT=$(python3 << 'PYEOF'
import json
import sys
import numpy as np
from osgeo import gdal

try:
    # Load Input DEM (Ground Truth)
    dem_ds = gdal.Open("/home/ga/GIS_Data/elevation.tif")
    dem_band = dem_ds.GetRasterBand(1)
    dem_arr = dem_band.ReadAsArray()
    gt = dem_ds.GetGeoTransform()
    
    # Load Agent Output
    out_ds = gdal.Open("/home/ga/GIS_Data/exports/solar_candidates.tif")
    if not out_ds:
        print(json.dumps({"valid_format": False, "error": "Could not open output file"}))
        sys.exit(0)
        
    out_band = out_ds.GetRasterBand(1)
    out_arr = out_band.ReadAsArray()
    out_gt = out_ds.GetGeoTransform()
    
    # Check dimensions and geotransform match
    if dem_arr.shape != out_arr.shape:
        print(json.dumps({
            "valid_format": True,
            "spatial_match": False, 
            "error": f"Shape mismatch: expected {dem_arr.shape}, got {out_arr.shape}"
        }))
        sys.exit(0)
        
    # Simple check on geotransform (tolerance for float precision)
    spatial_match = np.allclose(gt, out_gt, atol=1e-5)
    
    # --- Compute Ground Truth ---
    # We use GDAL's DEMProcessing (equivalent to gdaldem) to generate Slope and Aspect
    
    # Calculate Slope
    slope_ds = gdal.DEMProcessing("", dem_ds, "slope", format="MEM", computeEdges=True)
    slope_arr = slope_ds.GetRasterBand(1).ReadAsArray()
    
    # Calculate Aspect
    aspect_ds = gdal.DEMProcessing("", dem_ds, "aspect", format="MEM", computeEdges=True)
    aspect_arr = aspect_ds.GetRasterBand(1).ReadAsArray()
    
    # Criteria: Slope < 10 AND Aspect 135-225
    # Note: different tools might handle aspect boundaries differently, but core logic should hold
    truth_mask = (slope_arr < 10) & (aspect_arr >= 135) & (aspect_arr <= 225)
    
    # --- Analyze Agent Output ---
    # Normalize output to 0/1 (agent might use 0/255 or nodata)
    # Assume any positive value is "suitable"
    agent_mask = (out_arr > 0)
    
    # Calculate IoU (Intersection over Union)
    intersection = np.logical_and(truth_mask, agent_mask).sum()
    union = np.logical_or(truth_mask, agent_mask).sum()
    iou = intersection / union if union > 0 else 0.0
    
    # Calculate Pixel Accuracy
    matches = (truth_mask == agent_mask).sum()
    total_pixels = truth_mask.size
    accuracy = matches / total_pixels
    
    # Logic Verification:
    # Check pixels identified as suitable by agent: Do they generally match the criteria in the DEM?
    # This is more robust than pixel-perfect matching which depends on the specific slope algorithm used.
    
    if agent_mask.sum() > 0:
        # Get slope/aspect values for pixels agent marked as suitable
        agent_slopes = slope_arr[agent_mask]
        agent_aspects = aspect_arr[agent_mask]
        
        # Check percentage of valid pixels
        valid_slope_pct = (agent_slopes < 12).mean() # Allow slight buffer (12 vs 10) for alg diffs
        valid_aspect_pct = ((agent_aspects >= 130) & (agent_aspects <= 230)).mean()
        
        has_content = True
    else:
        valid_slope_pct = 0.0
        valid_aspect_pct = 0.0
        has_content = False
        
    result = {
        "valid_format": True,
        "spatial_match": spatial_match,
        "iou": float(iou),
        "accuracy": float(accuracy),
        "has_content": has_content,
        "valid_slope_pct": float(valid_slope_pct),
        "valid_aspect_pct": float(valid_aspect_pct),
        "pixel_count": int(agent_mask.sum())
    }
    
    print(json.dumps(result))
    
except Exception as e:
    print(json.dumps({"valid_format": False, "error": str(e)}))
PYEOF
    )
fi

# 5. Write JSON Result
cat > "$OUTPUT_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "analysis": $ANALYSIS_RESULT,
    "task_start": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# 6. Cleanup QGIS
kill_qgis ga 2>/dev/null || true

# 7. Print result for log
echo "Export complete. Result:"
cat "$OUTPUT_JSON"