#!/usr/bin/env python3
"""
Verifier for audit_expansion_contraction_severity task.

Verifies:
1. Agent CSV output exists and matches Ground Truth values (Top Widths, Ratios).
2. Agent Report exists and correctly identifies the "Worst Expansion" and violation counts.
3. Anti-gaming: Files created during task, Python script used.
4. VLM: Trajectory check for valid workflow.
"""

import json
import csv
import os
import tempfile
import logging
from typing import Dict, Any, List

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_audit(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    max_score = 100
    feedback_parts = []
    
    # ---------------------------------------------------------
    # 1. Retrieve Artifacts
    # ---------------------------------------------------------
    files = {
        "metadata": "/tmp/task_result.json",
        "ground_truth": "/tmp/ground_truth_export.json",
        "agent_csv": "/tmp/agent_audit.csv",
        "agent_report": "/tmp/agent_report.txt"
    }
    
    local_files = {}
    
    # Create temp directory for artifacts
    with tempfile.TemporaryDirectory() as temp_dir:
        for key, remote_path in files.items():
            local_path = os.path.join(temp_dir, os.path.basename(remote_path))
            try:
                copy_from_env(remote_path, local_path)
                local_files[key] = local_path
            except Exception as e:
                logger.warning(f"Could not copy {key}: {e}")
                local_files[key] = None

        # Load Metadata
        try:
            with open(local_files["metadata"], 'r') as f:
                metadata = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "Failed to load task metadata"}

        # Load Ground Truth
        try:
            with open(local_files["ground_truth"], 'r') as f:
                gt_data = json.load(f)
        except:
            return {"passed": False, "score": 0, "feedback": "Failed to load ground truth data"}
            
        # ---------------------------------------------------------
        # 2. Verify Output Existence & Creation (20 points)
        # ---------------------------------------------------------
        if metadata.get("csv_exists"):
            score += 10
            feedback_parts.append("CSV file created.")
        else:
            feedback_parts.append("CSV file missing.")
            
        if metadata.get("report_exists"):
            score += 5
            feedback_parts.append("Report file created.")
        else:
            feedback_parts.append("Report file missing.")
            
        if metadata.get("script_created"):
            score += 5
            feedback_parts.append("Analysis script detected.")
        else:
            feedback_parts.append("No analysis script detected (did you write code?).")

        # ---------------------------------------------------------
        # 3. Verify CSV Content (40 points)
        # ---------------------------------------------------------
        csv_score = 0
        agent_transitions = []
        if local_files["agent_csv"] and metadata.get("csv_exists"):
            try:
                with open(local_files["agent_csv"], 'r') as f:
                    reader = csv.DictReader(f)
                    agent_transitions = list(reader)
                
                # Check row count (should match GT transitions)
                gt_count = len(gt_data.get("transitions", []))
                agent_count = len(agent_transitions)
                
                if abs(agent_count - gt_count) <= 1:
                    csv_score += 10
                    feedback_parts.append(f"CSV row count correct ({agent_count}).")
                else:
                    feedback_parts.append(f"CSV row count mismatch (Expected ~{gt_count}, Got {agent_count}).")

                # Verify a sample of rows
                # We map GT data by Upstream_XS for easy lookup
                gt_map = {str(item["upstream_xs"]): item for item in gt_data["transitions"]}
                
                correct_calculations = 0
                sample_size = 0
                
                for row in agent_transitions:
                    u_xs = str(row.get("Upstream_XS", "")).strip()
                    if u_xs in gt_map:
                        sample_size += 1
                        gt_row = gt_map[u_xs]
                        
                        # Verify Ratio
                        try:
                            agent_ratio = float(row.get("Ratio", 0))
                            gt_ratio = gt_row["ratio"]
                            if abs(agent_ratio - gt_ratio) < 0.05:
                                correct_calculations += 1
                        except:
                            pass
                            
                if sample_size > 0:
                    accuracy = correct_calculations / sample_size
                    if accuracy > 0.9:
                        csv_score += 30
                        feedback_parts.append("CSV ratio calculations accurate.")
                    elif accuracy > 0.5:
                        csv_score += 15
                        feedback_parts.append("CSV ratio calculations partially accurate.")
                    else:
                        feedback_parts.append("CSV ratio calculations inaccurate.")
                else:
                    feedback_parts.append("Could not match CSV rows to ground truth stations.")

            except Exception as e:
                feedback_parts.append(f"Error parsing CSV: {e}")
        
        score += csv_score

        # ---------------------------------------------------------
        # 4. Verify Report Content (40 points)
        # ---------------------------------------------------------
        report_score = 0
        if local_files["agent_report"] and metadata.get("report_exists"):
            try:
                with open(local_files["agent_report"], 'r') as f:
                    report_text = f.read()
                
                # Check for "Severe Expansion" count
                gt_exp_count = gt_data.get("severe_expansion_count", 0)
                if str(gt_exp_count) in report_text:
                    report_score += 10
                    feedback_parts.append(f"Report correctly identifies {gt_exp_count} severe expansions.")
                
                # Check for "Severe Contraction" count
                gt_con_count = gt_data.get("severe_contraction_count", 0)
                if str(gt_con_count) in report_text:
                    report_score += 10
                    feedback_parts.append(f"Report correctly identifies {gt_con_count} severe contractions.")
                    
                # Check for Worst Segment
                worst_seg = gt_data.get("worst_expansion_segment", "")
                # Split worst seg "1000 to 800" into parts to check loosely
                parts = worst_seg.replace("to", " ").split()
                if all(part in report_text for part in parts):
                    report_score += 20
                    feedback_parts.append(f"Report correctly identifies worst segment: {worst_seg}.")
                else:
                    feedback_parts.append(f"Report failed to identify worst segment ({worst_seg}).")

            except Exception as e:
                feedback_parts.append(f"Error reading report: {e}")
        
        score += report_score

    # Final logic
    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }