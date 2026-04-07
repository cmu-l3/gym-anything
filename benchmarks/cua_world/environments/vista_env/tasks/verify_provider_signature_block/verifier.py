#!/usr/bin/env python3
"""
Verifier for verify_provider_signature_block task.

Verifies that the agent:
1. Navigated to ^VA(200) (New Person file)
2. Selected User 1
3. Displayed Node 20 (Signature Block)
4. Revealed the signature title matching database ground truth
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_signature_block(traj, env_info, task_info):
    """
    Score the agent's performance based on VLM analysis of the trajectory
    and database ground truth.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Check Environment Status (10 pts)
    if result.get("vista_status") == "running":
        score += 10
        feedback_parts.append("VistA container running")
    else:
        feedback_parts.append("VistA container NOT running")

    # 3. Get Ground Truth
    gt = result.get("ground_truth", {})
    sig_title = gt.get("signature_title", "").strip()
    sig_name = gt.get("signature_name", "").strip()
    
    if not sig_title:
        feedback_parts.append("Warning: Ground truth signature title is empty/missing")

    # 4. VLM Verification
    # We use the final screenshot to check the final state
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        prompt = f"""
        Analyze this screenshot of the VistA YDBGui Global Viewer.
        
        The user should be looking at the NEW PERSON file ^VA(200).
        Specifically, looking for User ID 1 (VEHU,ONE) and Node 20.
        
        Ground Truth to look for:
        - Global: ^VA(200)
        - User: 1 or VEHU,ONE
        - Node: 20
        - Title text: "{sig_title}"
        - Name text: "{sig_name}"
        
        Respond with a JSON object:
        {{
            "global_visible": boolean, // Is ^VA(200) visible?
            "user_selected": boolean, // Is user 1 expanded/selected?
            "node_20_expanded": boolean, // Is the '20' node visible/expanded?
            "title_visible": boolean // Is the text "{sig_title}" visible?
        }}
        """
        
        try:
            vlm_resp = query_vlm(image=final_screenshot, prompt=prompt)
            # Simple parsing if VLM returns string, or assume dict if structured
            if isinstance(vlm_resp, str):
                # Try to clean markdown
                vlm_resp = vlm_resp.replace("