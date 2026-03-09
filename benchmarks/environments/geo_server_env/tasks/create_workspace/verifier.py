#!/usr/bin/env python3
"""Verifier for create_workspace task."""

import json
import tempfile
import os


def verify_create_workspace(traj, env_info, task_info):
    """Verify that a workspace named 'natural_earth' was created in GeoServer."""

    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_workspace_name', 'natural_earth')
    expected_uri = metadata.get('expected_namespace_uri', 'http://naturalearthdata.com')

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/create_workspace_result.json", temp_file.name)
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

    # Score criteria
    score = 0
    feedback_parts = []

    # Workspace exists (20 points)
    if result.get('workspace_found'):
        score += 20
        feedback_parts.append("Workspace found in GeoServer")
    else:
        return {"passed": False, "score": 0, "feedback": "Workspace NOT found in GeoServer"}

    # Workspace name matches (40 points exact, 15 partial)
    ws_name = result.get('workspace_name', '').lower().strip()
    ws_no_sep = ws_name.replace('_', '').replace('-', '').replace(' ', '')
    if ws_name == expected_name.lower():
        score += 40
        feedback_parts.append(f"Workspace name exact match: '{result['workspace_name']}'")
    elif ws_name and (
        ('natural' in ws_name and 'earth' in ws_name) or
        'naturalearth' in ws_no_sep or
        'nat_earth' in ws_name or
        'natearth' in ws_no_sep
    ):
        score += 15
        feedback_parts.append(f"Workspace name partial match: '{result['workspace_name']}'")

    # Namespace URI matches (35 points exact, 10 partial)
    ns_uri = result.get('namespace_uri', '').lower().strip().rstrip('/')
    expected_uri_lower = expected_uri.lower().rstrip('/')
    if ns_uri == expected_uri_lower:
        score += 35
        feedback_parts.append(f"Namespace URI exact match: '{result['namespace_uri']}'")
    elif ns_uri and ('naturalearthdata' in ns_uri or 'natural-earth' in ns_uri or 'naturalearth' in ns_uri):
        score += 10
        feedback_parts.append(f"Namespace URI partial match: '{result['namespace_uri']}'")
    elif ns_uri and ('natural' in ns_uri and 'earth' in ns_uri):
        score += 10
        feedback_parts.append(f"Namespace URI partial match: '{result['namespace_uri']}'")

    # VLM verification using trajectory frames (up to 15 points)
    # If VLM is available and shows NO GUI interaction, block passing (REST API bypass guard)
    vlm_gui_confirmed = True  # default: pass if VLM not available
    query_vlm = env_info.get('query_vlm')
    if query_vlm and traj:
        vlm_gui_confirmed = False  # VLM available: must prove GUI interaction
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
                        "These images show a GUI agent's progression through creating a workspace in GeoServer.\n"
                        "Image 1 is the initial state, subsequent images are sampled during work, last is final state.\n\n"
                        "Check the following (answer JSON):\n"
                        "1. 'navigated_to_workspaces': Did the agent navigate to a workspace-related page?\n"
                        "2. 'workspace_form_visible': Was a workspace creation form visible at any point?\n"
                        "3. 'workspace_created': Is there evidence a workspace named 'natural_earth' was created?\n\n"
                        "Return JSON: {\"navigated_to_workspaces\": bool, \"workspace_form_visible\": bool, \"workspace_created\": bool}"
                    )
                )
                if vlm_result and isinstance(vlm_result, dict) and vlm_result.get('success', True):
                    parsed = vlm_result.get('parsed', {})
                    vlm_pts = 0
                    if parsed.get('navigated_to_workspaces'):
                        vlm_pts += 5
                    if parsed.get('workspace_form_visible'):
                        vlm_pts += 5
                    if parsed.get('workspace_created'):
                        vlm_pts += 5
                    if vlm_pts > 0:
                        score += vlm_pts
                        vlm_gui_confirmed = True
                        feedback_parts.append(f"VLM: trajectory checklist {vlm_pts}/15 pts")
                    else:
                        feedback_parts.append("VLM: no GUI interaction detected in trajectory")
                else:
                    vlm_gui_confirmed = True  # VLM call failed, don't penalize
        except Exception:
            vlm_gui_confirmed = True  # VLM import/call failed, don't penalize

    # Count change bonus (5 points)
    initial = int(result.get('initial_workspace_count', 0))
    current = int(result.get('current_workspace_count', 0))
    if current > initial:
        score += 5
        feedback_parts.append(f"Workspace count increased: {initial} -> {current}")

    # Access-log-based GUI interaction check (fallback when VLM unavailable)
    gui_interaction = result.get('gui_interaction_detected', True)  # default True for old results
    if not gui_interaction:
        feedback_parts.append("WARNING: No GUI form submissions detected in GeoServer access logs")

    # Combined anti-bypass: must have EITHER VLM confirmation OR access log evidence
    gui_confirmed = vlm_gui_confirmed or gui_interaction

    passed = score >= 65 and result.get('workspace_found') and gui_confirmed

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }
