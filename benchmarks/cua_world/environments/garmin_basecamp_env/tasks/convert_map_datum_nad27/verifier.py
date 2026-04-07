#!/usr/bin/env python3
"""
Verifier for convert_map_datum_nad27 task.

Checks:
1. File creation: Text file and PNG evidence created during task.
2. Content formatting: Validates strict DMS format regex.
3. Coordinate validity: Ensures numbers align with the Fells Reservation bounding box.
4. Visual Verification: Uses VLM to check if Track Properties is open, scrolled down, and displaying DMS.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_convert_map_datum_nad27(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Read JSON Export
    result_json_path = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    try:
        copy_from_env("C:\\tmp\\task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(result_json_path):
            os.unlink(result_json_path)

    txt_exists = result.get('txt_exists', False)
    png_exists = result.get('png_exists', False)
    txt_created = result.get('txt_created_during_task', False)
    png_created = result.get('png_created_during_task', False)
    app_running = result.get('app_was_running', False)

    if not app_running:
        feedback_parts.append("BaseCamp was closed.")
    else:
        score += 10
        feedback_parts.append("BaseCamp running.")

    if not (txt_exists and txt_created):
        feedback_parts.append("Text file missing or not created during task.")
    else:
        score += 15
        feedback_parts.append("Text file created.")

    if not (png_exists and png_created):
        feedback_parts.append("Screenshot proof missing or not created during task.")
    else:
        score += 15
        feedback_parts.append("Screenshot proof created.")

    # 2. Verify Text File Content
    parsed_coords_valid = False
    if txt_exists:
        txt_path = tempfile.NamedTemporaryFile(delete=False, suffix='.txt').name
        try:
            copy_from_env("C:\\workspace\\output\\nad27_coordinates.txt", txt_path)
            with open(txt_path, 'r', encoding='utf-8') as f:
                content = f.read().strip()
                
            lines = [l.strip() for l in content.split('\n') if l.strip()]
            if len(lines) == 2:
                # Format: "First Point: N 42° 26' 27.5", W 071° 06' 15.2""
                # Note: Allowing minor character variation (e.g., straight vs curly quotes)
                pattern = re.compile(r"^(First|Last)\sPoint:\s[NS]\s42°\s2[0-9]'\s\d{1,2}(\.\d+)?\",\s[EW]\s0?71°\s0[0-9]'\s\d{1,2}(\.\d+)?\"?$")
                matches = [pattern.match(l) for l in lines]
                
                if all(matches):
                    score += 30
                    parsed_coords_valid = True
                    feedback_parts.append("Coordinate format and Fells bounding box verified.")
                else:
                    feedback_parts.append("Coordinates formatted incorrectly or out of bounds (Fells is ~N 42°26', W 71°06').")
            else:
                feedback_parts.append("Text file must contain exactly 2 lines (First Point and Last Point).")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse text file: {e}")
        finally:
            if os.path.exists(txt_path):
                os.unlink(txt_path)

    # 3. VLM Verification of Screenshot Proof
    vlm_verified = False
    if png_exists:
        png_path = tempfile.NamedTemporaryFile(delete=False, suffix='.png').name
        try:
            copy_from_env("C:\\workspace\\output\\proof_last_point.png", png_path)
            
            # Using VLM to ensure the Track Properties dialog is actually what was captured
            from gym_anything.vlm import query_vlm
            prompt = """
            Examine this screenshot from Garmin BaseCamp.
            Does it show the 'Track Properties' dialog box?
            Are the coordinates inside the dialog shown in Degrees, Minutes, Seconds format (e.g. N 42° 27' ...)?
            Is the dialog's list scrolled down towards the bottom (showing a high index number, e.g. >500)?
            
            Reply strictly in JSON:
            {
                "is_track_properties": true/false,
                "shows_dms_format": true/false,
                "scrolled_to_bottom": true/false
            }
            """
            vlm_res = query_vlm(prompt=prompt, images=[png_path])
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("is_track_properties") and parsed.get("shows_dms_format") and parsed.get("scrolled_to_bottom"):
                    score += 30
                    vlm_verified = True
                    feedback_parts.append("VLM verified screenshot shows DMS Track Properties at bottom.")
                else:
                    feedback_parts.append("VLM verification failed criteria on screenshot.")
            else:
                feedback_parts.append("VLM evaluation error.")
        except Exception as e:
            feedback_parts.append(f"VLM verification exception: {e}")
        finally:
            if os.path.exists(png_path):
                os.unlink(png_path)

    passed = (score >= 60) and parsed_coords_valid and txt_created and vlm_verified
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }