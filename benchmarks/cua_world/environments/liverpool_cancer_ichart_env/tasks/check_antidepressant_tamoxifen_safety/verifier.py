#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_check_antidepressant_tamoxifen_safety(traj, env_info, task_info):
    """
    Verifies that the agent checked the Tamoxifen-Fluoxetine interaction and created a report.
    
    Scoring (100 pts total):
    - 10 pts: Report file exists and created during task
    - 10 pts: 'Tamoxifen' correctly identified in file
    - 10 pts: 'Fluoxetine' correctly identified in file
    - 15 pts: Valid interaction color reported (Red/Orange/Yellow/Green/Grey)
    - 15 pts: Clinical detail text is substantive (>10 chars)
    - 40 pts: VLM Trajectory Verification (App usage, navigation, detail view)
    """
    
    # 1. Setup and retrieve data from environment
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # Download result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/sdcard/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. File Verification (60 points total)
    file_exists = result_data.get('file_exists', False)
    created_during = result_data.get('file_created_during_task', False)
    content_raw = result_data.get('file_content', "")
    
    # Check 1: Existence & Timing (10 pts)
    if file_exists and created_during:
        score += 10
        feedback_parts.append("Report file created successfully.")
    elif file_exists:
        feedback_parts.append("Report file exists but is stale (created before task).")
    else:
        feedback_parts.append("Report file NOT found.")
        # If no file, we can't check content, but we still check VLM for partial credit
    
    if file_exists:
        # Normalize content for checking
        content_lower = content_raw.lower()
        
        # Check 2: Drug Name 1 (10 pts)
        if "tamoxifen" in content_lower:
            score += 10
            feedback_parts.append("Tamoxifen identified.")
        else:
            feedback_parts.append("Tamoxifen missing from report.")

        # Check 3: Drug Name 2 (10 pts)
        if "fluoxetine" in content_lower:
            score += 10
            feedback_parts.append("Fluoxetine identified.")
        else:
            feedback_parts.append("Fluoxetine missing from report.")
            
        # Check 4: Valid Color (15 pts)
        # Using regex to find color keyword
        if re.search(r"(red|orange|yellow|green|grey|gray)", content_lower):
            score += 15
            feedback_parts.append("Valid interaction color reported.")
        else:
            feedback_parts.append("No valid interaction color found.")
            
        # Check 5: Clinical Detail (15 pts)
        # Look for the detail line and check length
        detail_match = re.search(r"clinical detail:(.+)", content_lower)
        if detail_match and len(detail_match.group(1).strip()) > 10:
            score += 15
            feedback_parts.append("Clinical detail text present.")
        else:
            feedback_parts.append("Clinical detail missing or too short.")

    # 3. VLM Trajectory Verification (40 points)
    # We use trajectory frames to verify the agent actually used the app
    frames = sample_trajectory_frames(traj, n=5)
    
    vlm_prompt = """
    You are verifying an agent's workflow in the 'Liverpool Cancer iChart' Android app.
    The agent was asked to check the interaction between 'Tamoxifen' and 'Fluoxetine'.
    
    Analyze the provided screenshots of the agent's trajectory.
    Look for evidence of:
    1. The Cancer iChart app being open (lists of drugs, medical interface).
    2. 'Tamoxifen' being selected or visible in a list.
    3. 'Fluoxetine' being selected or visible.
    4. A 'Traffic Light' interaction result (likely RED or ORANGE for this pair).
    5. A detailed text view explaining the interaction (Mechanism/Management).
    
    Output JSON:
    {
        "app_used": true/false,
        "drugs_visible": true/false,
        "interaction_result_shown": true/false,
        "detail_view_accessed": true/false,
        "observed_color": "red/orange/yellow/green/grey/none"
    }
    """
    
    vlm_score = 0
    try:
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get('success'):
            parsed = vlm_result.get('parsed', {})
            
            # 10 pts: App used
            if parsed.get('app_used'):
                vlm_score += 10
                feedback_parts.append("VLM: App usage verified.")
                
            # 10 pts: Drugs visible
            if parsed.get('drugs_visible'):
                vlm_score += 10
                feedback_parts.append("VLM: Drug selection verified.")
                
            # 10 pts: Interaction Result
            if parsed.get('interaction_result_shown'):
                vlm_score += 10
                feedback_parts.append("VLM: Interaction result screen verified.")
                
            # 10 pts: Detail View
            if parsed.get('detail_view_accessed'):
                vlm_score += 10
                feedback_parts.append("VLM: Detail view verified.")
            else:
                feedback_parts.append("VLM: Detail view NOT observed.")
                
    except Exception as e:
        logger.error(f"VLM verification failed: {e}")
        feedback_parts.append("VLM verification failed (system error).")
        # Fallback: if file score is high (>40), give partial VLM credit (20) assuming work was done
        if score >= 40:
            vlm_score = 20
            feedback_parts.append("Fallback VLM credit awarded.")

    score += vlm_score

    # Final Pass/Fail Determination
    # Must have created file (10 pts) + correct drugs (20 pts) + some valid result (15 pts) = 45 pts minimum file score
    # Total pass threshold = 60
    passed = (score >= 60) and file_exists and created_during
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }