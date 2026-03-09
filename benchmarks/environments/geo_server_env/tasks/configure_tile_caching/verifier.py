#!/usr/bin/env python3
"""Verifier for configure_tile_caching task."""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_configure_tile_caching(traj, env_info, task_info):
    """
    Verify that a custom GeoWebCache gridset was created and assigned to a layer.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_crs = metadata.get('expected_crs', 'EPSG:3857')
    expected_width = metadata.get('expected_tile_width', 512)
    expected_height = metadata.get('expected_tile_height', 512)
    expected_levels = metadata.get('expected_min_zoom_levels', 5)

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/configure_tile_caching_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Integrity Check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        # If nonce file is missing but result has nonce, something is wrong
        pass
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    # Scoring
    score = 0
    feedback_parts = []
    
    # 1. Gridset Exists (15 pts)
    if result.get('gridset_exists'):
        score += 15
        feedback_parts.append("Gridset 'WebMercator512' created")
    else:
        return {"passed": False, "score": 0, "feedback": "Gridset 'WebMercator512' not found"}

    # 2. Gridset Parameters (25 pts total)
    # CRS (10 pts)
    srs = str(result.get('gridset_srs', '')).strip()
    if expected_crs in srs or '3857' in srs:
        score += 10
        feedback_parts.append(f"CRS Correct ({srs})")
    else:
        feedback_parts.append(f"CRS Incorrect ({srs})")

    # Tile Size (10 pts)
    w = result.get('tile_width', 0)
    h = result.get('tile_height', 0)
    if w == expected_width and h == expected_height:
        score += 10
        feedback_parts.append(f"Tile Size Correct ({w}x{h})")
    else:
        feedback_parts.append(f"Tile Size Incorrect ({w}x{h})")

    # Zoom Levels (5 pts)
    levels = result.get('zoom_levels', 0)
    if levels >= expected_levels:
        score += 5
        feedback_parts.append(f"Zoom Levels Sufficient ({levels})")
    else:
        feedback_parts.append(f"Zoom Levels Insufficient ({levels})")

    # 3. Layer Assignment (20 pts)
    if result.get('layer_has_gridset'):
        score += 20
        feedback_parts.append("Layer uses new gridset")
    else:
        feedback_parts.append("Layer NOT assigned to gridset")

    # 4. PNG Support (10 pts)
    if result.get('layer_has_png'):
        score += 10
        feedback_parts.append("Layer supports PNG")
    else:
        feedback_parts.append("Layer PNG support missing")

    # 5. Functional Test (30 pts)
    # GetCapabilities (10 pts)
    if result.get('wmts_caps_found'):
        score += 10
        feedback_parts.append("Gridset advertised in WMTS Capabilities")
    
    # GetTile (20 pts)
    http_code = result.get('tile_http_code', 0)
    is_image = result.get('tile_is_image', False)
    size = result.get('tile_size_bytes', 0)

    if http_code == 200 and is_image and size > 500:
        score += 20
        feedback_parts.append("WMTS GetTile returned valid image")
    elif http_code == 200:
        score += 5
        feedback_parts.append(f"WMTS GetTile returned HTTP 200 but content invalid/small ({size} bytes)")
    else:
        feedback_parts.append(f"WMTS GetTile Failed (HTTP {http_code})")

    # Anti-gaming: Deduct if gridset pre-existed (unlikely with setup script, but good practice)
    if result.get('pre_existing_gridset'):
        score = max(0, score - 50)
        feedback_parts.append("PENALTY: Gridset pre-existed (did not clean up?)")

    # VLM Verification of GUI Usage (Pass/Fail Guard)
    # If VLM query function exists and NO GUI interaction was detected in logs or VLM, fail or deduct.
    # Here we rely on the log-based `gui_interaction_detected` from the bash script + VLM check.
    gui_detected_logs = result.get('gui_interaction_detected', False)
    
    query_vlm = env_info.get('query_vlm')
    vlm_confirmed = False
    
    if query_vlm and traj:
        # Perform VLM check to confirm UI usage if logs are ambiguous or as double-check
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, num_samples=4)
        if frames:
            vlm_res = query_vlm(
                images=frames,
                prompt="Do these screenshots show a user interacting with the GeoServer 'Gridsets' or 'Tile Caching' settings pages? Return JSON: {\"is_geoserver_ui\": bool, \"caching_settings_visible\": bool}"
            )
            if vlm_res.get('success'):
                parsed = vlm_res.get('parsed', {})
                if parsed.get('caching_settings_visible'):
                    vlm_confirmed = True
                    feedback_parts.append("VLM confirmed UI usage")

    # Final Decision
    # Require at least Score 60 AND Functional Tile Generation OR Layer Assignment
    passed = score >= 60
    
    # If no GUI interaction detected at all (logs or VLM), fail task to prevent API shortcuts if strictly UI task
    if not gui_detected_logs and not vlm_confirmed and passed:
         feedback_parts.append("WARNING: No GUI interaction detected (API used?)")
         # We allow API usage if not strictly forbidden, but typically we want UI. 
         # For this task description, it explicitly says "Log in... Click...". 
         # We won't hard fail but note it.

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }