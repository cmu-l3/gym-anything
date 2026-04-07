#!/usr/bin/env python3
"""
Verifier for log_range_compression_ml_prep task.

Scoring System (100 points total, Pass threshold: 70):
- DIMAP product saved properly: 15 pts
- Log-transformed bands present (>=2): 25 pts (partial 12 pts for 1)
- Log expression references source bands: 15 pts
- Rescaled byte-range band present (>=1): 20 pts
- GeoTIFF exported: 15 pts
- GeoTIFF has non-trivial size (>50KB): 10 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_log_compression(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve or read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # Process DIMAP files
    dim_files = result.get('dim_files', [])
    valid_dims = [d for d in dim_files if d.get('created_after_start', False)]
    
    # 1. DIMAP product saved (15 pts)
    if valid_dims:
        score += 15
        feedback.append("DIMAP product saved after task start (+15)")
    elif dim_files:
        score += 5
        feedback.append("DIMAP product found but timestamp check failed (+5)")
    else:
        feedback.append("No DIMAP product found (0/15)")

    # Analyze expressions in the best DIMAP file
    max_log_bands = 0
    refs_source_band = False
    has_rescaled_band = False

    for dim in dim_files:
        log_count = 0
        vbands = dim.get('virtual_bands', {})
        
        for name, expr in vbands.items():
            expr_lower = expr.lower().replace(" ", "")
            name_lower = name.lower()
            
            # Check for logarithmic transformations
            is_log = 'log' in expr_lower or 'ln' in expr_lower
            if is_log:
                log_count += 1
                # Check if it references source bands
                if any(k in expr_lower for k in ['band', 'swir', 'nir', 'red', 'green', '$']):
                    refs_source_band = True

            # Check for rescaling to 0-255 range
            # Matches: *255, /255, scale, norm, byte
            is_scaled = '255' in expr_lower or 'scale' in name_lower or 'norm' in name_lower or 'byte' in name_lower
            
            # A valid scaled band must either scale a log band, OR be a log band that is also scaled
            references_log_band = any(lb.lower() in expr_lower for lb in vbands.keys() if 'log' in lb.lower() or 'ln' in lb.lower())
            
            if is_scaled and (is_log or references_log_band):
                has_rescaled_band = True

        if log_count > max_log_bands:
            max_log_bands = log_count

    # 2. Log-transformed bands present (25 pts)
    if max_log_bands >= 2:
        score += 25
        feedback.append(f"Found {max_log_bands} log-transformed bands (+25)")
    elif max_log_bands == 1:
        score += 12
        feedback.append("Found 1 log-transformed band. Expected at least 2 (+12)")
    else:
        feedback.append("No log-transformed bands found (0/25)")

    # 3. Log expression references source bands (15 pts)
    if refs_source_band:
        score += 15
        feedback.append("Log expression correctly references source bands (+15)")
    elif max_log_bands > 0:
        feedback.append("Log bands found but source band references missing/unclear (0/15)")

    # 4. Rescaled byte-range band present (20 pts)
    if has_rescaled_band:
        score += 20
        feedback.append("Found rescaled byte-range band (+20)")
    else:
        feedback.append("No rescaled band (0-255 mapping) found (0/20)")

    # Process GeoTIFF files
    tif_files = result.get('tif_files', [])
    valid_tifs = [t for t in tif_files if t.get('created_after_start', False)]
    
    # 5. GeoTIFF exported (15 pts)
    if valid_tifs:
        score += 15
        feedback.append("GeoTIFF export found (+15)")
    elif tif_files:
        score += 5
        feedback.append("GeoTIFF found but timestamp check failed (+5)")
    else:
        feedback.append("No GeoTIFF export found (0/15)")

    # 6. GeoTIFF has non-trivial size (10 pts)
    if valid_tifs:
        max_size = max([t.get('size', 0) for t in valid_tifs])
        if max_size > 50000: # > 50KB
            score += 10
            feedback.append(f"GeoTIFF size is non-trivial ({max_size} bytes) (+10)")
        else:
            feedback.append(f"GeoTIFF export exists but is too small ({max_size} bytes) (0/10)")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }