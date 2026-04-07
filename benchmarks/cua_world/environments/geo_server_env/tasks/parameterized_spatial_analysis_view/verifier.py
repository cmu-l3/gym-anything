#!/usr/bin/env python3
"""Verifier for parameterized_spatial_analysis_view task.

A GIS Engineer must:
1. Create workspace 'spatial_analytics' with PostGIS store 'city_demographics'
2. Create SQL view 'continental_city_stats' with ST_Contains spatial join,
   LEFT JOIN, GROUP BY aggregation, and target_continent parameter
3. Create SLD 'urban_density_gradient' with 5 graduated city_count rules
4. Apply style as default and generate WMS GetMap images with viewparams

Scoring (100 pts, pass >= 60):
- Workspace found:                           5 pts
- PostGIS datastore in workspace:            5 pts
- SQL view layer exists:                    10 pts
- SQL view has ST_Contains spatial join:    10 pts
- SQL view has GROUP BY aggregation:         5 pts
- SQL view has LEFT JOIN:                    5 pts
- SQL view has target_continent parameter:  10 pts
- Geometry declared as MultiPolygon/4326:    5 pts
- SLD style found with city_count rules:   10 pts
- SLD has >= 5 rules with correct colors:  10 pts
- Default style applied to layer:            5 pts
- Europe output image valid:               10 pts
- Asia output image valid:                 10 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 60


def verify_parameterized_spatial_analysis_view(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/parameterized_spatial_analysis_view_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Nonce integrity check
    nonce_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    try:
        copy_from_env("/tmp/result_nonce", nonce_temp.name)
        with open(nonce_temp.name, 'r') as f:
            expected_nonce = f.read().strip()
        if result.get('result_nonce') != expected_nonce:
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce mismatch"}
    except Exception:
        if result.get('result_nonce'):
            return {"passed": False, "score": 0,
                    "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []

    # 1. Workspace (5 pts)
    if result.get('workspace_found'):
        score += 5
        feedback_parts.append("Workspace 'spatial_analytics' found")
    else:
        feedback_parts.append("Workspace 'spatial_analytics' NOT found")
        return {"passed": False, "score": 0,
                "feedback": "Workspace not found - task not attempted"}

    # 2. PostGIS datastore (5 pts)
    if result.get('datastore_found') and result.get('datastore_is_postgis'):
        score += 5
        feedback_parts.append(f"PostGIS datastore '{result.get('datastore_name')}' found")
    elif result.get('datastore_found'):
        score += 2
        feedback_parts.append("Datastore found but not confirmed PostGIS")
    else:
        feedback_parts.append("No datastore found")

    # 3. SQL view layer exists (10 pts)
    if result.get('layer_found'):
        score += 10
        feedback_parts.append("Layer 'continental_city_stats' found")
    else:
        feedback_parts.append("Layer 'continental_city_stats' NOT found")

    # 4. SQL has ST_Contains (10 pts)
    if result.get('sql_has_st_contains'):
        score += 10
        feedback_parts.append("SQL view uses ST_Contains spatial join")
    else:
        feedback_parts.append("SQL view does not use ST_Contains")

    # 5. SQL has GROUP BY (5 pts)
    if result.get('sql_has_group_by'):
        score += 5
        feedback_parts.append("SQL view has GROUP BY aggregation")
    else:
        feedback_parts.append("SQL view missing GROUP BY")

    # 6. SQL has LEFT JOIN (5 pts)
    if result.get('sql_has_left_join'):
        score += 5
        feedback_parts.append("SQL view uses LEFT JOIN")
    else:
        feedback_parts.append("SQL view does not use LEFT JOIN")

    # 7. Parameter target_continent (10 pts)
    if result.get('has_parameter'):
        param_name = result.get('param_name', '')
        if 'continent' in param_name.lower():
            score += 10
            feedback_parts.append(
                f"Parameter '{param_name}' found "
                f"(default: '{result.get('param_default')}')")
        else:
            score += 5
            feedback_parts.append(
                f"Parameter found but named '{param_name}' "
                f"(expected 'target_continent')")
    else:
        feedback_parts.append("No SQL view parameter found")

    # 8. Geometry declaration (5 pts)
    geom_type = result.get('geom_type', '').lower()
    geom_srid = str(result.get('geom_srid', ''))
    if ('multi' in geom_type and 'polygon' in geom_type) and geom_srid == '4326':
        score += 5
        feedback_parts.append("Geometry correctly declared as MultiPolygon/4326")
    elif geom_srid == '4326':
        score += 2
        feedback_parts.append(f"SRID correct but geometry type is '{geom_type}'")
    else:
        feedback_parts.append(f"Geometry: type={geom_type}, srid={geom_srid}")

    # 9. SLD found with city_count (10 pts)
    if result.get('sld_found'):
        if result.get('sld_has_city_count'):
            score += 10
            feedback_parts.append(
                "SLD 'urban_density_gradient' found with city_count rules")
        else:
            score += 5
            feedback_parts.append("SLD found but no city_count property detected")
    else:
        feedback_parts.append("SLD 'urban_density_gradient' NOT found")

    # 10. SLD rules and colors (10 pts)
    rule_count = int(result.get('sld_rule_count', 0))
    if rule_count >= 5 and result.get('sld_has_correct_colors'):
        score += 10
        feedback_parts.append(
            f"SLD has {rule_count} rules with correct graduated colors")
    elif rule_count >= 5:
        score += 5
        feedback_parts.append(
            f"SLD has {rule_count} rules but colors don't match expected")
    elif rule_count > 0:
        score += 3
        feedback_parts.append(f"SLD has only {rule_count} rule(s) (expected >= 5)")
    else:
        feedback_parts.append("SLD has no rules")

    # 11. Default style applied (5 pts)
    if result.get('default_style_match'):
        score += 5
        feedback_parts.append(
            "Default style 'urban_density_gradient' applied to layer")
    elif result.get('default_style'):
        feedback_parts.append(
            f"Default style is '{result.get('default_style')}' "
            f"(expected urban_density_gradient)")
    else:
        feedback_parts.append("No default style set")

    # 12. Europe output image (10 pts)
    if result.get('europe_img_valid'):
        score += 10
        feedback_parts.append(
            f"Europe image valid ({result.get('europe_img_size')} bytes)")
    elif result.get('europe_img_exists'):
        score += 3
        feedback_parts.append("Europe image exists but may be invalid or too small")
    else:
        feedback_parts.append("Europe output image NOT found")

    # 13. Asia output image (10 pts)
    if result.get('asia_img_valid'):
        score += 10
        feedback_parts.append(
            f"Asia image valid ({result.get('asia_img_size')} bytes)")
    elif result.get('asia_img_exists'):
        score += 3
        feedback_parts.append("Asia image exists but may be invalid or too small")
    else:
        feedback_parts.append("Asia output image NOT found")

    # VLM trajectory verification
    vlm_gui_confirmed = True
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        vlm_gui_confirmed = False
        try:
            from gym_anything.vlm import (sample_trajectory_frames,
                                          get_first_screenshot,
                                          get_final_screenshot)
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
                        "A GIS agent is creating a parameterized SQL view "
                        "layer in GeoServer.\nCheck the following:\n"
                        "1. 'workspace_created': Was a new workspace created?\n"
                        "2. 'sql_view_configured': Was a SQL view creation "
                        "form used (SQL input visible)?\n"
                        "3. 'style_created': Was the SLD/style editor used?\n"
                        "4. 'terminal_used': Was a terminal opened for "
                        "curl/wget commands?\n"
                        'Return JSON: {"workspace_created": bool, '
                        '"sql_view_configured": bool, "style_created": bool, '
                        '"terminal_used": bool}'
                    )
                )
                if (vlm_result and isinstance(vlm_result, dict)
                        and vlm_result.get('success', True)):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('workspace_created'):
                        vlm_pts += 2
                    if parsed.get('sql_view_configured'):
                        vlm_pts += 4
                    if parsed.get('style_created'):
                        vlm_pts += 2
                    if parsed.get('terminal_used'):
                        vlm_pts += 2
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(
                            f"VLM confirmed: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append(
                            "VLM: no GUI interactions detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = (score >= PASS_THRESHOLD
              and result.get('layer_found')
              and gui_confirmed)

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
