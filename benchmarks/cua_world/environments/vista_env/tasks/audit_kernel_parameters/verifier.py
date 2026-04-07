#!/usr/bin/env python3
"""
Verifier for Audit Kernel Parameters task.

Verification Strategy:
1. Check VistA/YDBGui environment health (10 pts)
2. Verify browser is open to Global Viewer/SQL (10 pts)
3. Use VLM to confirm navigation to ^XTV(8989.51) specifically (30 pts)
4. Use VLM to confirm "ORWOR TIMEOUT CHART" and details are visible (50 pts)
"""

import json
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_kernel_parameters(traj, env_info, task_info):
    """
    Verify the agent successfully audited the Kernel Parameter Definition.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # Load result JSON
    import tempfile
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/audit_kernel_parameters_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Environment Checks (10 pts)
    if result.get('vista_container_status') == 'running' and result.get('ydbgui_accessible'):
        score += 10
        feedback_parts.append("Environment active")
    else:
        feedback_parts.append("Environment issues detected")

    # 2. Browser State (10 pts)
    title = result.get('browser_window_title', '').lower()
    if result.get('browser_window_open') and ('global' in title or 'ydbgui' in title or 'octo' in title):
        score += 10
        feedback_parts.append("YDBGui interface open")
    else:
        feedback_parts.append("Browser not on correct interface")

    # 3. Visual Verification with VLM (80 pts total)
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        # We use trajectory frames if available to check navigation, but final state is key here
        prompt = """
        Analyze this screenshot of the VistA YDBGui interface.
        
        I need to verify the user has found a specific Kernel Parameter Definition.
        
        Target Global: ^XTV(8989.51) or "Parameter Definition"
        Target Parameter: "ORWOR TIMEOUT CHART"
        
        Please check:
        1. Is the Global Viewer (or SQL output) visible?
        2. Is the global reference ^XTV(8989.51) or "8989.51" visible?
           (Note: ^XTV(8989.5) is WRONG, that is the Value file. It must be 8989.51)
        3. Is the text "ORWOR TIMEOUT CHART" visible?
        4. Are details like "VALUE DATA TYPE" or "TIMEOUT" visible?
        
        Return JSON:
        {
          "global_8989_51_visible": true/false,
          "parameter_name_visible": true/false,
          "definition_details_visible": true/false,
          "wrong_global_warning": true/false
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt, final_screenshot)
            # Simple parsing in case VLM returns markdown block
            if "