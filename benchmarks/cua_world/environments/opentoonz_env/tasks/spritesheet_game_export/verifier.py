#!/usr/bin/env python3
import json
import os
import tempfile
import math

def verify_spritesheet_game_export(traj, env_info, task_info):
    """
    Verifies that the agent correctly rendered animation frames at 256x256 with transparency
    and assembled them into a valid sprite sheet.
    """
    # 1. Setup and retrieve data
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Verification failed: copy_from_env not available."}
    
    # Load metadata
    metadata = task_info.get("metadata", {})
    target_res = metadata.get("target_res_x", 256)
    expected_cols = metadata.get("grid_columns", 6)
    min_frames = metadata.get("min_frame_count", 10)

    # Copy result file
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, "r") as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    # 2. Extract metrics
    frames_count = result_data.get("frames_count", 0)
    frames_valid_res = result_data.get("frames_valid_res", 0)
    frames_valid_alpha = result_data.get("frames_valid_alpha", 0)
    frames_new = result_data.get("frames_new", 0)
    
    sheet_exists = result_data.get("spritesheet_exists", False)
    sheet_width = result_data.get("spritesheet_width", 0)
    sheet_height = result_data.get("spritesheet_height", 0)
    sheet_mode = result_data.get("spritesheet_mode", "None")
    sheet_new = result_data.get("spritesheet_new", False)
    sheet_size = result_data.get("spritesheet_size_bytes", 0)

    score = 0
    feedback = []

    # 3. Scoring Logic

    # Criterion 1: Frames rendered (Max 25 points)
    if frames_count >= min_frames:
        score += 10
        feedback.append(f"Found {frames_count} frames.")
        
        # Check resolution
        if frames_valid_res >= frames_count * 0.9: # Allow minor sampling errors
            score += 10
            feedback.append("Frames are correct resolution (256x256).")
        elif frames_valid_res > 0:
             feedback.append(f"Only {frames_valid_res} frames have correct resolution.")
        else:
             feedback.append("Frames have INCORRECT resolution.")
             
        # Check transparency
        if frames_valid_alpha >= frames_count * 0.9:
            score += 5
            feedback.append("Frames have transparency.")
        else:
            feedback.append("Frames missing transparency (Alpha channel).")
            
        # Check timestamps (Anti-gaming)
        if frames_new < frames_count * 0.9:
             score -= 10
             feedback.append("Warning: Frames do not appear to be newly created.")
    else:
        feedback.append(f"Insufficient frames found ({frames_count}/{min_frames}).")

    # Criterion 2: Sprite Sheet Existence & Freshness (Max 25 points)
    if sheet_exists:
        if sheet_size > 1024: # Minimum viable size
            score += 15
            feedback.append("Sprite sheet file exists.")
            if sheet_new:
                score += 10
                feedback.append("Sprite sheet created during task.")
            else:
                feedback.append("Sprite sheet is old (pre-existing).")
        else:
            feedback.append("Sprite sheet file is empty or too small.")
    else:
        feedback.append("Sprite sheet file NOT found.")

    # Criterion 3: Sprite Sheet Geometry (Max 35 points)
    # Width must be exactly columns * frame_width (6 * 256 = 1536)
    expected_width = expected_cols * target_res
    
    # Height must be a multiple of 256 (rows * frame_height)
    # Rows = Ceil(Frames / Columns)
    if frames_count > 0:
        expected_rows = math.ceil(frames_count / expected_cols)
        expected_height = expected_rows * target_res
    else:
        expected_height = 0 # Cannot verify strictly if no frames, but check divisibility
        
    geo_score = 0
    if sheet_exists and sheet_width > 0 and sheet_height > 0:
        if sheet_width == expected_width:
            geo_score += 15
            feedback.append(f"Sprite sheet width correct ({sheet_width}px).")
        else:
            feedback.append(f"Sprite sheet width incorrect ({sheet_width}px, expected {expected_width}px).")
            
        if sheet_height % target_res == 0 and sheet_height > 0:
            if frames_count > 0 and abs(sheet_height - expected_height) > target_res:
                 # Wrong number of rows for frame count
                 feedback.append(f"Sprite sheet height plausible ({sheet_height}px) but doesn't match frame count.")
                 geo_score += 10
            else:
                 geo_score += 15
                 feedback.append(f"Sprite sheet height correct ({sheet_height}px).")
        else:
            feedback.append(f"Sprite sheet height {sheet_height}px is not a multiple of {target_res}.")
            
    score += geo_score

    # Criterion 4: Sprite Sheet Transparency (Max 15 points)
    if sheet_exists:
        if "A" in sheet_mode or "transparency" in str(sheet_mode).lower():
            score += 15
            feedback.append("Sprite sheet has alpha channel.")
        else:
            feedback.append(f"Sprite sheet missing alpha channel (Mode: {sheet_mode}).")

    # Final decision
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }