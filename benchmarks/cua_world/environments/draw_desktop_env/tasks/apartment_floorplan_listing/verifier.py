#!/usr/bin/env python3
"""
Verifier for apartment_floorplan_listing task.

Scoring breakdown (100 pts):
- File saved & modified: 5 pts
- Shape count (complexity): 15 pts
- Room labels present: 20 pts
- Dimension annotations: 10 pts
- Door shapes: 10 pts
- Window shapes: 5 pts
- Furniture shapes: 15 pts
- Title block: 5 pts
- Floorplan library usage: 5 pts
- PNG export: 10 pts

Pass threshold: 55 pts
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_apartment_floorplan(traj, env_info, task_info):
    """
    Verify the apartment floor plan task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve result file
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
            
    analysis = result.get('analysis', {})
    
    score = 0
    feedback = []
    
    # 1. File existence (5 pts)
    if result.get('drawio_exists') and result.get('drawio_modified'):
        score += 5
    else:
        return {"passed": False, "score": 0, "feedback": "Task failed: No modified .drawio file found."}

    # 2. Shape count (15 pts)
    # A full floor plan needs many shapes (walls, furniture, text)
    shape_count = analysis.get('shape_count', 0)
    if shape_count >= 30:
        score += 15
        feedback.append(f"Good shape complexity ({shape_count} shapes)")
    elif shape_count >= 20:
        score += 8
        feedback.append(f"Moderate shape complexity ({shape_count} shapes)")
    elif shape_count >= 10:
        score += 3
        feedback.append(f"Low shape complexity ({shape_count} shapes)")
    else:
        feedback.append(f"Too few shapes ({shape_count})")

    # 3. Room labels (20 pts)
    # We look for ~8 room names. 
    # The analysis script counts label matches. Note: 'master bedroom' might trigger both 'master' and 'bedroom' logic,
    # but the script counts occurrences of keywords found in text.
    # Let's verify specific room keywords from labels list to be more robust here if needed, 
    # but relying on analysis summary 'room_labels_found' is decent if implemented well.
    # Better: let's re-scan labels here for specific coverage.
    labels = [l.lower() for l in analysis.get('labels', [])]
    required_rooms = ['foyer', 'living', 'kitchen', 'master', 'closet', 'second', 'bath']
    rooms_found = 0
    for req in required_rooms:
        if any(req in l for l in labels):
            rooms_found += 1
            
    if rooms_found >= 6:
        score += 20
        feedback.append(f"Room labeling excellent ({rooms_found}/8+ types found)")
    elif rooms_found >= 4:
        score += 12
        feedback.append(f"Room labeling partial ({rooms_found} types found)")
    elif rooms_found >= 2:
        score += 5
        feedback.append(f"Room labeling sparse ({rooms_found} types found)")
    else:
        feedback.append("Missing room labels")

    # 4. Dimensions (10 pts)
    dims_found = analysis.get('dimensions_found', 0)
    if dims_found >= 4:
        score += 10
        feedback.append(f"Dimensions annotations found ({dims_found})")
    elif dims_found >= 2:
        score += 5
        feedback.append("Some dimensions found")
    else:
        feedback.append("Missing dimension annotations (e.g. 12' x 14')")

    # 5. Doors (10 pts)
    door_count = analysis.get('door_count', 0)
    # Also check labels for "door" if shapes aren't styled
    if door_count == 0:
        if any('door' in l for l in labels):
            door_count = 1 # minimal credit if labeled but no shape style detected
            
    if door_count >= 5:
        score += 10
        feedback.append(f"Doors placed ({door_count})")
    elif door_count >= 3:
        score += 5
        feedback.append(f"Some doors placed ({door_count})")
    else:
        feedback.append("Missing doors")

    # 6. Windows (5 pts)
    window_count = analysis.get('window_count', 0)
    if window_count >= 3:
        score += 5
        feedback.append(f"Windows placed ({window_count})")
    else:
        feedback.append("Missing windows")

    # 7. Furniture (15 pts)
    furn_count = analysis.get('furniture_count', 0)
    # Fallback to label search if styles missing
    furniture_keywords = ['bed', 'sofa', 'table', 'chair', 'toilet', 'sink', 'tub', 'shower', 'desk']
    label_furn_matches = 0
    for k in furniture_keywords:
        if any(k in l for l in labels):
            label_furn_matches += 1
    
    # Use the max of style-based or label-based detection
    effective_furn = max(furn_count, label_furn_matches)
    
    if effective_furn >= 10:
        score += 15
        feedback.append(f"Furniture placement good ({effective_furn} items)")
    elif effective_furn >= 5:
        score += 8
        feedback.append(f"Furniture placement partial ({effective_furn} items)")
    elif effective_furn >= 3:
        score += 3
        feedback.append("Minimal furniture")
    else:
        feedback.append("Missing furniture")

    # 8. Title block (5 pts)
    if analysis.get('title_found'):
        score += 5
        feedback.append("Title block found")

    # 9. Floorplan library usage (5 pts)
    if analysis.get('floorplan_shapes', 0) >= 3:
        score += 5
        feedback.append("Floorplan shape library used")
    else:
        feedback.append("Did not use floorplan specific shapes (walls/rooms)")

    # 10. PNG Export (10 pts)
    if result.get('png_exists') and result.get('png_size', 0) > 5000:
        score += 10
        feedback.append("PNG exported successfully")
    elif result.get('png_exists'):
        score += 4
        feedback.append("PNG exported but small/empty")
    else:
        feedback.append("PNG export missing")

    passed = score >= 55
    
    return {
        "passed": passed,
        "score": score,
        "feedback": ". ".join(feedback)
    }