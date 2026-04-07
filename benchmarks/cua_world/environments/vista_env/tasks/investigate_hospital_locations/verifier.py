#!/usr/bin/env python3
"""
Verifier for Investigate Hospital Locations task in VistA.

Verification Strategy:
1. Infrastructure check: VistA running, YDBGui accessible.
2. VLM Analysis of trajectory:
   - Confirm ^SC global was navigated to.
   - Confirm multiple entries were viewed (at least 5).
   - Confirm both 'Clinic' (Type C) and 'Ward' (Type W) locations were seen.
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_investigate_hospital_locations(traj, env_info, task_info):
    """
    Verify that the agent investigated Hospital Locations (^SC) in YDBGui.
    """
    # 1. Setup & Imports
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # 2. Retrieve Result JSON from container
    import tempfile
    local_result_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/investigate_locations_result.json", local_result_path)
        with open(local_result_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse result JSON: {e}"}
    finally:
        if os.path.exists(local_result_path):
            os.remove(local_result_path)

    # 3. Initialize Score
    score = 0
    feedback_parts = []
    subscores = {}

    # 4. Infrastructure Checks (20 points)
    # VistA Running (10)
    if result.get('vista_container_status') == 'running':
        score += 10
        subscores['infrastructure_vista'] = True
    else:
        subscores['infrastructure_vista'] = False
        feedback_parts.append("VistA container not running.")

    # YDBGui Accessible (10)
    if result.get('ydbgui_accessible'):
        score += 10
        subscores['infrastructure_ydbgui'] = True
    else:
        subscores['infrastructure_ydbgui'] = False
        feedback_parts.append("YDBGui not accessible.")

    # 5. VLM Visual Verification (80 points total)
    # We analyze the final screenshot (or a set of frames if available/supported by wrapper)
    # For this implementation, we focus on the final screenshot + trajectory summary if provided.
    
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        # Construct VLM Prompt
        ground_truth_sample = result.get('ground_truth_sample', 'No Ground Truth Available')
        
        vlm_prompt = f"""
Analyze this screenshot of the VistA/YDBGui web interface.
The user is supposed to be browsing the Hospital Location global (^SC).

Ground Truth Sample (Real locations in DB):
{ground_truth_sample[:500]}...

Please verify the following:
1. GLOBAL NAVIGATED: Is the user viewing the ^SC global (Hospital Location)? Look for "^SC" or "Hospital Location" in the header/navigation/search.
2. ENTRIES VISIBLE: Are there multiple hospital location entries listed or expanded? (Need to see at least 5 ideally).
3. CLINIC AND WARD TYPES: Can you identify entries that are Clinics (Type 'C' or labeled Clinic) AND Wards (Type 'W' or labeled Ward)?
   - Look for the 'Type' field in the data nodes (e.g., 'C' or 'W' in the caret-delimited strings).
   - Or look for location names that imply clinic/ward (e.g., "Gen Med", "Ward 3B").

Provide output in JSON format:
{{
  "sc_global_visible": true/false,
  "multiple_entries_visible": true/false,
  "clinic_type_seen": true/false,
  "ward_type_seen": true/false,
  "reasoning": "..."
}}
"""
        try:
            vlm_resp = query_vlm(prompt=vlm_prompt, image=final_screenshot)
            
            # Simple parsing of VLM response (assuming it returns a dict or json string)
            # If query_vlm returns string, we try to parse it. 
            # If it returns dict, use directly.
            if isinstance(vlm_resp, str):
                # Clean code blocks
                vlm_resp = vlm_resp.replace('