#!/usr/bin/env python3
"""
Verifier for calculate_surface_area task.
Calculates independent ground truth from the CSV using scipy Delaunay triangulation,
then compares the agent's reported values to the exact mathematical ground truth.
"""

import os
import json
import tempfile
import logging
import re
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def compute_ground_truth_areas(csv_path):
    """
    Independently compute 2D area, 3D surface area, and triangle count 
    from the raw CSV point data using Delaunay triangulation.
    """
    try:
        from scipy.spatial import Delaunay
    except ImportError:
        import subprocess
        import sys
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "scipy", "numpy"])
        from scipy.spatial import Delaunay

    points = []
    with open(csv_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) >= 4:
                try:
                    # PointID, X, Y, Z
                    x, y, z = float(parts[1]), float(parts[2]), float(parts[3])
                    points.append([x, y, z])
                except ValueError:
                    continue # Skip headers

    if not points:
        return None

    points = np.array(points)
    points_2d = points[:, :2]
    
    # Generate TIN (same algorithm TopoCal uses for 2.5D surfaces)
    tri = Delaunay(points_2d)
    simplices = tri.simplices

    gt_2d_area = 0.0
    gt_3d_area = 0.0

    for simplex in simplices:
        p0, p1, p2 = points[simplex]
        
        # 2D Area (Shoelace / Cross product of 2D vectors)
        v1_2d = p1[:2] - p0[:2]
        v2_2d = p2[:2] - p0[:2]
        area_2d = 0.5 * abs(v1_2d[0]*v2_2d[1] - v1_2d[1]*v2_2d[0])
        gt_2d_area += area_2d

        # 3D Area (Magnitude of 3D cross product)
        v1_3d = p1 - p0
        v2_3d = p2 - p0
        cross = np.cross(v1_3d, v2_3d)
        area_3d = 0.5 * np.linalg.norm(cross)
        gt_3d_area += area_3d

    return {
        "2d_area": gt_2d_area,
        "3d_area": gt_3d_area,
        "ratio": gt_3d_area / gt_2d_area if gt_2d_area > 0 else 1.0,
        "triangles": len(simplices)
    }

def verify_calculate_surface_area(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    csv_path = metadata.get('csv_path', "C:\\workspace\\data\\colorado_foothills.csv")
    report_path = metadata.get('report_path', "C:\\workspace\\data\\surface_area_report.txt")
    
    score = 0
    feedback_parts = []
    
    temp_dir = tempfile.mkdtemp()
    local_json = os.path.join(temp_dir, "task_result.json")
    local_report = os.path.join(temp_dir, "report.txt")
    local_csv = os.path.join(temp_dir, "data.csv")
    
    try:
        # 1. Fetch Task Result JSON
        try:
            copy_from_env("C:\\workspace\\data\\task_result.json", local_json)
            with open(local_json, 'r') as f:
                result = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Failed to read export results."}

        # 2. Fetch the Agent's Report File
        report_content = ""
        if result.get("report_exists"):
            try:
                copy_from_env(report_path, local_report)
                with open(local_report, 'r') as f:
                    report_content = f.read()
            except Exception:
                feedback_parts.append("Could not retrieve report file from container.")

        # 3. Fetch CSV and Calculate True Ground Truth
        gt = None
        try:
            copy_from_env(csv_path, local_csv)
            gt = compute_ground_truth_areas(local_csv)
        except Exception as e:
            logger.error(f"Failed to calculate ground truth: {e}")

        if not gt:
            return {"passed": False, "score": 0, "feedback": "Ground truth calculation failed."}

        # ==========================================
        # SCORING CRITERIA
        # ==========================================
        
        # Criterion 1: Project file saved (5 pts)
        if result.get("project_exists"):
            score += 5
            feedback_parts.append("Project file saved.")
            
        # Criterion 2: Timestamp Validity (Anti-gaming) (5 pts)
        if result.get("report_created_during_task"):
            score += 5
        else:
            feedback_parts.append("WARNING: Report file not created during task window.")

        # Parse agent report values
        agent_vals = {}
        for line in report_content.split('\n'):
            match = re.search(r'(2D_AREA_M2|3D_AREA_M2|SURFACE_RATIO|NUM_TRIANGLES):\s*([\d\.]+)', line)
            if match:
                agent_vals[match.group(1)] = float(match.group(2))

        # Criterion 3: Report file parseable (10 pts)
        if len(agent_vals) == 4:
            score += 10
            feedback_parts.append("Report file parsed successfully.")
        elif len(agent_vals) > 0:
            score += 5
            feedback_parts.append(f"Report partially parsed ({len(agent_vals)}/4 keys found).")
        else:
            feedback_parts.append("Report file is missing or formatted incorrectly.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        a_2d = agent_vals.get("2D_AREA_M2", 0)
        a_3d = agent_vals.get("3D_AREA_M2", 0)
        a_ratio = agent_vals.get("SURFACE_RATIO", 0)
        a_tri = agent_vals.get("NUM_TRIANGLES", 0)

        # Criterion 4: Fundamental truth: 3D > 2D area (10 pts)
        if a_3d > a_2d and a_2d > 0:
            score += 10
            
        # Criterion 5: Ratio in typical bounds (1.0 to 2.0) (10 pts)
        if 1.0 < a_ratio <= 2.0:
            score += 10

        # Criterion 6: 2D area plausible (10 pts) - Within 25% of GT
        if abs(a_2d - gt["2d_area"]) / gt["2d_area"] <= 0.25:
            score += 10
            feedback_parts.append(f"2D area matches GT ({a_2d:.1f}).")
            
        # Criterion 7: 3D area highly accurate (20 pts) - Within 15% of GT
        err_3d = abs(a_3d - gt["3d_area"]) / gt["3d_area"]
        if err_3d <= 0.05:
            score += 20
            feedback_parts.append(f"3D area highly accurate ({a_3d:.1f}).")
        elif err_3d <= 0.15:
            score += 10
            feedback_parts.append("3D area moderately accurate.")
        elif err_3d <= 0.30:
            score += 5
            feedback_parts.append("3D area roughly accurate.")

        # Criterion 8: Triangle count reasonable (5 pts)
        if abs(a_tri - gt["triangles"]) / gt["triangles"] <= 0.20:
            score += 5

        # ==========================================
        # VLM VERIFICATION (25 pts)
        # ==========================================
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            prompt = """
            Verify if the user successfully completed a topographic CAD workflow.
            Looking at these frames:
            1. Were points imported successfully? (Visible point cloud)
            2. Was a TIN/terrain model created? (Visible triangulated mesh connecting points)
            3. Did the user open an area/surface calculation tool?
            
            Respond in JSON:
            {"points_visible": true/false, "mesh_visible": true/false, "calculation_tool_used": true/false}
            """
            
            vlm_res = query_vlm(images=frames + [final_frame], prompt=prompt)
            if vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("points_visible"): score += 10
                if parsed.get("mesh_visible"): score += 10
                if parsed.get("calculation_tool_used"): score += 5
                
        # Passing Threshold logic
        # Must have >= 60 total, and must have at least partial 3D area accuracy
        key_criteria = err_3d <= 0.30 and a_3d > a_2d
        passed = score >= 60 and key_criteria

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }
        
    finally:
        # Cleanup
        for file in [local_json, local_report, local_csv]:
            if os.path.exists(file):
                os.remove(file)
        os.rmdir(temp_dir)