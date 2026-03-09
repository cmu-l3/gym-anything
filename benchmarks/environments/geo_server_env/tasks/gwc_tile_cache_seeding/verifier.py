#!/usr/bin/env python3
"""Verifier for gwc_tile_cache_seeding task.

A GIS Platform Architect must:
1. Configure GWC tile layer for ne:ne_countries
2. Add EPSG:4326 and EPSG:900913 gridsets
3. Set image/png as tile format
4. Trigger tile seeding for EPSG:4326, zoom 0-3

Scoring (100 pts, pass >= 60):
- GWC tile layer exists for ne:ne_countries: 20 pts
- EPSG:4326 gridset configured:            20 pts
- EPSG:900913 gridset configured:          15 pts
- image/png tile format configured:        15 pts
- Tile seeding triggered:                  30 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_gwc_tile_cache_seeding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/gwc_tile_cache_seeding_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Nonce check
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
    subscores = {}

    # ---- 1. GWC tile layer exists for ne:ne_countries (20 pts) ----
    if result.get('gwc_found'):
        score += 20
        subscores['gwc_layer'] = True
        feedback_parts.append("GWC tile layer found for ne:ne_countries")
    else:
        feedback_parts.append("GWC tile layer NOT found for ne:ne_countries — task not attempted")
        return {"passed": False, "score": 0,
                "feedback": "GWC tile layer for ne:ne_countries not found"}

    # ---- 2. EPSG:4326 gridset configured (20 pts) ----
    if result.get('has_epsg4326'):
        score += 20
        subscores['epsg4326'] = True
        feedback_parts.append("EPSG:4326 gridset is configured")
    else:
        gridsets = result.get('gridsets', '')
        feedback_parts.append(f"EPSG:4326 gridset NOT found. Configured gridsets: '{gridsets}'")

    # ---- 3. EPSG:900913 gridset configured (15 pts) ----
    if result.get('has_epsg900913'):
        score += 15
        subscores['epsg900913'] = True
        feedback_parts.append("EPSG:900913 (Web Mercator) gridset is configured")
    else:
        feedback_parts.append("EPSG:900913 gridset NOT found (expected Web Mercator)")

    # ---- 4. image/png format (15 pts) ----
    if result.get('has_png'):
        score += 15
        subscores['png_format'] = True
        feedback_parts.append("image/png tile format is configured")
    else:
        formats = result.get('formats', '')
        feedback_parts.append(f"image/png format NOT found. Configured formats: '{formats}'")

    # ---- 5. Tile seeding triggered (30 pts) ----
    seed_triggered = result.get('seed_triggered', False)
    seed_status = result.get('seed_task_status', '')
    seed_api_calls = int(result.get('seed_api_calls', 0))

    if seed_triggered:
        # Check the seed task status
        if 'done' in seed_status or 'running' in seed_status or 'pending' in seed_status:
            score += 30
            subscores['seed'] = True
            feedback_parts.append(f"Tile seeding triggered and active/complete: {seed_status}")
        elif 'aborted' in seed_status:
            score += 10
            feedback_parts.append(f"Tile seed was triggered but then aborted: {seed_status}")
        else:
            score += 20
            feedback_parts.append(f"Tile seeding triggered (status: {seed_status})")
    elif seed_api_calls > 0:
        # Detected GWC API calls in log (seed may have been triggered via REST)
        score += 15
        feedback_parts.append(f"GWC API calls detected in logs ({seed_api_calls} POST requests)")
    else:
        feedback_parts.append("Tile seeding NOT triggered for ne:ne_countries")
        # Score cap: configuring GWC without actually seeding cannot pass
        if score >= PASS_THRESHOLD:
            score = PASS_THRESHOLD - 5
            feedback_parts.append("Score capped: seeding required to pass")

    # ---- VLM trajectory ----
    vlm_gui_confirmed = True
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
                        "A GIS agent is configuring GeoWebCache tile caching in GeoServer.\n"
                        "Check the following in the screenshots:\n"
                        "1. 'gwc_tile_layers_visited': Was the Tile Caching/Tile Layers page shown?\n"
                        "2. 'gridset_config_used': Was a gridset configuration form or gridset selector visible?\n"
                        "3. 'seed_form_used': Was a tile seed/truncate form or operation initiated?\n"
                        "Return JSON: {\"gwc_tile_layers_visited\": bool, \"gridset_config_used\": bool, \"seed_form_used\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('gwc_tile_layers_visited'):
                        vlm_pts += 3
                    if parsed.get('gridset_config_used'):
                        vlm_pts += 4
                    if parsed.get('seed_form_used'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM confirmed GWC workflow: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no GWC tile configuration detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = score >= PASS_THRESHOLD and result.get('gwc_found') and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
