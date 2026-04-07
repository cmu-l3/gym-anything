#!/usr/bin/env python3
"""
Verifier for extract_points_by_boundary task.
Scoring:
- Filtered CSV created: 10 pts
- Project saved: 10 pts
- Data Authenticity (Prevent fabricated coords): 30 pts
- Spatial Filtering Precision (Zero points outside): 25 pts
- Data Preservation Recall (All points inside kept): 25 pts
"""

import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_extract_points(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    score = 0
    feedback_parts = []
    
    # 1. READ TASK RESULT JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\workspace\\data\\task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # 2. CHECK OUTPUT FILE EXISTENCE & ANTI-GAMING TIMESTAMPS
    if result.get('csv_exists') and result.get('csv_created_during_task'):
        score += 10
        feedback_parts.append("Filtered CSV correctly generated")
    elif result.get('csv_exists'):
        feedback_parts.append("Filtered CSV exists but was NOT created during task (Stale)")
        
    if result.get('top_exists') and result.get('top_created_during_task'):
        score += 10
        feedback_parts.append("Project file correctly saved")
    elif result.get('top_exists'):
        feedback_parts.append("Project file exists but was NOT created during task (Stale)")

    # 3. READ GROUND TRUTH (Expected points)
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    gt_points = {}
    try:
        copy_from_env("C:\\workspace\\data\\ground_truth_inside.csv", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            for line in f:
                parts = line.strip().split(',')
                if len(parts) >= 4:
                    gt_points[parts[0]] = {
                        'x': float(parts[1]),
                        'y': float(parts[2]),
                        'z': float(parts[3])
                    }
    except Exception as e:
        logger.error(f"Error reading Ground Truth: {e}")
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)
            
    # 4. PARSE AGENT EXPORTED CSV
    temp_out = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    out_points = {}
    out_raw_count = 0
    
    if result.get('csv_exists'):
        try:
            copy_from_env("C:\\workspace\\data\\site_filtered.csv", temp_out.name)
            with open(temp_out.name, 'r') as f:
                # CAD systems export formatting varies (commas vs spaces), normalize it
                content = f.read().replace('\t', ',')
                for line in content.split('\n'):
                    parts = [p.strip() for p in line.split(',') if p.strip()]
                    if len(parts) < 4 and ' ' in line:
                        parts = [p.strip() for p in line.split() if p.strip()]
                        
                    if len(parts) >= 4:
                        out_raw_count += 1
                        try:
                            pid = parts[0]
                            out_points[pid] = {
                                'x': float(parts[1]),
                                'y': float(parts[2]),
                                'z': float(parts[3])
                            }
                        except ValueError:
                            pass # Skip headers or malformed lines
        except Exception as e:
            logger.error(f"Error reading Agent CSV: {e}")
        finally:
            if os.path.exists(temp_out.name):
                os.unlink(temp_out.name)

    # 5. EVALUATE DATA
    if out_raw_count == 0:
        feedback_parts.append("Exported CSV contains no valid coordinates")
    else:
        # A) Data Authenticity (Check IDs and precise Z values match to prevent synthetic generation)
        authentic_count = sum(
            1 for pid, pt in out_points.items() 
            if pid in gt_points and abs(pt['z'] - gt_points[pid]['z']) < 0.1
        )
        auth_ratio = authentic_count / len(out_points) if len(out_points) > 0 else 0
        
        if auth_ratio >= 0.95:
            score += 30
            feedback_parts.append("Data authenticity verified")
        else:
            score += int(30 * auth_ratio)
            feedback_parts.append(f"Partial data authenticity ({auth_ratio:.1%}) - fake points detected?")
        
        # B) Spatial Filtering (Precision: Are any points left OUTSIDE the boundary?)
        outside_count = sum(
            1 for pid, pt in out_points.items()
            if not (476499 <= pt['x'] <= 476701 and 4399799 <= pt['y'] <= 4400001)
        )
        if outside_count == 0:
            score += 25
            feedback_parts.append("Perfect spatial filtering (0 outside points)")
        else:
            feedback_parts.append(f"Spatial filtering failed ({outside_count} points remained outside)")
            
        # C) Data Preservation (Recall: Did they accidentally delete INSIDE points?)
        retained_count = sum(1 for pid in gt_points if pid in out_points)
        recall = retained_count / len(gt_points) if len(gt_points) > 0 else 0
        
        if recall >= 0.95:
            score += 25
            feedback_parts.append(f"High data preservation ({recall:.1%})")
        else:
            score += int(25 * recall)
            feedback_parts.append(f"Data loss detected ({recall:.1%} of interior points preserved)")

    # 6. VLM VERIFICATION (Trajectory analysis)
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final = get_final_screenshot(traj)
            
            vlm_prompt = (
                "Look at these trajectory screenshots from a CAD topographic workflow. "
                "Did the agent draw a rectangular boundary, isolate the point cloud inside it, and delete the exterior points? "
                "Respond in JSON format: {'workflow_observed': true/false}"
            )
            vlm_result = query_vlm(images=frames + [final] if final else frames, prompt=vlm_prompt)
            
            if vlm_result and vlm_result.get("parsed", {}).get("workflow_observed"):
                feedback_parts.append("VLM verified workflow trajectory")
            else:
                feedback_parts.append("VLM did not clearly observe the isolation workflow")
        except Exception as e:
            logger.error(f"VLM verification query failed: {e}")

    # Determine Pass/Fail (Must get at least 80 AND have actually filtered the points)
    passed = score >= 80 and out_raw_count > 0 and outside_count == 0
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }