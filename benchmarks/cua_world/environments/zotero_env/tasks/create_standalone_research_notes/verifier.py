#!/usr/bin/env python3
"""
Verifier for create_standalone_research_notes task.

Verifies:
1. "Dissertation Notes" collection exists.
2. Two specific standalone notes exist with required keywords.
3. Both notes are added to the collection.
"""

import json
import tempfile
import os

def verify_create_standalone_research_notes(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_length = metadata.get('min_length', 100)

    # Load result
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
    feedback_parts = []
    
    # Check Collection (15 pts)
    collection_exists = result.get("collection_exists", False)
    if collection_exists:
        score += 15
        feedback_parts.append("Collection 'Dissertation Notes' created")
    else:
        feedback_parts.append("Collection 'Dissertation Notes' missing")

    # Analyze Notes
    notes = result.get("notes", [])
    
    # Note 1: "Research Questions"
    n1_found = False
    n1_score = 0
    n1_feedback = []
    
    # Note 2: "Key Findings"
    n2_found = False
    n2_score = 0
    n2_feedback = []

    # Find best matching notes
    for note in notes:
        content = note.get("content_text", "").lower()
        length = note.get("length", 0)
        in_coll = note.get("in_collection", False)

        # Check for Research Questions Note
        if "research questions" in content and not n1_found:
            n1_found = True
            n1_score += 10 # Base existence
            
            # Keywords
            if "transformer" in content: n1_score += 10
            if "attention" in content: n1_score += 10
            if "scalability" in content: n1_score += 5
            
            # Length
            if length >= min_length: n1_score += 5
            
            # Collection
            if in_coll: n1_score += 2.5 # Split 5 pts between two notes
            
            n1_feedback.append(f"Research Questions note found (Score: {n1_score})")
            continue # Don't use same note for both

        # Check for Key Findings Note
        if "key findings" in content and not n2_found:
            n2_found = True
            n2_score += 10 # Base existence
            
            # Keywords (allow variations)
            if "pre-training" in content or "pretraining" in content: n2_score += 10
            if "fine-tuning" in content or "finetuning" in content: n2_score += 10
            if "benchmark" in content: n2_score += 5
            
            # Length
            if length >= min_length: n2_score += 5
            
            # Collection
            if in_coll: n2_score += 2.5
            
            n2_feedback.append(f"Key Findings note found (Score: {n2_score})")

    score += n1_score + n2_score
    
    if not n1_found:
        feedback_parts.append("Missing 'Research Questions' note")
    else:
        feedback_parts.extend(n1_feedback)
        
    if not n2_found:
        feedback_parts.append("Missing 'Key Findings' note")
    else:
        feedback_parts.extend(n2_feedback)

    # Normalize score cap
    score = min(100, score)
    
    return {
        "passed": score >= 60,
        "score": int(score),
        "feedback": " | ".join(feedback_parts)
    }