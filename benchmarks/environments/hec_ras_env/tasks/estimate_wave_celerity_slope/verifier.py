#!/usr/bin/env python3
"""
Verifier for estimate_wave_celerity_slope task.

Verifies:
1. Existence of output CSV and Text Report.
2. Correctness of calculated Celerity and Velocity values (compared to ground truth).
3. Data extraction quality (checking if CSV contains rising limb data).
"""

import json
import os
import tempfile
import logging
import csv
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_estimate_wave_celerity_slope(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Tolerances
    metadata = task_info.get('metadata', {})
    tol_celerity = metadata.get('tolerances', {}).get('celerity_percent', 10) / 100.0
    tol_velocity = metadata.get('tolerances', {}).get('velocity_percent', 5) / 100.0

    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON and Ground Truth
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_csv = tempfile.NamedTemporaryFile(delete=False, suffix='.csv')
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    
    try:
        # Load main result metadata
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result_meta = json.load(f)
            
        # Load ground truth (generated inside container)
        try:
            copy_from_env(result_meta.get("ground_truth_path", "/tmp/ground_truth.json"), temp_gt.name)
            with open(temp_gt.name, 'r') as f:
                ground_truth = json.load(f)
        except Exception:
            ground_truth = {"ground_truth_calculated": False, "error": "Could not retrieve ground truth"}

        # 2. Verify File Existence (10 pts)
        if result_meta.get('csv_exists') and result_meta.get('report_exists'):
            score += 10
            feedback_parts.append("Output files exist.")
        else:
            feedback_parts.append("Missing output files.")
            return {"passed": False, "score": 0, "feedback": " | ".join(feedback_parts)}

        # 3. Retrieve User Files
        try:
            copy_from_env(result_meta['csv_path'], temp_csv.name)
            copy_from_env(result_meta['report_path'], temp_report.name)
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to copy user outputs: {e}"}

        # 4. Analyze User Report (Celerity/Velocity) - (50 pts total)
        user_celerity = None
        user_velocity = None
        user_ratio = None
        
        with open(temp_report.name, 'r') as f:
            content = f.read()
            # Extract values using regex
            # Looking for patterns like "Wave Celerity (ft/s): 4.5"
            cel_match = re.search(r"Celerity.*?:\s*([0-9.]+)", content, re.IGNORECASE)
            vel_match = re.search(r"Velocity.*?:\s*([0-9.]+)", content, re.IGNORECASE)
            rat_match = re.search(r"Ratio.*?:\s*([0-9.]+)", content, re.IGNORECASE)
            
            if cel_match: user_celerity = float(cel_match.group(1))
            if vel_match: user_velocity = float(vel_match.group(1))
            if rat_match: user_ratio = float(rat_match.group(1))

        if ground_truth.get("ground_truth_calculated"):
            gt_cel = ground_truth['celerity']
            gt_vel = ground_truth['mean_velocity']
            
            # Check Celerity (30 pts)
            if user_celerity is not None:
                error = abs(user_celerity - gt_cel) / gt_cel
                if error <= tol_celerity:
                    score += 30
                    feedback_parts.append(f"Celerity accurate (Error: {error:.1%}).")
                elif error <= tol_celerity * 2:
                    score += 15
                    feedback_parts.append(f"Celerity somewhat accurate (Error: {error:.1%}).")
                else:
                    feedback_parts.append(f"Celerity inaccurate (Expected ~{gt_cel:.2f}, Got {user_celerity:.2f}).")
            else:
                feedback_parts.append("Could not parse Celerity from report.")

            # Check Velocity (20 pts)
            if user_velocity is not None:
                error = abs(user_velocity - gt_vel) / gt_vel
                if error <= tol_velocity:
                    score += 20
                    feedback_parts.append(f"Velocity accurate (Error: {error:.1%}).")
                else:
                    feedback_parts.append(f"Velocity inaccurate (Expected ~{gt_vel:.2f}, Got {user_velocity:.2f}).")
            else:
                feedback_parts.append("Could not parse Velocity from report.")
        else:
            feedback_parts.append("Ground truth calculation failed - manual verification required for values.")
            # Fallback points if values look physically reasonable
            if user_celerity and 2 < user_celerity < 20: score += 15
            if user_velocity and 1 < user_velocity < 15: score += 10

        # 5. Analyze CSV (Rising Limb Isolation) - (30 pts)
        try:
            with open(temp_csv.name, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
            if len(rows) > 5:
                # Check monotonicity of Flow to verify rising limb roughly
                # Or just check start/end flow values
                try:
                    flows = [float(r['Flow_cfs']) for r in rows if 'Flow_cfs' in r]
                    if flows:
                        start_flow = flows[0]
                        end_flow = flows[-1]
                        peak_flow = max(flows)
                        
                        # Rising limb check: End flow should be near peak, start flow should be low
                        is_rising = end_flow >= peak_flow * 0.95 and start_flow < peak_flow * 0.5
                        
                        if is_rising:
                            score += 30
                            feedback_parts.append("CSV data correctly corresponds to rising limb.")
                        else:
                            score += 10
                            feedback_parts.append("CSV data exists but doesn't strictly look like rising limb (Start/End flow mismatch).")
                except ValueError:
                    feedback_parts.append("CSV contains non-numeric flow data.")
            else:
                feedback_parts.append("CSV has too few rows.")
                
        except Exception:
            feedback_parts.append("CSV format invalid.")

        # 6. Check Ratio Consistency (10 pts)
        if user_celerity and user_velocity and user_ratio:
            calc_ratio = user_celerity / user_velocity
            if abs(calc_ratio - user_ratio) < 0.1:
                score += 10
                feedback_parts.append("Ratio calculation is consistent.")
            else:
                feedback_parts.append("Ratio calculation inconsistent with reported C/V.")

    finally:
        # Cleanup
        for fname in [temp_result.name, temp_gt.name, temp_csv.name, temp_report.name]:
            if os.path.exists(fname):
                os.unlink(fname)

    passed = score >= 60
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }