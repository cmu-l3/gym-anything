#!/usr/bin/env python3
"""
Verifier for Checkpoint Peak Congestion State task.

Programmatic verification of output XML and text files.
1. Checks if summary.xml is valid and computes the peak congestion time natively.
2. Checks if peak_report.txt accurately identifies the peak.
3. Checks if peak_state.xml is a valid snapshot exactly at the peak time.
"""

import json
import tempfile
import os
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_checkpoint_peak_congestion_state(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Copy metadata JSON from env
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    task_start = result.get('task_start', 0)

    # ================================================================
    # 1. Summary File Parsing & Ground Truth Calculation (20 points)
    # ================================================================
    summary_exists = result.get('summary_exists', False)
    summary_mtime = result.get('summary_mtime', 0)
    
    gt_peak_time = None
    gt_max_halting = -1

    if summary_exists and summary_mtime >= task_start:
        temp_summary = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/home/ga/SUMO_Output/summary.xml", temp_summary.name)
            tree = ET.parse(temp_summary.name)
            root = tree.getroot()
            
            for step in root.findall('step'):
                time_val = float(step.get('time', -1))
                halting_val = int(step.get('halting', 0))
                
                if halting_val > gt_max_halting:
                    gt_max_halting = halting_val
                    gt_peak_time = time_val
                elif halting_val == gt_max_halting and gt_max_halting >= 0:
                    pass # Only update on strict greater-than to catch the earliest peak time
            
            if gt_peak_time is not None:
                score += 20
                feedback_parts.append(f"Summary valid (Ground Truth Peak: {gt_peak_time}s, Max Halting: {gt_max_halting})")
            else:
                feedback_parts.append("Summary file parsed but no simulation steps found")
        except Exception as e:
            feedback_parts.append(f"Summary parsing failed: {e}")
        finally:
            if os.path.exists(temp_summary.name):
                os.unlink(temp_summary.name)
    else:
        feedback_parts.append("Summary file missing or created before task start (failed anti-gaming check)")

    # ================================================================
    # 2. Peak Identification Report Verification (30 points)
    # ================================================================
    report_exists = result.get('report_exists', False)
    report_mtime = result.get('report_mtime', 0)
    
    report_peak_time = None
    report_max_halting = None
    
    if report_exists and report_mtime >= task_start:
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/home/ga/SUMO_Output/peak_report.txt", temp_report.name)
            with open(temp_report.name, 'r') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('Peak_Time:'):
                        try:
                            report_peak_time = float(line.split(':', 1)[1].strip())
                        except ValueError:
                            pass
                    elif line.startswith('Max_Halting:'):
                        try:
                            report_max_halting = float(line.split(':', 1)[1].strip())
                        except ValueError:
                            pass
            
            if gt_peak_time is not None:
                if report_peak_time is not None and report_max_halting is not None:
                    # Allow a tiny float tolerance just in case
                    if abs(report_peak_time - gt_peak_time) < 0.01 and abs(report_max_halting - gt_max_halting) < 0.01:
                        score += 30
                        feedback_parts.append("Report values exactly match ground truth")
                    else:
                        feedback_parts.append(f"Report mismatch: Expected ({gt_peak_time}, {gt_max_halting}), Got ({report_peak_time}, {report_max_halting})")
                else:
                    feedback_parts.append("Report format incorrect, could not parse 'Peak_Time:' or 'Max_Halting:' formats")
            else:
                feedback_parts.append("Could not evaluate report without verifiable ground truth from summary")
        except Exception as e:
            feedback_parts.append(f"Report parsing failed: {e}")
        finally:
            if os.path.exists(temp_report.name):
                os.unlink(temp_report.name)
    else:
        feedback_parts.append("Report file missing or created before task start")

    # ================================================================
    # 3. Snapshot Generated Verification (30 points)
    # ================================================================
    state_exists = result.get('state_exists', False)
    state_mtime = result.get('state_mtime', 0)
    state_time = None
    
    if state_exists and state_mtime >= task_start:
        temp_state = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/home/ga/SUMO_Output/peak_state.xml", temp_state.name)
            tree = ET.parse(temp_state.name)
            root = tree.getroot()
            
            if root.tag == 'snapshot':
                score += 30
                state_time = float(root.get('time', -1))
                feedback_parts.append(f"Valid SUMO snapshot found at time {state_time}")
            else:
                feedback_parts.append("State file is present but not a valid SUMO snapshot")
        except Exception as e:
            feedback_parts.append(f"State file XML parsing failed: {e}")
        finally:
            if os.path.exists(temp_state.name):
                os.unlink(temp_state.name)
    else:
        feedback_parts.append("State file missing or created before task start")

    # ================================================================
    # 4. Snapshot Accuracy Verification (20 points)
    # ================================================================
    if state_time is not None and gt_peak_time is not None:
        if abs(state_time - gt_peak_time) < 0.01:
            score += 20
            feedback_parts.append("Snapshot strictly matches peak congestion time")
        else:
            feedback_parts.append(f"Snapshot time ({state_time}) != Expected peak time ({gt_peak_time})")

    # Final pass logic (requires both identification and accurate snapshotting to pass)
    passed = score >= 80

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }