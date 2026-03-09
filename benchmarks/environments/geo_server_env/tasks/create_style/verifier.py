#!/usr/bin/env python3
"""Verifier for create_style task."""

import json
import tempfile
import os


def verify_create_style(traj, env_info, task_info):
    """Verify that a style named 'blue_polygon' was created with correct SLD."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_style_name', 'blue_polygon')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_style_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Verify nonce integrity (strict: fail if nonce exists in result but can't be verified)
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

    # Style exists (25 points)
    if result.get('style_found'):
        score += 25
        feedback_parts.append(f"Style found: '{result.get('style_name')}'")
    else:
        return {"passed": False, "score": 0, "feedback": "Style NOT found in GeoServer"}

    # Style name matches (25 points exact, 10 partial — requires both keywords)
    style_name = result.get('style_name', '').lower().strip()
    if style_name == expected_name.lower():
        score += 25
        feedback_parts.append("Style name exact match")
    elif style_name and 'blue' in style_name and 'polygon' in style_name:
        score += 10
        feedback_parts.append(f"Style name partial match: '{result['style_name']}'")

    # SLD has blue fill (20 points)
    if result.get('style_has_fill'):
        score += 20
        feedback_parts.append("SLD contains blue fill color (#0000FF)")

    # SLD has dark blue stroke color #000080 (15 points)
    if result.get('style_has_stroke'):
        score += 15
        feedback_parts.append("SLD contains dark blue stroke color (#000080)")

    # Style count increased (5 points)
    initial = int(result.get('initial_style_count', 0))
    current = int(result.get('current_style_count', 0))
    if current > initial:
        score += 5
        feedback_parts.append(f"Style count increased: {initial} -> {current}")

    # VLM verification using trajectory frames (up to 10 points)
    # If VLM is available and shows NO GUI interaction, block passing (REST API bypass guard)
    vlm_gui_confirmed = True  # default: pass if VLM not available
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        vlm_gui_confirmed = False
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_first_screenshot, get_final_screenshot
            first = get_first_screenshot(traj)
            last = get_final_screenshot(traj)
            frames = sample_trajectory_frames(traj, num_samples=4)
            images = []
            if first:
                images.append(first)
            images.extend([f for f in frames if f not in images])
            if last and last not in images:
                images.append(last)
            if images:
                vlm_result = query_vlm(
                    images=images,
                    prompt=(
                        "These images show a GUI agent's progression through creating an SLD style in GeoServer.\n"
                        "Image 1 is the initial state, subsequent images are sampled during work, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'navigated_to_styles': Did the agent navigate to a styles page?\n"
                        "2. 'style_editor_visible': Was an SLD/style editor or code editor visible at any point?\n"
                        "3. 'style_saved': Is there evidence a style was saved (success message, style list updated)?\n\n"
                        "Return JSON: {\"navigated_to_styles\": bool, \"style_editor_visible\": bool, \"style_saved\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('navigated_to_styles'):
                        vlm_pts += 3
                    if parsed.get('style_editor_visible'):
                        vlm_pts += 4
                    if parsed.get('style_saved'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM: trajectory checklist {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no GUI interaction detected in trajectory")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    has_correct_color = result.get('style_has_fill') and result.get('style_has_stroke')

    # Access-log-based GUI interaction check (fallback when VLM unavailable)
    gui_interaction = result.get('gui_interaction_detected', True)
    if not gui_interaction:
        feedback_parts.append("WARNING: No GUI form submissions detected in GeoServer access logs")

    # Combined anti-bypass: must have EITHER VLM confirmation OR access log evidence
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = score >= 65 and result.get('style_found') and has_correct_color and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
