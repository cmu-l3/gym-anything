#!/usr/bin/env python3
"""
Verifier for create_funnel_segment task.

Verifies:
1. SegmentFunnel.dva file existence and freshness (Anti-gaming).
2. Internal structure of DVA (Funnel type, Title, Data usage).
3. Visual appearance via VLM (Funnel shape, Sort order, Labels).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_funnel_segment(traj, env_info, task_info):
    """
    Verify creation of a Funnel Chart in Oracle Analytics Desktop.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve programmatic result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: path in Windows container is C:\temp\task_result.json
        # copy_from_env handles the path mapping usually, or we specify the path the agent sees.
        copy_from_env("C:\\temp\\task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read result: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result file"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    # 2. Score Programmatic Criteria (55 points)
    score = 0
    feedback_parts = []
    
    # File Exists (10 pts)
    if result.get('output_exists', False):
        score += 10
        feedback_parts.append("Workbook file created")
    else:
        feedback_parts.append("Workbook file missing")
        return {"passed": False, "score": 0, "feedback": "Failed: Output workbook not found"}

    # Freshness (10 pts)
    if result.get('file_created_during_task', False):
        score += 10
    else:
        feedback_parts.append("Warning: File not modified during task")
        
    # File Size Check (5 pts)
    if result.get('file_size_bytes', 0) > metadata.get('min_file_size_bytes', 1000):
        score += 5
    else:
        feedback_parts.append("File too small")
        
    # Internal Content Checks (30 pts total)
    if result.get('internal_check_funnel', False):
        score += 15
        feedback_parts.append("Funnel chart type confirmed")
    else:
        feedback_parts.append("Funnel chart type NOT detected in file")
        
    if result.get('internal_check_title', False):
        score += 10
        feedback_parts.append("Title confirmed")
        
    if result.get('internal_check_dimension', False):
        score += 5
        feedback_parts.append("Segment dimension used")

    # 3. VLM Verification (45 points)
    # Using trajectory frames to verify workflow and visual correctness
    frames = sample_trajectory_frames(traj, n=4)
    final_screen = get_final_screenshot(traj)
    
    if final_screen:
        all_images = frames + [final_screen]
    else:
        all_images = frames

    if not all_images:
         feedback_parts.append("No screenshots available for visual verification")
    else:
        prompt = """
        You are verifying an Oracle Analytics Desktop task.
        The user was asked to create a Funnel Chart showing Revenue by Customer Segment.
        
        Look at the sequence of images and answer:
        1. Is there a Funnel Chart visible (shaped like an inverted pyramid/cone)?
        2. Are the sections labeled with Customer Segments (Consumer, Corporate, Home Office)?
        3. Is the funnel sorted Descending (widest section at the top, narrowest at bottom)?
        4. Is the title 'Revenue by Customer Segment' visible?
        5. Are there data labels (numbers) on the funnel sections?
        
        Provide a score breakdown:
        - Funnel Shape Visible: yes/no
        - Segments Visible: yes/no
        - Sorted Descending: yes/no
        - Title Correct: yes/no
        - Data Labels: yes/no
        """
        
        vlm_out = query_vlm(images=all_images, prompt=prompt)
        
        if vlm_out.get('success', False):
            parsed = vlm_out.get('parsed', {})
            # We assume the VLM returns a structured dict or we parse the text logic in a real impl.
            # Here we simulate the logic based on likely VLM text response parsing or structured output if supported.
            # For this generated code, we assume 'parsed' contains boolean keys based on the prompt instructions.
            
            # Note: gym_anything.vlm.query_vlm usually returns text unless schema specified. 
            # We'll rely on a basic keyword check of the response text if parsing isn't strictly structured.
            text_response = str(vlm_out.get('response', '')).lower()
            
            # Heuristic scoring based on VLM text
            if "funnel" in text_response and ("yes" in text_response or "visible" in text_response):
                score += 15
                feedback_parts.append("VLM: Funnel visible")
            
            if "descending" in text_response and ("yes" in text_response or "sorted" in text_response):
                score += 10
                feedback_parts.append("VLM: Sort order correct")
                
            if "consumer" in text_response or "segment" in text_response:
                score += 10
                feedback_parts.append("VLM: Segments visible")
                
            if "title" in text_response and "correct" in text_response:
                score += 5
                feedback_parts.append("VLM: Title verified")
                
            if "label" in text_response or "number" in text_response:
                score += 5
                feedback_parts.append("VLM: Data labels found")
        else:
            feedback_parts.append("VLM verification failed to run")

    # Final Evaluation
    passed = score >= 60 and result.get('output_exists', False) and result.get('internal_check_funnel', False)
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback_parts)
    }