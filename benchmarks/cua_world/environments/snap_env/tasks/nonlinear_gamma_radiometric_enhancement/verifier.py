#!/usr/bin/env python3
"""
Verifier for nonlinear_gamma_radiometric_enhancement task.

Evaluates programmatic execution of SNAP tools.
Criteria:
1. DIMAP product saved & newly created (15 pts)
2. GeoTIFF product exported & newly created (15 pts)
3. Subsetting successful - Exactly 3 bands present in DIMAP (25 pts)
4. Non-linear Band Math applied - Expressions use sqrt or powers (25 pts)
5. GeoTIFF has realistic file size for 3-band export (20 pts)

Pass Threshold: 75 pts with both Subsetting and Band Math criteria showing success.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_nonlinear_gamma_enhancement(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve the result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load export results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # ---------------------------------------------------------
    # Criterion 1: DIMAP Existence & Timestamp (15 points)
    # ---------------------------------------------------------
    dim_exists = result.get('dim_exists', False)
    dim_newly_created = result.get('dim_newly_created', False)
    
    if dim_exists and dim_newly_created:
        score += 15
        feedback_parts.append("DIMAP product saved correctly (+15)")
    elif dim_exists:
        score += 5
        feedback_parts.append("DIMAP product exists but timestamp is old (potential gaming) (+5)")
    else:
        feedback_parts.append("DIMAP product missing (0/15)")

    # ---------------------------------------------------------
    # Criterion 2: GeoTIFF Existence & Timestamp (15 points)
    # ---------------------------------------------------------
    tif_exists = result.get('tif_exists', False)
    tif_newly_created = result.get('tif_newly_created', False)
    
    if tif_exists and tif_newly_created:
        score += 15
        feedback_parts.append("GeoTIFF product exported correctly (+15)")
    elif tif_exists:
        score += 5
        feedback_parts.append("GeoTIFF product exists but timestamp is old (+5)")
    else:
        feedback_parts.append("GeoTIFF product missing (0/15)")

    # ---------------------------------------------------------
    # Criterion 3: Subsetting Validation (25 points)
    # The output MUST contain exactly 3 bands to pass subsetting.
    # ---------------------------------------------------------
    dim_band_count = result.get('dim_band_count', 0)
    subset_passed = False
    
    if dim_band_count == 3:
        subset_passed = True
        score += 25
        feedback_parts.append("Subset successful: Exactly 3 bands found in DIMAP (+25)")
    elif dim_band_count > 3:
        score += 5
        feedback_parts.append(f"Subset failed: {dim_band_count} bands found instead of 3 (Original bands not dropped) (+5)")
    elif dim_band_count > 0:
        score += 10
        feedback_parts.append(f"Subset partial: {dim_band_count} bands found, expected 3 (+10)")
    else:
        feedback_parts.append("No bands found in output product (0/25)")

    # ---------------------------------------------------------
    # Criterion 4: Non-Linear Band Math Validation (25 points)
    # ---------------------------------------------------------
    expressions = result.get('dim_expressions', [])
    band_names = result.get('dim_band_names', [])
    math_passed = False
    
    # Keywords indicating a gamma/sqrt stretch
    math_keywords = ['sqrt', '0.5', '^', 'pow']
    
    expr_match_count = sum(1 for expr in expressions if any(kw in expr.lower() for kw in math_keywords))
    
    if expr_match_count >= 3:
        math_passed = True
        score += 25
        feedback_parts.append("Band Maths successful: Non-linear functions found in 3+ bands (+25)")
    elif expr_match_count > 0:
        score += 15
        feedback_parts.append(f"Band Maths partial: Non-linear functions found in {expr_match_count} bands (+15)")
    else:
        # Fallback check: Did they bake the bands (non-virtual) but name them properly?
        name_match_count = sum(1 for name in band_names if 'gamma' in name.lower() or 'sqrt' in name.lower())
        if name_match_count >= 3:
            math_passed = True
            score += 15
            feedback_parts.append("Band expressions lost, but 3+ bands correctly named 'gamma'/'sqrt' (+15)")
        elif len(expressions) > 0:
            score += 5
            feedback_parts.append("Band Maths used, but no non-linear square root logic detected (+5)")
        else:
            feedback_parts.append("No valid Band Maths expressions or naming conventions found (0/25)")

    # ---------------------------------------------------------
    # Criterion 5: GeoTIFF Size Validation (20 points)
    # ---------------------------------------------------------
    tif_size = result.get('tif_size_bytes', 0)
    
    if tif_size > 1000000:  # > 1MB expected for the Landsat multi-band crop
        score += 20
        feedback_parts.append(f"GeoTIFF size validated ({tif_size/1024/1024:.2f} MB) (+20)")
    elif tif_size > 100000:
        score += 10
        feedback_parts.append(f"GeoTIFF size suspiciously small ({tif_size/1024:.1f} KB) (+10)")
    else:
        feedback_parts.append("GeoTIFF empty or not exported properly (0/20)")

    # ---------------------------------------------------------
    # Optional VLM Trajectory Check
    # ---------------------------------------------------------
    vlm_feedback = ""
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, n=4)
        if frames:
            prompt = """Analyze these screenshots from ESA SNAP.
Does the agent open the 'Band Maths' dialog and use a mathematical formula like 'sqrt()'?
Does the agent open a 'Subset' or export dialog to select specific bands?
Reply in JSON: {"band_math_used": true/false, "subset_used": true/false}"""
            
            try:
                vlm_resp = query_vlm(prompt=prompt, images=frames)
                if vlm_resp.get("success"):
                    v_data = vlm_resp.get("parsed", {})
                    if v_data.get("band_math_used"):
                        vlm_feedback += " | VLM confirms Band Math usage"
                    if v_data.get("subset_used"):
                        vlm_feedback += " | VLM confirms Subset usage"
            except Exception as e:
                logger.warning(f"VLM verification failed: {e}")

    # Determine final pass status
    # Must get >= 75 points and both core criteria (Subset and Math) must have been proven
    passed = (score >= 75) and subset_passed and math_passed
    
    if passed and vlm_feedback:
        feedback_parts.append(vlm_feedback.strip(" | "))

    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback_parts)
    }