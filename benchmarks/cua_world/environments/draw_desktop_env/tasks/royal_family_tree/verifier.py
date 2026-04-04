#!/usr/bin/env python3
"""
Verifier for royal_family_tree task.

Scoring Criteria (100 points total):
1. File saved & modified: 5 pts
2. Family Members (Names) Found: 25 pts (1 pt per name, max 25)
3. Parent-Child Edges (Solid): 20 pts
4. Marriage Edges (Dashed/Distinct): 15 pts
5. Birth Years Present: 5 pts
6. Multiple Pages (Legend): 10 pts
7. Generational Layout (Rows): 10 pts
8. PNG Export: 10 pts

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_royal_family_tree(traj, env_info, task_info):
    """Verify the royal family tree diagram."""
    
    # 1. Load result from container
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}
    
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error reading result: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)
            
    analysis = result.get('analysis', {})
    score = 0
    feedback = []
    
    # --- Criterion 1: File Existence (5 pts) ---
    if result.get('file_exists') and result.get('file_modified_after_start'):
        score += 5
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not found or not saved.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    # --- Criterion 2: Member Names (25 pts) ---
    found_names = analysis.get('member_names_found', [])
    unique_names = len(set(found_names))
    name_score = min(25, unique_names)
    score += name_score
    if unique_names >= 20:
        feedback.append(f"Found {unique_names}/25 family members (Excellent).")
    elif unique_names >= 10:
        feedback.append(f"Found {unique_names}/25 family members.")
    else:
        feedback.append(f"Found only {unique_names}/25 family members.")

    # --- Criterion 3 & 4: Edges and Styles (35 pts) ---
    num_edges = analysis.get('num_edges', 0)
    dashed = analysis.get('dashed_edges', 0)
    solid = analysis.get('solid_edges', 0)
    
    # Parent-child edges (expecting around 15-20)
    if num_edges >= 15:
        score += 20
        feedback.append(f"Edge count good ({num_edges}).")
    elif num_edges >= 7:
        score += 10
        feedback.append(f"Edge count low ({num_edges}).")
    else:
        feedback.append("Very few connections drawn.")
        
    # Distinct styles for marriage
    if analysis.get('distinct_edge_styles'):
        score += 15
        feedback.append("Distinct line styles detected for marriages.")
    elif dashed > 0:
        score += 15
        feedback.append("Dashed lines detected.")
    else:
        feedback.append("No distinct line styles (dashed) detected for marriages.")

    # --- Criterion 5: Birth Years (5 pts) ---
    years_count = analysis.get('years_found_count', 0)
    if years_count >= 10:
        score += 5
        feedback.append("Birth years included.")
    else:
        feedback.append("Birth years missing or sparse.")

    # --- Criterion 6: Multiple Pages (10 pts) ---
    num_pages = analysis.get('num_pages', 0)
    if num_pages >= 2:
        score += 10
        feedback.append("Multi-page diagram (Tree + Legend) detected.")
    else:
        feedback.append("Only one page found (missing Legend page?).")

    # --- Criterion 7: Generational Layout (10 pts) ---
    gens = analysis.get('generations_detected', 0)
    if gens >= 3:
        score += 10
        feedback.append(f"Generational hierarchy detected ({gens} rows).")
    else:
        feedback.append("Generational hierarchy unclear (shapes not organized in distinct rows).")

    # --- Criterion 8: PNG Export (10 pts) ---
    if result.get('png_exists') and result.get('png_size', 0) > 1000:
        score += 10
        feedback.append("PNG export successful.")
    else:
        feedback.append("PNG export missing or empty.")

    # Final Result
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }