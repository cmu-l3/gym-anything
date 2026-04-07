#!/usr/bin/env python3
"""
Verifier for zone_employment_accessibility task.
Uses Ground Truth data comparison and Trajectory VLM verification.
"""

import json
import os
import sys
import re
import csv
import tempfile
import logging

try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
except ImportError:
    # Fallback if gym_anything isn't available in test env
    sample_trajectory_frames = lambda traj, n: []
    get_final_screenshot = lambda traj: None

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

VLM_PROMPT = """You are evaluating an agent performing a spatial data science task in Jupyter Lab.
The task involves computing employment accessibility for San Francisco zones and creating a scatter plot.

Look at these trajectory screenshots and assess:
1. Did the agent write and execute Python/Pandas code related to distance calculations or data merging?
2. Did the agent successfully generate a scatter plot showing colored zone centroids? (Check if a plot is visible in the notebook output).

Respond in JSON format exactly like this:
{
    "wrote_relevant_code": true/false,
    "plot_generated_and_visible": true/false,
    "reasoning": "brief explanation"
}
"""

def verify(traj, env_info, task_info):
    score = 0
    max_score = 100
    feedback = []
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    query_vlm = env_info.get('query_vlm')

    # --- Copy Ground Truth ---
    gt = None
    gt_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/ground_truth_accessibility.json', gt_temp.name)
        with open(gt_temp.name, 'r') as f:
            gt = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(gt_temp.name):
            os.unlink(gt_temp.name)

    if not gt or "error" in gt:
        return {"passed": False, "score": 0, "feedback": "Ground truth not found or failed during setup."}

    # --- Copy Export Results ---
    results = {}
    res_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env('/tmp/task_result.json', res_temp.name)
        with open(res_temp.name, 'r') as f:
            results = json.load(f)
    except Exception:
        pass
    finally:
        if os.path.exists(res_temp.name):
            os.unlink(res_temp.name)

    file_stats = results.get("files", {})

    # =========================================================
    # 1. CSV Validation (Structure and Data) [40 points]
    # =========================================================
    csv_local = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    csv_data = []
    has_csv = False
    
    if file_stats.get('csv', {}).get('exists'):
        try:
            copy_from_env('/home/ga/urbansim_projects/output/zone_accessibility.csv', csv_local.name)
            with open(csv_local.name, 'r') as f:
                reader = csv.DictReader(f)
                csv_data = list(reader)
                has_csv = True
        except Exception as e:
            feedback.append(f"Failed to read CSV: {e}")
    else:
        feedback.append("CSV output not found.")

    if os.path.exists(csv_local.name):
        os.unlink(csv_local.name)

    if has_csv and len(csv_data) > 0:
        required_cols = ['zone_id', 'total_jobs_in_zone', 'accessible_jobs_k10', 
                         'accessibility_score', 'accessibility_tier']
        actual_cols = list(csv_data[0].keys())
        has_cols = all(c in actual_cols for c in required_cols)

        if has_cols:
            score += 10
            feedback.append("CSV structure correct (10/10)")
            
            # Check numerical accuracy
            gt_zones = gt.get('zones', {})
            expected_zones_count = gt.get('total_zones', 0)
            
            # Check row count
            if abs(len(csv_data) - expected_zones_count) <= 5:
                score += 10
                feedback.append("CSV row count correct (10/10)")
            elif abs(len(csv_data) - expected_zones_count) <= 20:
                score += 5
                feedback.append("CSV row count partially correct (5/10)")
            
            # Check Accessibility Values & Tiers
            agent_lookup = {}
            for row in csv_data:
                try:
                    agent_lookup[str(int(float(row['zone_id'])))] = row
                except:
                    continue
            
            # Sample 10 zones to spot-check accuracy
            sample_ids = sorted(gt_zones.keys())[::max(1, len(gt_zones)//10)][:10]
            val_correct = 0
            tier_correct = 0
            
            for zid in sample_ids:
                gt_val = gt_zones[zid]['accessible_jobs_k10']
                gt_tier = gt_zones[zid]['accessibility_tier']
                agent_row = agent_lookup.get(str(zid))
                
                if agent_row:
                    try:
                        agent_val = float(agent_row['accessible_jobs_k10'])
                        agent_tier = agent_row['accessibility_tier'].strip()
                        
                        # Value tolerance check
                        if gt_val > 0:
                            if abs(agent_val - gt_val) / gt_val <= 0.05:
                                val_correct += 1
                        elif agent_val == 0:
                            val_correct += 1
                            
                        # Tier logic check
                        if agent_tier.lower() == gt_tier.lower():
                            tier_correct += 1
                    except:
                        pass
                        
            if val_correct >= 8:
                score += 15
                feedback.append(f"Accessibility values accurate {val_correct}/10 (15/15)")
            elif val_correct >= 5:
                score += 7
                feedback.append(f"Accessibility values partially accurate {val_correct}/10 (7/15)")
                
            if tier_correct >= 8:
                score += 5
                feedback.append(f"Tiers accurate {tier_correct}/10 (5/5)")
                
        else:
            feedback.append(f"CSV missing required columns. Found: {actual_cols}")

    # =========================================================
    # 2. Text Summary Check [15 points]
    # =========================================================
    txt_local = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    if file_stats.get('txt', {}).get('exists'):
        try:
            copy_from_env('/home/ga/urbansim_projects/output/accessibility_summary.txt', txt_local.name)
            with open(txt_local.name, 'r') as f:
                txt_content = f.read().lower()
                
            txt_score = 0
            # Zone count
            if str(gt.get('total_zones', -1)) in txt_content:
                txt_score += 5
            # Mean score check (roughly)
            mean_sc = gt.get('mean_score', -1)
            if str(int(mean_sc)) in txt_content or f"{mean_sc:.1f}" in txt_content or f"{mean_sc:.2f}" in txt_content:
                txt_score += 5
            # Bottom 5 check
            bottom_found = sum(1 for zid in gt.get('bottom_5_zones', []) if str(zid) in txt_content)
            if bottom_found >= 3:
                txt_score += 5
                
            score += txt_score
            feedback.append(f"Summary text check scored ({txt_score}/15)")
            
        except Exception as e:
            feedback.append(f"Failed to process summary text: {e}")
    else:
        feedback.append("Summary text file not found.")

    if os.path.exists(txt_local.name):
        os.unlink(txt_local.name)

    # =========================================================
    # 3. Notebook execution evidence [20 points]
    # =========================================================
    nb_local = tempfile.NamedTemporaryFile(delete=False, suffix='.ipynb')
    if file_stats.get('notebook', {}).get('exists'):
        try:
            copy_from_env('/home/ga/urbansim_projects/notebooks/employment_accessibility.ipynb', nb_local.name)
            with open(nb_local.name, 'r') as f:
                nb = json.load(f)
                
            code_cells = [c for c in nb.get('cells', []) if c.get('cell_type') == 'code']
            exec_cells = [c for c in code_cells if c.get('execution_count') is not None]
            
            source_combined = " ".join(["".join(c.get('source', [])) for c in code_cells]).lower()
            
            nb_score = 0
            if len(exec_cells) >= 3:
                nb_score += 10
            if 'merge' in source_combined or 'join' in source_combined:
                nb_score += 5
            if 'to_csv' in source_combined:
                nb_score += 5
                
            score += nb_score
            feedback.append(f"Notebook execution code check scored ({nb_score}/20)")
            
        except Exception as e:
            feedback.append(f"Failed to check notebook: {e}")
            
    if os.path.exists(nb_local.name):
        os.unlink(nb_local.name)

    # =========================================================
    # 4. VLM Trajectory Verification (Plot & UI) [25 points]
    # =========================================================
    vlm_score = 0
    if query_vlm:
        try:
            frames = sample_trajectory_frames(traj, n=4)
            final_frame = get_final_screenshot(traj)
            if final_frame:
                frames.append(final_frame)
                
            if frames:
                vlm_res = query_vlm(prompt=VLM_PROMPT, images=frames)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('wrote_relevant_code'):
                        vlm_score += 10
                    if parsed.get('plot_generated_and_visible'):
                        vlm_score += 15
                    feedback.append(f"VLM verified trajectory: {parsed.get('reasoning', 'OK')} ({vlm_score}/25)")
                else:
                    feedback.append(f"VLM query failed: {vlm_res.get('error')}")
                    # Fallback file check if VLM fails
                    if file_stats.get('png', {}).get('size', 0) > 10000:
                        vlm_score += 15
                        feedback.append("Fallback: PNG file exists and is reasonably sized.")
            else:
                feedback.append("No trajectory frames available for VLM.")
        except Exception as e:
            feedback.append(f"VLM exception: {e}")
            # Fallback file check
            if file_stats.get('png', {}).get('size', 0) > 10000:
                vlm_score += 15
    else:
        # Fallback file check if VLM isn't available
        if file_stats.get('png', {}).get('size', 0) > 10000:
            vlm_score += 25
            feedback.append("VLM not available, awarded plot points based on file size.")
            
    score += vlm_score

    # Limit and thresholds
    final_score = min(100, score)
    key_criteria_met = file_stats.get('csv', {}).get('created_during_task', False) and has_csv
    passed = final_score >= 60 and key_criteria_met

    if not key_criteria_met:
        feedback.append("CRITICAL: CSV output was not newly generated during the task.")

    return {
        "passed": passed,
        "score": final_score,
        "feedback": " | ".join(feedback)
    }