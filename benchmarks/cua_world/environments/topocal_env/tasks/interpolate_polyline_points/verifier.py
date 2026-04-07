#!/usr/bin/env python3
"""
Verifier for interpolate_polyline_points task in TopoCal.

Geometric & Programmatic Verification:
1. File Existence & Creation Checks (Anti-gaming timestamps)
2. Point Count Check (> 20 points means interpolation occurred)
3. Mathematical Path Accuracy Check (Points must lie on the PI polyline segments)
4. Distance Interval Accuracy Check (Distance between points must be ~25.0m)
5. VLM Trajectory Verification (Ensures the CAD tool was used, not just python)
"""

import json
import tempfile
import os
import re
import math
import logging
from typing import List, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def point_segment_distance(px: float, py: float, ax: float, ay: float, bx: float, by: float) -> float:
    """Calculate perpendicular distance from point (px, py) to line segment (ax, ay) -> (bx, by)."""
    line_mag = math.hypot(bx - ax, by - ay)
    if line_mag == 0:
        return math.hypot(px - ax, py - ay)
    
    u = ((px - ax) * (bx - ax) + (py - ay) * (by - ay)) / (line_mag ** 2)
    
    if u < 0:
        return math.hypot(px - ax, py - ay)
    elif u > 1:
        return math.hypot(px - bx, py - by)
    else:
        ix = ax + u * (bx - ax)
        iy = ay + u * (by - ay)
        return math.hypot(px - ix, py - iy)


def distance_to_polyline(px: float, py: float, pis: List[Tuple[float, float]]) -> float:
    """Find the shortest distance from a point to a connected polyline."""
    dists = []
    for i in range(len(pis) - 1):
        ax, ay = pis[i]
        bx, by = pis[i+1]
        dists.append(point_segment_distance(px, py, ax, ay, bx, by))
    return min(dists)


def extract_coordinates(filepath: str) -> List[Tuple[float, float]]:
    """Robustly extract X and Y coordinates from any text-based format."""
    coords = []
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            for line in f:
                # Extract anything that looks like a number
                numbers = [float(n) for n in re.findall(r'-?\d+\.\d+|-?\d+', line)]
                x, y = None, None
                
                # Assign based on the known coordinate bounds to handle varying column orders
                for n in numbers:
                    if 481000 <= n <= 482000:
                        x = n
                    if 4395000 <= n <= 4395500:
                        y = n
                
                if x is not None and y is not None:
                    # Avoid back-to-back exact duplicates if present
                    if not coords or (coords[-1][0] != x or coords[-1][1] != y):
                        coords.append((x, y))
    except Exception as e:
        logger.error(f"Failed to parse coordinates: {e}")
    return coords


def verify_interpolate_polyline_points(traj, env_info, task_info):
    """Main verification logic."""
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    feedback = []
    score = 0

    # 1. Fetch JSON Results
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.error(f"Failed to read JSON results: {e}")
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # File and Anti-gaming Checks
    if result.get("csv_exists", False):
        if result.get("csv_created_during_task", False):
            score += 10
            feedback.append("✅ CSV exported during task.")
        else:
            feedback.append("❌ CSV exists but was NOT created during this task (Anti-gaming).")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}
    else:
        feedback.append("❌ Target CSV not exported.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback)}

    if result.get("project_exists", False):
        score += 10
        feedback.append("✅ TopoCal project saved.")
    else:
        feedback.append("❌ TopoCal project not saved.")

    if not result.get("app_running", True):
        feedback.append("⚠️ TopoCal was not running at the end of the task.")

    # 2. Fetch & Analyze Exported CSV Points
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    coords = []
    try:
        copy_from_env("C:\\workspace\\data\\stakeout_points.csv", temp_csv.name)
        coords = extract_coordinates(temp_csv.name)
    except Exception as e:
        logger.error(f"Failed to copy/parse CSV: {e}")
    finally:
        if os.path.exists(temp_csv.name):
            os.unlink(temp_csv.name)

    # Point Count Check
    point_count = len(coords)
    if point_count >= 20:
        score += 20
        feedback.append(f"✅ Sufficient points generated ({point_count}).")
    else:
        feedback.append(f"❌ Insufficient points generated ({point_count}). Interpolation likely failed.")

    # Path & Geometric Accuracy Checks
    pis = [
        (481200.000, 4395100.000),
        (481350.500, 4395220.300),
        (481580.200, 4395280.800),
        (481900.000, 4395150.400)
    ]

    path_errors = []
    intervals = []

    if point_count > 1:
        for i in range(point_count):
            # Calculate distance to known Polyline
            path_errors.append(distance_to_polyline(coords[i][0], coords[i][1], pis))
            
            # Calculate distance to NEXT point (interval)
            if i < point_count - 1:
                dx = coords[i+1][0] - coords[i][0]
                dy = coords[i+1][1] - coords[i][1]
                intervals.append(math.hypot(dx, dy))

        avg_path_error = sum(path_errors) / len(path_errors)
        if avg_path_error < 0.2:  # 20cm tolerance
            score += 30
            feedback.append(f"✅ High Path Accuracy (Avg error: {avg_path_error:.3f}m).")
        elif avg_path_error < 1.0:
            score += 15
            feedback.append(f"⚠️ Marginal Path Accuracy (Avg error: {avg_path_error:.3f}m).")
        else:
            feedback.append(f"❌ Poor Path Accuracy (Avg error: {avg_path_error:.3f}m).")

        # Check intervals (target = 25.0)
        valid_intervals = [dist for dist in intervals if 24.5 <= dist <= 25.5]
        valid_interval_ratio = len(valid_intervals) / len(intervals) if intervals else 0

        if valid_interval_ratio >= 0.8:
            score += 30
            feedback.append(f"✅ High Interval Accuracy ({valid_interval_ratio*100:.1f}% points spaced ~25m).")
        elif valid_interval_ratio >= 0.5:
            score += 15
            feedback.append(f"⚠️ Moderate Interval Accuracy ({valid_interval_ratio*100:.1f}% points spaced ~25m).")
        else:
            feedback.append(f"❌ Poor Interval Accuracy (Points not spaced correctly).")

    # 3. VLM Trajectory Verification (Anti-Script Gaming)
    if query_vlm:
        from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
        frames = sample_trajectory_frames(traj, n=4)
        frames.append(get_final_screenshot(traj))

        vlm_prompt = """
        Review these screenshots from a Windows session.
        Did the agent use a Topography/CAD software (like TopoCal) to draw a polyline connecting points and generate intermediate points along it?
        Look for CAD interfaces, drawn lines, and array of points.
        Respond with {"cad_used": true/false}.
        """
        
        try:
            vlm_response = query_vlm(images=frames, prompt=vlm_prompt)
            if vlm_response.get("success") and not vlm_response.get("parsed", {}).get("cad_used", False):
                # If they didn't use the CAD, they likely gamed it via Python scripting
                score = 0
                feedback.append("🚨 VLM Analysis Failed: CAD software was not actively used. (Score Reset to 0)")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": "\n".join(feedback)
    }