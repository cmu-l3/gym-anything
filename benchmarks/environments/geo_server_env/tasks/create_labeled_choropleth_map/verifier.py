#!/usr/bin/env python3
"""Verifier for create_labeled_choropleth_map task."""

import json
import tempfile
import os

def verify_create_labeled_choropleth_map(traj, env_info, task_info):
    """Verify the choropleth map creation task."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
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

    # Verify nonce integrity
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce check fails (file missing), but other signals are strong, we might be lenient in dev, 
        # but for strict anti-gaming, we fail or warn. Here we strictly check if present in result.
        if result.get('result_nonce'):
             return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    
    # 1. Style Creation (10 pts)
    if result.get('style_found'):
        score += 10
        feedback_parts.append("Style 'population_choropleth' found")
    else:
        feedback_parts.append("Style 'population_choropleth' NOT found")

    # 2. Classification Rules (20 pts)
    rules_count = int(result.get('style_rules_count', 0))
    if rules_count >= 5:
        score += 20
        feedback_parts.append(f"Style has {rules_count} rules (>= 5)")
    elif rules_count > 0:
        score += 5
        feedback_parts.append(f"Style has {rules_count} rules (expected 5)")
    else:
        feedback_parts.append("Style has NO rules")

    # 3. Colors (15 pts)
    if result.get('style_has_colors'):
        score += 15
        feedback_parts.append("All 5 choropleth colors found")
    else:
        feedback_parts.append("Incorrect or missing color scheme")

    # 4. Text Symbolizer (10 pts)
    if result.get('style_has_text'):
        score += 10
        feedback_parts.append("Text labels configured")
    else:
        feedback_parts.append("No text labels found")

    # 5. Halo (5 pts)
    if result.get('style_has_halo'):
        score += 5
        feedback_parts.append("Label halo configured")

    # 6. Stroke (5 pts)
    if result.get('style_has_stroke'):
        score += 5
        feedback_parts.append("Polygon stroke configured")

    # 7. Default Style Application (15 pts)
    if result.get('layer_default_correct'):
        score += 15
        feedback_parts.append("Layer default style correctly set")
    else:
        current_def = result.get('layer_default_style', 'None')
        feedback_parts.append(f"Layer default style incorrect: '{current_def}'")

    # 8. Output Map Image (20 pts)
    if result.get('output_valid'):
        score += 20
        feedback_parts.append("Map image generated successfully")
    elif result.get('output_exists'):
        score += 5
        feedback_parts.append("Map image file exists but seems invalid/small")
    else:
        feedback_parts.append("Map image output NOT found")

    # VLM Verification (Trajectory Analysis)
    # Ensure agent actually used the GUI to create the style
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        # Sample frames
        from gym_anything.vlm import sample_trajectory_frames
        frames = sample_trajectory_frames(traj, num_samples=3)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these images show a user configuring map styles (SLD) or layers in GeoServer? Look for XML code or style editor forms. Answer JSON: {'is_styling': bool}"
            )
            if vlm_res and vlm_res.get('success'):
                is_styling = vlm_res.get('parsed', {}).get('is_styling', False)
                if not is_styling and result.get('style_found'):
                     feedback_parts.append("(VLM: No styling GUI detected)")
                     # We don't deduct points here to be safe, but it's a flag

    # Final Score Calculation
    passed = score >= 60
    
    # Critical failure checks
    if not result.get('style_found'):
        passed = False
    if not result.get('layer_default_correct'):
        passed = False

    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }