#!/usr/bin/env python3
import json
import os
import tempfile
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

def verify_apply_technical_indicators(traj, env_info, task_info):
    """
    Verifies that the agent configured the chart with SMA indicators and saved it.
    
    Scoring Criteria:
    1. Output file exists and is a valid PNG (30 pts)
    2. Output file was created *during* the task (anti-gaming) (20 pts)
    3. VLM Verification of trajectory/result (50 pts):
       - Did the agent open a chart for AAPL?
       - Are two indicator lines visible?
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function missing"}

    score = 0
    feedback = []
    
    # --- Step 1: File Verification (Programmatic) ---
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    output_exists = result_data.get("output_exists", False)
    is_valid_png = result_data.get("is_valid_png", False)
    created_during_task = result_data.get("file_created_during_task", False)
    
    if output_exists and is_valid_png:
        score += 30
        feedback.append("Success: Chart image file saved correctly.")
    elif output_exists:
        score += 10
        feedback.append("Partial: File exists but is not a valid PNG.")
    else:
        feedback.append("Fail: Output file not found.")

    if created_during_task:
        score += 20
        feedback.append("Success: File timestamp confirms new creation.")
    else:
        if output_exists:
            feedback.append("Fail: File timestamp is too old (pre-existing file?).")

    # --- Step 2: VLM Verification (Visual) ---
    # We examine the trajectory to see the chart configuration process
    # and the final output file if possible (via copying it out)
    
    frames = sample_trajectory_frames(traj, n=6)
    final_screenshot = get_final_screenshot(traj)
    
    # Try to fetch the actual output image for the VLM to see
    # If the file exists, we copy it to a temp file so we can pass it to VLM
    output_image_path = None
    if output_exists:
        try:
            temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            output_image_path = temp_img.name
            copy_from_env("/home/ga/Documents/aapl_trend_analysis.png", output_image_path)
            # We will append this image to the list of images for VLM analysis
            # Note: This depends on query_vlm accepting file paths or PIL images.
            # Assuming query_vlm handles PIL images or paths.
        except Exception:
            feedback.append("Warning: Could not retrieve output image for VLM verification.")

    images_to_analyze = frames + [final_screenshot]
    
    # If we successfully retrieved the output image, verify IT specifically
    vlm_score = 0
    
    if output_image_path:
        # Specific check on the output file
        prompt_output = (
            "This is an image file saved by the user. Does it show a stock chart for AAPL (Apple)? "
            "Does it show two distinct Moving Average (SMA) lines overlaid on the price chart? "
            "Look for legend text like 'SMA', '50', '200'. Answer YES only if these elements are visible."
        )
        try:
            # We pass just the output image for this specific query
            # We use the path directly if supported, or load it. 
            # query_vlm generally takes a list of PIL images or base64 strings.
            # We'll assume the framework handles paths or we'd load it here.
            # For safety, let's load it if we can, or just rely on trajectory if we can't.
            from PIL import Image
            img = Image.open(output_image_path)
            
            check_result = query_vlm(
                images=[img],
                prompt=prompt_output
            )
            
            if "YES" in check_result.upper():
                vlm_score += 25
                feedback.append("VLM: Saved image confirms chart with indicators.")
            else:
                feedback.append(f"VLM: Saved image analysis failed. Reason: {check_result}")
        except Exception as e:
            feedback.append(f"VLM Error on output file: {e}")
        finally:
            if os.path.exists(output_image_path):
                os.unlink(output_image_path)
    
    # General trajectory check (fallback or additional confirmation)
    prompt_traj = (
        "Analyze the user's workflow. Did they: "
        "1. Open a stock chart for 'AAPL'? "
        "2. Open a 'Technical Indicators' or 'Moving Average' dialog? "
        "3. Configure settings for 50 and 200 periods? "
        "4. Save the chart? "
        "Provide a score from 0 to 25 based on completion."
    )
    
    traj_result = query_vlm(images=frames, prompt=prompt_traj)
    
    # Simple heuristic parsing of VLM score if it returns a number, 
    # otherwise we rely on positive sentiment keywords
    if "25" in traj_result or "perfect" in traj_result.lower():
        vlm_score += 25
    elif "20" in traj_result:
        vlm_score += 20
    elif "YES" in traj_result.upper(): # Fallback if prompt ignored scoring instruction
        vlm_score += 25
    else:
        # Default fallback: if we didn't verify the file image, we need this score high
        # If we did verify the file, this is bonus/confirmation.
        # Let's just look for confirmation of the workflow steps.
        if "configure" in traj_result.lower() and "chart" in traj_result.lower():
            vlm_score += 15
            
    score += vlm_score
    feedback.append(f"VLM Analysis: {traj_result}")

    return {
        "passed": score >= 60,
        "score": min(100, score),
        "feedback": " | ".join(feedback)
    }