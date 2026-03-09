#!/usr/bin/env python3
"""
Verifier for annotate_pdf_highlight task.

Criteria:
1. 'Attention Is All You Need' has a PDF attachment.
2. The attachment has an annotation (highlight).
3. The highlighted text matches the target sentence (fuzzy match).
4. The annotation has the comment "Core definition".
"""

import json
import tempfile
import os
import difflib

def verify_annotate_pdf_highlight(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_highlight = metadata.get('target_highlight_text', "")
    target_comment = metadata.get('target_comment', "Core definition")

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
    
    db_result = result.get('db_query_result', {})
    
    # 1. Attachment Check (30 pts)
    if db_result.get('attachment_found'):
        score += 30
        feedback_parts.append("PDF Attached")
    elif db_result.get('paper_found'):
        feedback_parts.append("Paper found but PDF not attached")
    else:
        feedback_parts.append("Target paper not found in library")

    # 2. Annotation Existence Check (20 pts)
    if db_result.get('annotation_found') or db_result.get('annotation_count', 0) > 0:
        score += 20
        feedback_parts.append("Annotation created")
    else:
        feedback_parts.append("No annotation found")

    # 3. Highlight Text Match (30 pts)
    actual_text = db_result.get('highlight_text', "") or ""
    # Normalize texts for comparison (remove newlines, extra spaces)
    normalized_target = " ".join(target_highlight.split()).lower()
    normalized_actual = " ".join(actual_text.split()).lower()
    
    # Fuzzy match threshold (0.8) to account for PDF text selection quirks
    matcher = difflib.SequenceMatcher(None, normalized_target, normalized_actual)
    similarity = matcher.ratio()
    
    if similarity > 0.8:
        score += 30
        feedback_parts.append(f"Correct text highlighted")
    elif normalized_target in normalized_actual: # Substring match
        score += 30
        feedback_parts.append(f"Target text contained in highlight")
    elif similarity > 0.4:
        score += 15
        feedback_parts.append(f"Partial highlight match (sim={similarity:.2f})")
    elif len(normalized_actual) > 10:
        feedback_parts.append(f"Wrong text highlighted: '{actual_text[:30]}...'")
    
    # 4. Comment Check (20 pts)
    actual_comment = db_result.get('comment_text', "") or ""
    if target_comment.lower() in actual_comment.lower():
        score += 20
        feedback_parts.append(f"Correct comment: '{actual_comment}'")
    elif len(actual_comment) > 0:
        score += 5
        feedback_parts.append(f"Wrong comment: '{actual_comment}'")
    else:
        feedback_parts.append("No comment added")

    passed = (score >= 70)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": db_result
    }