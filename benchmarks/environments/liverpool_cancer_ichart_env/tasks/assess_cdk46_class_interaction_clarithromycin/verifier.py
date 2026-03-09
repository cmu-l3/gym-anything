#!/usr/bin/env python3
"""
Verifier for Assess CDK4/6 Inhibitor Class Interaction with Clarithromycin.

Verification Strategy:
1. File Verification (40 pts):
   - Report file exists and was created during the task.
   - Contains correct structure (Abemaciclib, Palbociclib, Ribociclib).
   - Interaction colors match expected high-severity (Red/Orange).
   - Conclusion (YES/NO) follows logically from the data.

2. VLM Trajectory Verification (60 pts):
   - Confirms the agent actually navigated to all three cancer drugs.
   - Confirms the agent viewed Clarithromycin interactions.
   - Prevents "hallucinating" the file without using the app.
"""

import json
import tempfile
import os
import logging
import re
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_cdk46_audit(traj, env_info, task_info):
    """
    Verify the CDK4/6 class audit task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # Scoring Breakdown
    score = 0
    feedback_parts = []
    
    # =========================================================
    # 1. RETRIEVE DATA
    # =========================================================
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Copy the JSON result created by export_result.sh
        # Note: export_result.sh runs on Android, so file is at /sdcard/task_result.json
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to retrieve task results from device"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # =========================================================
    # 2. FILE & CONTENT VERIFICATION (40 pts)
    # =========================================================
    content = result_data.get("file_content", "")
    file_exists = result_data.get("file_exists", False)
    created_fresh = result_data.get("file_created_during_task", False)

    if file_exists and created_fresh:
        score += 10
        feedback_parts.append("Report file created successfully.")
        
        # Parse content
        # Expected format: Drug: [Color]
        drugs_found = []
        colors_found = []
        
        # Regex to find lines like "Abemaciclib: Red"
        for drug in ["Abemaciclib", "Palbociclib", "Ribociclib"]:
            match = re.search(f"{drug}[:\\s-]+([A-Za-z]+)", content, re.IGNORECASE)
            if match:
                drugs_found.append(drug)
                color = match.group(1).lower()
                colors_found.append(color)
                
                # Check color severity (Red is standard for CYP3A4 strong inhibitors, Orange possible)
                if color in ["red", "orange"]:
                    score += 10  # 10 pts per drug with correct high-risk color
                    feedback_parts.append(f"{drug}: Correct high-risk color ({color}).")
                elif color in ["yellow", "green", "grey"]:
                    feedback_parts.append(f"{drug}: Incorrect low-risk color ({color}).")
                else:
                    feedback_parts.append(f"{drug}: Unknown color value ({color}).")
            else:
                feedback_parts.append(f"{drug}: Not found in report.")

        # Check Conclusion
        # If all colors are same, expected YES.
        if len(colors_found) == 3:
            all_same = all(c == colors_found[0] for c in colors_found)
            expected_conclusion = "YES" if all_same else "NO"
            
            match_conclusion = re.search(r"Class Effect[:\s-]+(YES|NO)", content, re.IGNORECASE)
            if match_conclusion:
                agent_conclusion = match_conclusion.group(1).upper()
                if agent_conclusion == expected_conclusion:
                    # Logic bonus (implied in passing threshold, but good for feedback)
                    feedback_parts.append(f"Conclusion '{agent_conclusion}' is logical.")
                else:
                    feedback_parts.append(f"Conclusion '{agent_conclusion}' contradicts data (expected {expected_conclusion}).")
    else:
        feedback_parts.append("Report file missing or not created during task.")

    # Max score for section 1 so far is 10 + 30 = 40.

    # =========================================================
    # 3. VLM TRAJECTORY VERIFICATION (60 pts)
    # =========================================================
    
    # We need to verify the agent actually navigated the app, not just guessed.
    # We'll sample frames and look for the specific cancer drug headers.
    
    frames = sample_trajectory_frames(traj, n=10)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the Liverpool Cancer iChart app.
    The agent was supposed to check interactions for three specific drugs:
    1. Abemaciclib
    2. Palbociclib
    3. Ribociclib
    
    And for each, check the co-medication "Clarithromycin".
    
    Look at the sequence of screenshots.
    
    1. List which of the three cancer drugs you see selected or listed as the primary drug in the header.
    2. Do you see "Clarithromycin" selected or in the results?
    3. Do you see interaction results (Red/Orange/Yellow/Green banners)?
    
    Return JSON:
    {
        "seen_abemaciclib": boolean,
        "seen_palbociclib": boolean,
        "seen_ribociclib": boolean,
        "seen_clarithromycin": boolean,
        "seen_results": boolean
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    
    if vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        seen_abema = parsed.get('seen_abemaciclib', False)
        seen_palbo = parsed.get('seen_palbociclib', False)
        seen_ribo = parsed.get('seen_ribociclib', False)
        seen_clari = parsed.get('seen_clarithromycin', False)
        
        # Scoring VLM
        if seen_abema: score += 10
        if seen_palbo: score += 10
        if seen_ribo: score += 10
        if seen_clari: score += 15
        if parsed.get('seen_results', False): score += 15
        
        feedback_parts.append(f"VLM Analysis: Abemaciclib={seen_abema}, Palbociclib={seen_palbo}, Ribociclib={seen_ribo}, Clarithromycin={seen_clari}")
    else:
        feedback_parts.append("VLM verification failed to process images.")
        # Fallback: if file is perfect, give partial credit, but hard to verify without VLM
        score += 0

    # =========================================================
    # 4. FINAL DECISION
    # =========================================================
    
    # Pass threshold: 80/100
    # Requires meaningful file content AND visual evidence of work
    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }