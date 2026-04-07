#!/usr/bin/env python3
"""
Verifier for raster_to_tabular_csv_export task.

Verification Strategy:
1. Dimensional constraint: We parse the XML of the DIMAP file to check that it is EXACTLY 100x100.
2. Tabular extraction limit: We parse the raw CSV directly inside the export hook, and ensure that the row count matches a ~10,000 spatial extraction.
3. Timestamp anti-gaming: Checks that file modification times occurred AFTER the task started.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_raster_to_tabular_csv(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    score = 0
    feedback_parts = []
    
    dim_exists = result.get('dim_exists', False)
    dim_recent = result.get('dim_recent', False)
    dim_width = result.get('dim_width', 0)
    dim_height = result.get('dim_height', 0)
    
    csv_exists = result.get('csv_exists', False)
    csv_recent = result.get('csv_recent', False)
    csv_rows = result.get('csv_rows', 0)
    csv_headers = result.get('csv_headers', [])
    
    # Criterion 1: DIMAP subset exists and is new (15 points)
    if dim_exists and dim_recent:
        score += 15
        feedback_parts.append("DIMAP subset saved (+15)")
    elif dim_exists:
        score += 5
        feedback_parts.append("DIMAP exists but timestamp unclear (+5)")
    else:
        feedback_parts.append("DIMAP subset not found (0/15)")
        
    # Criterion 2: DIMAP dimensions correct (20 points)
    if dim_exists:
        if dim_width == 100 and dim_height == 100:
            score += 20
            feedback_parts.append("Subset dimensions are exactly 100x100 (+20)")
        elif 90 <= dim_width <= 110 and 90 <= dim_height <= 110:
            score += 10
            feedback_parts.append(f"Subset dimensions are approximate ({dim_width}x{dim_height}) (+10)")
        else:
            feedback_parts.append(f"Subset dimensions incorrect ({dim_width}x{dim_height}) (0/20)")
    else:
        feedback_parts.append("Cannot verify dimensions (no DIMAP) (0/20)")
        
    # Criterion 3: CSV file exported and is new (20 points)
    if csv_exists and csv_recent:
        score += 20
        feedback_parts.append("CSV exported (+20)")
    elif csv_exists:
        score += 10
        feedback_parts.append("CSV exists but timestamp unclear (+10)")
    else:
        feedback_parts.append("CSV not found (0/20)")
        
    # Criterion 4: CSV headers contain spectral bands (15 points)
    # Different data sources may name them 'band_1' vs 'red'. Look for broad matches.
    if csv_exists and csv_headers:
        headers_lower = [h.lower() for h in csv_headers]
        band_cols = [h for h in headers_lower if 'band' in h or 'swir' in h or 'nir' in h or 'red' in h or 'green' in h]
        if len(band_cols) >= 4:
            score += 15
            feedback_parts.append("CSV contains all 4 spectral band columns (+15)")
        elif len(band_cols) > 0:
            score += 8
            feedback_parts.append(f"CSV contains partial spectral columns ({len(band_cols)}) (+8)")
        else:
            feedback_parts.append("CSV missing spectral band columns (0/15)")
    else:
        feedback_parts.append("Cannot verify CSV columns (0/15)")
        
    # Criterion 5: CSV headers contain spatial coordinates (10 points)
    if csv_exists and csv_headers:
        headers_lower = [h.lower() for h in csv_headers]
        has_spatial = any(c in h for h in headers_lower for c in ['x', 'y', 'lat', 'lon', 'pixel'])
        if has_spatial:
            score += 10
            feedback_parts.append("CSV contains spatial coordinate columns (+10)")
        else:
            feedback_parts.append("CSV missing spatial coordinate columns (0/10)")
    else:
        feedback_parts.append("Cannot verify spatial columns (0/10)")
        
    # Criterion 6: CSV row count matches a 100x100 extraction (20 points)
    if csv_exists:
        if 9800 <= csv_rows <= 10200:
            score += 20
            feedback_parts.append(f"CSV row count correct ({csv_rows} rows) (+20)")
        elif 9000 <= csv_rows <= 11000:
            score += 10
            feedback_parts.append(f"CSV row count approximate ({csv_rows} rows) (+10)")
        elif csv_rows > 100000:
            feedback_parts.append(f"CSV row count massive ({csv_rows} rows) - agent likely skipped subset operation (0/20)")
        else:
            feedback_parts.append(f"CSV row count incorrect ({csv_rows} rows) (0/20)")
    else:
        feedback_parts.append("Cannot verify row count (no CSV) (0/20)")
        
    # Key constraints to pass: CSV must exist and contain ~10,000 tabular rows
    key_criteria_met = csv_exists and (9000 <= csv_rows <= 11000)
    passed = (score >= 75) and key_criteria_met
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }