#!/usr/bin/env python3
"""
Verifier for rank_antifungal_safety_with_axitinib task.

Verification Strategy:
1. File Existence: Check if /sdcard/antifungal_ranking.txt exists.
2. VLM Trajectory Analysis:
   - Verify the agent actually navigated to Axitinib > Antifungals.
   - Verify the colors seen in the app match what the agent wrote in the file.
   - Verify the agent's ranking logic (Safe vs Dangerous) is consistent with the colors shown.
"""

import json
import tempfile
import os
import logging
import re
from typing import Dict, Any

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import query_vlm, sample_trajectory_frames
except ImportError:
    # Fallback/Mock for local testing
    def query_vlm(prompt, images, **kwargs):
        return {"success": False, "error": "VLM not available"}
    def sample_trajectory_frames(traj, n):
        return []

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_rank_antifungal_safety(traj, env_info, task_info):
    """
    Verify the antifungal ranking task using VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result JSON from Container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    # 2. Check File Existence (20 points)
    output_exists = result.get("output_exists", False)
    file_content = result.get("file_content", "").replace("\\n", "\n")
    
    if output_exists:
        score += 20
        feedback_parts.append("Output file created.")
    else:
        feedback_parts.append("Output file NOT created.")
        return {"passed": False, "score": 0, "feedback": "Output file missing. Task failed."}

    # 3. Parse Agent's Findings
    agent_findings = parse_agent_file(file_content)
    if not agent_findings["drugs_found"]:
        feedback_parts.append("File content format incorrect or empty.")
    else:
        score += 10
        feedback_parts.append("File content parsed successfully.")

    # 4. VLM Trajectory Verification (70 points)
    # We use VLM to ground-truth the agent's claims against what was actually shown on screen.
    frames = sample_trajectory_frames(traj, n=8)  # Sample frames to catch navigation
    
    if not frames:
         return {"passed": False, "score": score, "feedback": "No trajectory frames available for verification."}

    vlm_prompt = f"""
    You are verifying an agent's interaction with the 'Liverpool Cancer iChart' app.
    
    The agent claims the following interaction colors for Axitinib:
    - Fluconazole: {agent_findings.get('Fluconazole', 'Not reported')}
    - Itraconazole: {agent_findings.get('Itraconazole', 'Not reported')}
    - Voriconazole: {agent_findings.get('Voriconazole', 'Not reported')}
    
    Review the provided screenshots of the agent's session.
    
    1. Did the agent navigate to 'Axitinib'?
    2. Did the agent open the 'Antifungals' category?
    3. What traffic light colors are visible for Fluconazole, Itraconazole, and Voriconazole in the screenshots?
    4. Do the agent's claimed colors match the screenshots?
    5. Based on the colors you see, is the agent's ranking correct?
       - Safest claimed: {agent_findings.get('Safest', 'None')}
       - Dangerous claimed: {agent_findings.get('Dangerous', 'None')}
       (Green/Yellow is safer than Orange/Red).

    Respond in JSON:
    {{
        "navigated_axitinib": true/false,
        "navigated_antifungals": true/false,
        "observed_colors": {{
            "Fluconazole": "color or unknown",
            "Itraconazole": "color or unknown",
            "Voriconazole": "color or unknown"
        }},
        "claims_match_observation": true/false,
        "ranking_logic_correct": true/false,
        "reasoning": "explanation"
    }}
    """

    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Check Navigation
        if parsed.get("navigated_axitinib"):
            score += 15
            feedback_parts.append("VLM confirmed navigation to Axitinib.")
        else:
            feedback_parts.append("VLM could not confirm navigation to Axitinib.")
            
        if parsed.get("navigated_antifungals"):
            score += 15
            feedback_parts.append("VLM confirmed navigation to Antifungals.")
        
        # Check Color Accuracy
        if parsed.get("claims_match_observation"):
            score += 20
            feedback_parts.append("Agent reported colors match VLM observations.")
        else:
            feedback_parts.append("Mismatch between reported colors and screenshots.")

        # Check Logic
        if parsed.get("ranking_logic_correct"):
            score += 20
            feedback_parts.append("Safety ranking logic is correct.")
        else:
            feedback_parts.append("Safety ranking logic seems incorrect based on observations.")
            
    else:
        feedback_parts.append("VLM verification failed to execute.")

    # Pass Threshold
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }

def parse_agent_file(content):
    """Simple parser for the agent's text output."""
    findings = {
        "drugs_found": False,
        "Fluconazole": None,
        "Itraconazole": None,
        "Voriconazole": None,
        "Safest": None,
        "Dangerous": None
    }
    
    if not content:
        return findings

    findings["drugs_found"] = True
    
    # regex for drug colors
    for line in content.split('\n'):
        line = line.strip()
        if "Fluconazole" in line:
            findings["Fluconazole"] = line.split(":")[-1].strip()
        elif "Itraconazole" in line:
            findings["Itraconazole"] = line.split(":")[-1].strip()
        elif "Voriconazole" in line:
            findings["Voriconazole"] = line.split(":")[-1].strip()
        elif "Safest" in line:
            findings["Safest"] = line.split(":")[-1].strip()
        elif "Dangerous" in line:
            findings["Dangerous"] = line.split(":")[-1].strip()
            
    return findings