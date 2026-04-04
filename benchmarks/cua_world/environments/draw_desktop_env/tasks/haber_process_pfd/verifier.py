#!/usr/bin/env python3
"""
Verifier for haber_process_pfd task.
Checks for correct PFD creation, engineering library usage, and process logic.
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_haber_process_pfd(traj, env_info, task_info):
    """
    Verify the Haber Process PFD task.
    
    Criteria:
    1. Files (.drawio and .png) created/modified (10 pts)
    2. Specialized Engineering Library used (15 pts)
    3. 5 Main Units present (Compressor, Heater, Reactor, Cooler, Separator) (25 pts)
    4. Recycle Loop indicated (20 pts)
    5. Stream Labels (Chemicals) (15 pts)
    6. Flow Logic (Edge count) (15 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result
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
    
    analysis = result.get("analysis", {})
    
    # 1. File Check (10 pts)
    if result.get("file_exists") and result.get("file_modified"):
        score += 5
        feedback.append("Drawio file saved.")
    else:
        feedback.append("Drawio file missing or not saved.")
        
    if result.get("png_exists"):
        score += 5
        feedback.append("PNG export found.")
    else:
        feedback.append("PNG export missing.")

    # Stop if no file
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "No file created."}

    # 2. Library Usage (15 pts)
    # Check if 'pid' or 'proceng' shapes were used
    if analysis.get("has_pid_shapes"):
        score += 15
        feedback.append("Process Engineering shape library used.")
    else:
        feedback.append("Standard shapes used instead of Process Engineering library.")

    # 3. Main Units Presence (25 pts)
    # We check for keywords in the diagram text (or labels on shapes)
    found_keywords = analysis.get("found_keywords", [])
    required_units = ["compressor", "reactor", "separator"] # Core 3
    unit_matches = 0
    
    # Check for unit keywords
    for unit in ["compressor", "reactor", "separator", "heater", "cooler", "condenser", "exchanger"]:
        if unit in found_keywords:
            unit_matches += 1
    
    # Cap at 5 units (5 pts each)
    unit_score = min(25, unit_matches * 5)
    score += unit_score
    feedback.append(f"Equipment units identified: {unit_matches} (Score: {unit_score}/25)")
    
    missing_core = [u for u in required_units if u not in found_keywords]
    if missing_core:
        feedback.append(f"Missing core units: {', '.join(missing_core)}")

    # 4. Recycle Loop (20 pts)
    # Hard to verify topology perfectly, so we check for:
    # A. "Recycle" text label (strong signal)
    # B. High edge-to-shape ratio (implies loops)
    has_recycle_text = analysis.get("has_recycle_text")
    num_shapes = analysis.get("num_shapes", 0)
    num_edges = analysis.get("num_edges", 0)
    
    if has_recycle_text:
        score += 20
        feedback.append("Recycle loop labeled.")
    elif num_edges >= num_shapes + 1 and num_shapes >= 4:
        # A simple linear flow has N-1 edges. A loop has >= N edges. 
        # Extra connections imply complexity/loops.
        score += 15
        feedback.append("Topology suggests recycle loop (edges > shapes).")
    else:
        feedback.append("Recycle loop not clearly identified.")

    # 5. Stream Labels (15 pts)
    chemicals = ["nh3", "ammonia", "n2", "h2", "nitrogen", "hydrogen"]
    found_chemicals = [c for c in chemicals if c in found_keywords]
    if len(found_chemicals) >= 2:
        score += 15
        feedback.append(f"Chemical streams labeled: {', '.join(set(found_chemicals))}")
    elif len(found_chemicals) == 1:
        score += 8
        feedback.append("Partial chemical labeling.")
    else:
        feedback.append("Chemical stream labels missing.")

    # 6. Flow Logic / Complexity (15 pts)
    # A PFD needs edges.
    if num_edges >= 5:
        score += 15
        feedback.append(f"Diagram has sufficient connectivity ({num_edges} edges).")
    elif num_edges >= 3:
        score += 7
        feedback.append(f"Diagram connectivity low ({num_edges} edges).")
    else:
        feedback.append("Diagram has very few connections.")

    # Final Result
    passed = score >= 65
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }