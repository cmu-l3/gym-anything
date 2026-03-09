#!/usr/bin/env python3
"""
Verifier for simple_word_processing task.

Verifies that the agent:
1. Created the specific document in GCompris Word Processor.
2. Saved a screenshot of it to the correct location.
3. Used the correct text content.
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import query_vlm, get_final_screenshot, sample_trajectory_frames

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_simple_word_processing(traj, env_info, task_info):
    """
    Verify the Word Processor task using file checks and VLM.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    target_texts = metadata.get('target_text', {})
    
    # 1. Load result JSON from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    score = 0
    feedback_parts = []
    
    # Criterion 1: File Existence & Creation (10 pts)
    file_exists = result.get("file_exists", False)
    created_during = result.get("file_created_during_task", False)
    
    if file_exists and created_during:
        score += 10
        feedback_parts.append("Screenshot file created successfully.")
    elif file_exists:
        score += 5
        feedback_parts.append("Screenshot file exists but timestamp is old (reused?).")
    else:
        feedback_parts.append("Screenshot file NOT found at expected path.")

    # Criterion 2: VLM Content Verification (90 pts split)
    # We prefer the agent's screenshot, but fallback to final state if missing
    image_to_verify = None
    source_name = "Agent Screenshot"
    
    if file_exists:
        # Try to copy the agent's screenshot
        temp_img = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        try:
            copy_from_env(result["agent_screenshot_path"], temp_img.name)
            image_to_verify = temp_img.name
        except:
            image_to_verify = None
    
    if not image_to_verify:
        # Fallback to final state screenshot
        source_name = "Final State"
        image_to_verify = get_final_screenshot(traj)

    if not image_to_verify:
        return {
            "passed": False, 
            "score": score, 
            "feedback": " | ".join(feedback_parts) + " | No visual evidence available."
        }

    # Construct VLM prompt
    prompt = f"""
    You are a teacher grading a student's digital document task.
    
    Goal: The student should have opened the "Word Processor" in GCompris and typed a note.
    
    Expected Content:
    1. Title: "{target_texts.get('title', 'FIELD TRIP NOTICE')}"
    2. Details: "{target_texts.get('line1', 'Destination: City Zoo')}"
    3. Date: "{target_texts.get('line2', 'Date: May 15th')}"
    4. Note: "{target_texts.get('line3', 'Please bring a lunch')}"
    
    Analyze the image ({source_name}):
    - Is the GCompris Word Processor interface visible? (Look for a simplified word processor UI, not a game)
    - Is the text legible?
    - Does it match the expected content exactly?
    - Is the title bolded or larger (formatting)?
    
    Provide a JSON response:
    {{
        "is_word_processor": boolean,
        "text_content_score": number (0-60),
        "formatting_bonus": boolean,
        "errors": [list of strings],
        "feedback": string
    }}
    """
    
    vlm_result = query_vlm(prompt=prompt, image=image_to_verify)
    
    # Clean up temp image if we created one
    if source_name == "Agent Screenshot" and image_to_verify and os.path.exists(image_to_verify):
        os.unlink(image_to_verify)

    if vlm_result and vlm_result.get("success"):
        parsed = vlm_result.get("parsed", {})
        
        # Criterion 2a: Correct Activity (20 pts)
        if parsed.get("is_word_processor"):
            score += 20
            feedback_parts.append("Correct Word Processor activity used.")
        else:
            feedback_parts.append("Wrong activity or interface not visible.")
            
        # Criterion 2b: Text Content (60 pts)
        text_score = parsed.get("text_content_score", 0)
        # Cap text score to max 60
        text_score = min(60, max(0, text_score))
        score += text_score
        feedback_parts.append(f"Text accuracy score: {text_score}/60.")
        
        # Criterion 2c: Formatting (10 pts)
        if parsed.get("formatting_bonus"):
            score += 10
            feedback_parts.append("Formatting applied (Bonus).")
            
        feedback_parts.append(f"VLM Feedback: {parsed.get('feedback', '')}")
    else:
        feedback_parts.append("VLM verification failed.")

    # Criterion 3: Trajectory Check (sanity check)
    # Ensure they didn't just open a text editor, check for GCompris in frames
    # (Optional, but good for robustness)
    
    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }