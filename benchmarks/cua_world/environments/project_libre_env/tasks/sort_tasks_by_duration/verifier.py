#!/usr/bin/env python3
"""
Verifier for sort_tasks_by_duration task.

Verifies:
1. Output XML file exists and is valid.
2. File was created during the task session.
3. Tasks are sorted by duration (Descending).
4. Task IDs have been renumbered (checking logical ID order).
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NS = "http://schemas.microsoft.com/project"

def verify_sort_tasks_by_duration(traj, env_info, task_info):
    """
    Verify that the user sorted tasks by duration descending and renumbered them.
    """
    # 1. Setup and Environment Check
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Environment error: copy function missing"}

    score = 0
    feedback_parts = []
    
    # Load result JSON from the container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Check File Existence and Timestamp (Anti-gaming)
    if not result_data.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file sorted_risk_review.xml not found."}
    
    score += 10 # File exists
    
    if not result_data.get("file_created_during_task", False):
        feedback_parts.append("Warning: Output file timestamp is older than task start.")
        # We penalize heavily for pre-existing files
        return {"passed": False, "score": 10, "feedback": "File exists but was not created during this task session."}
    
    score += 10 # File created recently
    
    # 3. Retrieve and Parse the XML File
    remote_path = result_data["output_path"]
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        copy_from_env(remote_path, temp_xml.name)
        
        # Parse XML
        try:
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Output file is not valid XML."}
            
        tasks_elem = root.find(f"{{{NS}}}Tasks")
        if tasks_elem is None:
            return {"passed": False, "score": score, "feedback": "XML does not contain Tasks element."}
        
        # Build a map of Task Name -> Task ID (integer)
        # Note: In MSPDI, <ID> is the display ID (row number), <UID> is the unique ID.
        # "Permanently renumber" changes the <ID> to match the new sort order.
        task_map = {}
        all_tasks = []
        
        for task in tasks_elem.findall(f"{{{NS}}}Task"):
            name = task.findtext(f"{{{NS}}}Name", "")
            tid_str = task.findtext(f"{{{NS}}}ID", "")
            
            if name and tid_str:
                try:
                    tid = int(tid_str)
                    task_map[name] = tid
                    all_tasks.append(tid)
                except ValueError:
                    continue

        score += 10 # XML parsed successfully

        # 4. Verify Sorting Logic
        # We check specific pairs defined in metadata
        check_pairs = task_info.get("metadata", {}).get("check_pairs", [])
        
        # If metadata is missing, use defaults
        if not check_pairs:
            check_pairs = [
                {"long_task": "Backend API Development", "short_task": "System Architecture Design"},
                {"long_task": "Frontend Development", "short_task": "Requirements Gathering"}
            ]

        pairs_correct = 0
        total_pairs = len(check_pairs)
        
        for pair in check_pairs:
            long_name = pair["long_task"]
            short_name = pair["short_task"]
            
            if long_name in task_map and short_name in task_map:
                long_id = task_map[long_name]
                short_id = task_map[short_name]
                
                # In a descending sort, longer tasks should appear EARLIER (Lower ID)
                if long_id < short_id:
                    pairs_correct += 1
                    feedback_parts.append(f"✓ '{long_name}' (ID {long_id}) correctly sorted above '{short_name}' (ID {short_id}).")
                else:
                    feedback_parts.append(f"✗ '{long_name}' (ID {long_id}) should be above '{short_name}' (ID {short_id}).")
            else:
                feedback_parts.append(f"Missing tasks in XML: {long_name} or {short_name}.")

        # Award points for sorting
        if total_pairs > 0:
            sort_points = (pairs_correct / total_pairs) * 60
            score += sort_points
        else:
            score += 60 # Fallback if no pairs to check (unlikely)

        # 5. Verify "Permanently Renumber" (IDs should be sequential)
        # If tasks were sorted but NOT renumbered, the IDs would be jumpy (e.g. 6, 2, 7, 1...)
        # If renumbered, IDs should be roughly sequential 1, 2, 3... or at least monotonic
        # We assume the file writes tasks in order. If IDs are renumbered, ID matches file index.
        # Simple check: Is "Backend API Development" ID small? (It was 6 originally, should be smaller now)
        # Actually, the pair check implicitly verifies renumbering because if they weren't renumbered,
        # Backend (Orig ID 6) would still be > System Arch (Orig ID 2).
        # Since Backend (120h) > System Arch (64h), a descending sort puts Backend first.
        # IF renumbered: Backend ID becomes e.g. 2, System Arch becomes e.g. 4. (2 < 4) - PASS
        # IF NOT renumbered: Backend ID stays 6, System Arch stays 2. (6 > 2) - FAIL
        # Therefore, the pair check covers the renumbering requirement logic.
        
        # Explicit check for structure preservation
        if len(task_map) >= 15:
            score += 10
            feedback_parts.append("Project structure preserved (task count valid).")
        else:
            feedback_parts.append("Project seems to have lost tasks.")

    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error processing XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": int(score),
        "feedback": " ".join(feedback_parts)
    }