#!/usr/bin/env python3
"""
Verifier for Review Surgery Cases task in VistA.

Verification Logic:
1. Infrastructure: VistA running, YDBGui accessible.
2. Ground Truth: Confirm surgery data actually exists in the DB.
3. VLM Analysis:
   - Check if Global Viewer is open to ^SRF.
   - Check if case entries (IENs) are expanded.
   - Check if operative details (procedure names, dates) are visible.
   - Verify multiple cases were inspected (trajectory analysis).
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_review_surgery_cases(traj, env_info, task_info):
    """
    Verifies that the agent navigated to ^SRF and viewed surgery cases.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Load Task Result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # --- Scoring Weights ---
    weights = task_info.get('metadata', {}).get('scoring_weights', {
        "vista_running": 10,
        "ydbgui_accessible": 10,
        "global_navigated": 25,
        "cases_expanded": 25,
        "details_visible": 15,
        "multiple_cases": 15
    })

    # 2. Infrastructure Checks (20 pts)
    if result.get('vista_container_status') == 'running':
        score += weights['vista_running']
    else:
        feedback_parts.append("VistA container not running.")

    if result.get('ydbgui_accessible'):
        score += weights['ydbgui_accessible']
    else:
        feedback_parts.append("YDBGui not accessible.")

    # 3. Ground Truth Availability
    gt = result.get('ground_truth', {})
    if not gt.get('data_exists'):
        feedback_parts.append("Warning: Database appears empty. Task may be impossible.")
        # We might adjust scoring here if it was impossible, but usually we expect data.

    # 4. VLM Verification
    # We use the final screenshot primarily, but could verify trajectory for multiple cases
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        
        # We pass the sample data to the VLM so it knows what text to look for
        sample_data = gt.get('sample_data', '')
        
        prompt = f"""
        Analyze this screenshot of the YDBGui VistA interface.
        The user should be viewing the SURGERY file global ^SRF.
        
        Ground Truth Sample Data from DB: {sample_data}
        
        Please check for:
        1. GLOBAL NAVIGATION: Is '^SRF' or 'Surgery' visible in the global selector or path?
        2. ENTRIES EXPANDED: Are numeric entries (IENs) like 1, 2, 3 expanded in the tree view?
        3. DETAILS VISIBLE: Can you see surgery details like 'OP', 'OPERATION', or specific procedure names (e.g. from the sample data above)?
        4. SQL QUERY: Alternatively, is there an SQL query visible selecting from the SURGERY table?
        
        Return JSON:
        {{
            "global_visible": true/false,
            "cases_expanded": true/false,
            "details_visible": true/false,
            "reasoning": "..."
        }}
        """
        
        vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
        
        try:
            # Simple parsing if VLM returns string, or dict access if returns dict
            if isinstance(vlm_resp, str):
                # Try to clean markdown code blocks
                if "