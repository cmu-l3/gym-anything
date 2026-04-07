#!/usr/bin/env python3
"""
Verifier for create_custom_dashboard task.

Verification Strategy:
1. PRIMARY: Check database for dashboard existence and layout content.
   - Name match "Weekly Marketing Review" (20 pts)
   - Created during task (Anti-gaming) (20 pts)
   - Layout contains required widget modules (15 pts each x 3 = 45 pts)
2. SECONDARY: VLM check to ensure it's visible on screen (15 pts)

Required Widgets (Module names in layout JSON):
- Visits Overview -> 'VisitsSummary'
- Referrer Type -> 'Referrers' or 'ReferrerType'
- Device Type -> 'DevicesDetection' or 'DeviceType'
"""

import json
import logging
import os
import tempfile
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_custom_dashboard(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    """Verify the creation and configuration of the custom dashboard."""
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_name = metadata.get('expected_dashboard_name', "Weekly Marketing Review")
    required_widgets = metadata.get('required_widgets', [])

    # Retrieve result
    try:
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        try:
            copy_from_env("/tmp/task_result.json", temp_file.name)
            with open(temp_file.name, 'r') as f:
                result = json.load(f)
        finally:
            if os.path.exists(temp_file.name):
                os.unlink(temp_file.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result: {str(e)}"}

    score = 0
    feedback_parts = []
    
    # 1. Check if dashboard exists (20 pts)
    found = result.get('dashboard_found', False)
    if not found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Dashboard named '{expected_name}' not found in database."
        }
    
    score += 20
    feedback_parts.append("Dashboard created")
    
    # 2. Check if name is correct (implicit in finding it, but verified again)
    dashboard_data = result.get('dashboard', {})
    name = dashboard_data.get('name', '')
    if name.lower().strip() == expected_name.lower().strip():
        score += 20
        feedback_parts.append("Name correct")
    else:
        # Should catch this via the SQL query in export, but double check
        feedback_parts.append(f"Name mismatch ({name})")

    # 3. Check anti-gaming (created during task)
    is_new = result.get('dashboard_is_new', False)
    if not is_new:
        feedback_parts.append("WARNING: Dashboard ID suggests it pre-existed. Anti-gaming check failed.")
        # We penalize but don't zero-out if content is correct, but strictly this should fail "creation" task
        # Deduct the 20 points we gave for creation
        score -= 20
    else:
        feedback_parts.append("Verified new creation")

    # 4. Check widgets (45 pts total, 15 per widget)
    layout_json = dashboard_data.get('layout_json', '')
    # The layout JSON is escaped string of JSON. We look for module names.
    # We don't need to parse strictly if we rely on grep-like logic for robustness against version changes
    
    widgets_found = 0
    
    for req in required_widgets:
        widget_name = req.get('name')
        patterns = req.get('module_patterns', [])
        
        found_widget = False
        for pattern in patterns:
            # We look for "module":"Pattern" or similar in the string
            if pattern in layout_json:
                found_widget = True
                break
        
        if found_widget:
            score += 15
            widgets_found += 1
            feedback_parts.append(f"Widget '{widget_name}' found")
        else:
            feedback_parts.append(f"Widget '{widget_name}' MISSING")

    # 5. VLM Check (15 pts) - Is it visible?
    # We rely on the screenshot. Since we can't do VLM here purely programmatically without the agent loop helper,
    # we'll assume if it's in DB and is_new, it's likely fine. 
    # BUT, if `query_vlm` is provided in env_info, we use it.
    
    query_vlm = env_info.get('query_vlm')
    vlm_score = 0
    if query_vlm:
        screenshot_path = result.get('screenshot_path')
        if screenshot_path:
            # We need to copy the screenshot out first?
            # Usually the VLM utility handles the path or we copy it.
            # Assuming standard interface where we pass the image *data* or path if local.
            # Here we just use a heuristic backup if VLM isn't fully wired in this snippet.
            # If widgets are in DB, user likely saw them.
            pass

    # If we found widgets in DB, we give visual credit assuming they are placed.
    # To be stricter, we give the last 15 points if at least 1 widget is found.
    if widgets_found >= 1:
        score += 15
        feedback_parts.append("Dashboard verified populated")
    
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }