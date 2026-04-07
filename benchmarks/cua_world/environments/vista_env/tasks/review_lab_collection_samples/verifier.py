#!/usr/bin/env python3
"""
Verifier for review_lab_collection_samples task.

Verification Strategy:
1. System Check: VistA running, YDBGui accessible (20 pts).
2. Navigation Check: VLM confirms ^LAB(62) is displayed in YDBGui (30 pts).
3. Content Check: VLM confirms specific sample names (e.g., LAVENDER, RED TOP) are visible (50 pts).

The verifier uses ground truth data extracted from the database during setup
to help the VLM identify valid content.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_review_lab_collection_samples(traj, env_info, task_info):
    """
    Verify that the agent navigated to ^LAB(62) and viewed collection samples.
    """
    # 1. Setup - Import utilities and load result
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 2. Basic System Checks (20 points)
    vista_status = result.get('vista_container_status', 'unknown')
    ydbgui_accessible = result.get('ydbgui_accessible', False)
    
    if vista_status == 'running':
        score += 10
        feedback_parts.append("VistA container running")
    else:
        feedback_parts.append("VistA container NOT running")
        
    if ydbgui_accessible:
        score += 10
        feedback_parts.append("YDBGui accessible")
    else:
        feedback_parts.append("YDBGui NOT accessible")

    # 3. VLM Verification (80 points total)
    # We check the final screenshot to see if the correct global is loaded
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    ground_truth_samples = result.get('ground_truth_samples', [])
    
    # Construct VLM prompt with real data context
    sample_list_str = ", ".join(ground_truth_samples[:5]) # Show first 5 examples
    
    vlm_prompt = f"""
    Analyze this screenshot of the VistA YDBGui web interface.
    
    Task: The user should be viewing the 'Collection Sample' file, which is global ^LAB(62).
    
    Check for the following:
    1. GLOBAL NAVIGATION: Is the global '^LAB(62)' or just 'LAB(62)' visible in the navigation bar, breadcrumbs, or search field?
    2. CONTENT VISIBILITY: Do you see list entries for collection samples? Look for common tube names like: {sample_list_str} or similar (LAVENDER, RED TOP, BLUE, URINE, SERUM).
    3. DATA STRUCTURE: Do you see multiple numbered entries (IENs) expanded or listed?
    
    Respond in JSON format:
    {{
        "global_visible": true/false,
        "sample_names_visible": true/false,
        "multiple_entries_visible": true/false,
        "visible_text": ["list", "of", "words", "seen"],
        "reasoning": "explanation"
    }}
    """
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        try:
            vlm_response = query_vlm(prompt=vlm_prompt, image=final_screenshot)
            
            # Safe parsing
            if isinstance(vlm_response, str):
                # Attempt to extract JSON if VLM returned markdown block
                if "