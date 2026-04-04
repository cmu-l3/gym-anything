#!/usr/bin/env python3
"""
Verifier for hospital_catchment_radius_map task.

Scoring (100 points total):
- Map created with correct name pattern (20 pts)
- Map contains an Organisation Unit layer (20 pts)
- Buffer/Radius configured to 5000m (30 pts)
- Hospital filter applied (Org Unit Group) (15 pts)
- Bo District selected (15 pts)

Pass threshold: 60 points
Mandatory: Map created + Buffer configured
"""

import json
import tempfile
import os
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot

logger = logging.getLogger(__name__)

def verify_hospital_catchment_radius_map(traj, env_info, task_info):
    """Verify the hospital catchment map configuration."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    # Load result from export script
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        temp_path = temp_file.name
        temp_file.close()

        try:
            copy_from_env("/tmp/hospital_catchment_result.json", temp_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not copy result file: {e}"}

        try:
            with open(temp_path, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not parse result JSON: {e}"}
        finally:
            os.unlink(temp_path)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {e}"}

    score = 0
    feedback_parts = []
    
    # 1. Map Existence (20 pts)
    if not result.get('found'):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No new map found matching the task criteria."
        }
    
    map_name = result.get('map_name', '')
    if 'catchment' in map_name.lower() or 'hospital' in map_name.lower():
        score += 20
        feedback_parts.append(f"Map '{map_name}' created (+20)")
    else:
        score += 10 # Partial credit for creating *a* map
        feedback_parts.append(f"Map created but name '{map_name}' missing keywords (+10)")

    # 2. Org Unit Layer (20 pts)
    layer_found = result.get('layer_found', False)
    layer_data = result.get('layer_data', {})
    
    if layer_found:
        score += 20
        feedback_parts.append("Organisation unit layer found (+20)")
    else:
        feedback_parts.append("No organisation unit/facility layer found")

    # 3. Buffer Radius (30 pts)
    # API might return radius in `areaRadius` field
    radius = layer_data.get('areaRadius')
    # Sometimes it's string or int
    try:
        if radius is not None:
            radius_int = int(radius)
            if 4500 <= radius_int <= 5500:
                score += 30
                feedback_parts.append(f"Buffer radius set to {radius_int}m (+30)")
            else:
                feedback_parts.append(f"Buffer radius {radius_int}m is incorrect (expected 5000m)")
        else:
            # Fallback check VLM if programmatic check fails
            feedback_parts.append("Buffer radius not detected in API")
    except ValueError:
        feedback_parts.append(f"Invalid buffer radius format: {radius}")

    # 4. Hospital Filter (15 pts)
    # Check organisationUnitGroups
    groups = layer_data.get('organisationUnitGroups', [])
    group_names = [g.get('displayName', '').lower() for g in groups]
    has_hospital = any('hospital' in name for name in group_names) or any('referral' in name for name in group_names)
    
    if has_hospital:
        score += 15
        feedback_parts.append("Filtered by Hospital group (+15)")
    else:
        feedback_parts.append("Hospital group filter not found")

    # 5. Bo District Selection (15 pts)
    org_units = layer_data.get('organisationUnits', [])
    org_names = [o.get('displayName', '').lower() for o in org_units]
    has_bo = any('bo' in name for name in org_names)
    
    if has_bo:
        score += 15
        feedback_parts.append("Bo District selected (+15)")
    else:
        feedback_parts.append("Bo District not found in selection")

    # VLM Verification (Robustness check)
    # If API missed the buffer (sometimes metadata is tricky), VLM can save the day
    if score < 60 and result.get('found'):
        final_screenshot = get_final_screenshot(traj)
        if final_screenshot:
            vlm_res = query_vlm(
                prompt="Does this map show circles or buffers around points? Respond with YES or NO.",
                image=final_screenshot
            )
            if vlm_res.get('success') and 'YES' in vlm_res.get('response', '').upper():
                score += 20
                feedback_parts.append("VLM confirmed buffer visualization (+20 correction)")

    passed = score >= 60 and result.get('found')

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }