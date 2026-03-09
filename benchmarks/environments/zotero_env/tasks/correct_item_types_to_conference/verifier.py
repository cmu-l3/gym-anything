#!/usr/bin/env python3
"""
Verifier for correct_item_types_to_conference task.
"""

import json
import os
import tempfile

def verify_correct_item_types(traj, env_info, task_info):
    """
    Verifies that the agent changed the item types of 3 specific papers to 'conferencePaper'
    and left 1 control paper as 'journalArticle'.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # Task Metadata targets
    # We could read from task_info['metadata'], but for robustness we define logic here too
    # The JSON from export has the current state of papers.
    
    papers_result = result.get("papers", {})
    
    # Define scoring criteria
    targets = [
        {
            "title": "Attention Is All You Need",
            "expected": "conferencePaper",
            "points": 25,
            "must_modify": True
        },
        {
            "title": "ImageNet Classification with Deep Convolutional Neural Networks",
            "expected": "conferencePaper",
            "points": 25,
            "must_modify": True
        },
        {
            "title": "Deep Residual Learning for Image Recognition",
            "expected": "conferencePaper",
            "points": 25,
            "must_modify": True
        },
        {
            "title": "Mastering the Game of Go with Deep Neural Networks and Tree Search",
            "expected": "journalArticle",
            "points": 25,
            "must_modify": False  # Should NOT modify this one (control)
        }
    ]

    score = 0
    feedback_parts = []
    
    for target in targets:
        title = target["title"]
        expected = target["expected"]
        points = target["points"]
        must_mod = target["must_modify"]

        data = papers_result.get(title)
        
        if not data or not data.get("found"):
            feedback_parts.append(f"❌ Paper not found: '{title[:20]}...'")
            continue

        actual_type = data.get("current_type")
        was_modified = data.get("was_modified")

        # Check Type
        type_correct = (actual_type == expected)
        
        # Scoring Logic
        if must_mod:
            # For the ones we MUST change
            if type_correct:
                if was_modified:
                    score += points
                    feedback_parts.append(f"✅ Correct: '{title[:20]}...' -> {actual_type}")
                else:
                    # Type is correct but wasn't modified? 
                    # Means it was already correct (setup failed) or agent did nothing 
                    # and we accidentally set it correct.
                    # Given setup enforces JournalArticle, this implies gaming or setup error.
                    # We will give partial credit if it's correct but warn.
                    score += int(points / 2)
                    feedback_parts.append(f"⚠️ Correct but not modified: '{title[:20]}...' (Did you change it?)")
            else:
                feedback_parts.append(f"❌ Incorrect: '{title[:20]}...' is {actual_type}, expected {expected}")
        else:
            # For the control (Go paper)
            if type_correct:
                score += points
                feedback_parts.append(f"✅ Correctly preserved: '{title[:20]}...' as {actual_type}")
            else:
                feedback_parts.append(f"❌ Incorrectly changed: '{title[:20]}...' to {actual_type}")

    # Pass Threshold: 75 points
    # This allows for 1 mistake or failing the control check
    passed = (score >= 75)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }