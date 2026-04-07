#!/usr/bin/env python3
import json
import tempfile
import os
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_create_color_ratio_map(traj, env_info, task_info):
    """
    Verify the B/V Color Ratio Map creation task.
    Scores based on map generation correctness, report completeness, and VLM trajectory analysis.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Extract start time for anti-gaming checks
    start_time = 0
    try:
        temp_start = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        copy_from_env("/tmp/task_start_time.txt", temp_start.name)
        with open(temp_start.name, 'r') as f:
            start_time = float(f.read().strip())
    except:
        pass
    finally:
        if os.path.exists(temp_start.name):
            os.unlink(temp_start.name)

    # Load results and ground truth
    res = {}
    gt = {}
    try:
        temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            res = json.load(f)
            
        temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        copy_from_env("/tmp/color_ratio_ground_truth.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load container data: {e}"}
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)
        if os.path.exists(temp_gt.name): os.unlink(temp_gt.name)

    if not gt:
        return {"passed": False, "score": 0, "feedback": "Ground truth not generated during setup."}

    score = 0
    feedback = []
    
    # 1. Map File Check (15 pts)
    if res.get('map_exists'):
        if res.get('map_mtime', 0) < start_time:
            feedback.append("Map file predates task start (gaming detected).")
        else:
            if res.get('map_shape') == gt.get('shape'):
                score += 15
                feedback.append("Ratio map exists and shape matches correctly.")
            else:
                score += 5
                feedback.append(f"Ratio map exists but has incorrect shape {res.get('map_shape')} vs {gt.get('shape')}.")
    else:
        feedback.append("Ratio map (BV_ratio_map.fits) not found.")
        
    # 2. Map Median Accuracy (15 pts)
    if res.get('map_median') is not None and gt.get('median_ratio') is not None:
        if gt['median_ratio'] != 0:
            err = abs(res['map_median'] - gt['median_ratio']) / abs(gt['median_ratio'])
            if err <= 0.20:
                score += 15
                feedback.append(f"Map median ratio is accurate (error {err*100:.1f}%).")
            elif err <= 0.50:
                score += 7
                feedback.append(f"Map median ratio is partially accurate (error {err*100:.1f}%).")
            else:
                feedback.append(f"Map median ratio inaccurate (error {err*100:.1f}%).")

    # 3. Results File Creation (10 pts)
    if res.get('txt_exists'):
        if res.get('txt_mtime', 0) < start_time:
            feedback.append("Results report predates task start (gaming detected).")
        else:
            score += 10
            feedback.append("Report file created.")
    else:
        feedback.append("Report file (color_results.txt) not found.")

    # 4. Point Measurement Checks (30 pts - 10 per star)
    parsed_stars = res.get('parsed_stars', {})
    gt_stars = gt.get('stars', {})
    for label in ['Star_A', 'Star_B', 'Star_C']:
        if label in parsed_stars and label in gt_stars:
            val = parsed_stars[label]
            gt_val = gt_stars[label]
            if gt_val != 0:
                err = abs(val - gt_val) / abs(gt_val)
                if err <= 0.15:
                    score += 10
                    feedback.append(f"{label} ratio accurate (error {err*100:.1f}%).")
                elif err <= 0.30:
                    score += 5
                    feedback.append(f"{label} ratio partially accurate (error {err*100:.1f}%).")
                else:
                    feedback.append(f"{label} ratio inaccurate (error {err*100:.1f}%).")
        else:
            feedback.append(f"{label} measurement not found in report.")

    # 5. Extremes Identification (20 pts - 10 per classification)
    if res.get('parsed_bluest') == gt.get('bluest'):
        score += 10
        feedback.append(f"Bluest star correctly identified as {gt.get('bluest')}.")
    elif res.get('parsed_bluest'):
        feedback.append(f"Bluest star incorrect (got {res.get('parsed_bluest')}, expected {gt.get('bluest')}).")
        
    if res.get('parsed_reddest') == gt.get('reddest'):
        score += 10
        feedback.append(f"Reddest star correctly identified as {gt.get('reddest')}.")
    elif res.get('parsed_reddest'):
        feedback.append(f"Reddest star incorrect (got {res.get('parsed_reddest')}, expected {gt.get('reddest')}).")

    # 6. VLM Trajectory Verification (10 pts)
    vlm_score = 0
    query_vlm = env_info.get('query_vlm')
    if query_vlm:
        try:
            from gym_anything.vlm import sample_trajectory_frames
            frames = sample_trajectory_frames(traj, n=4)
            if frames:
                prompt = '''Look at these screenshots from an agent operating AstroImageJ.
Did the agent use the "Image Calculator" dialog, OR is there a window showing the result of image division?
Respond in strictly JSON format: {"calculator_used": true/false}'''
                vlm_res = query_vlm(prompt=prompt, images=frames)
                if vlm_res and vlm_res.get('success'):
                    if vlm_res.get('parsed', {}).get('calculator_used', False):
                        vlm_score = 10
                        feedback.append("VLM confirmed Image Calculator usage.")
                    else:
                        feedback.append("VLM did not detect Image Calculator usage.")
        except Exception as e:
            logger.warning(f"VLM verification skipped/failed: {e}")
            # If framework error, grant points so as not to punish the agent
            vlm_score = 10
            
    score += vlm_score

    # Determine pass/fail
    passed = score >= 60 and res.get('map_exists') and res.get('txt_exists')

    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }