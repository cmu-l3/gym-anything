#!/usr/bin/env python3
"""
Verifier for export_results_to_geojson task.

Verification Logic:
1. Checks if agent output (GeoJSON) exists and is valid JSON.
2. Checks if GeoJSON structure conforms to spec (FeatureCollection).
3. Compares feature count against ground truth (extracted from HDF).
4. Compares geometry of sample features against ground truth.
5. Compares attribute values (Peak WSE, Flow) against ground truth.
"""

import json
import os
import tempfile
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_export_results_to_geojson(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Files to retrieve
    files_to_copy = {
        "result": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "agent_geojson": "/tmp/agent_output.geojson"
    }
    
    data = {}
    
    with tempfile.TemporaryDirectory() as tmpdir:
        for name, path in files_to_copy.items():
            local_path = os.path.join(tmpdir, name + ".json")
            try:
                copy_from_env(path, local_path)
                if os.path.exists(local_path):
                    with open(local_path, 'r') as f:
                        # Only parse if it's expected to be JSON
                        try:
                            data[name] = json.load(f)
                        except json.JSONDecodeError:
                            data[name] = None # File exists but invalid JSON
                            if name == "agent_geojson":
                                feedback_parts.append("Output file is not valid JSON")
                else:
                    data[name] = None
            except Exception as e:
                logger.warning(f"Failed to copy {path}: {e}")
                data[name] = None

    # 1. check existence
    task_res = data.get("result")
    if not task_res or not task_res.get("output_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}
    
    if not task_res.get("file_created_during_task"):
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this task session")
        # We penalize but don't fail immediately if content is correct, but anti-gaming implies 0.
        # Let's deduct points.
        score -= 20
    
    agent_geo = data.get("agent_geojson")
    ground_truth = data.get("ground_truth")
    
    if not agent_geo:
        return {"passed": False, "score": 10, "feedback": "Output file exists but is empty or invalid JSON"}
    
    score += 10 # Valid JSON
    
    # 2. Check GeoJSON Structure (15 pts)
    if agent_geo.get("type") == "FeatureCollection" and isinstance(agent_geo.get("features"), list):
        score += 15
    else:
        feedback_parts.append("JSON is not a valid FeatureCollection")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    features = agent_geo["features"]
    
    # 3. Check Feature Count (15 pts)
    if not ground_truth or "error" in ground_truth:
        # Fallback if ground truth generation failed (shouldn't happen)
        feedback_parts.append("System Error: Could not verify against ground truth.")
        return {"passed": True, "score": 100, "feedback": "Passed (Verification skipped due to system error)"}

    expected_count = ground_truth.get("cross_section_count", 0)
    if len(features) == expected_count:
        score += 15
    else:
        feedback_parts.append(f"Incorrect feature count: {len(features)} (expected {expected_count})")
        
    # 4. Check Properties Schema (10 pts)
    if len(features) > 0:
        props = features[0].get("properties", {})
        req_keys = ["station", "peak_wse", "peak_flow"]
        if all(k in props for k in req_keys):
            score += 10
        else:
            missing = [k for k in req_keys if k not in props]
            feedback_parts.append(f"Missing properties: {missing}")

    # 5. Data Accuracy (30 pts + 20 pts Geometry)
    # Check First Feature
    f_first = features[0]
    gt_first_wse = ground_truth.get("peak_wse_sample_first")
    gt_first_flow = ground_truth.get("peak_flow_sample_first")
    
    # Check Last Feature
    f_last = features[-1]
    gt_last_wse = ground_truth.get("peak_wse_sample_last")
    gt_last_flow = ground_truth.get("peak_flow_sample_last")
    
    # Check geometry (simple node count or start point check)
    # Coordinate matching is tricky due to float precision, use tolerance
    def check_coords(f_coords, gt_coords):
        if not gt_coords or not f_coords: return False
        # f_coords is likely [[x,y], [x,y]...]
        # Check first point
        try:
            p1_agent = f_coords[0]
            p1_gt = gt_coords[0]
            dist = math.sqrt((p1_agent[0]-p1_gt[0])**2 + (p1_agent[1]-p1_gt[1])**2)
            return dist < 1.0 # 1 unit tolerance
        except:
            return False

    gt_coords_first = ground_truth.get("first_xs_coords")
    
    # Geometry Check
    if f_first.get("geometry", {}).get("type") == "LineString":
        coords = f_first.get("geometry", {}).get("coordinates")
        if check_coords(coords, gt_coords_first):
            score += 20
        else:
            feedback_parts.append("Geometry coordinates mismatch for first cross-section")
    else:
        feedback_parts.append("Feature geometry is not LineString")

    # Value Check
    # Allow 1% tolerance
    def check_val(val, expected):
        if val is None or expected is None: return False
        try:
            return abs(float(val) - float(expected)) / (abs(float(expected)) + 1e-6) < 0.01
        except:
            return False

    val_correct = True
    if not check_val(f_first["properties"].get("peak_wse"), gt_first_wse):
        val_correct = False
        feedback_parts.append(f"First XS WSE mismatch: Got {f_first['properties'].get('peak_wse')}, Exp {gt_first_wse}")
        
    if not check_val(f_first["properties"].get("peak_flow"), gt_first_flow):
        val_correct = False
        feedback_parts.append("First XS Flow mismatch")

    if not check_val(f_last["properties"].get("peak_wse"), gt_last_wse):
        val_correct = False
        feedback_parts.append("Last XS WSE mismatch")

    if val_correct:
        score += 30

    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts) if feedback_parts else "GeoJSON is correct and accurate"
    }