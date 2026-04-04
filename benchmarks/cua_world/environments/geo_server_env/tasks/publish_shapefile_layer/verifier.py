#!/usr/bin/env python3
"""Verifier for publish_shapefile_layer task."""

import json
import tempfile
import os


def verify_publish_shapefile_layer(traj, env_info, task_info):
    """Verify that the ne_countries layer was published from PostGIS."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_layer = metadata.get('expected_layer_name', 'ne_countries')
    expected_store = metadata.get('expected_store_name', 'postgis_natural_earth')
    expected_workspace = metadata.get('expected_workspace', 'cite')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/publish_shapefile_layer_result.json", temp_file.name)
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

    # Layer exists (25 points)
    if result.get('layer_found'):
        score += 25
        feedback_parts.append(f"Layer found: '{result.get('layer_name')}'")
    else:
        return {"passed": False, "score": 0, "feedback": "Layer NOT found in GeoServer"}

    # Layer name matches (20 points exact, 5 partial)
    layer_name = result.get('layer_name', '').lower().strip()
    if layer_name == expected_layer.lower():
        score += 20
        feedback_parts.append("Layer name exact match")
    elif layer_name and 'countries' in layer_name:
        score += 5
        feedback_parts.append(f"Layer name partial match: '{result['layer_name']}'")

    # Layer in correct workspace (10 points for cite, 0 for wrong workspace)
    layer_in_cite = result.get('layer_in_cite', False)
    layer_workspace = result.get('layer_workspace', '')
    if layer_in_cite:
        score += 10
        feedback_parts.append(f"Layer in correct workspace: '{expected_workspace}'")
    elif layer_workspace:
        feedback_parts.append(f"Layer in WRONG workspace: '{layer_workspace}' (expected '{expected_workspace}')")
    else:
        feedback_parts.append("Layer workspace unknown")

    # Data store exists (15 points)
    if result.get('store_found'):
        score += 15
        feedback_parts.append(f"Data store found: '{result.get('store_name')}'")

        # Store is PostGIS type (5 points)
        store_type = result.get('store_type', '').lower()
        if 'postgis' in store_type:
            score += 5
            feedback_parts.append("Store type is PostGIS")

    # SRS configured (10 points)
    srs = result.get('layer_srs', '')
    if srs and ('4326' in srs or 'EPSG' in srs.upper()):
        score += 10
        feedback_parts.append(f"SRS configured: {srs}")

    # Bounding box set (10 points)
    bbox = result.get('layer_bbox', '')
    if bbox and bbox != ',,,':
        parts = bbox.split(',')
        if len(parts) == 4 and all(p.strip() for p in parts):
            score += 10
            feedback_parts.append("Bounding box computed")

    # Layer count increased (5 points)
    initial = int(result.get('initial_layer_count', 0))
    current = int(result.get('current_layer_count', 0))
    if current > initial:
        score += 5
        feedback_parts.append(f"Layer count increased: {initial} -> {current}")

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
                        "These images show a GUI agent's progression through publishing a PostGIS layer in GeoServer.\n"
                        "Image 1 is the initial state, subsequent images are sampled during work, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'navigated_to_stores': Did the agent navigate to data stores or layers pages?\n"
                        "2. 'store_form_visible': Was a data store creation form visible (PostGIS connection fields)?\n"
                        "3. 'layer_published': Is there evidence a layer was published (layer list, publish button clicked)?\n\n"
                        "Return JSON: {\"navigated_to_stores\": bool, \"store_form_visible\": bool, \"layer_published\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('navigated_to_stores'):
                        vlm_pts += 3
                    if parsed.get('store_form_visible'):
                        vlm_pts += 4
                    if parsed.get('layer_published'):
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

    passed = score >= 60 and result.get('layer_found') and layer_in_cite and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
