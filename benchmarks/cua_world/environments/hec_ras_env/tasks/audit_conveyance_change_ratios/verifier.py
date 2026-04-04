#!/usr/bin/env python3
"""
Verifier for audit_conveyance_change_ratios task.
Compares agent's CSV output against a ground truth CSV generated inside the container.
"""

import json
import os
import tempfile
import logging
import pandas as pd
import numpy as np

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit_conveyance(traj, env_info, task_info):
    """
    Verify the conveyance audit report.
    
    Criteria:
    1. Output file exists and was created during task (20 pts)
    2. CSV Structure (Columns) is correct (10 pts)
    3. Correct number of rows (reaches) (10 pts)
    4. Conveyance (K) values match ground truth (30 pts)
    5. Flags ('Warning'/'OK') match ground truth (30 pts)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Setup temp files
    results_json_path = tempfile.mktemp(suffix='.json')
    agent_csv_path = tempfile.mktemp(suffix='.csv')
    ground_truth_csv_path = tempfile.mktemp(suffix='.csv')
    
    try:
        # 1. Fetch JSON result
        try:
            copy_from_env("/tmp/task_result.json", results_json_path)
            with open(results_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}

        score = 0
        feedback = []
        
        # Check existence
        if not result_data.get("output_exists", False):
            return {"passed": False, "score": 0, "feedback": "Output CSV file not found."}
            
        if not result_data.get("file_created_during_task", False):
            feedback.append("Warning: Output file timestamp is old (pre-task).")
            # We penalize but continue if content is good, though strictly it should be new.
            score += 5
        else:
            score += 20
            feedback.append("Output file created successfully.")
            
        # 2. Fetch CSVs
        try:
            copy_from_env("/tmp/ground_truth.csv", ground_truth_csv_path)
            copy_from_env("/tmp/agent_output.csv", agent_csv_path)
            
            df_gt = pd.read_csv(ground_truth_csv_path)
            df_agent = pd.read_csv(agent_csv_path)
        except Exception as e:
            return {
                "passed": False, 
                "score": score, 
                "feedback": f"Failed to read CSV files for comparison: {e}"
            }
            
        # 3. Check Structure
        required_cols = ['Upstream_River_Station', 'Downstream_River_Station', 'K_Upstream', 'K_Downstream', 'Ratio', 'Status']
        # Normalize columns (case insensitive, strip spaces)
        df_agent.columns = [c.strip() for c in df_agent.columns]
        
        missing_cols = [c for c in required_cols if c not in df_agent.columns]
        if missing_cols:
            feedback.append(f"Missing columns: {missing_cols}")
        else:
            score += 10
            feedback.append("CSV structure correct.")
            
        # 4. Check Row Count
        # Allow slight difference if they skipped 0s entirely, but ideally should match
        if len(df_agent) == len(df_gt):
            score += 10
        elif abs(len(df_agent) - len(df_gt)) < 5:
            score += 5
            feedback.append(f"Row count mismatch (Agent: {len(df_agent)}, GT: {len(df_gt)}).")
        else:
            feedback.append(f"Significant row count mismatch (Agent: {len(df_agent)}, GT: {len(df_gt)}).")
            
        # 5. Check Values (Conveyance K)
        # Merge on Upstream River Station to compare
        # Ensure RS is string for merging
        df_gt['Upstream_River_Station'] = df_gt['Upstream_River_Station'].astype(str)
        df_agent['Upstream_River_Station'] = df_agent['Upstream_River_Station'].astype(str)
        
        merged = pd.merge(df_gt, df_agent, on='Upstream_River_Station', suffixes=('_gt', '_ag'), how='inner')
        
        if len(merged) == 0:
            feedback.append("Could not match any rows based on River Station.")
        else:
            # Check K_Upstream values (within 5% tolerance)
            # Handle string/numeric conversion issues
            try:
                k_gt = pd.to_numeric(merged['K_Upstream_gt'], errors='coerce').fillna(0)
                k_ag = pd.to_numeric(merged['K_Upstream_ag'], errors='coerce').fillna(0)
                
                # Avoid division by zero in percent difference
                mask = k_gt > 1e-6
                diff_pct = np.abs((k_ag[mask] - k_gt[mask]) / k_gt[mask])
                
                # Passing if 90% of rows are within 5% error
                passing_rows = np.sum(diff_pct < 0.05)
                total_rows = len(k_gt)
                
                if total_rows > 0:
                    accuracy = passing_rows / total_rows
                    pts_k = int(30 * accuracy)
                    score += pts_k
                    feedback.append(f"Conveyance calculation accuracy: {accuracy:.1%} ({pts_k}/30 pts)")
            except Exception as e:
                feedback.append(f"Error comparing K values: {e}")

            # 6. Check Flags (Status)
            try:
                # Compare Status columns (Warning/OK)
                # Normalize text
                status_gt = merged['Status_gt'].str.lower().str.strip()
                status_ag = merged['Status_ag'].str.lower().str.strip()
                
                # Check match
                status_match = (status_gt == status_ag)
                status_accuracy = status_match.mean()
                
                pts_status = int(30 * status_accuracy)
                score += pts_status
                feedback.append(f"Flagging status accuracy: {status_accuracy:.1%} ({pts_status}/30 pts)")
            except Exception as e:
                feedback.append(f"Error comparing Status flags: {e}")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification system error: {e}"}
    finally:
        # Cleanup
        for p in [results_json_path, agent_csv_path, ground_truth_csv_path]:
            if os.path.exists(p):
                try:
                    os.unlink(p)
                except:
                    pass