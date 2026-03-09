#!/usr/bin/env python3
"""Verifier for wfs_feature_service_setup task.

A Spatial Data Engineer must:
1. Configure WFS service (enable, title, max features)
2. Create SQL view 'major_cities' in ne workspace
3. Create SLD 'city_marker' with circle mark, red fill
4. Apply style to major_cities layer

Scoring (100 pts, pass >= 60):
- WFS enabled:                          15 pts
- WFS title contains keywords:          10 pts
- WFS max features >= 1000:             10 pts
- SQL view layer 'major_cities' in ne:  25 pts
- Layer is Point geometry type:         10 pts
- SLD 'city_marker' with circle mark:   15 pts
- city_marker applied as default style: 15 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_wfs_feature_service_setup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/wfs_feature_service_setup_result.json", temp_file.name)
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

    # ---- 1. WFS enabled (15 pts) ----
    if result.get('wfs_enabled'):
        score += 15
        subscores['wfs_enabled'] = True
        feedback_parts.append("WFS service is enabled")
    else:
        feedback_parts.append("WFS service is not enabled")

    # ---- 2. WFS title contains keywords (10 pts) ----
    wfs_title = result.get('wfs_title', '')
    title_lower = wfs_title.lower()
    if 'natural earth' in title_lower or ('natural' in title_lower and 'earth' in title_lower):
        score += 10
        subscores['wfs_title'] = True
        feedback_parts.append(f"WFS title contains 'Natural Earth': '{wfs_title}'")
    else:
        feedback_parts.append(f"WFS title not updated: '{wfs_title}'")

    # ---- 3. WFS max features in range [1000, 50000] (10 pts) ----
    # Default GeoServer value is 1000000 — agent must set a specific reasonable limit
    max_features = int(result.get('wfs_max_features', 0))
    if 1000 <= max_features <= 50000:
        score += 10
        subscores['wfs_max_features'] = True
        feedback_parts.append(f"WFS maxFeatures={max_features} (in valid range [1000, 50000])")
    elif max_features > 50000:
        feedback_parts.append(f"WFS maxFeatures={max_features} (default or too high; must be <= 50000)")
    elif max_features > 0:
        score += 3
        feedback_parts.append(f"WFS maxFeatures={max_features} (low value)")
    else:
        feedback_parts.append("WFS maxFeatures not set or is 0")

    # ---- 4. SQL view layer major_cities in ne workspace (25 pts) ----
    if result.get('layer_found'):
        score += 25
        subscores['layer'] = True
        feedback_parts.append(f"SQL view layer '{result.get('layer_name')}' found in ne workspace")
    else:
        feedback_parts.append("SQL view layer 'major_cities' NOT found in ne workspace")
        # Can't pass without the layer
        return {"passed": False, "score": score,
                "feedback": " | ".join(feedback_parts) + " | CRITICAL: major_cities layer missing"}

    # ---- 5. Layer is Point type (10 pts) ----
    if result.get('is_point'):
        score += 10
        subscores['point_type'] = True
        feedback_parts.append("Layer has Point geometry type")
    else:
        geom_type = result.get('layer_geom_type', 'unknown')
        feedback_parts.append(f"Layer geometry type: {geom_type} (expected Point)")

    # ---- 6. SLD city_marker exists with circle mark (15 pts) ----
    if result.get('sld_found'):
        if result.get('sld_has_circle'):
            score += 15
            subscores['sld_circle'] = True
            feedback_parts.append("SLD 'city_marker' found with circle mark")
        else:
            score += 7
            feedback_parts.append("SLD 'city_marker' found but no circle mark detected")
    else:
        feedback_parts.append("SLD 'city_marker' NOT found")

    # ---- 7. Default style applied to major_cities (15 pts) ----
    if result.get('style_match'):
        score += 15
        subscores['style_applied'] = True
        feedback_parts.append(f"Default style '{result.get('major_cities_default_style')}' applied to major_cities")
    elif result.get('major_cities_default_style'):
        feedback_parts.append(f"Default style is '{result.get('major_cities_default_style')}' (expected city_marker)")
    else:
        feedback_parts.append("No default style set on major_cities")

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
                        "A GIS agent is configuring GeoServer WFS and creating an SQL view.\n"
                        "Check the following:\n"
                        "1. 'wfs_settings_visited': Was the WFS service settings page shown?\n"
                        "2. 'sql_view_form_used': Was a SQL view creation form used (SQL input field visible)?\n"
                        "3. 'style_created': Was a style creation/editing form used?\n"
                        "Return JSON: {\"wfs_settings_visited\": bool, \"sql_view_form_used\": bool, \"style_created\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('wfs_settings_visited'):
                        vlm_pts += 3
                    if parsed.get('sql_view_form_used'):
                        vlm_pts += 4
                    if parsed.get('style_created'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM confirmed: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no GUI interactions detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = score >= PASS_THRESHOLD and result.get('layer_found') and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
