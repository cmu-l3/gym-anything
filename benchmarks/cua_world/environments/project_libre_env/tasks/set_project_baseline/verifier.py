#!/usr/bin/env python3
"""
Verifier for set_project_baseline task.

Criteria:
1. Output file exists and was created during the task.
2. Output file is valid XML.
3. XML contains Baseline data for tasks (ProjectLibre MSPDI format).
4. VLM verification of UI interaction (Set Baseline dialog).
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Tuple

# Import VLM utilities from the environment
try:
    from gym_anything.vlm import sample_trajectory_frames, query_vlm
except ImportError:
    # Mock for testing if environment not available
    def sample_trajectory_frames(traj, n=5): return []
    def query_vlm(images, prompt): return {"success": False, "error": "VLM not available"}

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NS = "http://schemas.microsoft.com/project"

def _parse_mspdi_baseline(xml_path: str) -> Tuple[bool, int, int, str]:
    """
    Parses MSPDI XML to count tasks with baseline data.
    Returns: (is_valid_xml, total_tasks, tasks_with_baseline, error_msg)
    """
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        # Handle namespaces if present (ProjectLibre usually adds xmlns)
        # We'll search with and without namespace to be robust
        tasks_elem = root.find(f"{{{NS}}}Tasks")
        if tasks_elem is None:
            tasks_elem = root.find("Tasks")
            
        if tasks_elem is None:
            return True, 0, 0, "No <Tasks> element found"
            
        total_tasks = 0
        tasks_with_baseline = 0
        
        for task in tasks_elem:
            # Skip summary project task if it doesn't look like a normal task, 
            # but usually we count all to be safe.
            # ProjectLibre often includes a root task.
            total_tasks += 1
            
            # Check for Baseline data
            # ProjectLibre MSPDI often uses <Baseline><Number>0</Number>...</Baseline>
            # Or direct fields like <BaselineStart> (less common in MSPDI but possible)
            
            has_baseline = False
            
            # Strategy 1: Look for Baseline elements
            baselines = task.findall(f"{{{NS}}}Baseline") + task.findall("Baseline")
            for bl in baselines:
                # Check if it has data (Start/Finish/Duration)
                # Baseline 0 is the primary baseline
                bl_num = bl.findtext(f"{{{NS}}}Number") or bl.findtext("Number")
                if bl_num == "0":
                    start = bl.findtext(f"{{{NS}}}Start") or bl.findtext("Start")
                    finish = bl.findtext(f"{{{NS}}}Finish") or bl.findtext("Finish")
                    if start or finish:
                        has_baseline = True
                        break
            
            # Strategy 2: Look for flat Baseline fields (legacy support)
            if not has_baseline:
                bl_start = task.findtext(f"{{{NS}}}BaselineStart") or task.findtext("BaselineStart")
                if bl_start and "T" in bl_start: # Simple check for timestamp format
                    has_baseline = True

            if has_baseline:
                tasks_with_baseline += 1
                
        return True, total_tasks, tasks_with_baseline, ""
        
    except ET.ParseError as e:
        return False, 0, 0, f"XML Parse Error: {str(e)}"
    except Exception as e:
        return False, 0, 0, f"Error processing XML: {str(e)}"

def verify_set_project_baseline(traj, env_info, task_info):
    """
    Verifies that the agent set the project baseline and saved the file.
    """
    # 1. Setup and Copy Files
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System Error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/baseline_project.xml')
    min_coverage = metadata.get('min_baseline_coverage_percent', 75) / 100.0

    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json').name
    temp_xml_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xml').name

    try:
        # Get result JSON
        try:
            copy_from_env("/tmp/task_result.json", temp_result_json)
            with open(temp_result_json, 'r') as f:
                result_data = json.load(f)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Could not retrieve task execution results."}

        # Basic Checks (15 pts)
        output_exists = result_data.get("output_exists", False)
        created_during = result_data.get("file_created_during_task", False)
        initial_hash = result_data.get("initial_hash", "")
        output_hash = result_data.get("output_hash", "")

        score = 0
        feedback = []

        if not output_exists:
            return {"passed": False, "score": 0, "feedback": "The output file baseline_project.xml was not found."}
        
        score += 10 # File exists
        feedback.append("Output file created.")

        if created_during:
            score += 5 # Created during task
        else:
            feedback.append("Warning: File timestamp suggests it wasn't created during the task session.")

        if initial_hash == output_hash:
            feedback.append("Warning: Output file is identical to the input. Baseline likely not set.")
        else:
            score += 5 # File modified
            
        # 2. XML Content Verification (50 pts)
        try:
            copy_from_env(expected_path, temp_xml_file)
            is_valid, total_tasks, tasks_with_bl, err_msg = _parse_mspdi_baseline(temp_xml_file)
            
            if not is_valid:
                feedback.append(f"Output file is not valid XML: {err_msg}")
            else:
                score += 10 # Valid XML
                
                if total_tasks > 0:
                    coverage = tasks_with_bl / total_tasks
                    feedback.append(f"Baseline coverage: {tasks_with_bl}/{total_tasks} tasks ({coverage:.1%}).")
                    
                    if coverage >= min_coverage:
                        score += 40 # Passed baseline check
                    elif coverage > 0:
                        score += int(40 * coverage) # Partial credit
                        feedback.append("Baseline not set for all tasks.")
                    else:
                        feedback.append("No baseline data found in the file.")
                else:
                    feedback.append("XML file contains no tasks.")
                    
        except Exception as e:
            feedback.append(f"Failed to inspect output file: {str(e)}")

        # 3. VLM Verification (30 pts)
        # Check for "Set Baseline" dialog interaction
        frames = sample_trajectory_frames(traj, n=8)
        
        vlm_prompt = """
        Review this sequence of screenshots from ProjectLibre.
        I am looking for evidence that the user opened the 'Set Baseline' dialog.
        
        Look for:
        1. A popup window titled "Set Baseline".
        2. A menu interaction selecting "Baseline" or "Set Baseline".
        3. A dialog asking to "Save Baseline" for "Entire Project" or "Selected Tasks".
        
        Return JSON:
        {
            "baseline_dialog_visible": true/false,
            "save_dialog_visible": true/false,
            "confidence": "low/medium/high"
        }
        """
        
        vlm_res = query_vlm(images=frames, prompt=vlm_prompt)
        vlm_score = 0
        if vlm_res.get("success"):
            parsed = vlm_res.get("parsed", {})
            if parsed.get("baseline_dialog_visible"):
                vlm_score = 30
                feedback.append("Visual confirmation: Set Baseline dialog detected.")
            elif parsed.get("save_dialog_visible"):
                vlm_score = 15
                feedback.append("Visual confirmation: Save/Export dialog detected, but Baseline dialog ambiguous.")
            else:
                feedback.append("No visual evidence of Set Baseline dialog found.")
        
        score += vlm_score

        # Final pass determination
        # Must have valid XML with baseline data to pass
        passed = (tasks_with_bl > 0) and (score >= 60)

        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    finally:
        # Cleanup
        if os.path.exists(temp_result_json):
            os.unlink(temp_result_json)
        if os.path.exists(temp_xml_file):
            os.unlink(temp_xml_file)