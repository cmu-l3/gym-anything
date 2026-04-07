#!/usr/bin/env python3
"""
Verifier for heat_treat_furnace_tags task.

HYBRID VERIFICATION STRATEGY:
1. Programmatic (50 pts): 
   - Checks file creation, timestamps, and binary string extraction for tag presence.
   - Enforces the strict compliance violation rule (GATE): If Line B tags (NT_801, NH_801)
     are found in the binary, the agent fails completely (Score = 0).
2. VLM Trajectory Verification (50 pts):
   - Uses trajectory frames to verify that the agent correctly utilized the Crimson UI 
     to set Float data types, Min/Max ranges, and Labels for the tags.
"""

import json
import os
import tempfile
import logging
import re

# Import VLM utilities as required by framework
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    pass

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_heat_treat_furnace_tags(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_tags = metadata.get('required_tags', ["TT_701", "TT_702", "TT_703", "CP_701", "TT_704", "FT_701", "TT_705"])
    forbidden_tags = metadata.get('forbidden_tags', ["NT_801", "NH_801"])
    required_labels = metadata.get('required_labels', ["Degrees Celsius", "Percent Carbon", "Standard Cubic Feet per Hour"])

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the exported JSON result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\heat_treat_result.json", temp_file.name)
        with open(temp_file.name, 'r', encoding='utf-8') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve/parse export result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Basic file creation checks (Anti-gaming)
    project_found = result.get('project_found', False)
    file_created = result.get('file_created_during_task', False)
    extracted_text = result.get('extracted_text', '')

    if not project_found:
        return {"passed": False, "score": 0, "feedback": "Project file 'heat_treat_furnace.c3' was not found."}
    if not file_created:
        feedback_parts.append("Warning: File timestamp indicates it may not have been created during this session.")
    else:
        score += 15
        feedback_parts.append("Project correctly saved.")

    # 3. Compliance Violation Check (GATE)
    forbidden_found = []
    for f_tag in forbidden_tags:
        if re.search(r'\b' + re.escape(f_tag) + r'\b', extracted_text, re.IGNORECASE):
            forbidden_found.append(f_tag)
            
    if forbidden_found:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"COMPLIANCE VIOLATION: Agent configured unvalidated Line B tags ({', '.join(forbidden_found)}). "
                        "These are marked PENDING-VALIDATION and must not be configured."
        }
    else:
        score += 10
        feedback_parts.append("Compliance check passed (No unvalidated Line B tags found).")

    # 4. Required Tags Check (Binary extraction)
    tags_found = []
    for r_tag in required_tags:
        if re.search(r'\b' + re.escape(r_tag) + r'\b', extracted_text, re.IGNORECASE):
            tags_found.append(r_tag)
            
    if len(tags_found) == 0:
        return {"passed": False, "score": 0, "feedback": "No required tags found in project file."}
    
    tag_score = int((len(tags_found) / len(required_tags)) * 25)
    score += tag_score
    feedback_parts.append(f"Found {len(tags_found)}/{len(required_tags)} required tags in binary.")

    # 5. VLM Trajectory Verification for UI configuration accuracy
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """
            You are evaluating an agent using Red Lion Crimson 3.0 to configure SCADA Data Tags.
            Review these trajectory screenshots.
            
            Check for the following configuration details in the UI:
            1. Were the tags configured as Data Type: Float (or Real)?
            2. Were Engineering Ranges (Minimum and Maximum Values) entered correctly in the Data/Format tabs?
            3. Were Engineering Labels (e.g., 'Degrees Celsius', 'Percent Carbon') typed into the Format Label fields?
            4. Were Alarm limits entered?
            
            Reply with a JSON evaluating the process:
            {
                "data_type_float_used": true/false,
                "ranges_configured": true/false,
                "labels_configured": true/false,
                "alarms_configured": true/false,
                "estimated_accuracy_pct": 0-100,
                "reasoning": "brief explanation"
            }
            """
            
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                vlm_data = vlm_res.get("parsed", {})
                
                vlm_score = 0
                if vlm_data.get("data_type_float_used"): vlm_score += 10
                if vlm_data.get("ranges_configured"): vlm_score += 15
                if vlm_data.get("labels_configured"): vlm_score += 15
                if vlm_data.get("alarms_configured"): vlm_score += 10
                
                # Scale by their estimated overall accuracy
                acc = vlm_data.get("estimated_accuracy_pct", 50) / 100.0
                vlm_final_score = int(vlm_score * acc)
                
                score += vlm_final_score
                feedback_parts.append(f"VLM Visual Audit Score: +{vlm_final_score}/50 ({vlm_data.get('reasoning', 'No reasoning provided')})")
            else:
                # Fallback if VLM fails but string extraction saw labels
                labels_found = [l for l in required_labels if l.lower() in extracted_text.lower()]
                fallback_score = int((len(labels_found) / len(required_labels)) * 30)
                score += fallback_score
                feedback_parts.append(f"VLM unavailable. Fallback label extraction score: +{fallback_score}/50")
        except Exception as e:
            feedback_parts.append(f"VLM Verification error: {str(e)}")
    else:
        # Fallback if VLM isn't hooked up
        labels_found = [l for l in required_labels if l.lower() in extracted_text.lower()]
        fallback_score = int((len(labels_found) / len(required_labels)) * 30)
        score += fallback_score
        feedback_parts.append(f"VLM unavailable. Fallback label extraction score: +{fallback_score}/50")

    passed = score >= 75 and len(tags_found) == len(required_tags)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }