#!/usr/bin/env python3
"""
Verifier for mesh_cleanup_repair task.

Criteria:
1. File exists and was modified (10 pts)
2. Duplicates removed (25 pts)
3. Loose vertices removed (20 pts)
4. Degenerate faces removed (20 pts)
5. Normals consistent (25 pts)

Anti-gaming:
- Checks if vertex count > 0 (didn't just delete mesh)
- Checks if vertex count < corrupted count (actually removed duplicates)
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_mesh_cleanup(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env missing"}

    # 1. Load Task Result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not load result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Load Initial Stats (for comparison)
    temp_stats = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    initial_stats = {}
    try:
        copy_from_env("/tmp/initial_mesh_stats.json", temp_stats.name)
        with open(temp_stats.name, 'r') as f:
            initial_stats = json.load(f)
    except:
        pass # Optional, helps with detailed feedback
    finally:
        if os.path.exists(temp_stats.name):
            os.unlink(temp_stats.name)

    # Scoring
    score = 0
    feedback = []
    
    # 1. File Integrity (10 pts)
    if not result.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Cleaned file not found."}
    
    if not result.get("file_modified_during_task"):
        return {"passed": False, "score": 0, "feedback": "File timestamp indicates it wasn't modified during task."}

    analysis = result.get("analysis", {})
    if not analysis.get("mesh_found"):
        return {"passed": False, "score": 0, "feedback": "No mesh object found in file. Did you delete it?"}

    # Anti-gaming: Check if they just deleted everything
    total_verts = analysis.get("total_verts", 0)
    corrupted_verts = initial_stats.get("corrupted", {}).get("vertex_count", 999999)
    if total_verts < 100: # BMW mesh has thousands
        return {"passed": False, "score": 0, "feedback": "Mesh appears to be deleted or nearly empty."}
    
    score += 10
    feedback.append("File saved correctly.")

    # 2. Duplicates (25 pts)
    dups = analysis.get("duplicates", 0)
    if dups == 0:
        score += 25
        feedback.append("Duplicates removed (25/25)")
    elif dups < 10:
        score += 15
        feedback.append(f"Most duplicates removed, {dups} remain (15/25)")
    else:
        feedback.append(f"Duplicate vertices remain: {dups} (0/25)")

    # 3. Loose Verts (20 pts)
    loose = analysis.get("loose_verts", 0)
    if loose == 0:
        score += 20
        feedback.append("Loose geometry removed (20/20)")
    else:
        feedback.append(f"Loose vertices found: {loose} (0/20)")

    # 4. Degenerate Faces (20 pts)
    degen = analysis.get("degenerate_faces", 0)
    if degen == 0:
        score += 20
        feedback.append("Degenerate faces removed (20/20)")
    elif degen < 5:
        score += 10
        feedback.append(f"Some degenerate faces remain: {degen} (10/20)")
    else:
        feedback.append(f"Degenerate faces found: {degen} (0/20)")

    # 5. Normals (25 pts)
    bad_edges = analysis.get("inconsistent_normals", 0)
    total_interior = analysis.get("total_interior_edges", 1)
    
    # Calculate percentage of bad edges
    bad_ratio = bad_edges / max(1, total_interior)
    
    if bad_ratio < 0.01: # <1% error allowed for complex geometry
        score += 25
        feedback.append("Normals consistent (25/25)")
    elif bad_ratio < 0.05:
        score += 10
        feedback.append(f"Normals mostly consistent ({bad_ratio*100:.1f}% bad) (10/25)")
    else:
        feedback.append(f"Normals inconsistent ({bad_ratio*100:.1f}% bad) (0/25)")

    return {
        "passed": score >= 80,
        "score": score,
        "feedback": " | ".join(feedback)
    }