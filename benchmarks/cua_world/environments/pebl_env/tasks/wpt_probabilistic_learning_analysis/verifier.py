#!/usr/bin/env python3
"""
Verifier for wpt_probabilistic_learning_analysis task.

Verifies programmatic output against dynamically calculated Ground Truth from the agent's WPT dataset.
Also uses VLM to verify the generated learning curve plot and agent trajectory.

Scoring (100 points total):
1. Output JSON exists and is valid (10 pts)
2. Contaminated participant sub-999 correctly excluded (20 pts)
3. Individual block optimal rates & learning scores correct (25 pts)
4. Group mean learning curve correct (15 pts)
5. Plot PNG exists and is valid (10 pts)
6. VLM confirms the plot visually depicts a learning curve & trajectory shows work (20 pts)
"""

import os
import json
import csv
import tempfile
import base64
import logging
from collections import defaultdict

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

TOLERANCE = 0.015
CONTAMINATED_ID = "sub-999"

VLM_PROMPT = """You are evaluating an agent's trajectory and data visualization output for a probabilistic learning analysis task.
Look at the provided trajectory frames and the final screenshot.
Please assess the following:
1. TRAJECTORY_WORK: Do the trajectory frames show the agent writing code (e.g., Python script in an editor or terminal) to analyze data and generate a plot?
2. PLOT_VISIBLE: Does the final screenshot or any of the frames show an actual data visualization line plot?
3. LEARNING_CURVE: If a plot is visible, does it have an X-axis indicating "Blocks" (1 through 5) and a Y-axis indicating something like "Optimal Response Rate" or "Accuracy"? Does the line generally go upward from left to right?

Respond STRICTLY in JSON format:
{
    "trajectory_work_observed": true/false,
    "plot_visible": true/false,
    "valid_learning_curve": true/false,
    "reasoning": "brief explanation"
}
"""

def calculate_ground_truth(csv_path):
    """Calculates the exact ground truth from the deterministic CSV."""
    participant_data = defaultdict(lambda: defaultdict(list))
    
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            pid = row['participant_id']
            trial = int(row['trial'])
            block = str(((trial - 1) // 20) + 1)
            optimal = 1 if row['response'] == row['optimal_choice'] else 0
            participant_data[pid][block].append(optimal)

    gt_participants = {}
    valid_group_blocks = defaultdict(list)

    for pid, blocks in participant_data.items():
        rates = {}
        for b in ["1", "2", "3", "4", "5"]:
            if b in blocks:
                rates[b] = sum(blocks[b]) / len(blocks[b])
            else:
                rates[b] = 0.0
                
        learning_score = rates["5"] - rates["1"]
        gt_participants[pid] = {
            "block_optimal_rates": rates,
            "learning_score": learning_score
        }

        # Accumulate group means only for valid participants
        if pid != CONTAMINATED_ID:
            for b in ["1", "2", "3", "4", "5"]:
                valid_group_blocks[b].append(rates[b])

    gt_group_means = {}
    for b in ["1", "2", "3", "4", "5"]:
        if valid_group_blocks[b]:
            gt_group_means[b] = sum(valid_group_blocks[b]) / len(valid_group_blocks[b])
            
    return gt_participants, gt_group_means


def verify_wpt_analysis(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []

    # 1. Fetch the CSV to compute the Ground Truth
    csv_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    try:
        copy_from_env("/home/ga/pebl/data/wpt_data.csv", csv_tmp.name)
        gt_participants, gt_group_means = calculate_ground_truth(csv_tmp.name)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to calculate ground truth from CSV: {e}"}
    finally:
        os.unlink(csv_tmp.name)

    # 2. Fetch the agent's JSON report
    json_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    report = None
    try:
        copy_from_env("/home/ga/pebl/analysis/wpt_report.json", json_tmp.name)
        with open(json_tmp.name, 'r', encoding='utf-8') as f:
            report = json.load(f)
        score += 10
        feedback_parts.append("[+10] JSON output exists and is valid.")
    except Exception:
        feedback_parts.append("[0] JSON output missing or invalid.")
        return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}
    finally:
        os.unlink(json_tmp.name)

    # 3. Assess Contaminated Participant
    participants_list = report.get('participants', [])
    part_map = {str(p.get('id', p.get('participant_id', ''))): p for p in participants_list}

    if CONTAMINATED_ID in part_map and part_map[CONTAMINATED_ID].get('excluded') in [True, "true"]:
        score += 20
        feedback_parts.append(f"[+20] {CONTAMINATED_ID} correctly excluded.")
    elif CONTAMINATED_ID not in part_map:
        # Check if they put exclusions at the top level
        excluded_list = report.get('excluded', [])
        if isinstance(excluded_list, list) and CONTAMINATED_ID in excluded_list:
            score += 20
            feedback_parts.append(f"[+20] {CONTAMINATED_ID} correctly excluded.")
        else:
            feedback_parts.append(f"[0] {CONTAMINATED_ID} not explicitly excluded.")
    else:
        feedback_parts.append(f"[0] {CONTAMINATED_ID} not excluded.")

    # 4. Assess Individual Metrics (Valid Participants)
    correct_ppts = 0
    total_valid = 0
    for pid, gt_data in gt_participants.items():
        if pid == CONTAMINATED_ID:
            continue
        total_valid += 1
        agent_data = part_map.get(pid)
        if not agent_data or agent_data.get('excluded'):
            continue
            
        try:
            agent_rates = agent_data.get('block_optimal_rates', {})
            agent_score = float(agent_data.get('learning_score', 0))
            gt_score = gt_data['learning_score']
            
            blocks_correct = True
            for b in ["1", "2", "3", "4", "5"]:
                agent_val = float(agent_rates.get(b, 0))
                gt_val = gt_data['block_optimal_rates'][b]
                if abs(agent_val - gt_val) > TOLERANCE:
                    blocks_correct = False
                    break
                    
            if blocks_correct and abs(agent_score - gt_score) <= TOLERANCE:
                correct_ppts += 1
        except (ValueError, TypeError):
            pass

    if total_valid > 0 and (correct_ppts / total_valid) >= 0.9:
        score += 25
        feedback_parts.append(f"[+25] Individual metrics correct for {correct_ppts}/{total_valid} valid participants.")
    else:
        feedback_parts.append(f"[0] Individual metrics correct for only {correct_ppts}/{total_valid} valid participants.")

    # 5. Assess Group Metrics
    agent_group = report.get('group_learning_curve', {})
    if isinstance(agent_group, dict):
        group_correct = True
        for b in ["1", "2", "3", "4", "5"]:
            try:
                if abs(float(agent_group.get(b, 0)) - gt_group_means[b]) > TOLERANCE:
                    group_correct = False
            except (ValueError, TypeError):
                group_correct = False
                break
        
        if group_correct:
            score += 15
            feedback_parts.append("[+15] Group learning curve values are correct.")
        else:
            feedback_parts.append("[0] Group learning curve values incorrect.")
    else:
        feedback_parts.append("[0] group_learning_curve not found or not a dictionary.")

    # 6. Fetch Export Result to Check PNG existance
    export_result_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    png_exists = False
    try:
        copy_from_env("/tmp/task_result.json", export_result_tmp.name)
        with open(export_result_tmp.name, 'r') as f:
            res = json.load(f)
            if res.get('png_exists') and res.get('png_size_bytes', 0) > 1000:
                score += 10
                png_exists = True
                feedback_parts.append("[+10] Plot PNG file created and >1KB.")
            else:
                feedback_parts.append("[0] Plot PNG file missing or empty.")
    except Exception:
        feedback_parts.append("[0] Could not verify PNG existence from export data.")
    finally:
        os.unlink(export_result_tmp.name)

    # 7. VLM Verification of Trajectory and Visual Output
    if png_exists:
        try:
            # We sample trajectory frames
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            
            # Plus try to grab the actual PNG the agent made just to be sure it's seen
            agent_png_tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
            agent_png_data = None
            try:
                copy_from_env("/home/ga/pebl/analysis/wpt_learning_curve.png", agent_png_tmp.name)
                with open(agent_png_tmp.name, "rb") as image_file:
                    agent_png_data = base64.b64encode(image_file.read()).decode('utf-8')
            except Exception:
                pass
            finally:
                os.unlink(agent_png_tmp.name)

            all_images = frames
            if final_frame:
                all_images.append(final_frame)
            if agent_png_data:
                all_images.append(agent_png_data)

            query_vlm = env_info.get('query_vlm')
            if query_vlm:
                vlm_resp = query_vlm(prompt=VLM_PROMPT, images=all_images)
                if vlm_resp.get("success"):
                    vlm_parsed = vlm_resp.get("parsed", {})
                    if vlm_parsed.get("trajectory_work_observed") and vlm_parsed.get("valid_learning_curve"):
                        score += 20
                        feedback_parts.append("[+20] VLM confirmed trajectory coding work and valid plot.")
                    else:
                        feedback_parts.append(f"[0] VLM feedback: {vlm_parsed.get('reasoning', 'No valid plot or work observed')}")
                else:
                    feedback_parts.append("[0] VLM query failed.")
            else:
                feedback_parts.append("[0] VLM function not available.")
        except Exception as e:
            logger.warning(f"VLM verification exception: {e}")
            feedback_parts.append("[0] VLM verification error.")
            
    passed = (score >= 60) and png_exists and (correct_ppts > 0)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }