#!/usr/bin/env python3
"""
Verifier for the spectral_metadata_restoration task.

Verification Strategy:
1. Validates the BEAM-DIMAP XML export file exists and was modified during the task.
2. Parses the XML to extract the <Spectral_Band_Info> nodes.
3. Scores each of the 4 requested bands independently:
    - Band name renamed correctly (5 pts)
    - Center wavelength assigned (5 pts)
    - Reflectance unit assigned (5 pts)
    - NoData flag and value correctly assigned (5 pts)
   (20 pts per band * 4 = 80 pts)
4. Base score for saving the formatted product (20 pts)
Total = 100 points. Pass threshold = 80.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_spectral_metadata_restoration(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Execution error: copy_from_env not available."}

    # Retrieve output from the environment container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/spectral_metadata_result.json', temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Check 1: Product Archival (20 pts)
    if result.get('dim_found'):
        if result.get('dim_created_during_task'):
            score += 20
            feedback_parts.append("Product exported successfully during task (+20)")
        else:
            # File exists but timestamp doesn't verify it was created during this run
            score += 10
            feedback_parts.append("Product found but not verified as created during task (+10)")
    else:
        feedback_parts.append("Exported DIMAP product not found (0/20)")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    # Expected Band Configurations
    expected_bands = [
        {"name": "SWIR_1", "wavelength": 1650.0},
        {"name": "NIR", "wavelength": 865.0},
        {"name": "Red", "wavelength": 655.0},
        {"name": "Green", "wavelength": 560.0}
    ]
    expected_unit = "reflectance"
    expected_nodata_val = 0.0

    actual_bands = result.get('bands', {})

    # Check 2: Band Level Metadata (4 * 20 pts = 80 pts)
    for expected in expected_bands:
        bname = expected["name"]
        expected_wl = expected["wavelength"]
        
        # Check if band exists by exact name
        if bname in actual_bands:
            score += 5
            b_info = actual_bands[bname]
            band_fb = [f"{bname} found (+5)"]
            
            # Check wavelength (tolerate minor float deviations)
            try:
                actual_wl = float(b_info.get('wavelength') or 0.0)
                if abs(actual_wl - expected_wl) < 1.0:
                    score += 5
                    band_fb.append(f"Wavelength {actual_wl} (+5)")
                else:
                    band_fb.append(f"Wavelength {actual_wl} incorrect (0/5)")
            except ValueError:
                band_fb.append("Wavelength invalid (0/5)")

            # Check unit
            actual_unit = str(b_info.get('unit') or "").strip().lower()
            if actual_unit == expected_unit:
                score += 5
                band_fb.append(f"Unit '{actual_unit}' (+5)")
            else:
                band_fb.append(f"Unit '{actual_unit}' incorrect (0/5)")
                
            # Check NoData flag
            no_data_used = b_info.get('no_data_used', False)
            try:
                no_data_val = float(b_info.get('no_data_value') or -999.0)
                if no_data_used and abs(no_data_val - expected_nodata_val) < 0.01:
                    score += 5
                    band_fb.append("NoData properly configured (+5)")
                else:
                    band_fb.append("NoData misconfigured (0/5)")
            except ValueError:
                band_fb.append("NoData value invalid (0/5)")
                
            feedback_parts.append(f"[{bname}]: " + ", ".join(band_fb))
        else:
            # Fallback checks (Did they edit bands but fail to rename them?)
            # Just mark as 0/20 for this specific target
            feedback_parts.append(f"Band '{bname}' missing from output (0/20)")

    # Final Decision
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }