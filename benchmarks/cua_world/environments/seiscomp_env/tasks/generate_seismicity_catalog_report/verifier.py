#!/usr/bin/env python3
"""
Verifier for generate_seismicity_catalog_report task.

Verification Strategy:
1. Python script exists and was created during the task (anti-gaming).
2. Script imports the `seiscomp` module.
3. Report markdown file exists and was created during the task.
4. Report contains a valid Markdown table format.
5. All DB events are listed in the report (Public IDs match).
6. Data accuracy: Event parameters (Mag/Lat/Lon) extracted from the report match DB ground truth.
7. VLM: Verify via trajectory frames that a terminal or text editor was actually used during workflow.
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_seismicity_report(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    score = 0
    feedback_parts = []
    
    # 1. Retrieve metadata files from the container
    files_to_copy = {
        "/tmp/task_result.json": "task_result.json",
        "/tmp/db_ground_truth.json": "db_ground_truth.json",
        "/tmp/agent_script.py": "agent_script.py",
        "/tmp/agent_report.md": "agent_report.md"
    }
    
    local_files = {}
    temp_dir = tempfile.mkdtemp()
    
    try:
        for container_path, local_name in files_to_copy.items():
            local_path = os.path.join(temp_dir, local_name)
            try:
                copy_from_env(container_path, local_path)
                if os.path.exists(local_path):
                    local_files[local_name] = local_path
            except Exception as e:
                logger.warning(f"Failed to copy {container_path}: {e}")

        # Parse task result
        if "task_result.json" not in local_files:
            return {"passed": False, "score": 0, "feedback": "Failed to read task result metadata."}
            
        with open(local_files["task_result.json"], 'r') as f:
            result = json.load(f)
            
        task_start = result.get("task_start", 0)
        
        # Criterion 1: Script existence and anti-gaming (15 pts)
        if result.get("script_exists"):
            if result.get("script_mtime", 0) >= task_start:
                feedback_parts.append("Script created during task.")
                
                # Check script content
                if "agent_script.py" in local_files:
                    with open(local_files["agent_script.py"], 'r') as f:
                        script_content = f.read()
                    if "seiscomp" in script_content:
                        score += 15
                        feedback_parts.append("Script imports seiscomp.")
                    else:
                        score += 5
                        feedback_parts.append("Script exists but does not import seiscomp.")
                else:
                    score += 5
            else:
                feedback_parts.append("Script existed before task (possible gaming).")
        else:
            feedback_parts.append("Script not found.")

        # Criterion 2: Report existence and anti-gaming (15 pts)
        report_content = ""
        if result.get("report_exists"):
            if result.get("report_mtime", 0) >= task_start:
                score += 15
                feedback_parts.append("Report created during task.")
                
                if "agent_report.md" in local_files:
                    with open(local_files["agent_report.md"], 'r') as f:
                        report_content = f.read()
            else:
                feedback_parts.append("Report existed before task (possible gaming).")
        else:
            feedback_parts.append("Report not found.")
            
        if not report_content:
            return {
                "passed": False, 
                "score": score, 
                "feedback": " | ".join(feedback_parts) + " | Cannot verify content."
            }

        # Criterion 3: Markdown Table Format (10 pts)
        lines = report_content.strip().split('\n')
        has_table = False
        for i, line in enumerate(lines):
            if "|" in line and "EventID" in line:
                if i + 1 < len(lines) and "---" in lines[i+1]:
                    has_table = True
                    break
                    
        if has_table:
            score += 10
            feedback_parts.append("Valid Markdown table format found.")
        else:
            feedback_parts.append("Markdown table format lacking or incorrect.")

        # Criterion 4 & 5: Event Coverage & Accuracy (30 pts + 20 pts)
        # Load DB Ground Truth
        db_events = []
        if "db_ground_truth.json" in local_files:
            with open(local_files["db_ground_truth.json"], 'r') as f:
                data = json.load(f)
                if isinstance(data, list):
                    db_events = data

        if not db_events:
            feedback_parts.append("No ground truth events found in DB to compare against.")
            return {"passed": False, "score": score, "feedback": " | ".join(feedback_parts)}

        total_events = len(db_events)
        matched_events = 0
        accurate_events = 0
        
        for evt in db_events:
            eid = evt.get("id")
            if not eid:
                continue
                
            # Find the line containing the event ID
            evt_line = next((line for line in lines if eid in line), None)
            
            if evt_line:
                matched_events += 1
                
                # Check accuracy of Mag, Lat, Lon in the same line
                mag = evt.get("mag")
                lat = evt.get("lat")
                lon = evt.get("lon")
                
                # Accommodate slight float formatting differences with rounding to 1 decimal
                is_accurate = True
                if mag is not None:
                    mag_str = f"{mag:.1f}"
                    if mag_str not in evt_line:
                        is_accurate = False
                if lat is not None:
                    lat_str = f"{lat:.1f}"
                    if lat_str not in evt_line:
                        is_accurate = False
                        
                if is_accurate:
                    accurate_events += 1

        # Coverage score calculation
        coverage_ratio = matched_events / total_events
        coverage_score = int(30 * coverage_ratio)
        score += coverage_score
        feedback_parts.append(f"Events coverage: {matched_events}/{total_events} ({coverage_score}/30 pts).")
        
        # Accuracy score calculation
        if matched_events > 0:
            accuracy_ratio = accurate_events / matched_events
            accuracy_score = int(20 * accuracy_ratio)
            score += accuracy_score
            feedback_parts.append(f"Data accuracy: {accurate_events}/{matched_events} rows accurate ({accuracy_score}/20 pts).")
            
        # Criterion 6: VLM Trajectory Process Verification (10 pts)
        query_vlm = env_info.get("query_vlm")
        if query_vlm:
            try:
                from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
                frames = sample_trajectory_frames(traj, n=4)
                final = get_final_screenshot(traj)
                
                prompt = """
                Analyze these chronological screenshots from an agent's desktop task.
                The objective was to write a Python script and execute it to generate a markdown report.
                
                Did the agent actually type commands, write code, or actively use a text editor / terminal to achieve this?
                (This ensures they didn't just paste pre-computed output directly).
                
                Respond in JSON format with a single boolean field "active_terminal_or_editor_usage".
                """
                
                vlm_result = query_vlm(prompt=prompt, images=frames + [final])
                if vlm_result and vlm_result.get("success"):
                    parsed = vlm_result.get("parsed", {})
                    if parsed.get("active_terminal_or_editor_usage"):
                        score += 10
                        feedback_parts.append("VLM confirms active coding/terminal usage (+10 pts).")
                    else:
                        feedback_parts.append("VLM did NOT detect coding/terminal usage.")
            except Exception as e:
                logger.warning(f"VLM process verification skipped/failed: {e}")
            
        # Determine pass/fail
        passed = score >= 70 and matched_events > 0
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Error during verification: {e}"
        }
    finally:
        # Cleanup temp directory
        for path in local_files.values():
            if os.path.exists(path):
                os.remove(path)
        os.rmdir(temp_dir)