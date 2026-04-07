#!/usr/bin/env python3
"""
Verifier for Audit Outpatient Prescriptions task in VistA.

Verification Strategy:
1. Infrastructure: Check VistA running and YDBGui accessible.
2. Ground Truth: Confirm via DB query that refill data actually exists to be seen.
3. Visual (VLM): Analyze trajectory/screenshots to confirm:
   - Navigation to ^PSRX
   - Expansion of a prescription record
   - Visibility of the '1' (Refill) sub-node and its data

Scoring (100 points):
- VistA running: 10
- YDBGui accessible: 10
- Global ^PSRX navigated (VLM): 30
- Prescription record expanded (VLM): 20
- Refill data (Node 1) visible (VLM): 30

Pass threshold: 60 points (Must navigate and open a record)
"""

import os
import json
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_outpatient_prescriptions(traj, env_info, task_info):
    """
    Verify that the user audited outpatient prescription refills in YDBGui.
    """
    # Unpack environment capabilities
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Retrieve result JSON from the container
    import tempfile
    local_result_path = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env("/tmp/audit_outpatient_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    score = 0
    feedback_parts = []
    subscores = {}

    # -------------------------------------------------------------------------
    # 1. Infrastructure Checks (20 points)
    # -------------------------------------------------------------------------
    
    # VistA Status
    if result.get('vista_container_status') == 'running':
        score += 10
        subscores['vista_running'] = True
        feedback_parts.append("VistA container running")
    else:
        feedback_parts.append("VistA container NOT running")

    # YDBGui Accessibility
    if result.get('ydbgui_accessible'):
        score += 10
        subscores['ydbgui_accessible'] = True
        feedback_parts.append("YDBGui accessible")
    else:
        feedback_parts.append("YDBGui NOT accessible")

    # -------------------------------------------------------------------------
    # 2. Database Ground Truth Check (Informational/Prerequisite)
    # -------------------------------------------------------------------------
    db_ver = result.get('database_verification', {})
    if db_ver.get('refill_data_exists'):
        feedback_parts.append("Ground truth: Refill data exists in database")
    else:
        feedback_parts.append("Ground truth WARNING: No refill data found in DB (task might be impossible)")

    # -------------------------------------------------------------------------
    # 3. VLM Visual Verification (80 points)
    # -------------------------------------------------------------------------
    # We use the final screenshot (or a frame from the trajectory if available)
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    vlm_score = 0
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        prompt = """
        Analyze this screenshot of the YDBGui (YottaDB/VistA) web interface.
        
        The user task is to audit Outpatient Prescriptions in the ^PSRX global, specifically looking for REFILL records (Node 1).
        
        Please evaluate the following:
        1. GLOBAL NAVIGATION: Is the global '^PSRX' (Prescription File) visible? Or is an SQL query for PRESCRIPTION visible?
        2. RECORD EXPANSION: Are individual prescription entries (IENs) expanded/visible?
        3. REFILL DATA: Is the sub-node '1' (Refill) visible and expanded? Do you see refill dates or quantities?
           - Look for tree nodes labeled "1" under a prescription ID.
           - Look for data like dates (FileMan format like 3200101) or quantities.
        
        Respond in JSON format:
        {
            "global_visible": boolean,
            "record_expanded": boolean,
            "refill_node_visible": boolean,
            "evidence": "brief description of what you see"
        }
        """
        
        try:
            vlm_response = query_vlm(prompt=prompt, image=final_screenshot)
            
            # Simple parsing if VLM returns string instead of dict
            if isinstance(vlm_response, str):
                # Try to clean markdown
                clean_response = vlm_response.replace('