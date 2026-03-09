#!/usr/bin/env python3
"""
Verifier for NYC 311 Chronic Noise Analysis Task

Logic:
1. Calculates ground truth from the *actual* source CSV used in the environment.
   - Parses dates.
   - Sorts by address and date.
   - Uses a sliding window (or self-join logic) to find addresses with >=3 events in any 7-day delta.
2. Compares agent's output CSV against ground truth.
3. Checks for artifact creation (connection, script).
"""

import json
import csv
import pandas as pd
import os
import tempfile
import logging
from datetime import timedelta

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def calculate_ground_truth(csv_path):
    """
    Reads the source CSV and identifies chronic offenders.
    Rule: >= 3 complaints in any rolling 7-day window.
    """
    try:
        df = pd.read_csv(csv_path)
    except Exception as e:
        logger.error(f"Failed to read source CSV: {e}")
        return set()

    # Normalize columns
    df.columns = [c.strip() for c in df.columns]
    
    # Check required columns
    if 'Created Date' not in df.columns or 'Incident Address' not in df.columns:
        logger.error("Source CSV missing required columns")
        return set()

    # Drop rows with no address
    df = df.dropna(subset=['Incident Address'])
    
    # Parse dates
    # Try mixed format inference
    df['dt'] = pd.to_datetime(df['Created Date'], errors='coerce')
    df = df.dropna(subset=['dt'])

    chronic_addresses = set()

    # Group by address
    grouped = df.groupby('Incident Address')

    for address, group in grouped:
        if len(group) < 3:
            continue
        
        # Sort by date
        dates = group['dt'].sort_values().values
        
        # Check for any sequence of 3 events where date[i+2] - date[i] <= 7 days
        is_chronic = False
        for i in range(len(dates) - 2):
            # dates are in nanoseconds (numpy datetime64)
            # 7 days in nanoseconds
            seven_days_ns = np_timedelta64(7, 'D')
            
            t_start = dates[i]
            t_end = dates[i+2] # The 3rd event in the sequence
            
            if (t_end - t_start) <= seven_days_ns:
                is_chronic = True
                break
        
        if is_chronic:
            chronic_addresses.add(address.strip().upper())

    return chronic_addresses

def np_timedelta64(val, unit):
    import numpy as np
    return np.timedelta64(val, unit)

def verify_nyc_311_chronic_noise(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    # 1. Retrieve files
    temp_dir = tempfile.mkdtemp()
    source_csv_path = os.path.join(temp_dir, "source_data.csv")
    agent_csv_path = os.path.join(temp_dir, "agent_output.csv")
    result_json_path = os.path.join(temp_dir, "task_result.json")
    
    files_retrieved = {}
    try:
        copy_from_env("/tmp/source_data.csv", source_csv_path)
        files_retrieved['source'] = True
    except:
        files_retrieved['source'] = False

    try:
        copy_from_env("/tmp/agent_output.csv", agent_csv_path)
        files_retrieved['agent'] = True
    except:
        files_retrieved['agent'] = False

    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            meta_result = json.load(f)
    except:
        meta_result = {}

    score = 0
    feedback = []

    # 2. Check artifacts (Base points: 30)
    if meta_result.get('connection_exists'):
        score += 10
        feedback.append("DBeaver connection 'CityData' created.")
    else:
        feedback.append("Failed to create DBeaver connection 'CityData'.")

    if meta_result.get('script_exists'):
        score += 10
        feedback.append("SQL script saved.")
    else:
        feedback.append("SQL analysis script not saved.")
        
    if meta_result.get('csv_exists') and meta_result.get('csv_created_during_task'):
        score += 10
        feedback.append("Output CSV created.")
    else:
        feedback.append("Output CSV not created or not modified.")

    # 3. Validation Logic (Data points: 70)
    if files_retrieved.get('source') and files_retrieved.get('agent'):
        try:
            # Calculate GT
            gt_addresses = calculate_ground_truth(source_csv_path)
            
            # Read Agent Output
            try:
                agent_df = pd.read_csv(agent_csv_path)
                # Find the address column (flexible search)
                addr_col = next((c for c in agent_df.columns if 'address' in c.lower()), None)
                
                if addr_col:
                    agent_addresses = set(agent_df[addr_col].dropna().astype(str).str.strip().str.upper())
                else:
                    agent_addresses = set()
                    feedback.append("Could not find 'Address' column in output CSV.")
            except Exception as e:
                agent_addresses = set()
                feedback.append(f"Failed to parse output CSV: {str(e)}")

            # Compare
            # Case 1: GT is empty (maybe dataset was too small or no chronic offenders)
            if not gt_addresses:
                if not agent_addresses:
                    score += 70
                    feedback.append("Correctly identified 0 chronic offenders.")
                else:
                    # Agent found something where nothing existed
                    score += 0
                    feedback.append(f"Found {len(agent_addresses)} addresses, but expected 0.")
            else:
                # Calculate metrics
                tp = len(gt_addresses.intersection(agent_addresses))
                fp = len(agent_addresses - gt_addresses)
                fn = len(gt_addresses - agent_addresses)
                
                # Precision and Recall
                precision = tp / (tp + fp) if (tp + fp) > 0 else 0
                recall = tp / (tp + fn) if (tp + fn) > 0 else 0
                f1 = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
                
                # Scoring based on F1
                # If perfect match: 70 pts
                # If reasonable overlap: scaled
                data_score = int(f1 * 70)
                score += data_score
                
                feedback.append(f"Accuracy Analysis: Precision={precision:.2f}, Recall={recall:.2f}, F1={f1:.2f}")
                feedback.append(f"Identified {tp} correct addresses out of {len(gt_addresses)} expected.")
                if fp > 0:
                    feedback.append(f"Included {fp} incorrect addresses.")
                if fn > 0:
                    feedback.append(f"Missed {fn} chronic addresses.")

        except Exception as e:
            feedback.append(f"Error during verification calculation: {str(e)}")
    else:
        feedback.append("Missing source data or agent output for verification.")

    passed = score >= 60
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }