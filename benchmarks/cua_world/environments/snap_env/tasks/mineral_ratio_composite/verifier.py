#!/usr/bin/env python3
"""
Verifier for mineral_ratio_composite task.

Scoring Criteria:
1. DIMAP product saved and created during task (15 pts)
2. Derived ratio bands present (Total bands > 4) (20 pts)
3. Band expressions use division (>= 2 divisions: 20 pts, 1 division: 10 pts)
4. Ratio band naming is descriptive (10 pts)
5. GeoTIFF exported and created during task (15 pts)
6. GeoTIFF has non-trivial size > 500KB (10 pts)
7. VLM check: False color composite visible in trajectory frames (10 pts)

Pass Threshold: 70 points
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mineral_ratio_composite(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve programmatic results from environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: DIMAP product saved
    if result.get("dimap_found"):
        if result.get("dimap_created_during_task"):
            score += 15
            feedback_parts.append("DIMAP product successfully saved (+15)")
        else:
            feedback_parts.append("DIMAP product found but not created during task (0/15)")
    else:
        feedback_parts.append("No DIMAP product found (0/15)")

    # Criterion 2: Derived bands present
    total_bands = result.get("total_bands", 0)
    if total_bands >= 7:
        score += 20
        feedback_parts.append(f"Derived bands present: {total_bands} total bands (+20)")
    elif total_bands > 4:
        score += 10
        feedback_parts.append(f"Partial derived bands: {total_bands} total bands (+10)")
    else:
        feedback_parts.append(f"No derived bands added (Found {total_bands}) (0/20)")

    # Criterion 3: Band expressions use division
    divisions = result.get("division_expressions", 0)
    if divisions >= 2:
        score += 20
        feedback_parts.append(f"Division expressions found: {divisions} (+20)")
    elif divisions == 1:
        score += 10
        feedback_parts.append(f"Division expressions found: {divisions} (+10)")
    else:
        feedback_parts.append("No division expressions found in Band Maths (0/20)")

    # Criterion 4: Descriptive band naming
    named_ratios = result.get("ratio_bands_named", 0)
    if named_ratios >= 2:
        score += 10
        feedback_parts.append("Derived bands use descriptive naming (+10)")
    elif named_ratios == 1:
        score += 5
        feedback_parts.append("Partial descriptive naming (+5)")
    else:
        feedback_parts.append("No descriptive band naming found (0/10)")

    # Criterion 5: GeoTIFF exported
    if result.get("geotiff_found"):
        if result.get("geotiff_created_during_task"):
            score += 15
            feedback_parts.append("GeoTIFF successfully exported (+15)")
        else:
            feedback_parts.append("GeoTIFF found but not created during task (0/15)")
    else:
        feedback_parts.append("No GeoTIFF export found (0/15)")

    # Criterion 6: GeoTIFF size non-trivial
    tiff_size = result.get("geotiff_size_bytes", 0)
    if tiff_size > 500000:  # > 500 KB
        score += 10
        feedback_parts.append(f"GeoTIFF size is non-trivial: {tiff_size/1024:.1f} KB (+10)")
    elif tiff_size > 50000: # > 50 KB
        score += 5
        feedback_parts.append(f"GeoTIFF size is suspiciously small: {tiff_size/1024:.1f} KB (+5)")
    else:
        feedback_parts.append("GeoTIFF is empty or missing (0/10)")

    # 2. VLM Verification for False Color Composite visual evidence
    vlm_score = 0
    try:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        query_vlm = env_info.get("query_vlm")
        
        if query_vlm:
            frames = sample_trajectory_frames(traj, n=3)
            final_frame = get_final_screenshot(traj)
            
            prompt = """Analyze these screenshots of ESA SNAP Desktop.
            Determine if the user has successfully displayed a false-color composite image.
            
            Look for:
            1. An image displayed in the main canvas area.
            2. The image should look like a false-color composite (often highly saturated colors, distinct from standard natural green/brown imagery, usually mapping unusual bands to RGB).
            3. In the Product Explorer or RGB Image Window dialog, is there evidence of derived bands or ratios being used for the R, G, B channels?
            
            Respond with JSON format:
            {
                "image_visible": true/false,
                "is_false_color": true/false,
                "confidence": "low/medium/high",
                "reasoning": "brief explanation"
            }
            """
            
            vlm_res = query_vlm(prompt=prompt, images=frames + [final_frame])
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("image_visible") and parsed.get("is_false_color"):
                    vlm_score = 10
                    feedback_parts.append("VLM confirmed false color composite visible (+10)")
                else:
                    feedback_parts.append("VLM did not detect a valid false color composite (0/10)")
            else:
                feedback_parts.append("VLM check failed or returned no valid JSON (0/10)")
        else:
            feedback_parts.append("VLM check skipped (query_vlm not provided) (0/10)")
    except Exception as e:
        logger.warning(f"VLM verification error: {e}")
        feedback_parts.append(f"VLM verification error (0/10)")

    score += vlm_score

    # Final determination
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }