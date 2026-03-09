#!/usr/bin/env python3
"""
Verifier for algebra_addition task.

Combines programmatic verification of the generated report file with 
VLM trajectory analysis to ensure the agent actually interacted with GCompris.
"""

import json
import os
import re
import tempfile
import logging

# Import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Fallback for local testing
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(prompt, images): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_algebra_addition(traj, env_info, task_info):
    """
    Verify the agent completed the addition algebra task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    report_path = metadata.get('report_path', '/home/ga/Documents/addition_report.txt')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    # ================================================================
    # PART 1: Programmatic Verification of Report File (45 points)
    # ================================================================
    
    # Get the task result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_result_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_path)
        with open(temp_result_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load task result: {e}")
    finally:
        if os.path.exists(temp_result_path):
            os.unlink(temp_result_path)

    report_exists = task_result.get('report_exists', False)
    report_fresh = task_result.get('report_created_during_task', False)
    
    report_content = ""
    valid_equations = []
    
    if report_exists and report_fresh:
        score += 10
        feedback_parts.append("Report file created")
        
        # Read the report content
        with tempfile.NamedTemporaryFile(delete=False, suffix='.txt') as f:
            temp_report_path = f.name
            
        try:
            copy_from_env(report_path, temp_report_path)
            with open(temp_report_path, 'r') as f:
                report_content = f.read()
                
            # Check content
            # 1. Header/Context
            if "addition" in report_content.lower() and "report" in report_content.lower():
                score += 5
                feedback_parts.append("Header found")
                
            # 2. Extract and verify equations: "3 + 5 = 8"
            # Regex allows for loose spacing: digit + digit = digit
            eq_pattern = r'(\d+)\s*\+\s*(\d+)\s*=\s*(\d+)'
            matches = re.findall(eq_pattern, report_content)
            
            for m in matches:
                a, b, c = int(m[0]), int(m[1]), int(m[2])
                if a + b == c:
                    valid_equations.append((a, b, c))
            
            # Check for non-trivial math (not just 0+0=0 repeated)
            non_trivial = [eq for eq in valid_equations if eq[0] + eq[1] > 0]
            unique_eqs = set(non_trivial)
            
            if len(unique_eqs) >= 3:
                score += 20
                feedback_parts.append(f"Found {len(unique_eqs)} valid equations")
            elif len(unique_eqs) >= 1:
                score += 10
                feedback_parts.append("Found valid equations but fewer than requested")
            else:
                feedback_parts.append("No valid non-trivial equations found in report")
                
            # 3. Completeness (difficulty mention)
            if re.search(r'(level|difficulty|easy|hard)', report_content, re.IGNORECASE):
                score += 5
                feedback_parts.append("Difficulty noted")
            
            # 4. Problem count mentioned
            if re.search(r'[5-9]\d*\s*(problems?|solved)', report_content, re.IGNORECASE) or \
               re.search(r'(solved|count).*?:\s*[5-9]', report_content, re.IGNORECASE):
                score += 5
                feedback_parts.append("Problem count verified")
                
        except Exception as e:
            feedback_parts.append(f"Error reading report content: {str(e)}")
        finally:
            if os.path.exists(temp_report_path):
                os.unlink(temp_report_path)
    else:
        feedback_parts.append("Report file not found or not created during task")

    # ================================================================
    # PART 2: VLM Trajectory Verification (55 points)
    # ================================================================
    
    # We need to verify the agent actually used GCompris, not just wrote a text file.
    frames = sample_trajectory_frames(traj, n=6)
    
    vlm_prompt = """
    You are analyzing screenshots of an agent using the educational software GCompris.
    The agent was asked to:
    1. Navigate to the Addition activity (usually in the Math/Calculation category).
    2. Solve at least 5 addition problems (e.g., "3 + 4 = ?").
    3. Complete Level 1.

    Look at the sequence of images and answer the following in JSON format:
    
    1. "activity_found": (bool) Do you see the GCompris addition interface? It typically shows a math problem like "A + B =" in large text, possibly with a keypad or input field.
    2. "progression_visible": (bool) Do you see the problems changing across different frames? (e.g., one frame shows "2 + 3", another shows "5 + 1").
    3. "level_complete": (bool) Do you see a success screen, a "congratulations" animation (like a flower or smiley), or the level indicator changing (e.g., to Level 2)?
    4. "text_editor_used": (bool) Do you see a text editor being used to write a report?

    JSON Response:
    {
        "activity_found": true/false,
        "progression_visible": true/false,
        "level_complete": true/false,
        "text_editor_used": true/false,
        "confidence": "low/medium/high"
    }
    """
    
    vlm_result = query_vlm(prompt=vlm_prompt, images=frames)
    
    vlm_score = 0
    if vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        if parsed.get("activity_found"):
            vlm_score += 15
            feedback_parts.append("VLM: Addition activity verified")
            
        if parsed.get("progression_visible"):
            vlm_score += 20
            feedback_parts.append("VLM: Multiple problems solved")
            
        if parsed.get("level_complete"):
            vlm_score += 20
            feedback_parts.append("VLM: Level completion/bonus detected")
            
        # Cross-validation: If report has equations but VLM didn't see app, suspicious
        if len(valid_equations) > 0 and not parsed.get("activity_found"):
            feedback_parts.append("WARNING: Report contains math but GCompris usage not detected (possible gaming)")
            # Penalize gaming attempt
            vlm_score = 0
            score = max(0, score - 20)
            
    else:
        feedback_parts.append("VLM verification failed to run")
        
    score += vlm_score
    
    # Final Pass/Fail Logic
    # Must have created report AND shown visual evidence of doing the task
    passed = (score >= 60) and report_exists and (vlm_score >= 15)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }