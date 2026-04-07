#!/usr/bin/env python3
"""
Verifier for the TopoCal Elevation Datum Shift task.

Verification Strategy:
1. Anti-gaming: Ensure output files (.csv and .top) were created *after* task started.
2. Completeness: Ensure exported CSV contains the same number of points as the source file.
3. XY Preservation: Verify X and Y coordinates were not modified.
4. Z-Shift Accuracy: Verify Z coordinate mathematically shifted by exactly +845.32m.
5. Trajectory Verification: Samples trajectory frames to verify TopoCal UI was utilized.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_adjust_elevation_datum(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "❌ System error: Copy function not available."}

    # Load expected metadata
    metadata = task_info.get('metadata', {})
    expected_shift = float(metadata.get('z_shift', 845.32))
    tolerance = float(metadata.get('tolerance_m', 0.05))

    score = 0
    feedback_parts = []
    
    # Copy result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\tmp\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"❌ Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    csv_exists = result.get('csv_exists', False)
    top_exists = result.get('top_exists', False)
    start_time = result.get('task_start_time', 0)
    csv_mtime = result.get('csv_mtime', 0)

    # Criterion 1: Output Verification & Anti-gaming (15 pts)
    if csv_exists and top_exists:
        if csv_mtime >= start_time:
            score += 15
            feedback_parts.append("✅ Both CSV and TOP files created/modified successfully.")
        else:
            feedback_parts.append("❌ Output files existed before task started (Anti-gaming).")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    else:
        if not top_exists: feedback_parts.append("❌ TopoCal project file (.top) not saved.")
        if not csv_exists: feedback_parts.append("❌ Adjusted CSV file not exported.")
        return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

    # Copy Original and Agent's CSVs to evaluate data
    temp_orig = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_new = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("C:\\workspace\\data\\local_datum_survey.csv", temp_orig.name)
        copy_from_env("C:\\workspace\\data\\navd88_survey.csv", temp_new.name)

        orig_points = {}
        with open(temp_orig.name, 'r', encoding='utf-8') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) >= 4 and parts[0].replace('.', '', 1).isdigit():
                    orig_points[parts[0]] = (float(parts[1]), float(parts[2]), float(parts[3]))

        new_points = {}
        with open(temp_new.name, 'r', encoding='utf-8') as f:
            # Clean possible varying delimiters produced by different TopoCal export choices
            content = f.read().replace('\t', ',').replace(';', ',')
            lines = [line for line in content.splitlines() if line.strip()]
            for line in lines:
                parts = [x.strip() for x in line.split(',') if x.strip()]
                if len(parts) >= 4 and parts[0].replace('.', '', 1).isdigit():
                    try:
                        new_points[parts[0]] = (float(parts[1]), float(parts[2]), float(parts[3]))
                    except ValueError:
                        continue

        # Criterion 2: Data Completeness (15 pts)
        if len(new_points) == 0:
            feedback_parts.append("❌ Exported CSV contains no parseable data points.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        completeness_ratio = len(new_points) / len(orig_points)
        if completeness_ratio == 1.0:
            score += 15
            feedback_parts.append("✅ All original points are present in the export.")
        elif completeness_ratio >= 0.9:
            score += 7
            feedback_parts.append(f"⚠️ Minor point loss in export ({len(new_points)}/{len(orig_points)} points).")
        else:
            feedback_parts.append(f"❌ Significant point loss in export ({len(new_points)}/{len(orig_points)} points).")

        # Criterion 3 & 4: XY Preservation (25 pts) and Z-Shift Accuracy (35 pts)
        xy_matches = 0
        z_shifted = 0
        points_checked = 0

        for pid, (orig_x, orig_y, orig_z) in orig_points.items():
            if pid in new_points:
                points_checked += 1
                new_x, new_y, new_z = new_points[pid]

                dx = abs(new_x - orig_x)
                dy = abs(new_y - orig_y)
                dz = new_z - orig_z

                if dx < tolerance and dy < tolerance:
                    xy_matches += 1

                if abs(dz - expected_shift) < tolerance:
                    z_shifted += 1

        if points_checked > 0:
            xy_score = int(25 * (xy_matches / points_checked))
            z_score = int(35 * (z_shifted / points_checked))

            score += xy_score
            score += z_score

            if xy_score == 25:
                feedback_parts.append("✅ X and Y coordinates preserved exactly.")
            else:
                feedback_parts.append(f"❌ X/Y coordinates altered for some points ({xy_matches}/{points_checked} preserved).")

            if z_score == 35:
                feedback_parts.append(f"✅ Z-shift (+{expected_shift}m) correctly applied to all exported points.")
            elif z_score > 0:
                feedback_parts.append(f"⚠️ Z-shift applied successfully to {z_shifted}/{points_checked} points.")
            else:
                feedback_parts.append(f"❌ Z-shift (+{expected_shift}m) was not mathematically applied correctly.")

    except Exception as e:
        feedback_parts.append(f"❌ Error validating datasets: {str(e)}")
    finally:
        if os.path.exists(temp_orig.name): os.unlink(temp_orig.name)
        if os.path.exists(temp_new.name): os.unlink(temp_new.name)

    # Criterion 5: VLM UI Verification (10 pts)
    # Proves the agent utilized the TopoCal UI rather than writing a python/powershell script to manipulate the CSV
    query_vlm = env_info.get('query_vlm')
    if query_vlm and 'steps' in traj:
        steps = traj.get('steps', [])
        screenshots = [s.get('obs', {}).get('screenshot') for s in steps if s.get('obs', {}).get('screenshot')]
        if screenshots:
            import random
            sample_size = min(3, len(screenshots))
            # Sample middle workflow steps
            frames = random.sample(screenshots[:-1], sample_size) + [screenshots[-1]] if len(screenshots) > 1 else screenshots
            
            prompt = "Is the user visually interacting with the TopoCal application to edit or modify point coordinates/elevations? Answer YES or NO."
            vlm_res = query_vlm(images=frames, prompt=prompt)
            
            if vlm_res.get('success') and "YES" in vlm_res.get('text', '').upper():
                score += 10
                feedback_parts.append("✅ VLM verified TopoCal interaction.")
            else:
                feedback_parts.append("⚠️ VLM could not conclusively verify TopoCal manipulation.")

    passed = score >= 90
    return {"passed": passed, "score": score, "feedback": " | ".join(feedback_parts)}