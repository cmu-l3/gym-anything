#!/usr/bin/env python3
import json
import os
import tempfile

def verify_chest_pain_triage_flowchart(traj, env_info, task_info):
    """
    Verifies the Chest Pain Triage Flowchart task.
    Checks for file existence, flowchart structure (diamonds, edges),
    clinical content (keywords), and visual formatting (colors).
    """
    
    # 1. Setup - Get Result JSON
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env missing"}
    
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

    # 2. Scoring Logic
    score = 0
    feedback = []
    
    # Gating Criterion: File Existence
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Draw.io file not found."}
    
    if not result.get("file_modified_correctly"):
        feedback.append("Warning: File timestamp indicates it wasn't modified during the task.")
        # We don't fail immediately but this is suspicious
    else:
        score += 8
        feedback.append("File saved successfully.")

    # Structure: Shapes (Max 15)
    shapes = result.get("shape_count", 0)
    if shapes >= 15: score += 15
    elif shapes >= 10: score += 8
    elif shapes >= 5: score += 4
    feedback.append(f"Shapes found: {shapes}")

    # Structure: Decision Diamonds (Max 15)
    diamonds = result.get("diamond_count", 0)
    if diamonds >= 3: score += 15
    elif diamonds >= 1: score += 5
    feedback.append(f"Decision diamonds found: {diamonds}")

    # Structure: Edges (Max 10)
    edges = result.get("edge_count", 0)
    if edges >= 10: score += 10
    elif edges >= 5: score += 5
    feedback.append(f"Connections found: {edges}")

    # Content: Medical Keywords (Max 15)
    keywords = result.get("keywords_found", [])
    kw_count = len(keywords)
    if kw_count >= 5: score += 15
    elif kw_count >= 3: score += 10
    elif kw_count >= 1: score += 5
    feedback.append(f"Keywords found: {', '.join(keywords)}")

    # Visual: Color Coding (Max 10)
    colors = result.get("distinct_colors", 0)
    if colors >= 2: score += 10
    elif colors >= 1: score += 5
    feedback.append(f"Distinct colors used: {colors}")

    # Content: Terminal Outcomes (Max 7)
    terminals = result.get("terminal_nodes", 0)
    if terminals >= 3: score += 7
    elif terminals >= 1: score += 3
    feedback.append(f"Outcome nodes found: {terminals}")

    # Structure: Pages (Max 10)
    pages = result.get("page_count", 0)
    if pages >= 2: score += 10
    else: feedback.append("Missing second page for HEART score.")

    # Output: PNG Export (Max 10)
    if result.get("png_exists") and result.get("png_size", 0) > 2000:
        score += 10
        feedback.append("PNG export validated.")
    elif result.get("png_exists"):
        score += 5
        feedback.append("PNG export exists but is very small.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }