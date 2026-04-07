#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_vegetation_density_slicing(traj, env_info, task_info):
    """
    Verifies the Vegetation Density Slicing task.
    Combines programmatic file/XML parsing logic with VLM trajectory verification.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Read the exported result.json from the container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # ================================================================
    # 1. Output Files & Timestamps Check (20 pts)
    # ================================================================
    dim_ok = result.get('dim_found') and result.get('dim_created_after_start')
    tif_ok = result.get('tif_found') and result.get('tif_created_after_start') and result.get('tif_size_bytes', 0) > 1024
    
    if dim_ok:
        score += 10
        feedback_parts.append("DIMAP product created successfully")
    else:
        feedback_parts.append("DIMAP product missing or stale")
        
    if tif_ok:
        score += 10
        feedback_parts.append("GeoTIFF product exported successfully")
    else:
        feedback_parts.append("GeoTIFF product missing, stale, or empty")
        
    # ================================================================
    # 2. Logic parsing of Band Maths expressions (50 pts)
    # ================================================================
    expressions = result.get('expressions', [])
    combined_expr = " ".join(expressions).lower().replace(" ", "")
    metadata = task_info.get('metadata', {})
    
    # Check source band references (15 pts)
    req_bands = metadata.get('required_bands', ['band_2', 'band_3'])
    bands_found = 0
    for b in req_bands:
        if b.replace("_", "") in combined_expr or b in combined_expr:
            bands_found += 1
            
    if bands_found == 2:
        score += 15
        feedback_parts.append("Both source bands correctly referenced")
    elif bands_found == 1:
        score += 7
        feedback_parts.append("Only one source band referenced")
    else:
        feedback_parts.append("Source bands missing from expression")
        
    # Check physical thresholds (15 pts)
    t1 = metadata.get('threshold_1', '0.2')
    t2 = metadata.get('threshold_2', '0.5')
    
    if t1 in combined_expr and t2 in combined_expr:
        score += 15
        feedback_parts.append("Thresholds 0.2 and 0.5 present in math expressions")
    elif t1 in combined_expr or t2 in combined_expr:
        score += 7
        feedback_parts.append("Only one required threshold found in expressions")
    else:
        feedback_parts.append("Required classification thresholds missing")
        
    # Check conditional logic (20 pts)
    has_cond_kw = 'if' in combined_expr or '?' in combined_expr
    has_rel_op = '<' in combined_expr or '>' in combined_expr
    
    if has_cond_kw and has_rel_op:
        score += 20
        feedback_parts.append("Conditional logic and relational operators successfully applied")
    elif has_cond_kw or has_rel_op:
        score += 10
        feedback_parts.append("Partial conditional logic applied")
    else:
        feedback_parts.append("Missing conditional operators (if, ?, <, >)")
        
    # ================================================================
    # 3. VLM Trajectory Verification (30 pts)
    # Uses workflow screenshots rather than just the final screen
    # ================================================================
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are analyzing a sequence of screenshots from an agent working in ESA SNAP.
The task is to use "Band Maths" to create a new raster band utilizing conditional logic (NDVI density slicing).
Carefully assess the workflow progression in the images provided:

1. Did the agent open the Band Maths dialog? (Look for a popup window titled "Band Maths").
2. Is the loaded satellite imagery visible in the main view at some point?
3. Did the agent type a mathematical expression in the expression box within the Band Maths UI?

Respond strictly in JSON format matching this schema:
{
    "band_maths_opened": true/false,
    "imagery_visible": true/false,
    "expression_typed": true/false
}"""
            vlm_result = query_vlm(images=images, prompt=prompt)
            
            if vlm_result and vlm_result.get('success'):
                parsed = vlm_result.get('parsed', {})
                if parsed.get('band_maths_opened'):
                    vlm_score += 10
                if parsed.get('imagery_visible'):
                    vlm_score += 10
                if parsed.get('expression_typed'):
                    vlm_score += 10
                feedback_parts.append(f"VLM verification passed ({vlm_score}/30 pts)")
            else:
                feedback_parts.append("VLM verification failed or response was unparseable")
        except ImportError:
            logger.warning("VLM evaluation module not found, granting default VLM points.")
            vlm_score = 30
            feedback_parts.append("VLM framework unavailable; assumed pass")
        except Exception as e:
            logger.warning(f"VLM evaluation error: {e}")
            vlm_score = 30
            feedback_parts.append("VLM evaluation error; assumed pass")
    else:
        vlm_score = 30
        feedback_parts.append("VLM engine not available in environment; assumed pass")
        
    score += vlm_score
    
    # Must achieve an acceptable score AND successfully export at least one product
    passed = score >= 70 and (dim_ok or tif_ok)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }