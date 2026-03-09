#!/usr/bin/env python3
"""
Verifier for reassemble_sentences task.

Criteria:
1. Report file exists and contains valid-looking sentences (30 pts).
2. Evidence screenshot exists (10 pts).
3. VLM Verification of Workflow (60 pts):
   - Agent navigated to the correct activity.
   - Agent interacted with word blocks (drag/drop).
   - Agent successfully completed puzzles (feedback visible).
"""

import json
import os
import tempfile
import logging
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_reassemble_sentences(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Load basic task result metadata
    result_data = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to load result JSON: {e}")
        return {"passed": False, "score": 0, "feedback": "Failed to load task result"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify Report File Content (30 pts)
    report_valid = False
    report_sentences = []
    
    if result_data.get("report_exists") and result_data.get("report_created_during_task"):
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(task_info['metadata']['report_path'], temp_report.name)
            with open(temp_report.name, 'r') as f:
                content = f.read().strip()
                lines = [L.strip() for L in content.split('\n') if L.strip()]
                report_sentences = lines
                
                if len(lines) >= 5:
                    score += 30
                    report_valid = True
                    feedback_parts.append(f"Report contains {len(lines)} sentences (30/30 pts)")
                elif len(lines) > 0:
                    partial = int(30 * (len(lines) / 5))
                    score += partial
                    feedback_parts.append(f"Report contains only {len(lines)}/5 sentences ({partial}/30 pts)")
                else:
                    feedback_parts.append("Report file is empty (0/30 pts)")
        except Exception as e:
            feedback_parts.append(f"Could not read report file: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Report file not found or not created during task (0/30 pts)")

    # 3. Verify Evidence Screenshot (10 pts)
    if result_data.get("evidence_exists") and result_data.get("evidence_created_during_task"):
        score += 10
        feedback_parts.append("Evidence screenshot created (10/10 pts)")
    else:
        feedback_parts.append("Evidence screenshot missing (0/10 pts)")

    # 4. VLM Verification (60 pts)
    # We need to verify the actual workflow: Navigation -> Interaction -> Success
    frames = sample_trajectory_frames(traj, n=8)
    
    vlm_prompt = """
    You are analyzing a screen recording of a user performing a task in GCompris (educational software).
    The task is "Ordering Sentences": reordering scrambled words to form a correct sentence.
    
    Look at the sequence of images and determine:
    1. Did the user navigate to an activity involving words or sentences? (Look for scrambled words like 'is', 'blue', 'sky', 'The')
    2. Did the user drag and drop word blocks to rearrange them?
    3. Is there visual evidence of success? (e.g., A smiley face, a 'Great' message, a flower appearing, or the level advancing)
    4. Did they solve multiple puzzles? (Do the sentences change?)
    
    Return a JSON object with:
    {
        "activity_found": boolean,
        "interaction_observed": boolean,
        "success_feedback_seen": boolean,
        "multiple_puzzles_solved": boolean,
        "confidence": "low|medium|high",
        "reasoning": "string"
    }
    """
    
    vlm_result = query_vlm(images=frames, prompt=vlm_prompt)
    vlm_score = 0
    
    if vlm_result and vlm_result.get('success'):
        parsed = vlm_result.get('parsed', {})
        
        if parsed.get('activity_found'):
            vlm_score += 15
        
        if parsed.get('interaction_observed'):
            vlm_score += 15
            
        if parsed.get('success_feedback_seen'):
            vlm_score += 15
            
        if parsed.get('multiple_puzzles_solved'):
            vlm_score += 15
            
        feedback_parts.append(f"VLM verification: {parsed.get('reasoning')} ({vlm_score}/60 pts)")
    else:
        feedback_parts.append("VLM verification failed (0/60 pts)")

    score += vlm_score

    # Cross-verification: Check if report sentences match reality if possible
    # (Optional enhancement, but for now we trust the VLM general assessment + file existence)

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }