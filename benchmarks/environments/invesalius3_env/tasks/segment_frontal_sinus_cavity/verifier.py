#!/usr/bin/env python3
"""
Verifier for segment_frontal_sinus_cavity task.

Criteria:
1. STL file exists and is valid. (20 pts)
2. STL was created during the task. (10 pts)
3. Volume is within expected range for Frontal Sinus. (40 pts)
   - Too small (< 500 mm3) -> Empty/Noise
   - Too large (> 50000 mm3) -> Full air mask (includes outside air/nasal cavity)
4. Location (Centroid) is in Anterior-Superior quadrant. (30 pts)
   - Frontal sinus is in the forehead.
   - BBox Z (Vertical) should be high (Upper half of skull).
   - BBox Y (Anterior-Posterior) should be anterior (Front of skull).
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_segment_frontal_sinus_cavity(traj, env_info, task_info):
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_vol = metadata.get("min_volume_mm3", 500)
    max_vol = metadata.get("max_volume_mm3", 50000)
    
    # CT Cranium (0051) specifics:
    # Coordinate system: origin usually at one corner.
    # Dimensions approx: 200mm x 200mm x 150mm.
    # Forehead is high Z, Anterior Y (depending on orientation, typically InVesalius imports as standard medical orientation).
    # We will use relative bounds check based on common anatomy distribution.
    
    score = 0
    feedback_parts = []
    
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/frontal_sinus_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Could not read export result: {e}"
        }

    # 1. File Existence & Validity
    if result.get("file_exists") and result.get("is_valid_stl"):
        score += 20
        feedback_parts.append("Valid STL file created")
    elif result.get("file_exists"):
        feedback_parts.append("File exists but invalid STL")
        return {"passed": False, "score": 10, "feedback": " | ".join(feedback_parts)}
    else:
        feedback_parts.append("No output file found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 2. Created during task
    if result.get("created_during_task", False):
        score += 10
        feedback_parts.append("File created during task window")
    else:
        feedback_parts.append("File timestamp predates task (re-used file?)")

    # 3. Volume Check (The most important check for 'isolation')
    vol = result.get("volume_mm3", 0)
    if vol > 0:
        if min_vol <= vol <= max_vol:
            score += 40
            feedback_parts.append(f"Volume correct ({int(vol)} mm3)")
        elif vol > max_vol:
            # Likely exported all air (room air + sinuses)
            feedback_parts.append(f"Volume too large ({int(vol)} mm3) - did you crop/isolate the sinus?")
            score += 5 # Small credit for exporting something
        else: # vol < min_vol
            feedback_parts.append(f"Volume too small ({int(vol)} mm3) - empty or noise")
    else:
        feedback_parts.append("Volume is zero")

    # 4. Location Check
    # We need to know where the head is.
    # In dataset 0051:
    # Z-axis: 0 (bottom/neck) to ~162mm (top/vertex). Frontal sinus is roughly > 100mm.
    # Y-axis: 0 (back) to ~200mm (front/face). Frontal sinus is roughly > 120mm.
    # If the centroid is [x, y, z]:
    centroid = result.get("centroid", [0,0,0])
    cz = centroid[2]
    cy = centroid[1]
    
    # These thresholds are heuristic based on standard head orientation in this dataset
    # If the user successfully isolated the frontal sinus, the centroid MUST be in the upper-front.
    # If they exported the whole head's air, the centroid would be centered or outside (room air).
    
    location_ok = False
    if vol > 0:
        # Check Z (Height) - should be in top half
        if cz > 80: # Middle of head is approx 80
            # Check Y (Anterior) - should be in front half
            if cy > 100: # Middle of AP is approx 100
                location_ok = True
                score += 30
                feedback_parts.append(f"Location anatomically correct (Z={int(cz)}, Y={int(cy)})")
            else:
                feedback_parts.append(f"Location too posterior (Y={int(cy)})")
        else:
            feedback_parts.append(f"Location too low (Z={int(cz)})")

    # Final Pass Decision
    # Need 70 points.
    # If Volume is good (20+10+40 = 70) -> Pass.
    # If Volume is bad but location is good (20+10+30=60) -> Fail.
    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "volume": vol,
            "centroid": centroid,
            "bbox": result.get("bbox")
        }
    }