#!/usr/bin/env python3
"""Verifier for style_dynamic_geometry_buffer task."""

import json
import tempfile
import os


def verify_style_dynamic_geometry_buffer(traj, env_info, task_info):
    """
    Verify that a 'river_buffer' style was created with a geometry buffer function
    and assigned to the ne_rivers layer.
    """

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/style_dynamic_geometry_buffer_result.json", temp_file.name)
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
        if result.get('result_nonce'):
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Style Exists (20 points)
    if result.get('style_found'):
        score += 20
        feedback_parts.append("Style 'river_buffer' found")
    else:
        return {"passed": False, "score": 0, "feedback": "Style 'river_buffer' NOT found"}

    # 2. SLD Content Analysis (Geometry Buffer) (30 points)
    if result.get('style_has_buffer'):
        score += 30
        feedback_parts.append("SLD contains geometry buffer function")
    else:
        feedback_parts.append("SLD missing buffer function")

    # 3. SLD Content Analysis (Polygon Symbolizer) (10 points)
    if result.get('style_has_polygon'):
        score += 10
        feedback_parts.append("SLD uses PolygonSymbolizer")
    else:
        feedback_parts.append("SLD missing PolygonSymbolizer")

    # 4. SLD Parameters (Distance & Color) (20 points)
    params_score = 0
    if result.get('style_distance_correct'):
        params_score += 10
        feedback_parts.append("Buffer distance 0.1 found")
    if result.get('style_color_correct'):
        params_score += 5
        feedback_parts.append("Red fill found")
    if result.get('style_opacity_correct'):
        params_score += 5
        feedback_parts.append("Opacity 0.5 found")
    score += params_score

    # 5. Layer Assignment (10 points)
    if result.get('layer_assigned'):
        score += 10
        feedback_parts.append("Style assigned to 'ne:ne_rivers'")
    else:
        feedback_parts.append("Style NOT assigned to 'ne:ne_rivers' layer")

    # 6. VLM Verification (10 points) - Verify Style Editor Usage
    # We want to ensure they didn't just curl the REST API (unless that's their workflow, but task implies GUI)
    # Actually, we allow any method, but using VLM confirms "work done".
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, num_samples=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(
                    images=images,
                    prompt=(
                        "Review these screenshots of a user configuring GeoServer.\n"
                        "1. Did the user navigate to the 'Styles' page?\n"
                        "2. Is there an SLD editor or XML code visible?\n"
                        "3. Did the user assign the style to a layer?\n"
                        "Return JSON: {\"styles_page_visited\": bool, \"sld_editor_seen\": bool}"
                    )
                )
                if vlm_result.get('success'):
                    parsed = vlm_result.get('parsed', {})
                    if parsed.get('styles_page_visited') or parsed.get('sld_editor_seen'):
                        vlm_score = 10
                        feedback_parts.append("VLM confirmed GUI style editing")
        except Exception as e:
            print(f"VLM error: {e}")
            # If VLM fails, we fallback to GUI interaction log from export script
            if result.get('gui_interaction_detected'):
                vlm_score = 10
                feedback_parts.append("Log analysis confirmed GUI interaction")
    
    # Fallback if VLM not run but GUI logs exist
    if vlm_score == 0 and result.get('gui_interaction_detected'):
        vlm_score = 10
        feedback_parts.append("GUI interaction detected via logs")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }