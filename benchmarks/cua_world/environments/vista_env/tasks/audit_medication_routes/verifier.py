#!/usr/bin/env python3
"""
Verifier for Audit Medication Routes task.

Verification Strategy:
1. Ground Truth Check: Confirm 'INTRAVENOUS' exists in VistA database (via export script result).
2. Infrastructure Check: VistA running, YDBGui accessible.
3. VLM Verification: Analyze screenshot to ensure ^PS(51.2) was accessed and 'INTRAVENOUS'/'IV' is visible.

Scoring:
- 20 pts: Infrastructure active (VistA + YDBGui).
- 30 pts: Navigated to correct global ^PS(51.2).
- 25 pts: Target name "INTRAVENOUS" visible.
- 25 pts: Target abbreviation "IV" visible.
"""

import json
import os
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_medication_routes(traj, env_info, task_info):
    """
    Verify that the agent audited the INTRAVENOUS route in ^PS(51.2).
    """
    # Use copy_from_env to get the result file
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    # Load result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/audit_medication_routes_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Infrastructure (20 pts)
    if result.get('vista_container_status') == 'running':
        score += 10
    if result.get('ydbgui_accessible'):
        score += 10
    
    if score < 20:
        feedback_parts.append("Environment not healthy (VistA or YDBGui down)")
    
    # 2. Ground Truth Validation (Internal check)
    gt = result.get('ground_truth', {})
    if not gt.get('exists'):
        # If ground truth says it doesn't exist, the task is impossible, but this shouldn't happen in standard VEHU
        feedback_parts.append("Warning: Target data not found in database (Setup issue?)")
    
    # 3. VLM Verification (80 pts)
    final_screenshot = traj.get('final_screenshot') or traj.get('last_frame')
    vlm_passed = False
    
    if query_vlm and final_screenshot and os.path.exists(final_screenshot):
        prompt = """
        Analyze this screenshot of the VistA YDBGui interface.
        I am looking for evidence that the user is auditing the "MEDICATION ROUTES" file, specifically the "INTRAVENOUS" route.
        
        Please check for:
        1. Is the global "^PS(51.2)" or file "MEDICATION ROUTES" visible?
        2. Is the text "INTRAVENOUS" visible as a record name?
        3. Is the abbreviation "IV" visible associated with it?
        4. Alternatively, is there an SQL query showing this data?
        
        Respond in JSON:
        {
            "global_visible": true/false,
            "intravenous_visible": true/false,
            "iv_abbr_visible": true/false,
            "confidence": "high/medium/low"
        }
        """
        
        try:
            vlm_resp = query_vlm(prompt=prompt, image=final_screenshot)
            
            # Simple parsing if VLM returns string representation of JSON
            if isinstance(vlm_resp, str):
                # Try to extract JSON block if wrapped
                import re
                json_match = re.search(r'\{.*\}', vlm_resp, re.DOTALL)
                if json_match:
                    vlm_data = json.loads(json_match.group(0))
                else:
                    # Fallback text analysis
                    vlm_data = {
                        "global_visible": "PS(51.2)" in vlm_resp or "MEDICATION ROUTES" in vlm_resp,
                        "intravenous_visible": "INTRAVENOUS" in vlm_resp,
                        "iv_abbr_visible": "IV" in vlm_resp
                    }
            else:
                vlm_data = vlm_resp

            # Scoring based on VLM
            if vlm_data.get('global_visible'):
                score += 30
                feedback_parts.append("Correct global ^PS(51.2) accessed")
            
            if vlm_data.get('intravenous_visible'):
                score += 25
                feedback_parts.append("'INTRAVENOUS' record found")
                
            if vlm_data.get('iv_abbr_visible'):
                score += 25
                feedback_parts.append("Abbreviation 'IV' confirmed")
                
        except Exception as e:
            feedback_parts.append(f"VLM verification failed: {str(e)}")
    else:
        feedback_parts.append("No screenshot available for verification")

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }