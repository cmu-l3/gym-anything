#!/usr/bin/env python3
"""
Verifier for attach_pdf_files task.

Verifies:
1. Four specific PDF attachments added to the correct parent items.
2. Attachments are 'Stored Copies' (not linked files).
3. Attachments created during the task window.
"""

import json
import tempfile
import os

def verify_attach_pdf_files(traj, env_info, task_info):
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Targets defined in task metadata
    targets = {
        "Attention Is All You Need": "vaswani",
        "Deep Learning": "lecun",
        "ImageNet Classification with Deep Convolutional Neural Networks": "krizhevsky",
        "Deep Residual Learning for Image Recognition": "he"
    }

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

    if result.get("db_error"):
        return {"passed": False, "score": 0, "feedback": f"Database error: {result['db_error']}"}

    attachments = result.get("attachments_found", [])
    
    score = 0
    feedback_parts = []
    
    # 1. Check specific file matches (20 pts each)
    matched_papers = set()
    
    for att in attachments:
        parent_title = att.get("parent_title", "")
        path = att.get("path", "")
        
        # Normalize title for matching
        found_target_key = None
        for target_title, keyword in targets.items():
            if target_title.lower() in parent_title.lower():
                found_target_key = keyword
                break
        
        if found_target_key:
            # Check if the attached file path contains the expected keyword
            # e.g. path "storage:vaswani2017_transformers.pdf" contains "vaswani"
            if found_target_key in path.lower():
                if parent_title not in matched_papers:
                    score += 20
                    matched_papers.add(parent_title)
                    feedback_parts.append(f"Correctly attached to '{parent_title[:20]}...'")

    # 2. Check "Stored Copy" status (10 pts)
    # If all matched attachments are stored copies
    stored_count = result.get("stored_copies_count", 0)
    total_added = result.get("total_attachments_added", 0)
    
    if total_added > 0 and stored_count == total_added:
        score += 10
        feedback_parts.append("All attachments are stored copies")
    elif stored_count > 0:
        score += 5
        feedback_parts.append(f"Some attachments stored ({stored_count}/{total_added})")
    elif total_added > 0:
        feedback_parts.append("Attachments are linked, not stored (use 'Attach Stored Copy')")

    # 3. Check exact count (10 pts)
    # Should be exactly 4 attachments added
    if total_added == 4:
        score += 10
        feedback_parts.append("Correct number of files attached (4)")
    elif total_added > 0:
        feedback_parts.append(f"attached {total_added} files (expected 4)")
    else:
        feedback_parts.append("No files attached")

    passed = (score >= 60) and (len(matched_papers) >= 3)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }