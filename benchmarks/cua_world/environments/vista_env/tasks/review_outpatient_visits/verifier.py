#!/usr/bin/env python3
"""
Verifier for Review Outpatient Visits task in VistA.

Verification Strategy:
1. Verify VistA container and YDBGui are running (infrastructure check).
2. Verify visit data exists in the database (ground truth check).
3. VLM Verification of Trajectory/Final State:
   - Check if Global Viewer is open.
   - Check if ^AUPNVSIT global is selected/visible.
   - Check if visit entries (IENs) are expanded/visible.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_review_outpatient_visits(traj, env_info, task_info):
    """
    Verify that the agent navigated to ^AUPNVSIT and viewed visit records.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    score = 0
    feedback_parts = []
    subscores = {}
    
    # 1. Retrieve Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/review_outpatient_visits_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve/parse result JSON: {str(e)}"
        }
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Infrastructure Checks (20 points)
    # VistA Running (10)
    if result.get('vista_container_status') == 'running':
        score += 10
        subscores['vista_running'] = True
        feedback_parts.append("VistA container is running")
    else:
        feedback_parts.append("VistA container is NOT running")
        
    # YDBGui Accessible (10)
    if result.get('ydbgui_accessible', False):
        score += 10
        subscores['ydbgui_accessible'] = True
        feedback_parts.append("YDBGui is accessible")
    else:
        feedback_parts.append("YDBGui is NOT accessible")

    # 3. Ground Truth Data Availability (Info only, no points directly)
    visit_data_exists = result.get('database_verification', {}).get('visit_data_exists', False)
    sample_visits = result.get('database_verification', {}).get('sample_visits', "")
    if visit_data_exists:
        feedback_parts.append("Visit data confirmed in database")
    else:
        feedback_parts.append("WARNING: No visit data found in database")

    # 4. VLM Visual Verification (80 points)
    # We use the final screenshot to check for the correct global and data visibility
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        vlm_prompt = f"""Analyze this screenshot of the YDBGui VistA interface.
        
        The user was tasked to navigate to the Visit file global: ^AUPNVSIT.
        
        Please check for:
        1. GLOBAL NAVIGATION: Is the global "^AUPNVSIT" (or just "AUPNVSIT") visible? 
           - Look in the tree view, breadcrumbs, search bar, or global listing.
           - Also accept "9000010" (the file number).
           
        2. ENTRIES VISIBLE: Are there numbered entries (IENs) visible under the global?
           - Look for a tree structure expanded with numbers like 1, 2, 3... or larger numbers.
           - Look for data strings that might look like "3051015^..." (dates and pointers).
           
        3. DATA VISIBILITY: Can you see the content of these nodes?
           - Specifically the zero-nodes ending in ",0)".
        
        Ground Truth Sample Data (what to look for):
        {sample_visits[:200]}
        
        Respond in JSON format:
        {{
            "global_navigated": true/false,
            "evidence_global": "string explaining what text confirms the global",
            "entries_expanded": true/false,
            "evidence_entries": "string explaining what entries are seen",
            "data_visible": true/false
        }}
        """
        
        try:
            vlm_resp = query_vlm(prompt=vlm_prompt, image=final_screenshot)
            
            # Parse VLM response (handling potential markdown code blocks)
            if isinstance(vlm_resp, str):
                # Clean up json if wrapped in code blocks
                vlm_resp = vlm_resp.replace('