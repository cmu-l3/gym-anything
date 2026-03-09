#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chemical_pid_hazop_update(traj, env_info, task_info):
    """
    Verifies the Chemical P&ID HazOp Update task.
    Checks for:
    1. PDF Export existence
    2. Diagram file modification
    3. Specific equipment shapes (Pump, PSV, Exchanger, Check Valve) based on styles/labels
    4. Correct tagging labels (e.g., P-101)
    5. Connectivity (Pump connected to Tank, etc.)
    """
    
    # 1. Setup & Read Result
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 2. Extract Data
    export_exists = result.get("export_exists", False)
    file_modified = result.get("file_modified", False)
    analysis = result.get("diagram_analysis", {})
    
    shapes = analysis.get("shapes", [])
    labels = analysis.get("labels", [])
    styles = analysis.get("styles", [])
    edges = analysis.get("edges", [])

    # Flatten labels for easier searching (normalize case)
    flat_labels = [str(l).upper() for l in labels]
    flat_styles = " ".join(styles).lower()

    score = 0
    feedback = []

    # 3. Scoring Criteria

    # A. PDF Export (10 pts)
    if export_exists and result.get("export_size", 0) > 1000:
        score += 10
        feedback.append("PDF export found.")
    else:
        feedback.append("PDF export missing or empty.")

    # B. File Modified (10 pts)
    if file_modified:
        score += 10
        feedback.append("Diagram file modified.")
    else:
        feedback.append("Diagram file was not saved.")

    # C. Required Equipment Presence (Tags) (40 pts - 10 each)
    required_tags = {
        "PSV-101": ["PSV-101", "PSV101"],
        "P-101":   ["P-101", "P101"],
        "V-102":   ["V-102", "V102"],
        "E-101":   ["E-101", "E101"]
    }
    
    found_tags = []
    for tag_name, variants in required_tags.items():
        found = any(any(v in label for v in variants) for label in flat_labels)
        if found:
            score += 10
            found_tags.append(tag_name)
        else:
            feedback.append(f"Missing tag label: {tag_name}")

    # D. Correct Shape Library Usage (20 pts)
    # Check if they used P&ID specific shapes (looking for keywords in style string)
    # Generic rectangles have style 'rounded=0;whiteSpace=wrap;html=1;'
    # P&ID shapes usually have 'pid', 'valve', 'pump', 'exchanger', or 'mxgraph.pid'
    
    pid_keywords = ["pid", "valve", "pump", "exchanger", "vessel", "mxgraph.pid"]
    pid_shape_count = sum(1 for style in styles if any(k in style for k in pid_keywords))
    
    # We expect at least 4 P&ID specific shapes (Pump, PSV, Valve, Exchanger)
    if pid_shape_count >= 4:
        score += 20
        feedback.append("Used correct P&ID shape library.")
    elif pid_shape_count >= 1:
        score += 10
        feedback.append("Used some P&ID shapes, but some might be generic rectangles.")
    else:
        feedback.append("Failed to use P&ID shape library (likely used generic shapes).")

    # E. Connectivity (20 pts)
    # We check if there are enough edges. A full chain Tank->Pump->Valve->Exch needs at least 3-4 edges.
    # The starter diagram had 1 edge.
    # We verify if new edges were added.
    edge_count = len(edges)
    new_edges = edge_count - 1 # approximate since we started with 1
    
    if new_edges >= 3:
        score += 20
        feedback.append("Connectivity looks correct (sufficient piping lines added).")
    elif new_edges >= 1:
        score += 10
        feedback.append("Partial connectivity detected.")
    else:
        feedback.append("Missing connection lines between equipment.")

    # 4. Final Verification
    passed = score >= 65 and export_exists and len(found_tags) >= 3
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }