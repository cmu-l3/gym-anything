#!/usr/bin/env python3
"""Verifier for multi_workspace_portal task.

A GIS Lead must build a dual-workspace portal:
- 2 workspaces (infrastructure, environment)
- 2 PostGIS datastores
- 2 layers (settlements in infrastructure, waterways in environment)
- 2 SLD styles (settlement_marker, waterway_line)
- 1 layer group (regional_portal)

Scoring (100 pts, pass >= 65):
- Workspace infrastructure exists:         5 pts
- Workspace environment exists:            5 pts
- Layer settlements in infrastructure:    20 pts
- Layer waterways in environment:         20 pts
- SLD settlement_marker (circle/point):   10 pts
- SLD waterway_line (line symbolizer):    10 pts
- Styles applied as defaults:             10 pts
- Layer group regional_portal with layers: 20 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_multi_workspace_portal(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/multi_workspace_portal_result.json", temp_file.name)
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

    # ---- 1. Workspace infrastructure (5 pts) ----
    if result.get('infra_workspace_found'):
        score += 5
        subscores['infra_ws'] = True
        feedback_parts.append("Workspace 'infrastructure' created")
    else:
        feedback_parts.append("Workspace 'infrastructure' NOT found")

    # ---- 2. Workspace environment (5 pts) ----
    if result.get('env_workspace_found'):
        score += 5
        subscores['env_ws'] = True
        feedback_parts.append("Workspace 'environment' created")
    else:
        feedback_parts.append("Workspace 'environment' NOT found")

    # At least one workspace must exist for any work to be done
    if not result.get('infra_workspace_found') and not result.get('env_workspace_found'):
        return {"passed": False, "score": 0,
                "feedback": "Neither workspace created — task not attempted"}

    # ---- 3. Layer settlements in infrastructure (20 pts) ----
    if result.get('settlements_found'):
        score += 20
        subscores['settlements'] = True
        feedback_parts.append("Layer 'settlements' found in 'infrastructure' workspace")
    else:
        feedback_parts.append("Layer 'settlements' NOT found in 'infrastructure'")

    # ---- 4. Layer waterways in environment (20 pts) ----
    if result.get('waterways_found'):
        score += 20
        subscores['waterways'] = True
        feedback_parts.append("Layer 'waterways' found in 'environment' workspace")
    else:
        feedback_parts.append("Layer 'waterways' NOT found in 'environment'")

    # Mandatory: both layers must exist to pass
    if not result.get('settlements_found') and not result.get('waterways_found'):
        return {"passed": False, "score": score,
                "feedback": " | ".join(feedback_parts) + " | CRITICAL: both layers missing"}

    # ---- 5. SLD settlement_marker (10 pts) ----
    if result.get('settlement_marker_found'):
        if result.get('settlement_marker_has_circle'):
            score += 10
            subscores['settlement_style'] = True
            feedback_parts.append("SLD 'settlement_marker' found with circle mark")
        else:
            score += 5
            feedback_parts.append("SLD 'settlement_marker' found but no circle mark detected")
    else:
        feedback_parts.append("SLD 'settlement_marker' NOT found")

    # ---- 6. SLD waterway_line (10 pts) ----
    if result.get('waterway_line_found'):
        if result.get('waterway_line_has_line'):
            score += 10
            subscores['waterway_style'] = True
            feedback_parts.append("SLD 'waterway_line' found with line symbolizer")
        else:
            score += 5
            feedback_parts.append("SLD 'waterway_line' found but no line symbolizer detected")
    else:
        feedback_parts.append("SLD 'waterway_line' NOT found")

    # ---- 7. Styles applied as defaults (10 pts total) ----
    styles_applied = 0
    if result.get('settlements_style_match'):
        styles_applied += 1
        feedback_parts.append(f"Default style '{result.get('settlements_default_style')}' applied to settlements")
    else:
        ds = result.get('settlements_default_style', '')
        if ds:
            feedback_parts.append(f"Settlements default style: '{ds}' (expected settlement_marker)")
    if result.get('waterways_style_match'):
        styles_applied += 1
        feedback_parts.append(f"Default style '{result.get('waterways_default_style')}' applied to waterways")
    else:
        ds = result.get('waterways_default_style', '')
        if ds:
            feedback_parts.append(f"Waterways default style: '{ds}' (expected waterway_line)")

    if styles_applied == 2:
        score += 10
        subscores['styles_applied'] = True
    elif styles_applied == 1:
        score += 5

    # ---- 8. Layer group regional_portal (20 pts) ----
    if result.get('layer_group_found'):
        lg_count = int(result.get('layer_group_layer_count', 0))
        lg_has_settle = result.get('layer_group_has_settlements', False)
        lg_has_water = result.get('layer_group_has_waterways', False)

        if lg_count >= 2 and lg_has_settle and lg_has_water:
            score += 20
            subscores['layer_group'] = True
            feedback_parts.append(
                f"Layer group 'regional_portal' found with both layers ({lg_count} total)"
            )
        elif lg_count >= 2:
            score += 10
            feedback_parts.append(
                f"Layer group found with {lg_count} layers but missing settlements or waterways"
            )
        elif lg_count >= 1:
            score += 7
            feedback_parts.append(f"Layer group found with {lg_count} layer (expected 2)")
        else:
            score += 3
            feedback_parts.append("Layer group 'regional_portal' found but has no layers")
    else:
        feedback_parts.append("Layer group 'regional_portal' NOT found")

    # ---- VLM trajectory ----
    vlm_gui_confirmed = True
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        vlm_gui_confirmed = False
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_first_screenshot, get_final_screenshot
            first = get_first_screenshot(traj)
            last = get_final_screenshot(traj)
            frames = sample_trajectory_frames(traj, num_samples=5)
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
                        "A GIS agent is setting up a multi-workspace portal in GeoServer.\n"
                        "Check the following:\n"
                        "1. 'multiple_workspaces_created': Were multiple workspace creation forms used?\n"
                        "2. 'multiple_layers_published': Were multiple layer publishing steps visible?\n"
                        "3. 'layer_group_created': Was a layer group creation form shown?\n"
                        "Return JSON: {\"multiple_workspaces_created\": bool, \"multiple_layers_published\": bool, \"layer_group_created\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('multiple_workspaces_created'):
                        vlm_pts += 3
                    if parsed.get('multiple_layers_published'):
                        vlm_pts += 4
                    if parsed.get('layer_group_created'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM confirmed multi-workspace workflow: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no multi-workspace activity detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    # Score cap: if neither layer exists but other criteria pass by accident, cap below threshold
    both_layers = result.get('settlements_found') and result.get('waterways_found')
    if not both_layers and score >= PASS_THRESHOLD:
        score = PASS_THRESHOLD - 1
        feedback_parts.append("Score capped: both layers required to pass")

    passed = score >= PASS_THRESHOLD and both_layers and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
