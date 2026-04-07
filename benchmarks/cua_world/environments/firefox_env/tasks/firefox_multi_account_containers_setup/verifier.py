#!/usr/bin/env python3
"""
Verifier for Setup Multi-Account Containers for Workspace Isolation task.

Evaluates:
1. Programmatic: Was `containers.json` modified to include OSINT_Alpha (red/briefcase) and OSINT_Beta (purple/fingerprint)?
2. Programmatic: Are the correct Wikipedia URLs open within the assigned `userContextId` from the active Firefox sessionstore?
3. Anti-gaming: Were these created during the task window?
4. VLM Trajectory: Did the agent naturally navigate the UI, install the extension, and show colored tab indicators?
"""

import os
import json
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_container_identity(identities: List[Dict], name: str) -> Dict:
    """Helper to find a container identity by name."""
    for ident in identities:
        if ident.get('name', '').lower() == name.lower():
            return ident
    return None


def verify_multi_account_containers(traj, env_info, task_info) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    c1_meta = metadata.get('container_1', {})
    c2_meta = metadata.get('container_2', {})

    score = 0
    feedback_parts = []

    # Safe temp file loading wrapper
    def load_json_from_env(env_path: str) -> Dict:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env(env_path, temp_file.name)
            if os.path.getsize(temp_file.name) > 0:
                with open(temp_file.name, 'r') as f:
                    return json.load(f)
        except Exception as e:
            logger.warning(f"Could not load {env_path}: {e}")
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
        return {}

    # 1. Load exported data
    result_summary = load_json_from_env("/tmp/task_result.json")
    containers_data = load_json_from_env("/tmp/containers_export.json")
    session_data = load_json_from_env("/tmp/session_export.json")

    task_start = result_summary.get('task_start', 0)
    
    # Check if app is running
    if result_summary.get('app_running', False):
        score += 5
        feedback_parts.append("Firefox is running")
    else:
        feedback_parts.append("Firefox was closed")

    # =====================================================================
    # CRITERION 1: Verify Containers (identities)
    # =====================================================================
    identities = containers_data.get('identities', [])
    
    alpha_ident = get_container_identity(identities, c1_meta['name'])
    beta_ident = get_container_identity(identities, c2_meta['name'])

    alpha_context_id = None
    beta_context_id = None

    if alpha_ident:
        alpha_context_id = alpha_ident.get('userContextId')
        color_ok = alpha_ident.get('color') == c1_meta['color']
        icon_ok = alpha_ident.get('icon') == c1_meta['icon']
        if color_ok and icon_ok:
            score += 20
            feedback_parts.append("Alpha container perfect")
        else:
            score += 10
            feedback_parts.append("Alpha container exists but color/icon mismatch")
    else:
        feedback_parts.append("Alpha container missing")

    if beta_ident:
        beta_context_id = beta_ident.get('userContextId')
        color_ok = beta_ident.get('color') == c2_meta['color']
        icon_ok = beta_ident.get('icon') == c2_meta['icon']
        if color_ok and icon_ok:
            score += 20
            feedback_parts.append("Beta container perfect")
        else:
            score += 10
            feedback_parts.append("Beta container exists but color/icon mismatch")
    else:
        feedback_parts.append("Beta container missing")

    # Check anti-gaming timestamps
    c_mtime = result_summary.get('containers_json_mtime', 0)
    if alpha_ident or beta_ident:
        if c_mtime < task_start:
            # Containers were pre-existing somehow, heavily penalize
            score = 0
            feedback_parts.append("FAILED: Containers were modified before task start (Anti-gaming)")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # =====================================================================
    # CRITERION 2: Verify Session Store (Tabs in correct containers)
    # =====================================================================
    alpha_tab_found = False
    beta_tab_found = False

    if result_summary.get('session_decompressed', False) and session_data:
        # Search all windows and tabs
        for window in session_data.get('windows', []):
            for tab in window.get('tabs', []):
                # Context ID matches the container
                tab_context_id = tab.get('userContextId', 0)
                
                # Look at the active entry for this tab
                entries = tab.get('entries', [])
                if not entries:
                    continue
                
                # Active entry is usually index (tab.get('index', 1) - 1)
                active_idx = tab.get('index', 1) - 1
                if active_idx < 0 or active_idx >= len(entries):
                    active_idx = -1
                
                current_url = entries[active_idx].get('url', '')

                # Check Alpha
                if alpha_context_id and tab_context_id == alpha_context_id:
                    if c1_meta['url'] in current_url:
                        alpha_tab_found = True

                # Check Beta
                if beta_context_id and tab_context_id == beta_context_id:
                    if c2_meta['url'] in current_url:
                        beta_tab_found = True

    if alpha_tab_found:
        score += 15
        feedback_parts.append("Alpha tab loaded securely")
    else:
        feedback_parts.append("Alpha tab missing/wrong URL")

    if beta_tab_found:
        score += 15
        feedback_parts.append("Beta tab loaded securely")
    else:
        feedback_parts.append("Beta tab missing/wrong URL")

    # =====================================================================
    # CRITERION 3: VLM Trajectory Verification
    # =====================================================================
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    
    frames = sample_trajectory_frames(traj, n=4)
    final_frame = get_final_screenshot(traj)
    all_frames = frames + [final_frame] if final_frame else frames

    vlm_prompt = """
    Review the trajectory of a user configuring Firefox Multi-Account Containers.
    
    1. Did the user navigate the Firefox Add-ons store and legitimately install an extension?
    2. Are there two visibly distinct container tabs open in the final frames? 
       (Container tabs have colored underlines beneath the tab title - specifically red and purple).
    3. Does the UI show Wikipedia pages loaded in those tabs?

    Respond in JSON format:
    {
        "extension_installed": true/false,
        "colored_tabs_visible": true/false,
        "wikipedia_loaded": true/false
    }
    """

    vlm_result = query_vlm(images=all_frames, prompt=vlm_prompt)
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        if parsed.get("extension_installed"):
            score += 10
            feedback_parts.append("VLM confirmed extension installation")
        if parsed.get("colored_tabs_visible") and parsed.get("wikipedia_loaded"):
            score += 15
            feedback_parts.append("VLM confirmed container tab visibility")

    # Determine Pass/Fail
    # To pass, they must have created the containers AND successfully loaded at least one in context.
    key_criteria_met = (alpha_context_id is not None) and (beta_context_id is not None) and (alpha_tab_found or beta_tab_found)
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }