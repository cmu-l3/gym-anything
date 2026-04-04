#!/usr/bin/env python3
"""
Verifier for ESI Triage Decision Tree Task.

Scoring Breakdown (100 pts):
- File Saved & Valid (10 pts)
- Decision Logic Structure (15 pts): At least 4 decision-like nodes.
- Outcome Nodes (20 pts): At least 5 ESI outcome levels.
- Connectivity (10 pts): At least 8 connections.
- Color Coding (10 pts): At least 3 distinct non-white colors used.
- Keywords/Content (10 pts): Presence of specific medical terms.
- Multi-page (10 pts): Second page exists.
- PNG Export (10 pts): Valid PNG file exists.
- Title/Formatting (5 pts): "ESI" title present.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_esi_triage_decision_tree(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load metadata
    metadata = task_info.get('metadata', {})
    required_keywords = set(metadata.get('required_keywords', []))

    # Retrieve result
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
    feedback = []
    
    # Extract Analysis Data
    analysis = result.get("analysis", {})
    text_content = analysis.get("text_content", "").lower()
    
    # --- Criterion 1: File Saved (10 pts) ---
    if result.get("file_exists") and result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file saved successfully.")
    else:
        feedback.append("Draw.io file not saved or not modified.")
        return {"passed": False, "score": 0, "feedback": "\n".join(feedback)}

    # --- Criterion 2: Decision Nodes (15 pts) ---
    # Looking for diamonds/rhombus shapes or questions
    d_count = analysis.get("decision_node_count", 0)
    if d_count >= 4:
        score += 15
        feedback.append(f"Structure: Found {d_count} decision nodes (Pass).")
    elif d_count >= 2:
        score += 7
        feedback.append(f"Structure: Found only {d_count} decision nodes (Partial).")
    else:
        feedback.append(f"Structure: Insufficient decision nodes found ({d_count}).")

    # --- Criterion 3: ESI Outcome Nodes (20 pts) ---
    # We look for occurrences of "ESI Level X" in text
    levels_found = 0
    for i in range(1, 6):
        if f"level {i}" in text_content or f"esi {i}" in text_content or f"esi-{i}" in text_content:
            levels_found += 1
    
    if levels_found == 5:
        score += 20
        feedback.append("Content: All 5 ESI levels found.")
    elif levels_found >= 3:
        score += 10
        feedback.append(f"Content: Found {levels_found}/5 ESI levels.")
    else:
        feedback.append(f"Content: Missing most ESI levels (found {levels_found}).")

    # --- Criterion 4: Connectivity (10 pts) ---
    c_count = analysis.get("connector_count", 0)
    if c_count >= 8:
        score += 10
        feedback.append(f"Complexity: Diagram has sufficient connections ({c_count}).")
    elif c_count >= 4:
        score += 5
        feedback.append(f"Complexity: Diagram has few connections ({c_count}).")
    else:
        feedback.append("Complexity: Diagram is disconnected or sparse.")

    # --- Criterion 5: Color Coding (10 pts) ---
    colors = analysis.get("unique_fill_colors", [])
    if len(colors) >= 3:
        score += 10
        feedback.append(f"Styling: Used {len(colors)} distinct colors (Pass).")
    elif len(colors) >= 2:
        score += 5
        feedback.append(f"Styling: Used {len(colors)} colors (Partial).")
    else:
        feedback.append("Styling: Diagram appears monochrome or default colored.")

    # --- Criterion 6: Keywords (10 pts) ---
    # Check for specific medical logic terms
    hits = 0
    check_list = ["lifesaving", "high risk", "resources", "danger zone", "vitals"]
    for word in check_list:
        if word in text_content:
            hits += 1
            
    if hits >= 4:
        score += 10
        feedback.append("Content: Clinical logic keywords present.")
    elif hits >= 2:
        score += 5
        feedback.append("Content: Some clinical logic keywords found.")
    else:
        feedback.append("Content: Missing key clinical algorithm terms.")

    # --- Criterion 7: Multi-page (10 pts) ---
    p_count = analysis.get("page_count", 0)
    if p_count >= 2:
        score += 10
        feedback.append("Organization: Multiple pages created.")
    else:
        feedback.append("Organization: Only 1 page found (missing Legend page).")

    # --- Criterion 8: PNG Export (10 pts) ---
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback.append("Export: PNG file created successfully.")
    else:
        feedback.append("Export: PNG file missing or empty.")

    # --- Criterion 9: Title (5 pts) ---
    if "esi" in text_content and "triage" in text_content:
        score += 5
        feedback.append("Formatting: Title appears correct.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }