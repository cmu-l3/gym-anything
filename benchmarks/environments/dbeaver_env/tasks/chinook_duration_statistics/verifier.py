#!/usr/bin/env python3
"""
Verifier for Chinook Duration Statistics Task
"""

import json
import csv
import os
import math
import logging
import tempfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_chinook_duration_statistics(traj, env_info, task_info):
    """
    Verify the statistical analysis of Chinook track durations.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load Result JSON
    result = {}
    ground_truth = {}
    
    with tempfile.TemporaryDirectory() as tmpdir:
        # Copy files from env
        try:
            copy_from_env("/tmp/task_result.json", f"{tmpdir}/result.json")
            with open(f"{tmpdir}/result.json") as f:
                result = json.load(f)
                
            copy_from_env("/tmp/ground_truth.json", f"{tmpdir}/ground_truth.json")
            with open(f"{tmpdir}/ground_truth.json") as f:
                ground_truth = json.load(f)
                
            # Try copy CSVs if they exist
            if result.get('stats_csv_exists'):
                copy_from_env("/tmp/agent_stats.csv", f"{tmpdir}/agent_stats.csv")
            if result.get('outliers_csv_exists'):
                copy_from_env("/tmp/agent_outliers.csv", f"{tmpdir}/agent_outliers.csv")
                
        except Exception as e:
            logger.error(f"Error copying files: {e}")
            return {"passed": False, "score": 0, "feedback": f"Error retrieving task files: {str(e)}"}

    score = 0
    feedback = []
    passed = False

    # 1. Connection (10 pts)
    if result.get('connection_exists'):
        score += 10
        feedback.append("✅ DBeaver connection 'Chinook' exists.")
    else:
        feedback.append("❌ DBeaver connection 'Chinook' not found.")

    # 2. Stats CSV Structure (10 pts)
    agent_stats = []
    if result.get('stats_csv_exists'):
        try:
            with open(f"{tmpdir}/agent_stats.csv", 'r') as f:
                reader = csv.DictReader(f)
                agent_stats = list(reader)
                
            # Check columns
            required_cols = task_info['metadata']['stats_columns']
            headers = reader.fieldnames if reader.fieldnames else []
            # normalize headers
            headers_norm = [h.strip() for h in headers]
            
            missing_cols = [c for c in required_cols if c not in headers_norm]
            if not missing_cols:
                score += 10
                feedback.append("✅ Stats CSV has correct columns.")
            else:
                feedback.append(f"❌ Stats CSV missing columns: {', '.join(missing_cols)}")
                
        except Exception as e:
            feedback.append(f"❌ Error parsing Stats CSV: {e}")
    else:
        feedback.append("❌ Stats CSV not found.")

    # 3. Stats Data Accuracy (30 pts)
    # Compare rows against ground truth
    stats_accuracy_score = 0
    if agent_stats and 'genre_stats' in ground_truth:
        gt_stats = {g['GenreName']: g for g in ground_truth['genre_stats']}
        
        matches = 0
        checks = 0
        
        for row in agent_stats:
            g_name = row.get('GenreName')
            if g_name in gt_stats:
                checks += 1
                gt = gt_stats[g_name]
                
                # Check Median (Hardest)
                try:
                    # Allow 0.5 tolerance for median calculation differences (even/odd logic)
                    if abs(float(row['MedianDurationSec']) - gt['MedianDurationSec']) <= 0.5:
                        matches += 1
                    # Check StdDev
                    elif abs(float(row['StdDevDurationSec']) - gt['StdDevDurationSec']) <= 0.5:
                        matches += 1
                    # Check Mean
                    elif abs(float(row['AvgDurationSec']) - gt['AvgDurationSec']) <= 0.1:
                        matches += 1
                except ValueError:
                    continue
        
        # Scale score based on valid rows
        if checks > 0:
            accuracy = matches / checks  # Rough heuristic
            # Give full points if mostly correct (allowing for some calculation diffs)
            if accuracy > 0.8: 
                stats_accuracy_score = 30
            elif accuracy > 0.5:
                stats_accuracy_score = 15
            else:
                stats_accuracy_score = 5
        
        score += stats_accuracy_score
        feedback.append(f"📊 Stats data accuracy score: {stats_accuracy_score}/30")

    # 4. Outliers CSV (10 pts)
    if result.get('outliers_csv_exists'):
        score += 10
        feedback.append("✅ Outliers CSV exists.")
    else:
        feedback.append("❌ Outliers CSV not found.")

    # 5. Outliers Accuracy (20 pts)
    outlier_accuracy_score = 0
    if result.get('outliers_csv_exists') and 'outliers' in ground_truth:
        try:
            with open(f"{tmpdir}/agent_outliers.csv", 'r') as f:
                reader = csv.DictReader(f)
                agent_outliers = list(reader)
            
            # Simple check: Count should be roughly similar
            gt_count = len(ground_truth['outliers'])
            agent_count = len(agent_outliers)
            
            if abs(agent_count - gt_count) <= 5: # Allow small difference
                outlier_accuracy_score += 10
            
            # Check a specific known outlier (e.g., longest track)
            # Find max ZScore in GT
            max_outlier = max(ground_truth['outliers'], key=lambda x: abs(x['ZScore']))
            found_max = False
            for row in agent_outliers:
                if row.get('TrackName') == "Occupation / Precipice": # Known long track
                     found_max = True
                     break
            
            if found_max:
                outlier_accuracy_score += 10
                
        except Exception as e:
            feedback.append(f"⚠️ Error verifying outlier data: {e}")
            
        score += outlier_accuracy_score
        feedback.append(f"📊 Outlier accuracy score: {outlier_accuracy_score}/20")

    # 6. SQL Script (10 pts) & Timestamp (10 pts)
    if result.get('sql_script_exists'):
        score += 10
        feedback.append("✅ SQL script saved.")
    else:
        feedback.append("❌ SQL script not found.")
        
    if result.get('files_created_during_task'):
        score += 10
        feedback.append("✅ Files verified created during task.")
    else:
        feedback.append("⚠️ Files pre-dated task start (Anti-gaming check failed).")

    passed = (score >= 60)

    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }