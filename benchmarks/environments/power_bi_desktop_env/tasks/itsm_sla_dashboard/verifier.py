#!/usr/bin/env python3
"""
Verifier for itsm_sla_dashboard task.

Verification Logic:
1. Re-calculate Ground Truth from the source `helpdesk_tickets.csv`.
   - Compute resolution hours.
   - Apply variable SLA logic (Critical>4, High>8, etc.).
   - Aggregate 'Breached' counts by Agent and Priority.
2. Compare with `matrix_export.csv` (the file exported by the agent).
   - The agent's matrix export should match the ground truth aggregation.
3. Check PBIX structure (visuals present).

Scoring:
- 10 pts: PBIX Saved
- 15 pts: Visuals present (Card, Bar, Matrix)
- 25 pts: CSV Export exists and is readable
- 50 pts: Data Accuracy (Matches ground truth logic)
"""

import json
import os
import tempfile
import pandas as pd
import numpy as np
import logging

logger = logging.getLogger(__name__)

def verify_itsm_sla_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    # Define paths
    remote_result = "C:/Users/Docker/Desktop/task_result.json"
    remote_csv_export = "C:/Users/Docker/Desktop/matrix_export.csv"
    remote_source_data = "C:/Users/Docker/Desktop/PowerBITasks/helpdesk_tickets.csv"

    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        local_result = os.path.join(temp_dir, "task_result.json")
        local_csv_export = os.path.join(temp_dir, "matrix_export.csv")
        local_source_data = os.path.join(temp_dir, "helpdesk_tickets.csv")

        # Copy files
        try:
            copy_from_env(remote_result, local_result)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Result JSON not found (Script execution failed?)"}

        try:
            copy_from_env(remote_source_data, local_source_data)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Source data not found on VM"}

        # Attempt to copy export (it might not exist if agent failed)
        export_exists = False
        try:
            copy_from_env(remote_csv_export, local_csv_export)
            export_exists = True
        except Exception:
            pass

        # Load Result JSON
        try:
            with open(local_result, 'r') as f:
                result_data = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Invalid Result JSON"}

        score = 0
        feedback = []

        # 1. PBIX Existence (10 pts)
        if result_data.get('pbix_exists'):
            score += 10
            feedback.append("Report file saved.")
        else:
            feedback.append("Report file NOT saved.")

        # 2. Visual Types (15 pts)
        visuals = result_data.get('visuals_found', [])
        required = {'card', 'barChart', 'matrix'}
        found = set(visuals)
        if required.issubset(found):
            score += 15
            feedback.append("All required visual types found.")
        elif found:
            score += 5
            feedback.append(f"Some visuals found: {found}")
        else:
            feedback.append("No required visuals found in layout.")

        # 3. CSV Export Existence (15 pts)
        if export_exists:
            score += 15
            feedback.append("Matrix data exported.")
        else:
            feedback.append("Matrix data export NOT found.")

        # 4. Data Accuracy / Ground Truth Check (60 pts)
        if export_exists and os.path.getsize(local_csv_export) > 0:
            try:
                # --- Calculate Ground Truth ---
                df_source = pd.read_csv(local_source_data)
                
                # Parse dates
                df_source['Created'] = pd.to_datetime(df_source['Created_Timestamp'])
                df_source['Resolved'] = pd.to_datetime(df_source['Resolved_Timestamp'])
                
                # Calculate Duration (Hours)
                df_source['Duration'] = (df_source['Resolved'] - df_source['Created']).dt.total_seconds() / 3600.0
                
                # Apply SLA Logic
                def check_sla(row):
                    prio = row['Priority']
                    dur = row['Duration']
                    limit = 24
                    if prio == 'Critical': limit = 4
                    elif prio == 'High': limit = 8
                    elif prio == 'Medium': limit = 24
                    elif prio == 'Low': limit = 48
                    
                    return 1 if dur > limit else 0 # 1 = Breached

                df_source['Is_Breached'] = df_source.apply(check_sla, axis=1)
                
                # Aggregate: Count of Breaches by Agent
                # We group by Agent_Name and sum Is_Breached
                ground_truth = df_source.groupby('Agent_Name')['Is_Breached'].sum().reset_index()
                ground_truth = ground_truth.sort_values('Agent_Name')
                
                # --- Process Agent Export ---
                # Power BI export usually has Agent Name and count/values
                # It might have weird headers or encoding
                try:
                    df_agent = pd.read_csv(local_csv_export, encoding='utf-8-sig')
                except:
                    df_agent = pd.read_csv(local_csv_export, encoding='utf-16') # PBI sometimes exports utf-16
                
                # Normalize column names
                # Expecting 'Agent_Name' and some value column
                # Identify the value column (should be numeric)
                num_cols = df_agent.select_dtypes(include=[np.number]).columns
                if len(num_cols) == 0:
                    raise ValueError("No numeric columns in export")
                
                val_col = num_cols[0]
                agent_col = [c for c in df_agent.columns if c != val_col][0]
                
                # Group agent export just in case
                agent_agg = df_agent.groupby(agent_col)[val_col].sum().reset_index()
                agent_agg = agent_agg.sort_values(agent_col)
                
                # Compare
                # We check if the breach counts match for known agents
                # Use Alice as a canary (she has breaches in the seed data)
                matched_rows = 0
                total_rows = 0
                
                for index, row in ground_truth.iterrows():
                    agent = row['Agent_Name']
                    truth_val = row['Is_Breached']
                    
                    # Find agent in user export
                    # Fuzzy match name? PBI export should be exact match
                    user_row = agent_agg[agent_agg[agent_col] == agent]
                    
                    if not user_row.empty:
                        user_val = user_row.iloc[0][val_col]
                        total_rows += 1
                        if abs(user_val - truth_val) < 0.01: # Float tolerance
                            matched_rows += 1
                        else:
                            feedback.append(f"Mismatch for {agent}: Expected {truth_val}, Got {user_val}")
                
                if total_rows > 0:
                    accuracy = matched_rows / total_rows
                    points = int(accuracy * 60)
                    score += points
                    feedback.append(f"Data Accuracy: {int(accuracy*100)}% ({points}/60 pts)")
                else:
                    feedback.append("Could not align Agent names for verification.")

            except Exception as e:
                feedback.append(f"Error verifying data: {str(e)}")
        
        passed = (score >= 70)
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }