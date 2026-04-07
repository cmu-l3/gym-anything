#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_layout_design(traj, env_info, task_info):
    """
    Verifies that the 'Gate Monitor' layout was created with two items
    pointing to the Parking Lot Camera, one zoomed and one wide.
    """
    # 1. Boilerplate: Access Copy Function
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: Copy function not available"}

    # 2. Retrieve Result JSON from Container
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task results: {str(e)}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    # 3. Retrieve Target Camera ID (stored during setup to ensure match)
    # We'll try to get it from the container or task metadata.
    # For robustness, we'll assume the verifier can query the API or use the ID if we exported it.
    # Let's try to fetch the ID file from the container too.
    target_cam_id = None
    try:
        temp_id_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/target_camera_id.txt", temp_id_file.name)
        with open(temp_id_file.name, 'r') as f:
            target_cam_id = f.read().strip()
        os.unlink(temp_id_file.name)
    except:
        logger.warning("Could not retrieve target camera ID file, will rely on layout inspection.")

    # 4. Scoring Logic
    score = 0
    feedback = []
    
    # Check 1: Layout Exists (20 pts)
    if not result.get('layout_found'):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Layout 'Gate Monitor' was not found in the system."
        }
    
    score += 20
    feedback.append("Layout 'Gate Monitor' created.")
    
    layout_data = result.get('layout_data', {})
    items = layout_data.get('items', [])
    
    # Check 2: Correct Item Count (20 pts)
    # We expect exactly 2 items
    if len(items) == 2:
        score += 20
        feedback.append("Layout contains exactly 2 items.")
    else:
        feedback.append(f"Layout contains {len(items)} items (expected 2).")
    
    # Check 3: Resource Verification (20 pts)
    # Both items must point to the target camera
    correct_resources = 0
    for item in items:
        # In Nx Witness API, 'resourceId' links to the camera
        rid = item.get('resourceId')
        # If we have the ID, match it. If not, we assume agent acted correctly if items are identical resource.
        if target_cam_id and rid == target_cam_id:
            correct_resources += 1
        elif not target_cam_id:
            # Fallback: check if resources are identical if we don't know the ID
            pass 
            
    if correct_resources == len(items) and len(items) > 0:
        score += 20
        feedback.append("All items verify as 'Parking Lot Camera'.")
    elif correct_resources > 0:
        score += 10
        feedback.append(f"Only {correct_resources} items verify as 'Parking Lot Camera'.")
    else:
        feedback.append("Items do not match 'Parking Lot Camera'.")

    # Check 4: Zoom Configuration (40 pts)
    # One item should be "full" (zoom rect 0,0,1,1 or similar)
    # One item should be "zoomed" (zoom rect significantly smaller)
    # Nx Witness item params: 'zoomLeft', 'zoomTop', 'zoomRight', 'zoomBottom'
    # Default/Full is usually 0,0,1,1 (or 0,0,0,0 depending on API version interpretation).
    # Actually, Nx Witness uses coordinates where 0,0 is top-left, 1,1 is bottom-right.
    # A zoom rect of 0,0,1,1 means full view.
    
    zoomed_items = 0
    full_items = 0
    
    for item in items:
        # Extract zoom params. Keys might vary slightly by version, checking common ones.
        # Often these are direct properties of the item object in the REST API v1/v2
        z_left = float(item.get('zoomLeft', 0))
        z_right = float(item.get('zoomRight', 1))
        z_top = float(item.get('zoomTop', 0))
        z_bottom = float(item.get('zoomBottom', 1))
        
        width = z_right - z_left
        height = z_bottom - z_top
        
        # Check if it's a full view (approx 1.0 width/height)
        if width > 0.95 and height > 0.95:
            full_items += 1
        # Check if it's a zoomed view (significantly cropped, e.g., < 0.8 area)
        elif width < 0.8 or height < 0.8:
            zoomed_items += 1
            
    if full_items >= 1 and zoomed_items >= 1:
        score += 40
        feedback.append("Correct split-screen configuration: One context view, one zoomed detail view.")
    elif full_items == 2:
        feedback.append("Both views appear to be zoomed out (context only).")
    elif zoomed_items == 2:
        feedback.append("Both views appear to be zoomed in.")
    else:
        feedback.append("Zoom configuration unclear.")

    # 5. Final Result
    passed = (score >= 80)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }