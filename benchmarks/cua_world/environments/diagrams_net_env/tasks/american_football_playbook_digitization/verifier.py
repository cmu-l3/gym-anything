#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_playbook_digitization(traj, env_info, task_info):
    """
    Verifies the American Football Playbook Digitization task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Fetch Result JSON
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

    score = 0
    feedback = []
    
    # Extract data
    analysis = result.get("diagram_analysis", {})
    labels = [l.upper() for l in analysis.get("labels", [])]
    edges = analysis.get("edges", [])
    shapes = analysis.get("shapes", [])
    
    # --- SCORING CRITERIA ---

    # 1. File Modification & Export (30 pts)
    if result.get("file_modified"):
        score += 10
        feedback.append("Draw.io file modified.")
    else:
        feedback.append("Draw.io file NOT modified.")

    if result.get("pdf_exists") and result.get("pdf_size", 0) > 1000:
        score += 20
        feedback.append("PDF exported successfully.")
    else:
        feedback.append("PDF export missing or empty.")

    # 2. Formation Labels (30 pts)
    # Looking for offensive players: QB, C, Y, Z, X, FB
    required_labels = ["QB", "C", "Y", "Z", "X", "FB"]
    found_labels = 0
    missing_labels = []
    
    for req in required_labels:
        # Check for exact match or contained match (e.g. "QB1")
        if any(req == l or f" {req} " in f" {l} " for l in labels):
            found_labels += 1
        else:
            missing_labels.append(req)
            
    # Calculate score for labels (5 pts each, max 30)
    label_score = min(30, found_labels * 5)
    score += label_score
    if missing_labels:
        feedback.append(f"Missing player labels: {', '.join(missing_labels)}")
    else:
        feedback.append("All key offensive players labeled.")

    # 3. Defensive Front (10 pts)
    # Look for 'X' labels or red shapes (checking style string)
    def_count = 0
    for shape in shapes:
        # Check if value is X or style implies defense color (red/pinkish)
        # Template uses fillColor=#F8CECC for defense
        style = shape.get("style", "")
        val = shape.get("value", "").strip().upper()
        if "F8CECC" in style or val == "X":
            def_count += 1
            
    if def_count >= 4:
        score += 10
        feedback.append(f"Defensive front present ({def_count} players).")
    else:
        feedback.append(f"Defensive front insufficient ({def_count}/4 players).")

    # 4. Route Geometry & Types (30 pts)
    # We need to detect:
    # - Curved lines (Banana, Flat) -> style contains 'curved=1' or 'edgeStyle' that isn't straight
    # - Straight lines (Post, Shallow) -> default or 'straight'
    # - Dashed lines (QB) -> 'dashed=1'
    
    curved_routes = 0
    straight_routes = 0
    dashed_routes = 0
    
    for edge in edges:
        style = edge.get("style", "")
        # Check for curve
        if "curved=1" in style or "entityRelationEdgeStyle" in style or "orthogonalEdgeStyle" in style:
            curved_routes += 1
        else:
            straight_routes += 1
            
        if "dashed=1" in style:
            dashed_routes += 1
            
    # Expecting at least 2 curved (FB, Y) and 2 straight (Z, X)
    if curved_routes >= 2:
        score += 15
        feedback.append("Curved routes detected (Banana/Flat).")
    elif curved_routes == 1:
        score += 7
        feedback.append("Only 1 curved route detected (expected 2).")
    else:
        feedback.append("No curved routes detected.")
        
    if straight_routes >= 2:
        score += 10
        feedback.append("Straight routes detected (Post/Shallow).")
    else:
        feedback.append("Insufficient straight routes.")
        
    if dashed_routes >= 1:
        score += 5
        feedback.append("Dashed line detected (QB Action).")

    # Final Check
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }