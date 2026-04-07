#!/usr/bin/env python3
"""
Verifier for filter_dense_points task.

Verification Strategy (Multi-Criteria):
1. Timestamp Check: Ensures required files (.csv, .top, .txt) were created/modified DURING the task context. (Anti-gaming)
2. Spatial Math Check: Parses the exported CSV and calculates the pairwise spatial distance to guarantee no two points are < 2.45m apart.
3. Content & Quality Check: Validates the CSV isn't fully empty (must have >500 points) and checks the text report data.
4. Visual Trajectory Check (VLM): Confirms the agent used the UI, not just python scripting to solve it.
"""

import os
import json
import csv
import re
import tempfile
import logging
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def get_min_distance(pts_list):
    """Calculates the minimum distance between any two distinct points using SciPy or NumPy fallback."""
    if not pts_list or len(pts_list) < 2:
        return 0.0
    pts_arr = np.array(pts_list)
    
    try:
        from scipy.spatial import cKDTree
        tree = cKDTree(pts_arr)
        # k=2 because k=1 is the point itself (distance 0)
        distances, _ = tree.query(pts_arr, k=2)
        return np.min(distances[:, 1])
    except ImportError:
        # Fallback to pure numpy broadcasting
        logger.warning("SciPy not found. Using NumPy broadcasting fallback.")
        if len(pts_arr) > 4000:
            # Sample to prevent OOM on massive arrays
            idx = np.random.choice(len(pts_arr), 4000, replace=False)
            sample = pts_arr[idx]
        else:
            sample = pts_arr

        diff = sample[:, np.newaxis, :] - sample[np.newaxis, :, :]
        sq_dist = np.sum(diff ** 2, axis=-1)
        np.fill_diagonal(sq_dist, np.inf)
        return np.sqrt(np.min(sq_dist))


def verify_filter_dense_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    tmp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    tmp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')

    try:
        # 1. Fetch JSON state
        try:
            copy_from_env("C:\\tmp\\task_result.json", tmp_result.name)
            with open(tmp_result.name, 'r') as f:
                result = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to read result metadata: {e}"}

        task_start = result.get('task_start', 0)
        
        # Criterion 1: Check required files and anti-gaming (15 points)
        thinned_csv_exists = result.get('thinned_csv_exists', False)
        thinned_csv_mtime = result.get('thinned_csv_mtime', 0)
        top_exists = result.get('top_exists', False)
        top_mtime = result.get('top_mtime', 0)
        report_exists = result.get('report_exists', False)
        
        if thinned_csv_exists and top_exists:
            if thinned_csv_mtime >= task_start and top_mtime >= task_start:
                score += 15
                feedback_parts.append("✅ Output files generated during the task.")
            else:
                feedback_parts.append("❌ Output files exist but timestamps predate task (Gaming detected).")
        else:
            feedback_parts.append("❌ Missing required .csv or .top files.")
            
        # Criterion 2 & 3: CSV Content & Spatial Distance Check (55 points)
        pts = []
        csv_valid = False
        if thinned_csv_exists:
            try:
                copy_from_env("C:\\workspace\\data\\thinned_points.csv", tmp_csv.name)
                with open(tmp_csv.name, 'r', encoding='utf-8') as f:
                    reader = csv.reader(f)
                    for row in reader:
                        if len(row) >= 4:
                            try:
                                pts.append([float(row[1]), float(row[2])])
                            except ValueError:
                                pass # Skip headers if they exist
                csv_valid = True
            except Exception as e:
                feedback_parts.append(f"❌ Failed to parse exported CSV: {e}")

        if csv_valid:
            num_points = len(pts)
            # Count check (20 points)
            if 500 < num_points < 14000:
                score += 20
                feedback_parts.append(f"✅ Point count reduced properly ({num_points} pts).")
            else:
                feedback_parts.append(f"❌ Invalid point reduction ({num_points} pts). Should be >500 and <14000.")

            # Spatial distance check (35 points) - 2.45m tolerance for a 2.5m filter
            if 500 < num_points < 15000:
                min_dist = get_min_distance(pts)
                if min_dist >= 2.45:
                    score += 35
                    feedback_parts.append(f"✅ Spatial decimation mathematically verified (min distance: {min_dist:.2f}m).")
                else:
                    feedback_parts.append(f"❌ Decimation failed. Found points {min_dist:.2f}m apart, expected >= 2.45m.")

        # Criterion 4: Report validation (15 points)
        if report_exists:
            try:
                copy_from_env("C:\\workspace\\data\\filter_report.txt", tmp_report.name)
                with open(tmp_report.name, 'r', encoding='utf-8') as f:
                    report_text = f.read()

                orig_match = re.search(r'Original_Count:\s*(\d+)', report_text, re.IGNORECASE)
                final_match = re.search(r'Final_Count:\s*(\d+)', report_text, re.IGNORECASE)

                if orig_match and final_match:
                    orig_val = int(orig_match.group(1))
                    final_val = int(final_match.group(1))

                    if abs(orig_val - 15000) <= 500 and abs(final_val - len(pts)) <= 50:
                        score += 15
                        feedback_parts.append("✅ Report structure and counts are accurate.")
                    else:
                        feedback_parts.append(f"❌ Report values inaccurate (Orig: {orig_val}, Final: {final_val}).")
                else:
                    feedback_parts.append("❌ Report missing required syntax.")
            except Exception as e:
                feedback_parts.append(f"❌ Failed to verify report: {e}")
        else:
            feedback_parts.append("❌ Missing report file.")

        # Criterion 5: VLM Trajectory (15 points) - Confirm agent actually used TopoCal
        query_vlm = env_info.get('query_vlm')
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images_to_check = frames + [final] if final else frames
            
            if query_vlm and images_to_check:
                prompt = (
                    "You are checking a topography CAD task. "
                    "Did the agent use TopoCal's graphical menus/UI to perform point filtering or decimation "
                    "rather than just scripting? Look for open dialogs or software usage.\n"
                    "Reply strictly in JSON: {'used_topocal_ui': true/false}"
                )
                vlm_result = query_vlm(prompt=prompt, images=images_to_check)
                if vlm_result and vlm_result.get('success'):
                    if vlm_result.get('parsed', {}).get('used_topocal_ui', False):
                        score += 15
                        feedback_parts.append("✅ VLM confirmed usage of TopoCal UI.")
                    else:
                        feedback_parts.append("⚠️ VLM could not confirm TopoCal UI usage.")
        except Exception as e:
            feedback_parts.append(f"⚠️ VLM Check Exception: {e}")

        # Final Evaluation
        # 70 pts required, but must include spatial success
        spatial_success = "Spatial decimation mathematically verified" in " ".join(feedback_parts)
        passed = (score >= 70) and spatial_success

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    finally:
        for temp_f in [tmp_result, tmp_csv, tmp_report]:
            if os.path.exists(temp_f.name):
                try:
                    os.unlink(temp_f.name)
                except:
                    pass