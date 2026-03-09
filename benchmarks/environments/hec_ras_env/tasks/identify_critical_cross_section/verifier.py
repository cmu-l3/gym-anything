#!/usr/bin/env python3
"""
Verifier for identify_critical_cross_section task.

Checks:
1. Output files existence and creation time.
2. CSV format and content against ground truth.
3. Summary file correctness (Critical section, Freeboard).
"""

import json
import csv
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_critical_section(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Temporary directory for files
    with tempfile.TemporaryDirectory() as temp_dir:
        # File paths
        res_json_path = os.path.join(temp_dir, "task_result.json")
        report_path = os.path.join(temp_dir, "agent_report.csv")
        summary_path = os.path.join(temp_dir, "agent_summary.txt")
        gt_path = os.path.join(temp_dir, "ground_truth.json")

        # Copy files
        try:
            copy_from_env("/tmp/task_result.json", res_json_path)
            copy_from_env("/tmp/agent_report.csv", report_path)
            copy_from_env("/tmp/agent_summary.txt", summary_path)
            copy_from_env("/tmp/ground_truth.json", gt_path)
        except Exception as e:
            logger.warning(f"File copy warning: {e}")

        # Load Metadata
        try:
            with open(res_json_path, 'r') as f:
                result_meta = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "Failed to load result metadata"}

        # Load Ground Truth
        try:
            with open(gt_path, 'r') as f:
                ground_truth = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "System Error: Ground truth not found"}

        score = 0
        feedback = []

        # 1. File Existence and Anti-Gaming (20 pts)
        if result_meta.get("report_exists") and result_meta.get("summary_exists"):
            if result_meta.get("report_created_during_task"):
                score += 20
                feedback.append("Output files created successfully.")
            else:
                score += 5
                feedback.append("Output files exist but timestamp is old (potential reuse).")
        else:
            return {"passed": False, "score": 0, "feedback": "Output files missing."}

        # 2. CSV Content Verification (40 pts)
        agent_data = {}
        try:
            with open(report_path, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
                # Check columns
                required_cols = {'River_Station', 'Peak_WSE_ft', 'Freeboard_ft'}
                if not required_cols.issubset(reader.fieldnames):
                    feedback.append(f"CSV missing required columns. Found: {reader.fieldnames}")
                else:
                    score += 10
                    
                    # Check Row Count
                    if abs(len(rows) - ground_truth['total_sections']) <= 1:
                        score += 10
                    else:
                        feedback.append(f"Row count mismatch: Agent {len(rows)}, GT {ground_truth['total_sections']}")

                    # Check Values (Sample check)
                    # We map agent RS to GT data
                    gt_map = {item['River_Station']: item for item in ground_truth['data']}
                    
                    matches = 0
                    total_checked = 0
                    
                    for row in rows:
                        rs = row.get('River_Station')
                        if rs in gt_map:
                            gt_row = gt_map[rs]
                            try:
                                # Tolerate 0.1 ft difference (floating point/interp diffs)
                                wse_ok = abs(float(row['Peak_WSE_ft']) - gt_row['Peak_WSE_ft']) < 0.1
                                fb_ok = abs(float(row['Freeboard_ft']) - gt_row['Freeboard_ft']) < 0.1
                                if wse_ok and fb_ok:
                                    matches += 1
                            except ValueError:
                                pass
                            total_checked += 1
                    
                    if total_checked > 0 and (matches / total_checked) > 0.8:
                        score += 20
                        feedback.append("CSV data values match ground truth.")
                    else:
                        feedback.append("CSV data values have significant discrepancies.")
                        
        except Exception as e:
            feedback.append(f"Failed to parse CSV: {e}")

        # 3. Summary File Verification (40 pts)
        try:
            with open(summary_path, 'r') as f:
                summary_content = f.read()
            
            # Simple parsing of key-value pairs
            summary_dict = {}
            for line in summary_content.splitlines():
                if ':' in line:
                    key, val = line.split(':', 1)
                    summary_dict[key.strip()] = val.strip()

            gt_crit_rs = ground_truth['critical_section']
            gt_min_fb = ground_truth['min_freeboard']
            
            # Check Critical River Station
            agent_rs = summary_dict.get('Critical_River_Station', '')
            if agent_rs == gt_crit_rs:
                score += 20
                feedback.append(f"Correctly identified critical section: {agent_rs}")
            else:
                feedback.append(f"Wrong critical section. Agent: {agent_rs}, GT: {gt_crit_rs}")

            # Check Freeboard Value
            try:
                agent_fb = float(summary_dict.get('Freeboard_ft', 999))
                if abs(agent_fb - gt_min_fb) < 0.1:
                    score += 10
                    feedback.append("Critical freeboard value is accurate.")
            except:
                pass

            # Check Overtopping Count
            try:
                agent_over = int(summary_dict.get('Num_Overtopped_Sections', -1))
                if agent_over == ground_truth['overtopped_count']:
                    score += 10
                elif abs(agent_over - ground_truth['overtopped_count']) <= 1:
                    score += 5 # Close enough
            except:
                pass

        except Exception as e:
            feedback.append(f"Failed to parse summary file: {e}")

        passed = score >= 60
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }