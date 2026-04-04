#!/usr/bin/env python3
"""
Verifier for audit_reach_length_consistency task.

Verifies:
1. Python script exists (20 pts)
2. CSV output exists and matches Ground Truth (65 pts)
   - Correct columns (15 pts)
   - Correct values (Stored, Implied, Discrepancy, Status) (50 pts)
3. Summary text file exists (15 pts)
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_reach_length_consistency(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # 1. Fetch Task Metadata
    result_json_path = "/tmp/task_result.json"
    agent_csv_path = "/tmp/agent_audit.csv"
    gt_csv_path = "/tmp/ground_truth.csv"
    
    # 2. Load Result JSON
    with tempfile.NamedTemporaryFile(suffix=".json") as f:
        try:
            copy_from_env(result_json_path, f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

    script_exists = result_data.get("script_exists", False)
    csv_exists = result_data.get("csv_exists", False)
    summary_exists = result_data.get("summary_exists", False)
    created_during = result_data.get("file_created_during_task", False)

    # CRITERION 1: Script Exists (20 pts)
    if script_exists:
        score += 20
        feedback_parts.append("Script found (+20)")
    else:
        feedback_parts.append("Script missing")

    # CRITERION 2: CSV Analysis (65 pts)
    if csv_exists and created_during:
        try:
            # Download Agent CSV
            with tempfile.NamedTemporaryFile(mode='w+', suffix=".csv", delete=False) as f_agent, \
                 tempfile.NamedTemporaryFile(mode='w+', suffix=".csv", delete=False) as f_gt:
                
                agent_local = f_agent.name
                gt_local = f_gt.name
                
                # Copy files
                copy_from_env(agent_csv_path, agent_local)
                has_gt = False
                try:
                    copy_from_env(gt_csv_path, gt_local)
                    has_gt = True
                except:
                    feedback_parts.append("Ground Truth generation failed in env")

                if has_gt:
                    # Compare
                    with open(agent_local, 'r') as fa, open(gt_local, 'r') as fg:
                        reader_a = list(csv.DictReader(fa))
                        reader_g = list(csv.DictReader(fg))

                    # Check Columns (15 pts)
                    required_cols = {'River', 'Reach', 'River_Station', 'Stored_Length', 'Implied_Length', 'Discrepancy', 'Status'}
                    agent_cols = set(reader_a[0].keys()) if reader_a else set()
                    
                    if required_cols.issubset(agent_cols):
                        score += 15
                        feedback_parts.append("CSV columns correct (+15)")
                        
                        # Check Data Accuracy (50 pts)
                        # We match rows by River_Station
                        gt_map = {row['River_Station']: row for row in reader_g}
                        
                        match_count = 0
                        total_rows = len(gt_map)
                        correct_status_count = 0
                        
                        for row_a in reader_a:
                            rs = row_a.get('River_Station')
                            if rs in gt_map:
                                row_g = gt_map[rs]
                                match_count += 1
                                
                                # Compare numeric values with tolerance
                                try:
                                    # Implied Length
                                    impl_a = float(row_a.get('Implied_Length', -999))
                                    impl_g = float(row_g.get('Implied_Length', -999))
                                    
                                    # Discrepancy
                                    disc_a = float(row_a.get('Discrepancy', -999))
                                    disc_g = float(row_g.get('Discrepancy', -999))
                                    
                                    # Status
                                    stat_a = row_a.get('Status', '').strip().upper()
                                    stat_g = row_g.get('Status', '').strip().upper()
                                    
                                    if abs(impl_a - impl_g) < 0.1 and abs(disc_a - disc_g) < 0.1:
                                        if stat_a == stat_g:
                                            correct_status_count += 1
                                except ValueError:
                                    pass

                        # Scoring logic for accuracy
                        if match_count > 0:
                            accuracy = correct_status_count / total_rows
                            pts = int(50 * accuracy)
                            score += pts
                            feedback_parts.append(f"Data accuracy: {int(accuracy*100)}% (+{pts})")
                        else:
                            feedback_parts.append("No matching River Stations found")
                            
                    else:
                        feedback_parts.append(f"Missing columns: {required_cols - agent_cols}")
                        
                else:
                    feedback_parts.append("Could not verify data accuracy (GT missing)")
        except Exception as e:
            feedback_parts.append(f"Error analyzing CSV: {e}")
            
    elif csv_exists and not created_during:
        feedback_parts.append("CSV exists but was not created during task (Anti-gaming)")
    else:
        feedback_parts.append("CSV output missing")

    # CRITERION 3: Summary File (15 pts)
    if summary_exists:
        score += 15
        feedback_parts.append("Summary file exists (+15)")
    else:
        feedback_parts.append("Summary file missing")

    # Pass Threshold
    passed = score >= 60

    # Cleanup
    if 'agent_local' in locals() and os.path.exists(agent_local): os.unlink(agent_local)
    if 'gt_local' in locals() and os.path.exists(gt_local): os.unlink(gt_local)

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }