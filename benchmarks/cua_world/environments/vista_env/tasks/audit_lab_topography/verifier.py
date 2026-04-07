#!/usr/bin/env python3
"""
Verifier for Audit Lab Topography task in VistA.

Verification Strategy:
1. Environment Check: VistA container running, Browser open.
2. VLM Verification: Analyze screenshot for:
   - Navigation to ^LAB(61)
   - Expanded entries showing data
   - Visibility of specimen names (BLOOD, URINE, etc.)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_lab_topography(traj, env_info, task_info):
    """
    Verify that the agent navigated to ^LAB(61) and revealed specimen data.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')

    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_specimens = metadata.get('expected_specimens', ["BLOOD", "URINE", "SERUM"])

    # 1. Retrieve result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/audit_lab_topography_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: VistA Running (10 pts)
    if result.get('vista_container_status') == 'running':
        score += 10
        feedback_parts.append("VistA container running")
    else:
        return {"passed": False, "score": 0, "feedback": "VistA container not running"}

    # Criterion 2: Global Viewer Open (heuristic)
    if result.get('global_viewer_open', False):
        # We give partial credit here, but VLM is the ultimate decider
        feedback_parts.append("Global Viewer detected in title")
    
    # Criterion 3: VLM Visual Verification (90 pts distributed)
    # We prioritize the final screenshot, but could check trajectory if needed.
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        specimens_str = ", ".join(expected_specimens)
        vlm_prompt = f"""
        Analyze this screenshot of the VistA/YottaDB web interface.
        
        Task: Navigate to the Topography Field global ^LAB(61) and browse specimen types.
        
        Please check for the following visual evidence:
        1. Is the Global Viewer visible?
        2. Is the global '^LAB(61)' or '^LAB' with subscript '61' visible in the navigation path or search bar?
        3. Are there expanded tree nodes showing data entries? (Look for indentation or tree structure).
        4. Do you see any of these specimen names: {specimens_str}?
        
        Return a JSON object with:
        {{
            "global_navigated": boolean,
            "entries_expanded": boolean,
            "specimens_visible": boolean,
            "visible_specimen_names": [list of strings found],
            "reasoning": "string"
        }}
        """
        
        try:
            vlm_response = query_vlm(prompt=vlm_prompt, image=final_screenshot)
            # Handle string response vs dict response depending on wrapper
            if isinstance(vlm_response, str):
                # Attempt to parse code block if LLM returned one
                if "