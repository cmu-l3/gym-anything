#!/usr/bin/env python3
"""
Verifier for inspect_mumps_routine task.

Verification Strategy:
1. Basic Environment Checks (Container, Browser, YDBGui)
2. Ground Truth Validation (Did we extract the real source?)
3. VLM Verification (Does the screen show the Routine Viewer with XLFDT source?)

The VLM is crucial here because we cannot easily introspect the DOM of the
web interface running inside the container's Firefox from the host.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_inspect_mumps_routine(traj, env_info, task_info):
    """
    Verify agent used YDBGui Routine Viewer to inspect XLFDT.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Result JSON
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
    
    # 2. Basic Checks (15 points)
    if result.get('vista_status') == 'running':
        score += 5
    else:
        feedback_parts.append("VistA container not running")

    if result.get('ydbgui_accessible'):
        score += 5
    else:
        feedback_parts.append("YDBGui not accessible")

    if result.get('browser_open'):
        score += 5
    else:
        feedback_parts.append("Browser not open")

    # 3. VLM Verification (85 points)
    # We use trajectory sampling + final screenshot for robust verification
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    ground_truth_sample = result.get('ground_truth_sample', '')
    
    if query_vlm and final_screenshot:
        prompt = f"""
        You are verifying a VistA/MUMPS Routine Inspection task.
        
        The user should be viewing the source code of the routine "XLFDT" in the YDBGui web interface.
        
        The screen should show:
        1. A "Routine" viewer interface (NOT the Global viewer or Dashboard).
        2. The routine name "XLFDT".
        3. M/MUMPS Source code. 
        
        Here is a sample of the expected source code text:
        ---
        {ground_truth_sample[:200]}
        ---
        
        Analyze the screenshot:
        1. Is the Routine Viewer active? (Look for tabs/headers saying "Routine")
        2. Is "XLFDT" visible clearly as the loaded routine?
        3. Is the code visible (look for labels like 'HTFM', 'FMTE' or commands like 'SET', 'QUIT', 'NEW')?
        
        Return JSON:
        {{
            "routine_viewer_active": true/false,
            "routine_name_xlfdt_visible": true/false,
            "mumps_code_visible": true/false,
            "confidence": "high/medium/low"
        }}
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            parsed = vlm_resp.get('parsed', {})
            
            # Criterion: Routine Viewer Active (20 pts)
            if parsed.get('routine_viewer_active'):
                score += 20
                feedback_parts.append("Routine viewer active")
            else:
                feedback_parts.append("Routine viewer not detected (might be in Global viewer?)")

            # Criterion: Routine Name Visible (20 pts)
            if parsed.get('routine_name_xlfdt_visible'):
                score += 20
                feedback_parts.append("XLFDT routine name visible")
            else:
                feedback_parts.append("XLFDT name not clearly visible")

            # Criterion: Code Visible (45 pts)
            if parsed.get('mumps_code_visible'):
                score += 45
                feedback_parts.append("MUMPS source code visible")
            else:
                feedback_parts.append("Source code content not visible")

        except Exception as e:
            logger.error(f"VLM error: {e}")
            feedback_parts.append("Verification analysis failed")
    else:
        feedback_parts.append("No screenshots available for verification")

    # Final Calculation
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }