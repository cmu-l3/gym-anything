#!/usr/bin/env python3
"""
Verifier for wordpress_c4_architecture task.
Scores based on:
1. File creation/modification
2. Presence of required shapes (Context & Container layers)
3. Correct use of C4 notation
4. Multi-page structure
5. PNG Export
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_wordpress_c4(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Get results
    temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp.name)
        with open(temp.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp.name):
            os.unlink(temp.name)

    score = 0
    feedback = []
    
    # 1. File saved (10 pts)
    if result.get('file_exists') and result.get('file_modified'):
        score += 10
        feedback.append("Draw.io file saved")
    elif result.get('file_exists'):
        score += 5
        feedback.append("Draw.io file exists but not modified (stale?)")
    else:
        return {"passed": False, "score": 0, "feedback": "No file saved"}

    analysis = result.get('analysis', {})
    
    # 2. Context Elements (20 pts)
    # Expected: ~8 keywords (Reader, Author, Admin, WordPress, Email, CDN, Social, Repo)
    ctx_matches = analysis.get('context_matches', 0)
    if ctx_matches >= 6:
        score += 20
        feedback.append(f"Context elements: Good ({ctx_matches}/8 found)")
    elif ctx_matches >= 4:
        score += 10
        feedback.append(f"Context elements: Partial ({ctx_matches}/8 found)")
    else:
        feedback.append(f"Context elements: Missing ({ctx_matches}/8 found)")

    # 3. Container Elements (20 pts)
    # Expected: ~7 keywords (Web, PHP, Admin, API, DB, Storage, Cron)
    cnt_matches = analysis.get('container_matches', 0)
    if cnt_matches >= 5:
        score += 20
        feedback.append(f"Container elements: Good ({cnt_matches}/7 found)")
    elif cnt_matches >= 3:
        score += 10
        feedback.append(f"Container elements: Partial ({cnt_matches}/7 found)")
    else:
        feedback.append(f"Container elements: Missing ({cnt_matches}/7 found)")

    # 4. Relationships/Edges (15 pts)
    edges = analysis.get('edges', 0)
    labels = analysis.get('edge_labels', 0)
    if edges >= 8:
        if labels >= 4:
            score += 15
            feedback.append(f"Relationships: {edges} edges with {labels} labels")
        else:
            score += 10
            feedback.append(f"Relationships: {edges} edges but missing labels")
    elif edges >= 4:
        score += 7
        feedback.append("Relationships: Partial edges")
    else:
        feedback.append("Relationships: Too few connections")

    # 5. Multi-page (10 pts)
    pages = analysis.get('pages', 0)
    if pages >= 2:
        score += 10
        feedback.append("Multi-page diagram created")
    else:
        feedback.append("Single page only (expected 2)")

    # 6. System Boundary (10 pts)
    if analysis.get('has_boundary'):
        score += 10
        feedback.append("System boundary found")
    else:
        feedback.append("Missing system boundary container")

    # 7. C4 Notation Usage (5 pts)
    if analysis.get('c4_keywords', 0) > 0:
        score += 5
        feedback.append("C4 shapes detected")

    # 8. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 2000:
        score += 10
        feedback.append("PNG exported")
    else:
        feedback.append("PNG export missing or empty")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }