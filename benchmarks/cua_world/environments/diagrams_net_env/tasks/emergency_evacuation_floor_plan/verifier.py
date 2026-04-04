#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_emergency_evacuation_floor_plan(traj, env_info, task_info):
    """
    Verifies the Emergency Evacuation Floor Plan task.
    Checks:
    1. File modified & PDF exported.
    2. Room labels (Requirements check).
    3. Safety symbols (Exit, Extinguisher, First Aid).
    4. Routes (Edges).
    5. Legend/Title.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result from container
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
    
    # 1. Basics (20 pts)
    if result.get("file_modified"):
        score += 10
        feedback_parts.append("File modified")
    else:
        feedback_parts.append("File NOT modified")

    if result.get("pdf_exists"):
        score += 10
        feedback_parts.append("PDF export found")
    else:
        feedback_parts.append("PDF export missing")

    # 2. Text Content Analysis (40 pts)
    text_content = " ".join(result.get("text_content", [])).lower()
    
    # Check Room Labels
    required_rooms = ["301", "302", "304", "server", "kitchen", "conference", "reception", "restroom"]
    rooms_found = sum(1 for r in required_rooms if r in text_content)
    
    if rooms_found >= len(required_rooms) - 1:
        score += 15
        feedback_parts.append(f"Room labels present ({rooms_found}/{len(required_rooms)})")
    elif rooms_found > 0:
        score += 5
        feedback_parts.append(f"Some room labels missing ({rooms_found}/{len(required_rooms)})")
    else:
        feedback_parts.append("Room labels missing")

    # Check Safety Terms
    safety_terms = {
        "exit": "exit",
        "assembly": "assembly point",
        "legend": "legend",
        "title": "building c"
    }
    
    found_terms = 0
    for key, term in safety_terms.items():
        if term in text_content:
            found_terms += 1
    
    if found_terms >= 3:
        score += 15
        feedback_parts.append("Safety labels found")
    else:
        feedback_parts.append(f"Safety labels missing (found {found_terms}/4)")

    # Check Title specifically
    if result.get("has_title"):
        score += 5
        feedback_parts.append("Title block present")
    
    # Check Legend specifically
    if result.get("has_legend"):
        score += 5
        feedback_parts.append("Legend present")

    # 3. Shape & Edge Analysis (40 pts)
    # Start shapes was ~16. Expect > 40 total now (labels + icons).
    total_shapes = result.get("total_shapes", 0)
    total_edges = result.get("total_edges", 0)
    
    if total_shapes >= 35:
        score += 20
        feedback_parts.append(f"Sufficient shapes added ({total_shapes})")
    elif total_shapes >= 25:
        score += 10
        feedback_parts.append(f"Some shapes added ({total_shapes})")
    else:
        feedback_parts.append(f"Not enough shapes ({total_shapes})")

    # Edges (Routes)
    if total_edges >= 8:
        score += 15
        feedback_parts.append(f"Evacuation routes drawn ({total_edges} edges)")
    elif total_edges >= 3:
        score += 5
        feedback_parts.append("Few routes drawn")
    else:
        feedback_parts.append("No evacuation routes drawn")

    # Color Check (Red/Green/Orange)
    colors = " ".join(result.get("colors_used", [])).lower()
    # Simple check for hex or names. Red often #FF0000, Green #00FF00 etc.
    # Note: draw.io often uses color codes like #ff0000.
    has_red = "ff0000" in colors or "red" in colors or "ea6b66" in colors # ea6b66 is a standard drawio red
    has_green = "00ff00" in colors or "green" in colors or "82b366" in colors # standard green
    
    if has_red and has_green:
        score += 5
        feedback_parts.append("Safety colors used")
    else:
        feedback_parts.append("Standard safety colors not detected")

    # Final Pass/Fail
    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }