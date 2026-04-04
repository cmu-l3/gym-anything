#!/usr/bin/env python3
"""
Verifier for compare_antihistamine_safety_dasatinib task.
"""

import json
import tempfile
import os
import logging
from typing import Dict, Any

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# VLM Prompt to verify the agent actually checked the interactions
VLM_PROMPT = """
You are verifying an agent's workflow in the 'Liverpool Cancer iChart' app.
The agent was supposed to:
1. Select 'Dasatinib' as the cancer drug.
2. Check the interaction with 'Loratadine'.
3. Check the interaction with 'Cetirizine'.

Review the provided screenshots (trajectory) and answer:
1. Did the agent navigate to 'Dasatinib'? (Look for 'Dasatinib' header or selection).
2. Did the agent view the 'Loratadine' interaction? (Look for 'Loratadine' in the list or detail view, likely with a traffic light color).
3. Did the agent view the 'Cetirizine' interaction? (Look for 'Cetirizine' in the list or detail view).
4. What colors were displayed for these interactions if visible?

Return JSON:
{
  "dasatinib_selected": true/false,
  "loratadine_checked": true/false,
  "cetirizine_checked": true/false,
  "observed_loratadine_color": "red/amber/green/unknown",
  "observed_cetirizine_color": "red/amber/green/unknown",
  "confidence": "high/medium/low"
}
"""

def verify_antihistamine_comparison(traj, env_info, task_info):
    """
    Verifies that the agent compared Loratadine and Cetirizine with Dasatinib
    and recommended the safer one.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm', None) # Assuming this might be passed in env_info or handled externally
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    risky_drug = metadata.get('comed_risky', 'Loratadine').lower()
    safe_drug = metadata.get('comed_safe', 'Cetirizine').lower()
    expected_risky_colors = metadata.get('expected_risky_colors', ['amber', 'red', 'orange', 'yellow'])
    expected_safe_colors = metadata.get('expected_safe_colors', ['green', 'grey', 'gray'])
    
    # 1. Retrieve Result JSON from device
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    
    # 2. Verify Report Existence (10 pts)
    if not result_data.get('report_exists', False):
        return {"passed": False, "score": 0, "feedback": "Report file /sdcard/dasatinib_antihistamine_report.txt was not created."}
    
    score += 10
    feedback.append("Report file created.")
    
    content = result_data.get('report_content', '').lower()
    
    # 3. Verify Content - Drug Names (10 pts)
    if risky_drug in content and safe_drug in content:
        score += 10
        feedback.append(f"Report mentions both {risky_drug} and {safe_drug}.")
    else:
        feedback.append("Report missing one or both drug names.")
        
    # 4. Verify Content - Interaction Colors (20 pts)
    # We look for color keywords associated with the drugs
    # This is a heuristic text check
    risky_color_found = any(c in content for c in expected_risky_colors)
    safe_color_found = any(c in content for c in expected_safe_colors)
    
    if risky_color_found:
        score += 10
    else:
        feedback.append(f"Could not find expected color ({expected_risky_colors}) for {risky_drug} in report.")

    if safe_color_found:
        score += 10
    else:
        feedback.append(f"Could not find expected color ({expected_safe_colors}) for {safe_drug} in report.")

    # 5. Verify Recommendation (20 pts)
    # The user should recommend the safe drug
    if safe_drug in content and ("recommend" in content or "safer" in content or "better" in content or "use" in content):
        score += 20
        feedback.append(f"Report correctly implies {safe_drug} is the recommendation.")
    else:
        feedback.append("Report recommendation is unclear or missing.")

    # 6. VLM Trajectory Verification (40 pts)
    # We need to verify the agent actually looked these up and didn't just guess
    vlm_score = 0
    if query_vlm:
        # Sample frames from trajectory
        # Note: In a real implementation we would grab frames from 'traj' object
        # Here we simulate the VLM check call
        try:
            # Using the framework's VLM hook
            # We pass the list of images from the trajectory
            images = [step['screenshot'] for step in traj if 'screenshot' in step]
            if len(images) > 5:
                # Subsample if too many
                indices = [int(i * len(images) / 5) for i in range(5)]
                sampled_images = [images[i] for i in indices]
            else:
                sampled_images = images
                
            vlm_response = query_vlm(
                prompt=VLM_PROMPT,
                images=sampled_images
            )
            
            if vlm_response.get("success"):
                parsed = vlm_response.get("parsed", {})
                
                if parsed.get("dasatinib_selected"):
                    vlm_score += 10
                    feedback.append("VLM: Dasatinib selection observed.")
                
                if parsed.get("loratadine_checked"):
                    vlm_score += 15
                    feedback.append("VLM: Loratadine check observed.")
                    
                if parsed.get("cetirizine_checked"):
                    vlm_score += 15
                    feedback.append("VLM: Cetirizine check observed.")
            else:
                feedback.append("VLM analysis failed to execute.")
                # Fallback: if text report is perfect, give partial credit? 
                # Strict anti-gaming: No VLM = No points for this section.
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback.append(f"VLM verification error: {e}")
    else:
        feedback.append("No VLM query function available.")

    score += vlm_score

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }