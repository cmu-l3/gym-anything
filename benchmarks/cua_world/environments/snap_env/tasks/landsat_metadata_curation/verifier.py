#!/usr/bin/env python3
import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_landsat_metadata_curation(traj, env_info, task_info):
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
    feedback = []
    
    metadata = task_info.get('metadata', {})
    expected_band_names = set(metadata.get('expected_band_names', ["SWIR1", "NIR", "Red", "Green"]))
    expected_unit = metadata.get('expected_unit', "reflectance")
    expected_nd_value = metadata.get('expected_no_data_value', 0.0)
    
    if not result.get('dim_found'):
        return {"passed": False, "score": 0, "feedback": "DIMAP product not saved to the expected location (/home/ga/snap_exports/curated_landsat.dim)"}
        
    score += 15
    feedback.append("Product saved in DIMAP format (+15)")
    if not result.get('dim_created_after_start'):
        feedback.append("Warning: DIMAP file was not created/modified after task started")
        
    bands = result.get('bands', [])
    actual_names = [b.get('name', '') for b in bands]
    
    # Criterion 1: Check band names (25 pts)
    renamed_count = sum(1 for name in expected_band_names if name in actual_names)
    if renamed_count == 4:
        score += 25
        feedback.append("All bands renamed correctly (+25)")
    elif renamed_count > 0:
        pts = int(25 * (renamed_count / 4))
        score += pts
        feedback.append(f"Some bands renamed ({renamed_count}/4) (+{pts})")
    else:
        feedback.append("No bands renamed correctly (0/25)")
        
    # Criteria 2-4: Score properties only for available bands
    if len(bands) > 0:
        # Check units (20 pts)
        units_correct = sum(1 for b in bands if b.get('unit', '').lower() == expected_unit.lower())
        if units_correct == 4:
            score += 20
            feedback.append(f"Units assigned correctly for all bands (+20)")
        elif units_correct > 0:
            pts = int(20 * (units_correct / 4))
            score += pts
            feedback.append(f"Units assigned for {units_correct} bands (+{pts})")
        else:
            feedback.append("Units not assigned correctly (0/20)")
            
        # Check no-data enabled (25 pts)
        nd_enabled = sum(1 for b in bands if b.get('no_data_used', False))
        if nd_enabled == 4:
            score += 25
            feedback.append("No-Data enabled for all bands (+25)")
        elif nd_enabled > 0:
            pts = int(25 * (nd_enabled / 4))
            score += pts
            feedback.append(f"No-Data enabled for {nd_enabled} bands (+{pts})")
        else:
            feedback.append("No-Data not enabled correctly (0/25)")
            
        # Check no-data value (15 pts)
        nd_val_correct = sum(1 for b in bands if float(b.get('no_data_value', -999)) == expected_nd_value)
        if nd_val_correct == 4:
            score += 15
            feedback.append(f"No-Data value set to {expected_nd_value} for all bands (+15)")
        elif nd_val_correct > 0:
            pts = int(15 * (nd_val_correct / 4))
            score += pts
            feedback.append(f"No-Data value set correctly for {nd_val_correct} bands (+{pts})")
        else:
            feedback.append("No-Data value not set correctly (0/15)")
    else:
        feedback.append("No bands found in the saved product")
        
    # Consider passed if 75% of criteria are met
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }