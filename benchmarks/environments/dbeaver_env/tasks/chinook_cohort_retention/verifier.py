#!/usr/bin/env python3
"""
Verifier for chinook_cohort_retention task.
"""

import json
import os
import pandas as pd
import numpy as np
import tempfile
import shutil

def verify_chinook_cohort_retention(traj, env_info, task_info):
    """
    Verifies the cohort retention analysis task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # Setup temporary directory for files
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Retrieve task result metadata
        task_result_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("/tmp/task_result.json", task_result_path)
            with open(task_result_path, 'r') as f:
                result_meta = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # 2. Retrieve Ground Truth
        gt_path = os.path.join(temp_dir, "ground_truth.json")
        try:
            copy_from_env(result_meta.get('ground_truth_path', '/tmp/cohort_ground_truth.json'), gt_path)
            with open(gt_path, 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve ground truth: {str(e)}"}

        # 3. Retrieve Agent CSV (if exists)
        agent_csv_local = os.path.join(temp_dir, "agent_cohort.csv")
        csv_retrieved = False
        if result_meta.get('csv_exists'):
            try:
                copy_from_env(result_meta.get('agent_csv_path'), agent_csv_local)
                csv_retrieved = True
            except Exception as e:
                feedback_parts.append(f"CSV exists but could not be copied: {str(e)}")

        # --- SCORING CRITERIA ---

        # Criterion 1: Connection Created (10 pts)
        if result_meta.get('connection_found'):
            score += 10
            feedback_parts.append("DBeaver connection 'ChinookCohort' found (+10)")
        else:
            feedback_parts.append("Connection 'ChinookCohort' NOT found in DBeaver config")

        # Criterion 2: SQL Script Saved (5 pts)
        if result_meta.get('sql_exists'):
            score += 5
            feedback_parts.append("SQL script file saved (+5)")
        else:
            feedback_parts.append("SQL script file missing")

        # Criterion 3: Summary Report Saved (5 pts)
        if result_meta.get('summary_exists'):
            score += 5
            feedback_parts.append("Summary report saved (+5)")
        else:
            feedback_parts.append("Summary report missing")

        # Criterion 4: CSV File Existence & Creation (5 pts)
        if result_meta.get('csv_exists') and result_meta.get('csv_created_during_task'):
            score += 5
            feedback_parts.append("CSV output created during task (+5)")
        elif result_meta.get('csv_exists'):
            score += 2
            feedback_parts.append("CSV exists but timestamp check inconclusive (+2)")
        else:
            feedback_parts.append("CSV output file missing")

        # DATA VERIFICATION
        if csv_retrieved and 'data' in ground_truth:
            try:
                # Load Agent Data
                # Flexible loading: skip rows if header is not first, try comma separator
                try:
                    df_agent = pd.read_csv(agent_csv_local)
                except:
                    df_agent = pd.read_csv(agent_csv_local, sep=None, engine='python')

                # Load GT Data
                df_gt = pd.DataFrame(ground_truth['data'])
                
                # Check 5: Required Columns (15 pts)
                required_cols = {'CohortMonth', 'MonthNumber', 'CohortSize', 'ActiveCustomers', 'RetentionPct'}
                agent_cols = set(df_agent.columns)
                
                # Allow case-insensitive matching
                agent_cols_lower = {c.lower(): c for c in agent_cols}
                required_cols_lower = {c.lower() for c in required_cols}
                
                missing_cols = required_cols_lower - set(agent_cols_lower.keys())
                
                if not missing_cols:
                    score += 15
                    feedback_parts.append("All required columns present (+15)")
                    
                    # Normalize column names for further checking
                    rename_map = {agent_cols_lower[c]: c for c in required_cols_lower} # map actual -> canonical lower
                    # Wait, we want to map Actual -> Canonical Standard
                    # Actually just mapping to lower is easier for comparison
                    df_agent.rename(columns=lambda x: x.lower(), inplace=True)
                    df_gt.rename(columns=lambda x: x.lower(), inplace=True)
                    
                    # Check 6: Row Count (10 pts)
                    # Allow +/- 10%
                    gt_count = len(df_gt)
                    agent_count = len(df_agent)
                    if 0.9 * gt_count <= agent_count <= 1.1 * gt_count:
                        score += 10
                        feedback_parts.append(f"Row count valid ({agent_count}) (+10)")
                    else:
                        feedback_parts.append(f"Row count mismatch: Got {agent_count}, expected ~{gt_count}")

                    # Check 7: Definitional Correctness (Month 0 = 100%) (10 pts)
                    # Check rows where monthnumber == 0
                    month0_mask = df_agent['monthnumber'] == 0
                    if month0_mask.any():
                        m0_retention = df_agent.loc[month0_mask, 'retentionpct']
                        # Check if all are close to 100
                        if np.allclose(m0_retention, 100.0, atol=0.1):
                            score += 10
                            feedback_parts.append("Month 0 retention is 100% (+10)")
                        else:
                            feedback_parts.append("Month 0 retention values are not all 100%")
                    else:
                        feedback_parts.append("No Month 0 rows found")

                    # Check 8: Total Customer Count (10 pts)
                    # Sum of cohortsize for unique cohorts
                    # Since structure might be strictly one row per cohort/month, we take max size per cohort
                    try:
                        agent_cohorts = df_agent.groupby('cohortmonth')['cohortsize'].max()
                        total_customers = agent_cohorts.sum()
                        if 59 == total_customers:
                            score += 10
                            feedback_parts.append("Total customer count (59) is correct (+10)")
                        else:
                            feedback_parts.append(f"Total customer count incorrect: {total_customers} (expected 59)")
                    except Exception as e:
                        feedback_parts.append(f"Could not verify customer count: {e}")

                    # Check 9: Data Accuracy (20 pts)
                    # Join on CohortMonth and MonthNumber and compare ActiveCustomers
                    # Ensure types match
                    try:
                        merged = pd.merge(df_gt, df_agent, on=['cohortmonth', 'monthnumber'], suffixes=('_gt', '_ag'), how='inner')
                        
                        if len(merged) > 0:
                            # Compare ActiveCustomers
                            matches = np.abs(merged['activecustomers_gt'] - merged['activecustomers_ag']) <= 1
                            match_rate = matches.mean()
                            
                            if match_rate >= 0.8:
                                score += 20
                                feedback_parts.append(f"Data values match ground truth (>80% accuracy) (+20)")
                            elif match_rate >= 0.5:
                                score += 10
                                feedback_parts.append(f"Data values partially match ground truth (>50% accuracy) (+10)")
                            else:
                                feedback_parts.append(f"Data values mismatch (Accuracy: {match_rate:.1%})")
                        else:
                            feedback_parts.append("Could not align data for value comparison")
                    except Exception as e:
                        feedback_parts.append(f"Error comparing data values: {e}")

                else:
                    feedback_parts.append(f"Missing columns: {missing_cols}")
            
            except Exception as e:
                feedback_parts.append(f"Error parsing CSV: {str(e)}")
        else:
            feedback_parts.append("Skipping data verification (CSV missing)")

        # Summary check (10 pts split)
        # We can't easily parse the text file for exact semantics without LLM, 
        # but we can check if it contains numbers relevant to the result
        if result_meta.get('summary_exists'):
            try:
                summary_local = os.path.join(temp_dir, "summary.txt")
                copy_from_env(result_meta.get('expected_summary_path', '/home/ga/Documents/exports/cohort_summary.txt'), summary_local)
                with open(summary_local, 'r') as f:
                    content = f.read()
                    # Check for "max_cohort_month" (e.g. 2009-01) from GT
                    max_month = ground_truth.get('max_cohort_month', '')
                    if max_month and max_month in content:
                        score += 5
                        feedback_parts.append("Summary mentions largest cohort correctly (+5)")
                    
                    # Check if it has reasonable length
                    if len(content.split()) > 10:
                        score += 5
                        feedback_parts.append("Summary has reasonable content length (+5)")
            except:
                pass

        return {
            "passed": score >= 60,
            "score": score,
            "feedback": "; ".join(feedback_parts)
        }

    finally:
        shutil.rmtree(temp_dir)