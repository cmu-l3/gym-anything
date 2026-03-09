#!/usr/bin/env python3
"""
Verifier for windsor_family_tree task.

Scoring Breakdown (100 pts total):
1. File saved & modified: 10 pts
2. Shape count (≥20): 20 pts (Partial: ≥12 = 10 pts)
3. Edge count (≥15): 15 pts (Partial: ≥8 = 7 pts)
4. Key names found: 20 pts (≥8 names) (Partial: ≥5 = 10 pts)
5. Marriage diff (dashed/labeled edges): 10 pts
6. Page count (≥2): 5 pts
7. Deceased styling detected: 5 pts
8. Dates/Years present: 5 pts
9. PNG export: 10 pts

Pass Threshold: 60 pts
"""

import json
import tempfile
import os
import logging

logger = logging.getLogger(__name__)

def verify_windsor_family_tree(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function unavailable"}

    # Retrieve result from container
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

    analysis = result.get("analysis", {})
    score = 0
    feedback = []

    # 1. File Saved (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("File saved successfully.")
    else:
        feedback.append("File not saved or not modified.")

    # 2. Shape Count (20 pts)
    v_count = analysis.get("vertex_count", 0)
    if v_count >= 20:
        score += 20
        feedback.append(f"Excellent shape count ({v_count}).")
    elif v_count >= 12:
        score += 10
        feedback.append(f"Adequate shape count ({v_count}).")
    else:
        feedback.append(f"Too few shapes ({v_count}).")

    # 3. Edge Count (15 pts)
    e_count = analysis.get("edge_count", 0)
    if e_count >= 15:
        score += 15
        feedback.append(f"Complex connections ({e_count} edges).")
    elif e_count >= 8:
        score += 7
        feedback.append(f"Basic connections ({e_count} edges).")
    else:
        feedback.append(f"Too few connections ({e_count}).")

    # 4. Key Names (20 pts)
    names = analysis.get("names_found", [])
    unique_names = len(set(names))
    if unique_names >= 8:
        score += 20
        feedback.append(f"Key family members found ({unique_names}).")
    elif unique_names >= 5:
        score += 10
        feedback.append(f"Some family members found ({unique_names}).")
    elif unique_names >= 3:
        score += 5
        feedback.append(f"Few family members found ({unique_names}).")
    else:
        feedback.append("Key names missing from diagram.")

    # 5. Marriage Differentiation (10 pts)
    m_edges = analysis.get("marriage_edges_found", 0)
    if m_edges >= 1:
        score += 10
        feedback.append("Marriage relationships visually distinguished.")
    else:
        feedback.append("No distinct style detected for marriage connections.")

    # 6. Page Count (5 pts)
    p_count = analysis.get("page_count", 0)
    if p_count >= 2:
        score += 5
        feedback.append("Multiple pages created (Legend included).")
    else:
        feedback.append("Only one page detected (Legend missing).")

    # 7. Deceased Styling (5 pts)
    if analysis.get("deceased_styling_found"):
        score += 5
        feedback.append("Deceased members visually styled.")
    else:
        feedback.append("No specific styling for deceased members detected.")

    # 8. Dates/Years (5 pts)
    if analysis.get("years_found", 0) >= 5:
        score += 5
        feedback.append("Birth/Death years included.")
    else:
        feedback.append("Dates/Years missing or scarce.")

    # 9. PNG Export (10 pts)
    if result.get("png_exists") and result.get("png_size", 0) > 1000:
        score += 10
        feedback.append("PNG exported successfully.")
    else:
        feedback.append("PNG export missing or empty.")

    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " ".join(feedback)
    }