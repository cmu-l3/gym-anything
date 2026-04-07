#!/usr/bin/env python3
"""
Verifier for Measure Angle Tool task in Weasis.
Uses multi-criteria evaluation combining file checks, parsing, and VLM trajectory analysis.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- VLM Prompts ---

TRAJECTORY_PROMPT = """You are analyzing a sequence of screenshots from an AI agent performing a task in the Weasis DICOM Viewer.

The goal was to measure an angle on a medical image using the 3-point angle measurement tool.

Review these chronological frames and determine:
1. Did the agent interact with the Weasis interface?
2. Is there evidence that the agent selected or used a measurement tool (specifically an angle tool)?
3. Does a multi-point angle annotation appear on the medical image in the later frames?

Respond ONLY in valid JSON format:
{
    "weasis_used": true/false,
    "angle_tool_activity_visible": true/false,
    "angle_annotation_drawn": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation of what is visible"
}
"""

SCREENSHOT_PROMPT = """You are verifying an exported medical image screenshot.

Analyze the image and determine:
1. Does this image contain a medical scan (like a CT, MRI, or X-ray)?
2. Is there a visible 3-point angle measurement annotation overlaid on the image (usually two lines joined at a vertex)?
3. Is there a numeric angle value displayed next to the annotation?

Respond ONLY in valid JSON format:
{
    "contains_medical_image": true/false,
    "angle_annotation_visible": true/false,
    "angle_value_visible": true/false,
    "confidence": "low/medium/high",
    "reasoning": "Brief explanation"
}
"""


def extract_trajectory_frames(traj, num_frames=4):
    """Extract chronological frames from the trajectory for VLM analysis."""
    frames = []
    if not traj:
        return frames
    
    # Try to safely extract images
    for step in traj:
        try:
            if isinstance(step, dict):
                obs = step.get('observation', step.get('obs', {}))
                img = obs.get('image', obs.get('screenshot'))
                if img is not None:
                    frames.append(img)
            elif hasattr(step, 'obs'):
                obs = step.obs
                if isinstance(obs, dict):
                    img = obs.get('image', obs.get('screenshot'))
                    if img is not None:
                        frames.append(img)
        except Exception:
            continue

    if not frames:
        return []
        
    # Sample evenly spaced frames
    if len(frames) <= num_frames:
        return frames
    
    indices = [int(i * (len(frames) - 1) / (num_frames - 1)) for i in range(num_frames)]
    return [frames[i] for i in indices]


def query_vlm_safe(query_vlm_func, prompt, image=None, images=None):
    """Safely query the VLM and return the parsed JSON response."""
    if not query_vlm_func:
        return None
    try:
        response = query_vlm_func(prompt=prompt, image=image, images=images)
        if response and response.get("success"):
            return response.get("parsed", {})
    except Exception as e:
        logger.warning(f"VLM query failed: {e}")
    return None


def verify_measure_angle_tool(traj, env_info, task_info):
    """
    Verify the measure_angle_tool task.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_screenshot = metadata.get('expected_screenshot_path', '/home/ga/DICOM/exports/angle_measurement.png')
    expected_report = metadata.get('expected_report_path', '/home/ga/DICOM/exports/angle_report.txt')
    min_screenshot_size = metadata.get('min_screenshot_size_bytes', 5000)
    angle_min = metadata.get('angle_min', 1.0)
    angle_max = metadata.get('angle_max', 179.0)

    score = 0
    feedback_parts = []
    
    # 1. Read the task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    screenshot_exists = result.get('screenshot_exists', False)
    screenshot_size = result.get('screenshot_size_bytes', 0)
    screenshot_created = result.get('screenshot_created_during_task', False)
    
    report_exists = result.get('report_exists', False)
    report_created = result.get('report_created_during_task', False)
    
    # --- Criterion 1: Screenshot exists and valid size (20 pts) ---
    if screenshot_exists and screenshot_size >= min_screenshot_size and screenshot_created:
        score += 20
        feedback_parts.append(f"Screenshot created ({screenshot_size} bytes)")
    elif screenshot_exists and screenshot_size < min_screenshot_size:
        feedback_parts.append("Screenshot exists but is too small (invalid)")
    elif screenshot_exists and not screenshot_created:
        feedback_parts.append("Screenshot exists but was not created during this task")
    else:
        feedback_parts.append("Screenshot missing")

    # --- Criterion 2: Report exists (15 pts) ---
    if report_exists and report_created:
        score += 15
        feedback_parts.append("Report file created")
    elif report_exists and not report_created:
        feedback_parts.append("Report exists but was not created during this task")
    else:
        feedback_parts.append("Report file missing")

    # --- Criterion 3 & 4: Report Parsing (30 pts) ---
    report_content = ""
    angle_parsed = False
    format_correct = False
    
    if report_exists and report_created:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(expected_report, temp_report.name)
            with open(temp_report.name, 'r') as f:
                report_content = f.read()
            
            # Look for Angle value
            match = re.search(r'[Aa]ngle[:\s]+(\d+\.?\d*)', report_content)
            if match:
                angle_val = float(match.group(1))
                if angle_min <= angle_val <= angle_max:
                    score += 20
                    angle_parsed = True
                    feedback_parts.append(f"Angle value parsed: {angle_val}°")
                else:
                    feedback_parts.append(f"Angle value parsed ({angle_val}) but out of bounds (1-179)")
            else:
                feedback_parts.append("Could not find numeric angle value in report")
                
            # Check format keywords
            has_angle = bool(re.search(r'[Aa]ngle', report_content))
            has_degrees = bool(re.search(r'[Dd]egrees?', report_content))
            if has_angle and has_degrees:
                score += 10
                format_correct = True
                feedback_parts.append("Report formatting correct")
            else:
                feedback_parts.append("Report missing 'Angle' or 'degrees' keywords")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)

    # --- Criterion 5 & 6: VLM Verification (35 pts) ---
    vlm_traj_ok = False
    vlm_img_ok = False
    
    if query_vlm:
        # Check trajectory (20 pts)
        frames = extract_trajectory_frames(traj, num_frames=4)
        if frames:
            traj_result = query_vlm_safe(query_vlm, TRAJECTORY_PROMPT, images=frames)
            if traj_result:
                if traj_result.get("angle_annotation_drawn") or traj_result.get("angle_tool_activity_visible"):
                    score += 20
                    vlm_traj_ok = True
                    feedback_parts.append("VLM confirmed angle tool trajectory")
                else:
                    feedback_parts.append("VLM did not observe angle measurement activity in trajectory")
        
        # Check the actual exported screenshot (15 pts)
        if screenshot_exists and screenshot_created:
            temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            try:
                copy_from_env(expected_screenshot, temp_screenshot.name)
                # Ensure it has size
                if os.path.getsize(temp_screenshot.name) > 100:
                    from PIL import Image
                    img = Image.open(temp_screenshot.name)
                    img_result = query_vlm_safe(query_vlm, SCREENSHOT_PROMPT, image=img)
                    
                    if img_result and img_result.get("angle_annotation_visible"):
                        score += 15
                        vlm_img_ok = True
                        feedback_parts.append("VLM confirmed exported screenshot contains angle annotation")
                    else:
                        feedback_parts.append("VLM did not detect angle annotation in exported screenshot")
            except Exception as e:
                logger.error(f"Failed VLM screenshot check: {e}")
            finally:
                if os.path.exists(temp_screenshot.name):
                    os.unlink(temp_screenshot.name)
    else:
        # Fallback if VLM not available but files exist
        if screenshot_exists and screenshot_size >= min_screenshot_size and angle_parsed:
            score += 35
            feedback_parts.append("VLM unavailable - awarded points based on valid files and parsed angle")

    # --- Final Evaluation ---
    # To pass, the agent must have created both valid files and we must have extracted an angle
    key_criteria_met = screenshot_exists and screenshot_created and angle_parsed
    passed = score >= 65 and key_criteria_met

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }