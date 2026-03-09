#!/usr/bin/env python3
"""
Verifier for estimate_bankfull_capacity task.
Compares agent's CSV output against a ground truth generated from the actual HDF5 file.
"""

import json
import tempfile
import os
import csv
import logging
import math

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_estimate_bankfull_capacity(traj, env_info, task_info):
    """
    Verifies that the agent correctly calculated bankfull discharge.
    
    Criteria:
    1. Output CSV exists and has correct columns.
    2. Bank elevations match ground truth (proves geometry extraction).
    3. Bankfull Q matches ground truth (proves event detection + interpolation).
    4. Script was created (anti-gaming).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Metadata tolerances
    metadata = task_info.get('metadata', {})
    tol_elev = metadata.get('tolerances', {}).get('elevation_ft', 0.15)
    tol_flow_pct = metadata.get('tolerances', {}).get('flow_percent', 5.0)

    # 1. Fetch files from environment
    # We need: task_result.json, ground_truth.json, and the agent's CSV
    
    files_to_fetch = {
        "result_meta": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth.json",
        "agent_csv": "/home/ga/Documents/hec_ras_results/bankfull_capacity.csv"
    }
    
    local_files = {}
    
    for key, remote_path in files_to_fetch.items():
        temp_file = tempfile.NamedTemporaryFile(delete=False, suffix=f'_{key}')
        local_files[key] = temp_file.name
        temp_file.close()
        try:
            copy_from_env(remote_path, local_files[key])
        except Exception:
            # It's okay if agent_csv fails (file missing), handled later
            pass

    score = 0
    feedback_parts = []
    
    try:
        # Load Metadata
        try:
            with open(local_files["result_meta"], 'r') as f:
                meta = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "Failed to load task metadata"}
            
        output_exists = meta.get("output_exists", False)
        script_created = meta.get("script_count", 0) > 0
        
        # Criterion 1: Output Exists (10 pts)
        if output_exists:
            score += 10
            feedback_parts.append("Output CSV exists")
        else:
            return {"passed": False, "score": 0, "feedback": "Output CSV not found"}
            
        # Criterion 2: Process Verification (Script Exists) (10 pts)
        if script_created:
            score += 10
            feedback_parts.append("Analysis script detected")
        else:
            feedback_parts.append("WARNING: No analysis script found (manual entry?)")

        # Load Ground Truth
        try:
            with open(local_files["ground_truth"], 'r') as f:
                ground_truth = json.load(f)
                # Handle error case in GT generation
                if isinstance(ground_truth, dict) and "error" in ground_truth:
                    return {"passed": False, "score": 0, "feedback": f"Ground truth generation failed: {ground_truth['error']}"}
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": "Failed to load ground truth data"}
            
        # Load Agent CSV
        agent_data = {}
        try:
            with open(local_files["agent_csv"], 'r') as f:
                reader = csv.DictReader(f)
                # Normalize headers (strip spaces)
                reader.fieldnames = [name.strip() for name in reader.fieldnames]
                
                required_cols = ["RiverStation", "Min_Bank_Elev_ft", "Bankfull_Q_cfs"]
                missing = [c for c in required_cols if c not in reader.fieldnames]
                if missing:
                    return {"passed": False, "score": score, "feedback": f"CSV missing columns: {missing}"}
                
                for row in reader:
                    rs = row["RiverStation"].strip()
                    agent_data[rs] = row
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Failed to parse CSV: {e}"}

        # Compare Data
        total_xs = len(ground_truth)
        valid_elev_count = 0
        valid_flow_count = 0
        
        if total_xs == 0:
             return {"passed": False, "score": 0, "feedback": "Ground truth empty (model error?)"}

        for gt_row in ground_truth:
            rs = gt_row["RiverStation"]
            
            if rs not in agent_data:
                continue
                
            agent_row = agent_data[rs]
            
            try:
                # Check Elevation (Geometry)
                gt_elev = gt_row["Min_Bank_Elev_ft"]
                ag_elev = float(agent_row["Min_Bank_Elev_ft"])
                
                if abs(gt_elev - ag_elev) <= tol_elev:
                    valid_elev_count += 1
                
                # Check Flow (Results/Interpolation)
                gt_flow = gt_row["Bankfull_Q_cfs"]
                ag_flow = float(agent_row["Bankfull_Q_cfs"])
                
                # Handle 0 flow case
                if gt_flow == 0:
                    if ag_flow == 0:
                        valid_flow_count += 1
                else:
                    pct_diff = abs(gt_flow - ag_flow) / gt_flow * 100
                    if pct_diff <= tol_flow_pct:
                        valid_flow_count += 1
                        
            except ValueError:
                continue

        # Criterion 3: Geometry Accuracy (40 pts)
        elev_accuracy = valid_elev_count / total_xs
        elev_score = int(elev_accuracy * 40)
        score += elev_score
        
        # Criterion 4: Flow Accuracy (40 pts)
        flow_accuracy = valid_flow_count / total_xs
        flow_score = int(flow_accuracy * 40)
        score += flow_score
        
        feedback_parts.append(f"Elevation Accuracy: {elev_accuracy:.1%}")
        feedback_parts.append(f"Flow Accuracy: {flow_accuracy:.1%}")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        # Cleanup
        for path in local_files.values():
            if os.path.exists(path):
                os.unlink(path)

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }