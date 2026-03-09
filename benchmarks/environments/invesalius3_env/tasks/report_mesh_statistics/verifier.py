#!/usr/bin/env python3
"""
Verifier for report_mesh_statistics task.

Scoring (100 points total):
1. Files Existence (20 pts): Both STL and Report files must exist.
2. STL Validity (20 pts): STL must be a valid binary file with non-trivial geometry.
3. Triangle Count Match (30 pts): Reported triangle count must match actual STL count (±1%).
4. Plausible Metrics (15 pts): Reported volume/area must be realistic numbers.
5. Anti-gaming (15 pts): Files must be created during the task window.

Pass threshold: 85 points
"""

import json
import os
import tempfile
import logging

logger = logging.getLogger(__name__)

def verify_report_mesh_statistics(traj, env_info, task_info):
    """Verify generated mesh statistics report against the exported STL."""
    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env unavailable"}

    metadata = task_info.get("metadata", {})
    min_triangles = metadata.get("min_triangles", 50000)
    
    score = 0
    feedback_parts = []
    
    # Load result
    try:
        tmp = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
        tmp.close()
        copy_from_env("/tmp/report_mesh_statistics_result.json", tmp.name)
        with open(tmp.name) as f:
            result = json.load(f)
        os.unlink(tmp.name)
    except Exception as e:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load verification result: {e}"
        }

    stl_stats = result.get("stl_stats", {})
    report_content = result.get("report_content", {})

    # --- Criterion 1: Files Existence (20 pts) ---
    if result.get("stl_exists") and result.get("report_exists"):
        score += 20
        feedback_parts.append("Both output files found")
    elif result.get("stl_exists"):
        score += 10
        feedback_parts.append("STL found but report missing")
    elif result.get("report_exists"):
        score += 10
        feedback_parts.append("Report found but STL missing")
    else:
        feedback_parts.append("No output files found")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

    # --- Criterion 2: STL Validity (20 pts) ---
    actual_triangles = stl_stats.get("triangle_count", 0)
    if stl_stats.get("valid_binary") and actual_triangles > min_triangles:
        score += 20
        feedback_parts.append(f"Valid binary STL ({actual_triangles} triangles)")
    elif stl_stats.get("valid_binary"):
        # Valid format but suspiciously simple geometry
        score += 10
        feedback_parts.append(f"Valid STL but low detail ({actual_triangles} < {min_triangles})")
    else:
        feedback_parts.append("STL invalid or corrupt")

    # --- Criterion 3: Triangle Count Match (30 pts) ---
    parsed_triangles = report_content.get("parsed_triangles")
    
    if parsed_triangles is not None and actual_triangles > 0:
        # Calculate percentage difference
        diff = abs(parsed_triangles - actual_triangles)
        percent_diff = (diff / actual_triangles) * 100
        
        if diff == 0:
            score += 30
            feedback_parts.append("Reported triangle count matches exactly")
        elif percent_diff <= 1.0:
            score += 30
            feedback_parts.append(f"Reported triangle count matches within 1% (Report: {parsed_triangles}, STL: {actual_triangles})")
        elif percent_diff <= 5.0:
            score += 15
            feedback_parts.append(f"Reported triangle count close (Report: {parsed_triangles}, STL: {actual_triangles})")
        else:
            feedback_parts.append(f"Reported count mismatch (Report: {parsed_triangles}, STL: {actual_triangles})")
    else:
        feedback_parts.append("Could not parse triangle count from report")

    # --- Criterion 4: Plausible Metrics (15 pts) ---
    vol = report_content.get("parsed_volume")
    area = report_content.get("parsed_area")
    
    if vol is not None and area is not None:
        # Check for non-zero positive values
        if vol > 1000 and area > 1000:
            score += 15
            feedback_parts.append("Volume and Area recorded")
        else:
            score += 5
            feedback_parts.append("Volume/Area found but values look trivial/small")
    elif vol is not None or area is not None:
        score += 10
        feedback_parts.append("Partial metrics recorded (Volume or Area)")
    else:
        feedback_parts.append("Volume/Area not found in report")

    # --- Criterion 5: Anti-gaming / Timestamps (15 pts) ---
    if stl_stats.get("created_during_task") and report_content.get("created_during_task"):
        score += 15
    elif stl_stats.get("created_during_task") or report_content.get("created_during_task"):
        score += 7
        feedback_parts.append("One file outdated/pre-existing")
    else:
        feedback_parts.append("Files not created during this task session")

    # Final Check
    passed = score >= 85
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "actual_triangles": actual_triangles,
            "reported_triangles": parsed_triangles,
            "reported_volume": vol
        }
    }