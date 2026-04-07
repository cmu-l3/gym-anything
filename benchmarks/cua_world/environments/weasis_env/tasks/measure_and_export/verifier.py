#!/usr/bin/env python3
"""
Verifier for Measure and Export task.
Checks programmatic criteria (file existence, timestamps, format)
and uses VLM to visually verify both trajectory progression and the exported result.
"""

import sys
import os
import json
import logging
import tempfile

# Attempt to import VLM utilities from the framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False
    
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_measure_and_export(traj, env_info, task_info):
    """
    Verify the agent used the measurement tool and exported the annotated image.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_size_bytes = metadata.get('min_file_size_bytes', 10240)
    export_path = metadata.get('export_path', '/home/ga/DICOM/exports/annotated_measurement.jpg')

    score = 0
    feedback_parts = []
    
    # 1. Fetch JSON results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # Criterion 1: File exists (15 points)
    file_exists = result.get('file_exists', False)
    if file_exists:
        score += 15
        feedback_parts.append("Export file found")
    else:
        feedback_parts.append("Export file NOT found")
        # Fail early if no file
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts)
        }

    # Criterion 2: File size is reasonable (10 points)
    file_size = result.get('file_size_bytes', 0)
    if file_size >= min_size_bytes:
        score += 10
        feedback_parts.append(f"File size OK ({file_size // 1024} KB)")
    elif file_size > 0:
        score += 5
        feedback_parts.append(f"File unusually small ({file_size} bytes)")
    else:
        feedback_parts.append("File is empty")

    # Criterion 3: Valid JPEG magic bytes (10 points)
    is_valid_jpeg = result.get('is_valid_jpeg', False)
    if is_valid_jpeg:
        score += 10
        feedback_parts.append("Valid JPEG format")
    else:
        feedback_parts.append("Invalid or corrupted JPEG format")

    # Criterion 4: Created during task (10 points) - Anti-gaming
    created_during_task = result.get('created_during_task', False)
    if created_during_task:
        score += 10
        feedback_parts.append("File created during task session")
    else:
        feedback_parts.append("File timestamp predates task start (Possible gaming)")

    # 2. VLM Verification
    if VLM_AVAILABLE:
        # Fetch the exported image for visual inspection
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.jpg')
        has_exported_img = False
        try:
            copy_from_env(export_path, temp_img.name)
            if os.path.exists(temp_img.name) and os.path.getsize(temp_img.name) > 0:
                has_exported_img = True
        except Exception as e:
            logger.warning(f"Failed to copy exported image for VLM: {e}")

        # Evaluate Trajectory: Did they use the measurement tool? (25 points)
        try:
            frames = sample_trajectory_frames(traj, n=5)
            if frames:
                prompt_traj = (
                    "You are verifying an agent's workflow in a medical imaging viewer (Weasis). "
                    "Review these chronological screenshots. "
                    "Did the agent activate a line or distance MEASUREMENT TOOL and draw a line on the image? "
                    "Look for the measurement tool icon being selected, or a drawn line with endpoint handles "
                    "and a numeric distance value. "
                    "Answer ONLY with YES or NO."
                )
                vlm_res_traj = query_vlm(images=frames, prompt=prompt_traj)
                
                if vlm_res_traj and "YES" in vlm_res_traj.upper():
                    score += 25
                    feedback_parts.append("VLM confirms measurement tool used")
                else:
                    feedback_parts.append("VLM did not detect measurement tool usage")
        except Exception as e:
            logger.warning(f"VLM trajectory evaluation failed: {e}")

        # Evaluate Final Exported Image: Is the annotation visible? (30 points total: 25 for annotation + 5 for real medical content)
        try:
            # If we successfully copied the exported image, evaluate it. Otherwise fallback to final screenshot.
            img_to_evaluate = [temp_img.name] if has_exported_img else [get_final_screenshot(traj)]
            
            prompt_export = (
                "You are analyzing an exported medical image. "
                "Assess two things:\n"
                "1. Is there a visible DISTANCE MEASUREMENT ANNOTATION overlaid on the image? "
                "(Look for a drawn line with a numeric distance value like 'mm' or 'px' next to it).\n"
                "2. Does the background contain actual grayscale medical image content (not just a blank or solid screen)?\n"
                "Respond in JSON format: {\"has_annotation\": true/false, \"has_medical_content\": true/false}"
            )
            vlm_res_export = query_vlm(images=img_to_evaluate, prompt=prompt_export)
            
            if vlm_res_export:
                # Handle possible string/json response from query_vlm
                res_str = vlm_res_export.lower()
                has_annotation = "true" in res_str.split('"has_annotation"')[1].split(',')[0] if '"has_annotation"' in res_str else False
                has_medical_content = "true" in res_str.split('"has_medical_content"')[1].split('}')[0] if '"has_medical_content"' in res_str else False
                
                if has_annotation:
                    score += 25
                    feedback_parts.append("VLM confirms visible annotation in export")
                else:
                    feedback_parts.append("VLM: No annotation visible in export")
                    
                if has_medical_content:
                    score += 5
                    feedback_parts.append("VLM confirms medical content")
                else:
                    feedback_parts.append("VLM: Export appears blank or non-medical")
        except Exception as e:
            logger.warning(f"VLM export evaluation failed: {e}")
            
        finally:
            if os.path.exists(temp_img.name):
                os.unlink(temp_img.name)
    else:
        logger.warning("VLM utilities not available. Proceeding with programmatic score only.")
        # If VLM is not available, scale the score to assume some points if programmatic passes
        if score == 45: # All programmatic passed
            score = 100
            feedback_parts.append("VLM unavailable; programmatic checks fully passed (Scaled to 100)")

    passed = score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }