#!/usr/bin/env python3
"""
Verifier for ops_log_trajectory_reconstruction@1

Agent must construct a GMAT trajectory from an operations log containing
3 impulsive burns and output the final Keplerian orbital state.

Scoring (total 100 pts, pass >= 60):
  - script_created (5): Script created during task window
  - report_written (10): Final report file written during task window
  - structural_checks (15): Script contains 3 ImpulsiveBurns and multiple Propagate commands
  - sma_accurate (30): Final SMA matches ground truth within tolerance (most sensitive)
  - ecc_accurate (15): Final ECC matches ground truth within tolerance
  - inc_accurate (15): Final INC matches ground truth within tolerance
  - raan_accurate (10): Final RAAN matches ground truth within tolerance

Pass condition: score >= 60 AND report_written AND sma_accurate
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_ops_log_trajectory_reconstruction(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    
    scores = {
        "script_created": 5,
        "report_written": 10,
        "structural_checks": 15,
        "sma_accurate": 30,
        "ecc_accurate": 15,
        "inc_accurate": 15,
        "raan_accurate": 10
    }

    total_score = 0
    feedback = []
    report_ok = False
    sma_ok = False

    # 1. Load task result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # 2. Check Script Creation
    script_file = task_result.get('script_file', {})
    if isinstance(script_file, dict) and script_file.get('created_during_task'):
        total_score += scores["script_created"]
        feedback.append("Script file created during task window.")
    else:
        feedback.append("Script file not found or not created during task window.")

    # 3. Check Script Structure
    burn_count = task_result.get('burn_count', 0)
    propagate_count = task_result.get('propagate_count', 0)
    
    if burn_count >= 3 and propagate_count >= 3:
        total_score += scores["structural_checks"]
        feedback.append(f"Script structure correct: {burn_count} burns, {propagate_count} propagate commands.")
    elif burn_count > 0:
        total_score += scores["structural_checks"] // 2
        feedback.append(f"Partial script structure: {burn_count} burns found (expected 3).")
    else:
        feedback.append("Missing required maneuver definitions in script.")

    # 4. Check Report File
    report_file = task_result.get('report_file', {})
    report_path = task_result.get('report_path', '/home/ga/GMAT_output/reconstructed_state.txt')
    agent_sma, agent_ecc, agent_inc, agent_raan = None, None, None, None
    
    if isinstance(report_file, dict) and report_file.get('exists'):
        total_score += scores["report_written"]
        report_ok = True
        
        # Load Report Content
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(report_path, temp_report.name)
            with open(temp_report.name, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read().strip()
                
            # Parse the last line with enough numbers
            lines = content.split('\n')
            for line in reversed(lines):
                # Match integers and floats (including scientific notation)
                nums = re.findall(r'[-+]?\d*\.\d+(?:[eE][-+]?\d+)?|[-+]?\d+', line)
                if len(nums) >= 4:
                    agent_sma = float(nums[0])
                    agent_ecc = float(nums[1])
                    agent_inc = float(nums[2])
                    agent_raan = float(nums[3])
                    break
                    
            if agent_sma is not None:
                feedback.append(f"Parsed agent state: SMA={agent_sma:.2f}, ECC={agent_ecc:.4f}, INC={agent_inc:.2f}, RAAN={agent_raan:.2f}")
            else:
                feedback.append("Failed to parse Keplerian state from report file.")
                
        except Exception as e:
            feedback.append(f"Error parsing agent report: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback.append("Report file not created.")

    # 5. Load Ground Truth State
    gt_sma, gt_ecc, gt_inc, gt_raan = None, None, None, None
    temp_gt = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/gt_state.json", temp_gt.name)
        with open(temp_gt.name, 'r') as f:
            gt_data = json.load(f)
            if gt_data.get('success'):
                gt_sma = float(gt_data['sma'])
                gt_ecc = float(gt_data['ecc'])
                gt_inc = float(gt_data['inc'])
                gt_raan = float(gt_data['raan'])
                feedback.append("Using dynamically generated Ground Truth.")
    except Exception:
        pass
    finally:
        if os.path.exists(temp_gt.name):
            os.unlink(temp_gt.name)

    # Use fallbacks if GT generation failed
    if gt_sma is None:
        gt_sma = metadata.get('fallback_sma_km', 7360.5)
        gt_ecc = metadata.get('fallback_ecc', 0.003)
        gt_inc = metadata.get('fallback_inc_deg', 52.03)
        gt_raan = metadata.get('fallback_raan_deg', 48.0)
        feedback.append("Using fallback Ground Truth values.")

    # 6. Compare & Score
    tol_sma = metadata.get('sma_tolerance_km', 20.0)
    tol_ecc = metadata.get('ecc_tolerance', 0.005)
    tol_inc = metadata.get('inc_tolerance_deg', 0.5)
    tol_raan = metadata.get('raan_tolerance_deg', 3.0)

    if agent_sma is not None:
        # Check SMA
        if abs(agent_sma - gt_sma) <= tol_sma:
            total_score += scores["sma_accurate"]
            sma_ok = True
            feedback.append(f"SMA accurate (diff: {abs(agent_sma - gt_sma):.2f} km).")
        else:
            feedback.append(f"SMA inaccurate: got {agent_sma:.2f}, expected ~{gt_sma:.2f} km.")

        # Check ECC
        if abs(agent_ecc - gt_ecc) <= tol_ecc:
            total_score += scores["ecc_accurate"]
            feedback.append(f"ECC accurate (diff: {abs(agent_ecc - gt_ecc):.4f}).")
        else:
            feedback.append(f"ECC inaccurate: got {agent_ecc:.4f}, expected ~{gt_ecc:.4f}.")

        # Check INC
        if abs(agent_inc - gt_inc) <= tol_inc:
            total_score += scores["inc_accurate"]
            feedback.append(f"INC accurate (diff: {abs(agent_inc - gt_inc):.2f} deg).")
        else:
            feedback.append(f"INC inaccurate: got {agent_inc:.2f}, expected ~{gt_inc:.2f} deg.")

        # Check RAAN (wrap around 360 logic)
        raan_diff = abs(agent_raan - gt_raan) % 360
        raan_diff = min(raan_diff, 360 - raan_diff)
        if raan_diff <= tol_raan:
            total_score += scores["raan_accurate"]
            feedback.append(f"RAAN accurate (diff: {raan_diff:.2f} deg).")
        else:
            feedback.append(f"RAAN inaccurate: got {agent_raan:.2f}, expected ~{gt_raan:.2f} deg.")

    passed = (total_score >= 60) and report_ok and sma_ok

    return {
        "passed": passed,
        "score": total_score,
        "feedback": " | ".join(feedback)
    }