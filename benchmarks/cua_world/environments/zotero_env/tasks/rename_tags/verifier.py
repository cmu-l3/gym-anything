#!/usr/bin/env python3
"""
Verifier for rename_tags@1.
Checks if tags were renamed correctly and associations preserved.
"""

import json
import tempfile
import os

def verify_rename_tags(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy unavailable"}

    # Load result
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error loading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    metadata = task_info.get("metadata", {})
    expected_counts = metadata.get("expected_counts", {})
    
    score = 0
    feedback_parts = []
    
    # 1. Verify New Tags (15 pts each x 5 = 75 pts)
    # Logic: Tag must exist AND have >= expected items
    
    targets = [
        ("machine-learning", "ML"),
        ("natural-language-processing", "NLP"),
        ("computer-vision", "CV"),
        ("information-theory", "info theory"),
        ("computer-science", "comp sci")
    ]
    
    tags_data = result.get("tags", {})
    old_tags_present = result.get("old_tags_present", [])
    
    for new_name, old_name in targets:
        tag_info = tags_data.get(new_name, {"exists": False, "count": 0})
        expected = expected_counts.get(new_name, 0)
        
        # Sub-check A: Old tag gone? (5 pts)
        if old_name not in old_tags_present:
            score += 5
            old_gone = True
        else:
            old_gone = False
            
        # Sub-check B: New tag exists? (5 pts)
        if tag_info["exists"]:
            score += 5
            new_exists = True
        else:
            new_exists = False
            
        # Sub-check C: Count correct? (5 pts)
        # We allow it to be equal or greater in case they added more, but not less.
        if tag_info["count"] >= expected:
            score += 5
            count_ok = True
        else:
            count_ok = False
            
        if old_gone and new_exists and count_ok:
            feedback_parts.append(f"✓ '{old_name}' -> '{new_name}'")
        else:
            fail_reason = []
            if not old_gone: fail_reason.append("old tag remains")
            if not new_exists: fail_reason.append("new tag missing")
            if not count_ok: fail_reason.append(f"item count low ({tag_info['count']}/{expected})")
            feedback_parts.append(f"✗ '{old_name}' ({', '.join(fail_reason)})")

    # 2. Verify Preservation (15 pts)
    # Total item tags should not have dropped significantly
    # (Allow small delta in case they manually messed up one or two, but generally should match)
    initial = result.get("initial_item_tags", 0)
    current = result.get("total_item_tags", 0)
    
    if current >= initial:
        score += 15
        feedback_parts.append(f"✓ Associations preserved ({current}/{initial})")
    elif current >= initial - 3:
        score += 10
        feedback_parts.append(f"⚠ Minor association loss ({current}/{initial})")
    else:
        feedback_parts.append(f"✗ Significant data loss ({current}/{initial})")

    # 3. Clean Cleanup (10 pts)
    # All old tags should be gone
    if len(old_tags_present) == 0:
        score += 10
        feedback_parts.append("✓ Clean cleanup")
    else:
        feedback_parts.append(f"✗ {len(old_tags_present)} old tags remain")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }