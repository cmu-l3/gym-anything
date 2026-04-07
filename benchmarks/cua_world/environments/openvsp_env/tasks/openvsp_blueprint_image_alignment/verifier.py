#!/usr/bin/env python3
"""
Verifier for openvsp_blueprint_image_alignment task.

Scoring Breakdown (100 points total):
  - File exists and was created during the task (Anti-Gaming): 20 pts
  - Valid XML structure: 10 pts
  - Background image path matching p51_top_view.jpg found: 20 pts
  - Correct calculated scale value (0.004) configured: 30 pts
  - VLM visual confirmation of dialog/background usage: 20 pts

Pass threshold: 70 points.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an AI agent's performance in OpenVSP. 
The agent was asked to open the Background Image dialog, load a blueprint into the Top viewport, and set the Image Scale.

Please look at these trajectory frames and the final screenshot and determine:
1. Did the agent open the "Background" dialog at any point?
2. Is there a blueprint image loaded/visible in the OpenVSP 3D viewport?
3. Did the agent interact with the Scale text box in the Background dialog?

Respond in JSON format:
{
    "background_dialog_opened": true/false,
    "image_visible_in_viewport": true/false,
    "scale_interacted": true/false,
    "confidence": "low/medium/high"
}
"""

def verify_openvsp_blueprint_alignment(traj, env_info, task_info):
    result_file = task_info.get("metadata", {}).get(
        "result_file", "/tmp/openvsp_blueprint_alignment_result.json"
    )
    expected_filename = task_info.get("metadata", {}).get("expected_filename", "p51_top_view.jpg")
    expected_scale = task_info.get("metadata", {}).get("expected_scale", 0.004)
    scale_tolerance = task_info.get("metadata", {}).get("scale_tolerance", 0.0001)
    
    copy_from_env = env_info.get("copy_from_env")
    query_vlm = env_info.get("query_vlm")
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment copy function unavailable"}

    # Retrieve results
    local_tmp = tempfile.mktemp(suffix=".json")
    try:
        copy_from_env(result_file, local_tmp)
        with open(local_tmp, "r") as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve results: {e}"}
    finally:
        if os.path.exists(local_tmp):
            os.unlink(local_tmp)

    score = 0
    feedback_parts = []

    # 1. Check File Creation (Anti-Gaming)
    file_exists = data.get("file_exists", False)
    created_during_task = data.get("created_during_task", False)
    
    if not file_exists:
        return {
            "passed": False,
            "score": 0,
            "feedback": "p51_workspace.vsp3 was not saved.",
            "subscores": {"file_exists": 0, "xml_valid": 0, "image_set": 0, "scale_set": 0, "vlm_score": 0}
        }
    
    if created_during_task:
        score += 20
        feedback_parts.append("File created during session (+20)")
    else:
        feedback_parts.append("File modified timestamp predates task (Anti-Gaming Triggered)")

    content = data.get("file_content", "")
    
    # 2. Check XML Validity
    try:
        xml_root = ET.fromstring(content)
        score += 10
        feedback_parts.append("Valid VSP3 XML (+10)")
    except ET.ParseError as e:
        return {
            "passed": False,
            "score": score,
            "feedback": f"File is not valid XML: {e}",
        }

    # 3. and 4. Check Background Setup via XML Parsing
    image_found = False
    scale_found = False
    best_scale_diff = float('inf')
    found_scales = []

    # Search the XML structure for the image filename and its corresponding scale
    for parent in xml_root.iter():
        has_correct_image = False
        for child in parent:
            if child.tag == 'FileName' and child.text and expected_filename in child.text:
                has_correct_image = True
                image_found = True
                break
        
        if has_correct_image:
            # We found the block configuring our image. Now check its Scale setting.
            for sibling in parent:
                if sibling.tag == 'Scale' and sibling.text:
                    try:
                        val = float(sibling.text)
                        found_scales.append(val)
                        if abs(val - expected_scale) <= scale_tolerance:
                            scale_found = True
                        else:
                            best_scale_diff = min(best_scale_diff, abs(val - expected_scale))
                    except ValueError:
                        pass

    if image_found:
        score += 20
        feedback_parts.append(f"Image {expected_filename} successfully configured in Background (+20)")
    else:
        feedback_parts.append(f"Background image {expected_filename} not found in model XML (+0)")

    if scale_found:
        score += 30
        feedback_parts.append(f"Calculated scale ({expected_scale}) is correct (+30)")
    else:
        if found_scales:
            feedback_parts.append(f"Found incorrect scale values: {found_scales}. Expected {expected_scale} (+0)")
        elif image_found:
            feedback_parts.append("Image configured, but Scale parameter not found (+0)")

    # 5. VLM Visual Verification
    vlm_score = 0
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            if images:
                vlm_result = query_vlm(images=images, prompt=VLM_PROMPT)
                if vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("background_dialog_opened"): vlm_score += 10
                    if parsed.get("scale_interacted") or parsed.get("image_visible_in_viewport"): vlm_score += 10
                    
                    score += vlm_score
                    feedback_parts.append(f"VLM verification passed ({vlm_score}/20)")
                else:
                    feedback_parts.append("VLM query failed, skipping visual bonus")
            else:
                feedback_parts.append("No screenshots available for VLM")
        except Exception as e:
            logger.error(f"VLM verification error: {e}")
            feedback_parts.append("VLM verification encountered an error")

    passed = (score >= 70) and image_found and scale_found

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
    }