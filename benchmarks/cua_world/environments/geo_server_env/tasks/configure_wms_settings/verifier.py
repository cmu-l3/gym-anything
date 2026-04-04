#!/usr/bin/env python3
"""Verifier for configure_wms_settings task."""

import json
import tempfile
import os


def verify_configure_wms_settings(traj, env_info, task_info):
    """Verify that WMS settings were configured correctly."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_memory = metadata.get('expected_max_memory', 131072)
    expected_time = metadata.get('expected_max_time', 120)
    expected_watermark = metadata.get('expected_watermark_enabled', True)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_wms_settings_result.json", temp_file.name)
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
    any_change = False

    # Max rendering memory (35 points exact + changed, 10 if changed to wrong value, 0 if unchanged)
    current_memory = result.get('current_max_memory', '')
    try:
        memory_val = int(current_memory)
        if memory_val == expected_memory and result.get('memory_changed'):
            score += 35
            feedback_parts.append(f"Max rendering memory correct: {memory_val} KB")
            any_change = True
        elif memory_val == expected_memory:
            # Value matches but wasn't changed — no credit (could be default coincidence)
            feedback_parts.append(f"Max rendering memory matches target but no change detected: {memory_val} KB")
        elif result.get('memory_changed'):
            score += 10
            feedback_parts.append(f"Max rendering memory changed to: {memory_val} KB (expected {expected_memory})")
            any_change = True
        else:
            feedback_parts.append(f"Max rendering memory unchanged: {memory_val} KB")
    except (ValueError, TypeError):
        feedback_parts.append(f"Max rendering memory not set or invalid: '{current_memory}'")

    # Max rendering time (30 points exact + changed, 10 if changed to wrong value, 0 if unchanged)
    current_time = result.get('current_max_time', '')
    try:
        time_val = int(current_time)
        if time_val == expected_time and result.get('time_changed'):
            score += 30
            feedback_parts.append(f"Max rendering time correct: {time_val}s")
            any_change = True
        elif time_val == expected_time:
            # Value matches but wasn't changed — no credit
            feedback_parts.append(f"Max rendering time matches target but no change detected: {time_val}s")
        elif result.get('time_changed'):
            score += 10
            feedback_parts.append(f"Max rendering time changed to: {time_val}s (expected {expected_time})")
            any_change = True
        else:
            feedback_parts.append(f"Max rendering time unchanged: {time_val}s")
    except (ValueError, TypeError):
        feedback_parts.append(f"Max rendering time not set or invalid: '{current_time}'")

    # Watermark enabled (25 points exact + changed, 5 if changed to wrong value, 0 if unchanged)
    current_watermark = result.get('current_watermark', 'false')
    watermark_enabled = current_watermark.lower() == 'true'
    if watermark_enabled == expected_watermark and result.get('watermark_changed'):
        score += 25
        feedback_parts.append(f"Watermark enabled: {watermark_enabled}")
        any_change = True
    elif watermark_enabled == expected_watermark:
        # Value matches but wasn't changed — no credit
        feedback_parts.append(f"Watermark matches target but no change detected: {current_watermark}")
    elif result.get('watermark_changed'):
        score += 5
        feedback_parts.append(f"Watermark setting changed (current: {current_watermark})")
        any_change = True
    else:
        feedback_parts.append(f"Watermark unchanged: {current_watermark}")

    # Any settings changed at all (10 points)
    if any_change:
        score += 10
        feedback_parts.append("WMS settings were modified via GUI")

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
                        "These images show a GUI agent's progression through configuring WMS settings in GeoServer.\n"
                        "Image 1 is the initial state, subsequent images are sampled during work, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'navigated_to_wms': Did the agent navigate to a WMS or services settings page?\n"
                        "2. 'settings_modified': Were form fields modified (memory, time, or watermark settings visible)?\n"
                        "3. 'settings_saved': Is there evidence settings were saved (submit clicked, confirmation shown)?\n\n"
                        "Return JSON: {\"navigated_to_wms\": bool, \"settings_modified\": bool, \"settings_saved\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('navigated_to_wms'):
                        vlm_pts += 3
                    if parsed.get('settings_modified'):
                        vlm_pts += 4
                    if parsed.get('settings_saved'):
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

    # Access-log-based GUI interaction check (fallback when VLM unavailable)
    gui_interaction = result.get('gui_interaction_detected', True)
    if not gui_interaction:
        feedback_parts.append("WARNING: No GUI form submissions detected in GeoServer access logs")

    # Combined anti-bypass: must have EITHER VLM confirmation OR access log evidence
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = score >= 75 and any_change and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
