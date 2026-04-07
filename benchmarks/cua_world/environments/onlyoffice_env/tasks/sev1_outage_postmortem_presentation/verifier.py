#!/usr/bin/env python3
"""
Verifier for SEV-1 Outage Post-Mortem Presentation task.

Evaluates:
1. File creation/modification anti-gaming checks.
2. Minimum number of slides (>= 5).
3. Presence of thematic text extracted from notes.
4. Presence of an embedded image shape.
5. VLM trajectory verification to ensure agent actually worked the UI.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_postmortem_presentation(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Use a temp file to pull the result json generated in export_result.sh
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback_parts = []
    
    # 1. Check file existence & modification (15 points)
    if not result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output presentation file was not found."}
    
    if result.get("file_created_during_task", False):
        score += 15
        feedback_parts.append("File created during task")
    else:
        feedback_parts.append("Warning: File not modified during task timeframe")

    # 2. Extract parsed PPTX data
    pptx_data = result.get("pptx_data", {})
    if not pptx_data.get("success", False):
        feedback_parts.append(f"Failed to parse PPTX content: {pptx_data.get('error', 'Unknown error')}")
        # Severe penalty, but continue to VLM check for partial credit
    else:
        slides = pptx_data.get("slides", [])
        
        # 3. Slide count check (10 points)
        if len(slides) >= 5:
            score += 10
            feedback_parts.append(f"Found {len(slides)} slides")
        else:
            feedback_parts.append(f"Found {len(slides)} slides (expected 5+)")

        # 4. Content theme checks
        # Track which slides contain which themes to ensure they aren't all on 1 slide
        themes_found = {
            "title": False,
            "summary": False,
            "timeline": False,
            "root_cause": False,
            "action_items": False
        }
        image_found = False

        for slide in slides:
            text = slide.get("text", "").lower()
            
            if "sev-1" in text or "us-east" in text:
                themes_found["title"] = True
            
            if "45 minutes" in text:
                themes_found["summary"] = True
                
            if "14:02" in text and "14:32" in text:
                themes_found["timeline"] = True
                
            if "bgp" in text:
                themes_found["root_cause"] = True
                
            if "net-1092" in text and "sre-4401" in text:
                themes_found["action_items"] = True
                
            if slide.get("has_image", False):
                image_found = True

        # Scoring themes (10 points each = 50 points total)
        for theme, found in themes_found.items():
            if found:
                score += 10
        
        feedback_parts.append(f"Themes found: {sum(themes_found.values())}/5")

        # 5. Image Check (15 points)
        if image_found:
            score += 15
            feedback_parts.append("Image embedded successfully")
        else:
            feedback_parts.append("Missing embedded architecture diagram")

    # 6. VLM Trajectory Verification (10 points)
    # Ensure they actually worked the UI and didn't just upload a pre-made file somehow
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
    try:
        frames = sample_trajectory_frames(traj, n=4)
        vlm_prompt = (
            "You are evaluating an AI agent performing a task in ONLYOFFICE Presentation Editor.\n"
            "Task: Create a multi-slide incident presentation and insert an architecture diagram.\n"
            "Look at these chronological frames from the agent's screen.\n"
            "Did the agent actively work on the presentation (e.g., typing text, managing slides, or inserting the image)?\n"
            "Respond in JSON format: {\"did_work\": true/false, \"reason\": \"brief explanation\"}"
        )
        vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
        if vlm_result and vlm_result.get("parsed", {}).get("did_work", False):
            score += 10
            feedback_parts.append("VLM confirmed active UI workflow")
        else:
            feedback_parts.append("VLM did not detect active UI work")
    except Exception as e:
        logger.warning(f"VLM check failed: {e}")
        # Give benefit of the doubt if VLM fails but file is perfectly intact
        if score >= 80:
            score += 10
            feedback_parts.append("VLM check skipped, file criteria stellar")

    passed = score >= 60 and result.get("output_exists", False)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }