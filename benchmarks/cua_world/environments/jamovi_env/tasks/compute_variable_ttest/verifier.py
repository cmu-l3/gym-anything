#!/usr/bin/env python3
import json
import os
import tempfile
import base64
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_compute_variable_ttest(traj, env_info, task_info):
    """
    Verifies the compute_variable_ttest task.
    
    Criteria:
    1. .omv file created and valid (10 pts)
    2. Results text file exists (10 pts)
    3. Results content matches ground truth (40 pts)
       - Male Mean (10)
       - Female Mean (10)
       - T-stat (10)
       - P-value (10)
    4. VLM verification of trajectory (40 pts)
       - Shows 'Compute' variable dialog
       - Shows T-Test results
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy access failed"}

    score = 0
    feedback_parts = []
    
    # 1. Load result JSON from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Check OMV file (10 pts)
    if result.get("omv_exists") and result.get("omv_created_during_task"):
        score += 10
        feedback_parts.append(".omv file saved successfully")
    elif result.get("omv_exists"):
        score += 5
        feedback_parts.append(".omv file exists but timestamp is old")
    else:
        feedback_parts.append(".omv file missing")

    # 3. Check Text File Existence (10 pts)
    txt_exists = result.get("txt_exists")
    txt_content_b64 = result.get("txt_content_base64", "")
    txt_lines = []
    
    if txt_exists and txt_content_b64:
        score += 10
        feedback_parts.append("Results text file found")
        try:
            txt_decoded = base64.b64decode(txt_content_b64).decode('utf-8')
            txt_lines = [l.strip() for l in txt_decoded.split('\n') if l.strip()]
        except:
            feedback_parts.append("Could not decode text file")
    else:
        feedback_parts.append("Results text file missing")

    # 4. Check Content Accuracy (40 pts)
    ground_truth = result.get("ground_truth", {})
    gt_male = ground_truth.get("male_mean")
    gt_female = ground_truth.get("female_mean")
    gt_t = ground_truth.get("t_stat")
    
    content_score = 0
    
    if len(txt_lines) >= 3 and gt_male and gt_female and gt_t:
        try:
            # Helper to parse floats loosely
            def parse_float(s):
                return float(''.join(c for c in s if c.isdigit() or c == '.' or c == '-'))

            # Check Male Mean
            val_male = parse_float(txt_lines[0])
            if abs(val_male - gt_male) < 0.1:
                content_score += 10
                feedback_parts.append(f"Male mean correct ({val_male})")
            else:
                feedback_parts.append(f"Male mean incorrect (got {val_male}, exp {gt_male})")
                
            # Check Female Mean
            val_female = parse_float(txt_lines[1])
            if abs(val_female - gt_female) < 0.1:
                content_score += 10
                feedback_parts.append(f"Female mean correct ({val_female})")
            else:
                feedback_parts.append(f"Female mean incorrect (got {val_female}, exp {gt_female})")
                
            # Check T-Stat (allow loose match for Welch vs Student differences)
            val_t = parse_float(txt_lines[2])
            if abs(val_t - gt_t) < 0.5:
                content_score += 10
                feedback_parts.append(f"T-stat correct ({val_t})")
            else:
                feedback_parts.append(f"T-stat incorrect (got {val_t}, exp ~{gt_t})")
            
            # Check P-Value
            # Expecting < .001 or 0.000
            p_line = txt_lines[3].lower()
            if "<" in p_line or "0.000" in p_line or "0.001" in p_line:
                 content_score += 10
                 feedback_parts.append("P-value correct")
            else:
                 feedback_parts.append(f"P-value format mismatch ({p_line})")
                 
        except Exception as e:
            feedback_parts.append(f"Error parsing values: {str(e)}")
    
    score += content_score

    # 5. VLM Verification (40 pts)
    # We want to verify they actually used the Compute Variable tool
    
    frames = sample_trajectory_frames(traj, n=6)
    final_shot = get_final_screenshot(traj)
    
    vlm_prompt = """
    You are verifying a Jamovi statistics task. The user was supposed to:
    1. Compute a new variable 'A1r' (reverse coding)
    2. Compute a new variable 'Agreeableness' (mean)
    3. Run an Independent Samples T-Test
    
    Look at the sequence of screenshots.
    
    Check for:
    - Is the 'Computed Variable' panel or formula box visible in any frame? (Look for formula '7-A1' or 'MEAN(...)')
    - Is the 'Independent Samples T-Test' analysis visible?
    - Are the results (tables with t-stats) visible?
    
    Return JSON:
    {
       "compute_tool_used": boolean,
       "ttest_run": boolean,
       "results_visible": boolean,
       "confidence": "high/medium/low"
    }
    """
    
    vlm_score = 0
    if frames:
        try:
            vlm_res = query_vlm(images=frames + [final_shot] if final_shot else frames, prompt=vlm_prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("compute_tool_used"):
                    vlm_score += 15
                    feedback_parts.append("VLM: Compute tool usage detected")
                if parsed.get("ttest_run"):
                    vlm_score += 15
                    feedback_parts.append("VLM: T-Test detected")
                if parsed.get("results_visible"):
                    vlm_score += 10
                    feedback_parts.append("VLM: Results table visible")
            else:
                feedback_parts.append("VLM analysis failed")
        except Exception as e:
            logger.error(f"VLM error: {e}")
            # Fallback: if text file was perfect, assume they did it
            if content_score == 40:
                vlm_score = 40
                feedback_parts.append("VLM skipped (perfect results)")
    
    score += vlm_score

    # Final verdict
    passed = score >= 60 and content_score >= 20  # Must have got some numbers right
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback_parts)
    }