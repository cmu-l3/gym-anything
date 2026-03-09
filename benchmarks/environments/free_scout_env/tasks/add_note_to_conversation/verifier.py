#!/usr/bin/env python3
"""
Verifier for add_note_to_conversation task.

VERIFICATION CRITERIA:
1.  Conversation exists and was found.
2.  An Internal Note (type=2) was created during the task.
3.  The note content contains specific technical details from instructions.
4.  CRITICAL: The agent did NOT send a Reply (type=3) to the customer.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_add_note(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    required_phrases = metadata.get('required_content', [])
    
    # Read result from container
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
    
    # 1. Conversation Found (10 pts)
    if result.get('conversation_found', False):
        score += 10
        feedback_parts.append("Target conversation found")
    else:
        feedback_parts.append("Target conversation NOT found")
        return {"passed": False, "score": 0, "feedback": "Target conversation not found"}

    # 2. Check for Wrong Action (Reply vs Note) (Critical Safety Check)
    if result.get('new_reply_found', False):
        score = 0
        feedback_parts.append("FAILED: You sent a reply to the customer instead of adding an internal note!")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # 3. Check if Note Exists (30 pts)
    if result.get('new_note_found', False):
        score += 30
        feedback_parts.append("Internal note created successfully")
    else:
        feedback_parts.append("No new internal note found")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # 4. Content Verification (60 pts total)
    # Phrases: "10.0.3.1", "Gi1/0/24", "CRC errors", "patch cable", "maintenance window"
    body = result.get('note_body', '').lower()
    
    # We allocate 60 points across the keywords (12 pts each)
    phrase_score = 0
    missing_phrases = []
    
    # Normalize phrases
    for phrase in required_phrases:
        if phrase.lower() in body:
            phrase_score += 12
        else:
            missing_phrases.append(phrase)
            
    score += phrase_score
    
    if len(missing_phrases) == 0:
        feedback_parts.append("All technical details present")
    else:
        feedback_parts.append(f"Missing details: {', '.join(missing_phrases)}")

    # Final Pass Logic
    # Must have found conversation, created a note (not reply), and have reasonable content score
    passed = result.get('new_note_found', False) and score >= 70

    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }