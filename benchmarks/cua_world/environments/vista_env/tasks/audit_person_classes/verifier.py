#!/usr/bin/env python3
"""
Verifier for Audit Person Classes task.

Verification Strategy:
1. Environment Check: VistA running, YDBGui accessible.
2. Ground Truth Verification: Confirm 'Emergency Medicine' exists in database.
3. VLM Verification: Analyze screenshot for:
   - Navigation to ^USC(8932.1)
   - Visibility of 'Emergency Medicine'
   - Visibility of the X12 Taxonomy Code (e.g., 207P00000X)
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_person_classes(traj, env_info, task_info):
    """
    Verify that the agent found the Emergency Medicine person class and its code.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Environment Checks (20 pts)
    if result.get('ydbgui_accessible'):
        score += 20
        feedback_parts.append("YDBGui was accessible.")
    else:
        feedback_parts.append("YDBGui was NOT accessible.")

    # 2. Ground Truth Check
    gt = result.get('ground_truth', {})
    gt_code = gt.get('x12_code', '')
    if not gt.get('found'):
        return {
            "passed": False, 
            "score": score, 
            "feedback": "Internal Error: 'Emergency Medicine' not found in VistA database (Ground Truth check failed)."
        }

    # 3. VLM Verification (80 pts)
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        prompt = f"""
        Analyze this screenshot of the VistA/YDBGui Electronic Health Record interface.
        
        Task: The user should be viewing the 'Person Class' file (^USC(8932.1)) to find 'Emergency Medicine'.
        
        Look for:
        1. The global name '^USC' or '^USC(8932.1)' or 'PERSON CLASS'.
        2. The text 'Emergency Medicine'.
        3. A code appearing near 'Emergency Medicine', specifically '{gt_code}' or a code starting with '207P'.
        
        Return JSON:
        {{
            "global_visible": boolean,
            "term_visible": boolean,
            "code_visible": boolean,
            "visible_code_text": "text of code if seen"
        }}
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
        
        # Parse VLM response
        try:
            # Handle potential markdown wrapping
            if "