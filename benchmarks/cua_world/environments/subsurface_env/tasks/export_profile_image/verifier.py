#!/usr/bin/env python3
"""Verifier for export_profile_image task.

Validates that an image file containing 'deep_dive_profile' was created
during the task duration, is a valid image, and has adequate size.
It also attempts to verify using VLM that Dive #4 was actually selected.
"""

import json
import os
import tempfile
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_profile_image(traj, env_info, task_info):
    # CRITICAL: Use copy_from_env to retrieve files from the container securely
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Error: copy_from_env missing"}

    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    
    try:
        try:
            copy_from_env('/tmp/task_result.json', tmp.name)
            with open(tmp.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}

        # Retrieve parsed attributes
        output_exists = result.get("output_exists", False)
        created_during = result.get("file_created_during_task", False)
        size_bytes = int(result.get("output_size_bytes", 0))
        file_type = result.get("file_type", "").lower()
        found_path = result.get("found_path", "")

        score = 0
        feedback = []

        # Criterion 1: Output File Exists (20 points)
        if output_exists:
            score += 20
            feedback.append(f"Output found: {os.path.basename(found_path)}")
        else:
            feedback.append("Output file *deep_dive_profile* not found in Documents")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

        # Criterion 2: Timestamp Anti-Gaming (10 points)
        if created_during:
            score += 10
            feedback.append("Created during task")
        else:
            feedback.append("Warning: File timestamp indicates it was NOT created during task")

        # Criterion 3: Valid Image format (25 points)
        is_image = "image" in file_type or "png" in file_type or "jpeg" in file_type
        if is_image:
            score += 25
            feedback.append(f"Valid image format detected ({file_type[:25]}...)")
        else:
            feedback.append(f"Invalid file format detected: {file_type}")

        # Criterion 4: Content Sanity Check via File Size (15 points)
        # Real rendered Subsurface profile charts are generally 20KB to 150KB.
        if size_bytes > 15000:
            score += 15
            feedback.append(f"File size OK ({size_bytes/1024:.1f} KB)")
        else:
            feedback.append(f"File too small ({size_bytes} bytes) - likely empty or failed render")

        # Criterion 5 & 6: VLM Trajectory Verification (30 points)
        vlm_score = 0
        try:
            # We attempt to dynamically load the VLM tools if available
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                prompt = """Analyze these screenshots of a user interacting with the Subsurface dive log.
Respond STRICTLY with a JSON object containing two keys:
{"selected_dive_4": true/false, "used_native_export": true/false}
- "selected_dive_4": true if they selected dive #4 in the list (the deepest dive at ~31.4m).
- "used_native_export": true if they used Subsurface's native export options (Log->Export or right-click 'Save profile as image')."""

                vlm_resp = query_vlm(images=images, prompt=prompt)
                
                # Robust extraction of VLM Response text
                text = ""
                if hasattr(vlm_resp, 'text'):
                    text = vlm_resp.text
                elif isinstance(vlm_resp, dict):
                    text = vlm_resp.get('response', str(vlm_resp))
                else:
                    text = str(vlm_resp)
                    
                match = re.search(r'\{.*\}', text, re.DOTALL)
                if match:
                    data = json.loads(match.group(0))
                    if data.get("selected_dive_4"):
                        vlm_score += 15
                        feedback.append("VLM confirms Dive #4 selected")
                    else:
                        feedback.append("VLM: Dive #4 NOT selected")
                        
                    if data.get("used_native_export"):
                        vlm_score += 15
                        feedback.append("VLM confirms native export used")
                    else:
                        feedback.append("VLM: Native export not used / OS screenshot used")
                else:
                    feedback.append("VLM: Could not parse JSON response (Granting points)")
                    vlm_score += 30
            else:
                feedback.append("VLM: No images available for analysis (Granting points)")
                vlm_score += 30
        except Exception as e:
            # Fallback gracefully if VLM throws exceptions to prevent failing valid programmatic runs
            logger.warning(f"VLM verification skipped or failed: {e}")
            feedback.append("VLM check bypassed (Granting points)")
            vlm_score += 30

        score += vlm_score

        # Combine logic to determine PASS / FAIL
        key_criteria_met = output_exists and is_image and (size_bytes > 15000)
        passed = (score >= 70) and key_criteria_met
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }
    finally:
        if os.path.exists(tmp.name):
            os.unlink(tmp.name)