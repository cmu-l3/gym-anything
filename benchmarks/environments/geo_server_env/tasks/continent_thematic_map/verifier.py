#!/usr/bin/env python3
"""Verifier for continent_thematic_map task.

A GIS Analyst must:
1. Create workspace 'regional_atlas'
2. Create a PostGIS datastore in it
3. Publish ne_countries as layer 'countries'
4. Create SLD 'continent_colors' with 7 continent rules (distinct colors + ogc filters)
5. Apply style as default to the layer

Scoring (100 pts total, pass >= 65):
- Workspace found:                     10 pts
- PostGIS datastore in workspace:      15 pts
- Layer 'countries' in regional_atlas: 20 pts
- SLD 'continent_colors' found:        10 pts
- SLD has >= 7 rules:                  15 pts
- SLD uses 'continent' in filters:     10 pts
- SLD has >= 6 distinct fill colors:   10 pts
- Default style applied to layer:      10 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

PASS_THRESHOLD = 65


def verify_continent_thematic_map(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})

    # Read result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/continent_thematic_map_result.json", temp_file.name)
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
            return {"passed": False, "score": 0, "feedback": "INTEGRITY FAIL: nonce in result but nonce file unreadable"}
    finally:
        if os.path.exists(nonce_temp.name):
            os.unlink(nonce_temp.name)

    score = 0
    feedback_parts = []
    subscores = {}

    # ---- 1. Workspace found (10 pts) ----
    if result.get('workspace_found'):
        score += 10
        subscores['workspace'] = True
        feedback_parts.append("Workspace 'regional_atlas' found")
    else:
        feedback_parts.append("Workspace 'regional_atlas' NOT found")
        return {"passed": False, "score": 0,
                "feedback": "Workspace 'regional_atlas' not found — task not attempted"}

    # ---- 2. PostGIS datastore (15 pts) ----
    if result.get('datastore_found'):
        ds_type = result.get('datastore_type', '').lower()
        if 'postgis' in ds_type or 'postgres' in ds_type:
            score += 15
            subscores['datastore'] = True
            feedback_parts.append(f"PostGIS datastore '{result.get('datastore_name')}' found")
        else:
            score += 7
            subscores['datastore'] = False
            feedback_parts.append(f"Datastore found but not confirmed PostGIS type: {ds_type}")
    else:
        feedback_parts.append("No datastore found in regional_atlas workspace")

    # ---- 3. Layer 'countries' published (20 pts) ----
    if result.get('layer_found'):
        layer_name = result.get('layer_name', '').lower()
        layer_ws = result.get('layer_workspace', '').lower()
        if layer_ws == 'regional_atlas':
            score += 20
            subscores['layer'] = True
            feedback_parts.append(f"Layer '{result.get('layer_name')}' found in regional_atlas")
        else:
            score += 8
            subscores['layer'] = False
            feedback_parts.append(f"Layer found but in wrong workspace: '{result.get('layer_workspace')}'")
    else:
        feedback_parts.append("Layer 'countries' NOT found in regional_atlas")

    # ---- 4. SLD 'continent_colors' found (10 pts) ----
    if result.get('sld_found'):
        score += 10
        subscores['sld'] = True
        feedback_parts.append("SLD 'continent_colors' found")
    else:
        feedback_parts.append("SLD 'continent_colors' NOT found")

    # ---- 5. SLD has >= 7 rules (15 pts, partial for >= 3) ----
    rule_count = int(result.get('sld_rule_count', 0))
    if rule_count >= 7:
        score += 15
        subscores['sld_rules'] = True
        feedback_parts.append(f"SLD has {rule_count} rules (>= 7 required)")
    elif rule_count >= 3:
        score += 7
        subscores['sld_rules'] = False
        feedback_parts.append(f"SLD has {rule_count} rules (expected >= 7)")
    elif rule_count > 0:
        score += 3
        feedback_parts.append(f"SLD has only {rule_count} rule(s)")
    else:
        feedback_parts.append("SLD has no rules or SLD not found")

    # ---- 6. SLD uses 'continent' property in filters (10 pts) ----
    if result.get('sld_has_continent_filter'):
        score += 10
        subscores['sld_filter'] = True
        feedback_parts.append("SLD uses ogc:PropertyIsEqualTo filter on 'continent' field")
    else:
        feedback_parts.append("SLD does not use 'continent' property in ogc:Filter expressions")

    # ---- 7. SLD has >= 6 distinct fill colors (10 pts, partial for >= 3) ----
    distinct_colors = int(result.get('sld_distinct_colors', 0))
    if distinct_colors >= 6:
        score += 10
        subscores['sld_colors'] = True
        feedback_parts.append(f"SLD has {distinct_colors} distinct fill colors")
    elif distinct_colors >= 3:
        score += 5
        feedback_parts.append(f"SLD has {distinct_colors} distinct fill colors (expected >= 6)")
    elif distinct_colors > 0:
        score += 2
        feedback_parts.append(f"SLD has only {distinct_colors} distinct color(s)")

    # ---- 8. Default style applied to layer (10 pts) ----
    if result.get('default_style_match'):
        score += 10
        subscores['style_applied'] = True
        feedback_parts.append(f"Default style '{result.get('default_style')}' applied to layer")
    elif result.get('default_style'):
        feedback_parts.append(f"Default style is '{result.get('default_style')}' — expected 'continent_colors'")
    else:
        feedback_parts.append("No default style set on layer")

    # ---- VLM trajectory verification (bonus, up to 10 pts) ----
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
                        "A GIS agent is creating a thematic map in GeoServer admin GUI.\n"
                        "Check the following in the screenshots:\n"
                        "1. 'workspace_created': Was a new workspace created (workspace form or list visible)?\n"
                        "2. 'style_editor_used': Was the SLD/style editor used (SLD XML visible or style form)?\n"
                        "3. 'layer_published': Was a new layer published (layer configuration page visible)?\n"
                        "Return JSON: {\"workspace_created\": bool, \"style_editor_used\": bool, \"layer_published\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('workspace_created'):
                        vlm_pts += 3
                    if parsed.get('style_editor_used'):
                        vlm_pts += 4
                    if parsed.get('layer_published'):
                        vlm_pts += 3
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM confirmed GUI workflow: {vlm_pts}/10 pts")
                    else:
                        feedback_parts.append("VLM: no GUI interaction detected")
                else:
                    vlm_gui_confirmed = True
        except Exception:
            vlm_gui_confirmed = True

    gui_interaction = result.get('gui_interaction_detected', True)
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    # Pass condition: must have layer in correct workspace
    layer_in_ws = (result.get('layer_found') and
                   result.get('layer_workspace', '').lower() == 'regional_atlas')
    passed = score >= PASS_THRESHOLD and layer_in_ws and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }
