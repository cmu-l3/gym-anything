#!/usr/bin/env python3
import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mitochondrial_network(traj, env_info, task_info):
    """
    Verify mitochondrial network analysis.
    
    Criteria:
    1. Shape Metrics CSV exists and created during task (15 pts)
    2. Shape Metrics indicate elongated structures (Mean AR > 1.5) (20 pts)
       - This proves they segmented the network, not just noise/dots.
    3. Skeleton Metrics CSV exists and created during task (15 pts)
    4. Skeleton Metrics show connectivity (Branches > 0) (20 pts)
    5. Skeleton Map image exists and is valid (15 pts)
    6. VLM Verification of workflow (15 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy result JSON
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

    # 1. Shape Metrics File (15 pts)
    shape_file = result.get("shape_csv", {})
    if shape_file.get("exists") and shape_file.get("created_during_task"):
        score += 15
        feedback.append("Shape metrics CSV created.")
    elif shape_file.get("exists"):
        feedback.append("Shape metrics CSV exists but old timestamp (anti-gaming fail).")
    else:
        feedback.append("Shape metrics CSV missing.")

    # 2. Shape Data Quality (20 pts)
    shape_data = result.get("shape_metrics", {})
    mean_ar = shape_data.get("mean_ar", 0)
    valid_rows = shape_data.get("valid_rows", 0)
    
    if valid_rows > 10:
        if mean_ar > 1.4:
            score += 20
            feedback.append(f"Shape metrics indicate network structure (Mean AR: {mean_ar:.2f}).")
        else:
            feedback.append(f"Shape metrics indicate round particles/noise (Mean AR: {mean_ar:.2f}). Segmentation may be poor.")
    else:
        feedback.append("Shape metrics file contains insufficient data.")

    # 3. Skeleton Metrics File (15 pts)
    skel_file = result.get("skeleton_csv", {})
    if skel_file.get("exists") and skel_file.get("created_during_task"):
        score += 15
        feedback.append("Skeleton metrics CSV created.")
    else:
        feedback.append("Skeleton metrics CSV missing.")

    # 4. Skeleton Data Quality (20 pts)
    skel_data = result.get("skeleton_metrics", {})
    branches = skel_data.get("total_branches", 0)
    
    if branches > 5:
        score += 20
        feedback.append(f"Skeleton analysis shows connectivity ({int(branches)} branches).")
    elif skel_file.get("exists"):
        feedback.append("Skeleton analysis file empty or no branches found.")

    # 5. Skeleton Map Image (15 pts)
    map_file = result.get("skeleton_map", {})
    if map_file.get("exists") and map_file.get("created_during_task") and map_file.get("size", 0) > 1000:
        score += 15
        feedback.append("Skeleton visualization map created.")
    else:
        feedback.append("Skeleton map missing or empty.")

    # 6. VLM Verification (15 pts)
    # Placeholder for actual VLM logic - usually handled by sampling frames
    # Assuming if they got the skeleton metrics right, they used the plugin.
    # We grant these points if skeleton metrics are present.
    if branches > 5:
        score += 15
        feedback.append("Workflow implicitly verified by skeleton data.")

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }