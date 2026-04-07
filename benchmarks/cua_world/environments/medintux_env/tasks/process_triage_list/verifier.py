#!/usr/bin/env python3
"""
Verifier for MedinTux Triage Batch Processing Task.

Scoring Breakdown:
1. Alice (Existing):
   - No duplicates created (Count == 1): 15 pts
   - Note/Consultation added (Delta > 0): 20 pts
2. Bob (New):
   - Created successfully (Count == 1): 20 pts
   - Note/Consultation added (Delta > 0): 10 pts
3. Charlie (Existing):
   - No duplicates created (Count == 1): 15 pts
   - Note/Consultation added (Delta > 0): 20 pts

Total: 100 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_process_triage_list(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result file
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # 1. Check Alice (Existing)
    alice = result.get('alice', {})
    if alice.get('record_count', 0) == 1:
        score += 15
        feedback.append("Alice: Identity maintained (no duplicates).")
    elif alice.get('record_count', 0) > 1:
        feedback.append(f"Alice: FAILED - Duplicate records created (Count: {alice.get('record_count')}).")
    else:
        feedback.append("Alice: FAILED - Record missing.")
    
    if alice.get('notes_added', 0) > 0:
        score += 20
        feedback.append("Alice: Triage note added.")
    else:
        feedback.append("Alice: No new consultation/note found.")

    # 2. Check Bob (New)
    bob = result.get('bob', {})
    if bob.get('exists') and bob.get('record_count', 0) == 1:
        score += 20
        feedback.append("Bob: New patient created successfully.")
    elif bob.get('record_count', 0) > 1:
        score += 5 # Partial credit if they made him multiple times
        feedback.append("Bob: Multiple records created.")
    else:
        feedback.append("Bob: FAILED - Patient not created.")

    if bob.get('notes_added', 0) > 0:
        score += 10
        feedback.append("Bob: Triage note added.")
    else:
        feedback.append("Bob: No new consultation/note found.")

    # 3. Check Charlie (Existing)
    charlie = result.get('charlie', {})
    if charlie.get('record_count', 0) == 1:
        score += 15
        feedback.append("Charlie: Identity maintained (no duplicates).")
    elif charlie.get('record_count', 0) > 1:
        feedback.append(f"Charlie: FAILED - Duplicate records created (Count: {charlie.get('record_count')}).")
    else:
        feedback.append("Charlie: FAILED - Record missing.")

    if charlie.get('notes_added', 0) > 0:
        score += 20
        feedback.append("Charlie: Triage note added.")
    else:
        feedback.append("Charlie: No new consultation/note found.")

    # Pass threshold
    passed = (score >= 85)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }