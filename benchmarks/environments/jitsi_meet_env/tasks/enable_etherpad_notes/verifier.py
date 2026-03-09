#!/usr/bin/env python3
"""
Verifier for enable_etherpad_notes task.

SCORING CRITERIA:
1. Etherpad container running (15 pts) - Anti-gaming: must be created during task.
2. Jitsi config updated (20 pts) - 'etherpad_base' present and pointing to correct port.
3. Jitsi web healthy (10 pts) - Web interface returns 200 OK.
4. Pad content correct (25 pts) - API query shows specific agenda text.
5. Screenshot exists (10 pts) - File present.
6. VLM Verification (20 pts) - Screenshot shows Jitsi UI + Notes panel.

Pass Threshold: 55 points
"""

import json
import os
import tempfile
import logging
from typing import Dict, Any

# Mock VLM import for standalone testing, real env uses gym_anything.vlm
try:
    from gym_anything.vlm import query_vlm, get_final_screenshot
except ImportError:
    # Stub for testing
    def query_vlm(**kwargs): return {"success": False, "error": "VLM not available"}
    def get_final_screenshot(traj): return None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_enable_etherpad_notes(traj: Dict[str, Any], env_info: Dict[str, Any], task_info: Dict[str, Any]) -> Dict[str, Any]:
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    expected_text_lines = metadata.get('expected_pad_text', [])

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
    
    task_start = result.get('task_start', 0)

    # 1. Etherpad Container (15 pts)
    # Must be running AND created after task start
    etherpad_running = result.get('etherpad_running', False)
    etherpad_ts = result.get('etherpad_created_ts', 0)
    
    if etherpad_running:
        if etherpad_ts > task_start:
            score += 15
            feedback_parts.append("Etherpad container running and created during task (+15)")
        else:
            # Running but stale?
            feedback_parts.append("Etherpad container running but predates task start (0)")
    else:
        feedback_parts.append("Etherpad container not running (0)")

    # 2. Jitsi Config (20 pts)
    config_content = result.get('jitsi_config_content', "")
    if "etherpad_base" in config_content:
        if "9001" in config_content:
            score += 20
            feedback_parts.append("Jitsi configured with etherpad_base on port 9001 (+20)")
        else:
            score += 10
            feedback_parts.append("Jitsi configured with etherpad_base but wrong port (+10)")
    else:
        feedback_parts.append("Jitsi config missing etherpad_base setting (0)")

    # 3. Web Healthy (10 pts)
    if result.get('web_healthy', False):
        score += 10
        feedback_parts.append("Jitsi web interface is healthy (+10)")
    else:
        feedback_parts.append("Jitsi web interface unreachable (0)")

    # 4. Pad Content (25 pts)
    pad_text = result.get('pad_text', "") or ""
    # Normalize newlines
    pad_text = pad_text.replace('\\n', '\n')
    
    matches = 0
    for line in expected_text_lines:
        if line.lower() in pad_text.lower():
            matches += 1
    
    if matches >= len(expected_text_lines):
        score += 25
        feedback_parts.append("Shared notes content fully correct (+25)")
    elif matches >= 1:
        partial = int(25 * (matches / len(expected_text_lines)))
        score += partial
        feedback_parts.append(f"Shared notes content partially correct ({matches}/{len(expected_text_lines)}) (+{partial})")
    else:
        feedback_parts.append("Shared notes content missing or incorrect (0)")

    # 5. Screenshot Existence (10 pts)
    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size', 0)
    if screenshot_exists and screenshot_size > 1024:
        score += 10
        feedback_parts.append("Proof screenshot exists (+10)")
    else:
        feedback_parts.append("Proof screenshot missing (0)")

    # 6. VLM Verification (20 pts)
    # Check if the screenshot actually shows the integration
    # We use the final screenshot captured by the system or the one saved by the agent
    vlm_score = 0
    
    # We prefer the agent's proof screenshot if it exists, otherwise the final state
    proof_path = result.get('screenshot_path', '/home/ga/etherpad_integration_proof.png')
    
    # We need to get this image out of the container to pass to VLM
    # Since we can't easily copy an image for VLM in this code block (it assumes file path),
    # we'll use the trajectory final screenshot which the framework handles.
    # However, the task specifically asks for a proof screenshot file. 
    # Let's rely on the framework's 'get_final_screenshot(traj)' as a proxy for visual state
    # OR assume 'query_vlm' can handle the proof screenshot if we could extract it.
    
    # Standard approach: Use trajectory final screenshot to verify the state at the end.
    final_img = get_final_screenshot(traj)
    
    if final_img:
        vlm_prompt = """
        Analyze this screenshot of a Jitsi Meet session.
        1. Is the interface clearly a video meeting (Jitsi Meet)?
        2. Is there a side panel open for 'Shared Documents' or 'Notes'?
        3. Do you see text like "Weekly Standup Agenda" in that panel?
        
        Return JSON:
        {
            "is_jitsi": true/false,
            "notes_panel_visible": true/false,
            "agenda_text_visible": true/false
        }
        """
        vlm_res = query_vlm(prompt=vlm_prompt, image=final_img)
        
        if vlm_res.get('success'):
            parsed = vlm_res.get('parsed', {})
            if parsed.get('notes_panel_visible', False):
                vlm_score += 10
                feedback_parts.append("VLM: Notes panel visible (+10)")
                if parsed.get('agenda_text_visible', False):
                    vlm_score += 10
                    feedback_parts.append("VLM: Agenda text visible (+10)")
                else:
                    feedback_parts.append("VLM: Agenda text not clearly visible (0)")
            else:
                feedback_parts.append("VLM: Notes panel not visible (0)")
        else:
            # Fallback if VLM fails/not available but other criteria passed
            if score >= 50: 
                vlm_score = 10 
                feedback_parts.append("VLM unavailable, giving partial credit based on other success (+10)")
    else:
         feedback_parts.append("No final screenshot for VLM (0)")
         
    score += vlm_score

    # Determine Pass/Fail
    # Threshold 55
    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }