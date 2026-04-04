#!/usr/bin/env python3
import json
import os
import tempfile

def verify_convert_notes_to_tags(traj, env_info, task_info):
    """
    Verify that notes were converted to tags correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []

    # Helper checks
    def check_paper(key, expected_tag, forbidden_note_text, is_control=False):
        paper = data.get(key)
        if not paper:
            return 0, [f"Paper {key} not found"]
        
        p_score = 0
        p_feedback = []
        
        # Check Tags
        tags = paper.get("tags", [])
        if is_control:
            # Control shouldn't have priority tags
            if "priority:high" in tags or "priority:low" in tags:
                p_feedback.append(f"Control paper {key} incorrectly tagged")
            else:
                p_score += 10
                p_feedback.append(f"Control paper {key} tags OK")
        else:
            # Target should have specific tag
            if expected_tag in tags:
                p_score += 15
                p_feedback.append(f"Paper {key} has tag '{expected_tag}'")
            else:
                p_feedback.append(f"Paper {key} MISSING tag '{expected_tag}'")

        # Check Notes
        notes = paper.get("notes", [])
        notes_text = " ".join(notes).lower()
        
        if is_control:
            # Control MUST have its note
            if "key reference" in notes_text:
                p_score += 15
                p_feedback.append(f"Control paper {key} note preserved")
            else:
                p_feedback.append(f"Control paper {key} note incorrectly deleted")
        else:
            # Target MUST NOT have status note
            if forbidden_note_text.lower() in notes_text:
                p_feedback.append(f"Paper {key} still has note '{forbidden_note_text}'")
            else:
                p_score += 10
                p_feedback.append(f"Paper {key} note deleted")

        return p_score, p_feedback

    # 1. Urgent Paper 1 (Attention...)
    s, f = check_paper("urgent_1", "priority:high", "Status: Urgent")
    score += s
    feedback.extend(f)

    # 2. Urgent Paper 2 (Deep Learning)
    s, f = check_paper("urgent_2", "priority:high", "Status: Urgent")
    score += s
    feedback.extend(f)

    # 3. Later Paper 1 (Computing...)
    s, f = check_paper("later_1", "priority:low", "Status: Later")
    score += s
    feedback.extend(f)

    # 4. Control Paper (Einstein)
    s, f = check_paper("control_1", None, None, is_control=True)
    score += s
    feedback.extend(f)

    # Total score calculation (Max 100)
    # Urgent1: 15+10 = 25
    # Urgent2: 15+10 = 25
    # Later1:  15+10 = 25
    # Control: 10+15 = 25
    # Sum = 100
    
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }