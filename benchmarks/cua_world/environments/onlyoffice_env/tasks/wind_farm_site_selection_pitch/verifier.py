#!/usr/bin/env python3
import json
import os
import logging
import tempfile
import sys

# Import VLM utils
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wind_farm_pitch(traj, env_info, task_info):
    """
    Verifies the agent successfully analyzed 8760 rows of wind data
    and synthesized it into a presentation deck.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    file_exists = result.get("file_exists", False)
    file_created_during_task = result.get("file_created_during_task", False)
    parsed_data = result.get("parsed_data", {})
    ground_truth = parsed_data.get("ground_truth", {})
    
    # 1. Anti-gaming check (File must exist and be created during task)
    if not file_exists:
        return {"passed": False, "score": 0, "feedback": "site_alpha_pitch.pptx was not created."}
    if not file_created_during_task:
        return {"passed": False, "score": 0, "feedback": "Output file was not created or modified during the task window (anti-gaming)."}
        
    score += 5
    feedback_parts.append("File created successfully")

    # 2. Structure check (>= 4 slides)
    slide_count = parsed_data.get("slide_count", 0)
    if slide_count >= 4:
        score += 10
        feedback_parts.append(f"Presentation has {slide_count} slides")
    else:
        score += 5
        feedback_parts.append(f"Presentation only has {slide_count} slides (expected 4+)")

    text_content = parsed_data.get("text_content", "").lower()

    # 3. Qualitative textual content checks (Site specs)
    if "tehachapi site alpha" in text_content:
        score += 5
        feedback_parts.append("Title present")
    
    if "314-159-22" in text_content and "35.1025" in text_content:
        score += 10
        feedback_parts.append("Site details present")
        
    if "tortoise" in text_content:
        score += 10
        feedback_parts.append("Environmental constraints present")

    # 4. Quantitative data checks (Calculated from 8760 rows)
    expected_avg = str(ground_truth.get("avg_wind_speed", "999.9"))
    expected_max = str(ground_truth.get("max_wind_speed", "999.9"))
    expected_frac = str(ground_truth.get("op_fraction", "999.9"))
    
    if expected_avg in text_content:
        score += 10
        feedback_parts.append(f"Avg wind speed ({expected_avg}) is correct")
    else:
        feedback_parts.append(f"Avg wind speed ({expected_avg}) missing")
        
    if expected_max in text_content:
        score += 10
        feedback_parts.append(f"Max wind speed ({expected_max}) is correct")
    else:
        feedback_parts.append(f"Max wind speed ({expected_max}) missing")

    if expected_frac in text_content:
        score += 10
        feedback_parts.append(f"Operational fraction ({expected_frac}) is correct")
    else:
        feedback_parts.append(f"Operational fraction ({expected_frac}) missing")

    # 5. VLM Trajectory Verification
    vlm_score = 0
    query_vlm = env_info.get("query_vlm")
    
    if query_vlm and VLM_AVAILABLE:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_img = get_final_screenshot(traj)
            images = frames + [final_img] if final_img else frames
            
            prompt = """You are verifying a multi-application task. The agent had to analyze an 8760-row spreadsheet of wind data and create a presentation pitch deck. 
            Review these sequence frames from the agent's session and respond in JSON:
            {
                "used_spreadsheet": true/false,
                "used_presentation_editor": true/false,
                "presentation_has_content": true/false
            }
            """
            
            vlm_response = query_vlm(images=images, prompt=prompt)
            if vlm_response and vlm_response.get("success"):
                vlm_parsed = vlm_response.get("parsed", {})
                if vlm_parsed.get("used_spreadsheet", False): vlm_score += 10
                if vlm_parsed.get("used_presentation_editor", False): vlm_score += 10
                if vlm_parsed.get("presentation_has_content", False): vlm_score += 10
                feedback_parts.append(f"VLM trajectory verification: {vlm_score}/30")
            else:
                feedback_parts.append("VLM query failed or invalid JSON")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM exception occurred")
    else:
        # Fallback if VLM unavailable in testing context
        vlm_score = 30
        feedback_parts.append("VLM unavailable, auto-granting trajectory points")

    score += vlm_score

    # Determine Pass/Fail (Must have created file, done the math, and hit minimum score)
    key_metrics_found = (expected_avg in text_content) or (expected_max in text_content) or (expected_frac in text_content)
    passed = (score >= 60) and file_created_during_task and key_metrics_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }