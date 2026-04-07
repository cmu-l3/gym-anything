#!/usr/bin/env python3
"""
Verifier for interactive_log_explorer task.

Validates the agent successfully created a form-based Simple XML dashboard
in Splunk with specific parameterized search inputs.

Scoring Breakdown (Total: 100):
1. Dashboard Exists (15 pts)
2. Root is a Form (15 pts)
3. Text Input Token matches 'ip_filter' (15 pts)
4. Dropdown Input Token matches 'level_filter' (15 pts)
5. Search Parameterization uses tokens & index (20 pts)
6. VLM Trajectory Verification of UI Usage (20 pts)
"""

import json
import tempfile
import os
import logging
import xml.etree.ElementTree as ET

from gym_anything.vlm import get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


# =============================================================================
# VLM PROMPT FOR UI VERIFICATION
# =============================================================================

UI_VERIFICATION_PROMPT = """You are verifying if an agent used the Splunk web interface to create an interactive dashboard.

TASK: Create a form dashboard in Splunk with Text and Dropdown inputs.

Look at these screenshots from the agent's chronological trajectory:
1. Is the Splunk web interface visible?
2. Did the agent interact with the dashboard editing UI (e.g., clicking "Edit", "Add Input", configuring tokens)?
3. Is there evidence of adding or configuring inputs (like a Text box, Dropdown, or Time Picker)?

Respond in JSON format:
{
    "splunk_ui_visible": true/false,
    "dashboard_edit_ui_used": true/false,
    "inputs_added_or_configured": true/false,
    "confidence": "low"/"medium"/"high",
    "reasoning": "brief explanation of what you see"
}
"""

def verify_interactive_log_explorer(traj, env_info, task_info):
    """Verify that the agent built the parameterized form dashboard."""
    
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/interactive_log_explorer_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    dashboard_found = result.get('found', False)
    xml_content = result.get('xml', '')

    # CRITERION 1: Dashboard Exists (15 pts)
    if dashboard_found and xml_content:
        score += 15
        feedback_parts.append("Dashboard 'web_error_investigator' found")
    else:
        feedback_parts.append("FAIL: Dashboard 'web_error_investigator' was not found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # XML Parsing
    try:
        root = ET.fromstring(xml_content)
        
        # CRITERION 2: Root is a Form (15 pts)
        is_form = root.tag == 'form' or root.find('.//fieldset') is not None
        if is_form:
            score += 15
            feedback_parts.append("Dashboard configured as a form")
        else:
            feedback_parts.append("FAIL: Dashboard is not a form (missing <fieldset> / <form>)")

        # CRITERION 3 & 4: Input Tokens (15 pts each)
        inputs = root.findall('.//input')
        has_ip_token = False
        has_level_token = False

        for i in inputs:
            itype = i.attrib.get('type', '').lower()
            token = i.attrib.get('token', '')

            if itype == 'text' and token == 'ip_filter':
                has_ip_token = True
            elif itype == 'dropdown' and token == 'level_filter':
                has_level_token = True

        if has_ip_token:
            score += 15
            feedback_parts.append("Text input 'ip_filter' found")
        else:
            feedback_parts.append("FAIL: Missing Text Input with token='ip_filter'")

        if has_level_token:
            score += 15
            feedback_parts.append("Dropdown input 'level_filter' found")
        else:
            feedback_parts.append("FAIL: Missing Dropdown Input with token='level_filter'")

        # CRITERION 5: Search Parameterization (20 pts)
        queries = root.findall('.//query')
        search_valid = False

        for q in queries:
            if q.text:
                q_text = q.text.lower().replace('"', '').replace("'", "")
                if 'index=web_logs' in q_text and '$ip_filter$' in q.text.lower() and '$level_filter$' in q.text.lower():
                    search_valid = True
                    break
        
        if search_valid:
            score += 20
            feedback_parts.append("Search correctly parameterized with tokens and index")
        else:
            feedback_parts.append("FAIL: Search does not contain index=web_logs and both $ip_filter$ and $level_filter$ tokens")

    except ET.ParseError:
        feedback_parts.append("FAIL: Dashboard contains malformed XML")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # CRITERION 6: VLM Trajectory Verification (20 pts)
    vlm_passed = False
    if query_vlm and traj:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final_frame = get_final_screenshot(traj)
            all_frames = frames + [final_frame] if final_frame else frames
            
            vlm_response = query_vlm(
                prompt=UI_VERIFICATION_PROMPT,
                images=all_frames
            )
            
            if vlm_response and vlm_response.get('success'):
                parsed = vlm_response.get('parsed', {})
                if parsed.get('dashboard_edit_ui_used') and parsed.get('inputs_added_or_configured'):
                    score += 20
                    vlm_passed = True
                    feedback_parts.append("VLM verified Splunk UI dashboard editing")
                else:
                    feedback_parts.append("VLM did not detect dashboard UI editing in trajectory")
            else:
                feedback_parts.append("VLM query failed or returned no response")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append(f"VLM verification error: {str(e)[:50]}")
    else:
        feedback_parts.append("VLM verification skipped (not available)")

    # Key requirements for passing: Dashboard exists, Inputs exist, Search Valid
    key_criteria_met = dashboard_found and has_ip_token and has_level_token and search_valid
    passed = score >= 80 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }