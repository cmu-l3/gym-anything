#!/usr/bin/env python3
"""
Verifier for Perspective Grid Construction.
Analyzes the GeoGebra construction to verify 2-point perspective rules.
"""

import json
import zipfile
import xml.etree.ElementTree as ET
import os
import math
import tempfile
import logging
import numpy as np
from collections import defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_perspective_grid_construction(traj, env_info, task_info):
    """
    Verifies that the agent created a 4x4 grid in 2-point perspective.
    Checks:
    1. File existence and timestamps.
    2. Existence of Horizon Line and Vanishing Points.
    3. Convergence of grid lines to VPs.
    4. Geometric correctness of depth (Diagonal check).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Result Metadata
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result metadata: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_meta.get('file_found') or not result_meta.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Perspective grid file not found or not created during task."}

    # 2. Retrieve GGB File
    temp_ggb = tempfile.NamedTemporaryFile(delete=False, suffix='.ggb')
    try:
        copy_from_env("/tmp/result_construction.ggb", temp_ggb.name)
        
        # Parse GGB (which is a zip)
        with zipfile.ZipFile(temp_ggb.name, 'r') as z:
            if 'geogebra.xml' not in z.namelist():
                return {"passed": False, "score": 20, "feedback": "Invalid GGB file (no geogebra.xml)."}
            xml_content = z.read('geogebra.xml')
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to process GGB file: {e}"}
    finally:
        if os.path.exists(temp_ggb.name):
            os.unlink(temp_ggb.name)

    # 3. Analyze Geometry
    analysis = analyze_geometry(xml_content)
    
    score = 0
    feedback = []

    # Criterion: File Exists (10 pts)
    score += 10
    feedback.append("File created.")

    # Criterion: Horizon & VPs (10 pts)
    # Check if we identified a horizon-like structure or points on a line
    if analysis['horizon_detected']:
        score += 10
        feedback.append("Horizon line detected.")
    else:
        feedback.append("Horizon line not clearly detected.")

    # Criterion: Convergence (Left/Right) (40 pts total)
    # We look for clusters of intersections
    vps = analysis['vanishing_points']
    left_vp_lines = 0
    right_vp_lines = 0
    
    # Sort VPs by x-coordinate
    vps.sort(key=lambda p: p[0])
    
    if len(vps) >= 2:
        # Assuming the two strongest clusters are the VPs
        vp1 = vps[0] # Left
        vp2 = vps[-1] # Right
        
        # Count lines passing near these VPs
        left_vp_lines = count_converging_lines(analysis['lines'], vp1)
        right_vp_lines = count_converging_lines(analysis['lines'], vp2)
        
        if left_vp_lines >= 5:
            score += 20
            feedback.append(f"Left perspective convergence good ({left_vp_lines} lines).")
        elif left_vp_lines >= 3:
            score += 10
            feedback.append(f"Left perspective convergence weak ({left_vp_lines} lines).")
            
        if right_vp_lines >= 5:
            score += 20
            feedback.append(f"Right perspective convergence good ({right_vp_lines} lines).")
        elif right_vp_lines >= 3:
            score += 10
            feedback.append(f"Right perspective convergence weak ({right_vp_lines} lines).")
    else:
        feedback.append("Could not identify two distinct vanishing points.")

    # Criterion: Grid Structure & Depth Accuracy (20 pts)
    # We check if diagonals converge to a point on the horizon (Diagonal Vanishing Point)
    # This proves they used a geometric method rather than guessing
    if analysis['diagonal_convergence']:
        score += 20
        feedback.append("Depth spacing is geometrically correct (diagonals converge).")
    elif analysis['grid_connectivity'] > 10: # At least they drew a connected grid
        score += 10
        feedback.append("Grid structure exists but depth spacing may be inaccurate.")
    else:
        feedback.append("Grid structure not well-formed.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }

def analyze_geometry(xml_data):
    """
    Parses GeoGebra XML to extract points and lines, then analyzes perspective.
    """
    root = ET.fromstring(xml_data)
    
    points = {} # label -> (x, y)
    lines = []  # list of (slope, intercept) or ((x1,y1), (x2,y2))
    
    # Extract Points
    for elem in root.findall(".//element[@type='point']"):
        label = elem.get('label')
        coords = elem.find('coords')
        if coords is not None:
            x = float(coords.get('x', 0))
            y = float(coords.get('y', 0))
            z = float(coords.get('z', 1)) # Homogeneous coords
            if z != 0:
                points[label] = (x/z, y/z)

    # Extract Segments/Lines
    # In GeoGebra XML, segments often define start/end points
    for elem in root.findall(".//command[@name='Segment']"):
        inp = elem.find('input')
        if inp is not None:
            p1_label = inp.get('a0')
            p2_label = inp.get('a1')
            if p1_label in points and p2_label in points:
                lines.append((points[p1_label], points[p2_label]))
    
    # Also Check Explicit Lines
    for elem in root.findall(".//command[@name='Line']"):
        inp = elem.find('input')
        if inp is not None:
            p1_label = inp.get('a0')
            p2_label = inp.get('a1')
            if p1_label in points and p2_label in points:
                lines.append((points[p1_label], points[p2_label]))

    # Analyze Vanishing Points via Intersection Clustering
    intersections = []
    # Brute force intersection of all line pairs (optimization: filter nearly parallel)
    for i in range(len(lines)):
        for j in range(i + 1, len(lines)):
            l1 = lines[i]
            l2 = lines[j]
            pt = intersect(l1[0], l1[1], l2[0], l2[1])
            if pt:
                intersections.append(pt)
    
    # Simple clustering: Bin intersections to find dense spots
    # For a 4x4 grid, we expect lots of hits at VP1 and VP2
    vp_candidates = cluster_points(intersections, radius=0.5, min_count=4)
    
    # Check for Horizon (do VPs lie on a horizontal-ish line?)
    horizon_detected = False
    if len(vp_candidates) >= 2:
        y_coords = [p[1] for p in vp_candidates]
        y_range = max(y_coords) - min(y_coords)
        if y_range < 1.0: # Roughly horizontal
            horizon_detected = True

    # Check Diagonals
    # This is tricky without knowing which lines are diagonals.
    # Heuristic: Diagonals in a perspective grid usually have different VPs than the main grid VPs.
    # If we find a 3rd cluster of intersections on the same horizon line, that's the DVP.
    diagonal_convergence = False
    if len(vp_candidates) >= 3 and horizon_detected:
        diagonal_convergence = True # Found VP1, VP2, and DVP

    return {
        'lines': lines,
        'points': points,
        'vanishing_points': vp_candidates,
        'horizon_detected': horizon_detected,
        'grid_connectivity': len(lines), # Simplified proxy
        'diagonal_convergence': diagonal_convergence
    }

def intersect(p1, p2, p3, p4):
    """Find intersection of line(p1,p2) and line(p3,p4). Returns (x,y) or None."""
    x1, y1 = p1
    x2, y2 = p2
    x3, y3 = p3
    x4, y4 = p4
    
    denom = (y4 - y3) * (x2 - x1) - (x4 - x3) * (y2 - y1)
    if abs(denom) < 1e-6: return None # Parallel
    
    ua = ((x4 - x3) * (y1 - y3) - (y4 - y3) * (x1 - x3)) / denom
    
    x = x1 + ua * (x2 - x1)
    y = y1 + ua * (y2 - y1)
    return (x, y)

def cluster_points(points, radius=0.5, min_count=3):
    """Greedy clustering to find intersection hotspots."""
    centroids = []
    if not points: return []
    
    used = [False] * len(points)
    
    for i, p in enumerate(points):
        if used[i]: continue
        
        cluster = [p]
        used[i] = True
        
        for j, q in enumerate(points):
            if not used[j]:
                dist = math.sqrt((p[0]-q[0])**2 + (p[1]-q[1])**2)
                if dist < radius:
                    cluster.append(q)
                    used[j] = True
        
        if len(cluster) >= min_count:
            # Average
            avg_x = sum(c[0] for c in cluster) / len(cluster)
            avg_y = sum(c[1] for c in cluster) / len(cluster)
            centroids.append((avg_x, avg_y))
            
    return centroids

def count_converging_lines(lines, vp, tolerance=0.5):
    """Count how many lines, if extended, pass near the VP."""
    count = 0
    for p1, p2 in lines:
        # Check distance from VP to the line defined by p1, p2
        # Line eq: ax + by + c = 0
        # (y1-y2)x + (x2-x1)y + x1y2 - x2y1 = 0
        a = p1[1] - p2[1]
        b = p2[0] - p1[0]
        c = p1[0]*p2[1] - p2[0]*p1[1]
        
        dist = abs(a*vp[0] + b*vp[1] + c) / math.sqrt(a*a + b*b)
        if dist < tolerance:
            count += 1
    return count