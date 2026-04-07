#!/usr/bin/env python3
"""
Verifier for level_resources task in ProjectLibre.
Verifies that the agent has resolved resource over-allocations by leveling the project.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for MSPDI XML
NS = {'p': 'http://schemas.microsoft.com/project'}

def parse_mspdi_date(date_str):
    """Parses MSPDI date string (YYYY-MM-DDTHH:MM:SS) to datetime object."""
    if not date_str:
        return None
    try:
        return datetime.strptime(date_str, "%Y-%m-%dT%H:%M:%S")
    except ValueError:
        return None

def verify_level_resources(traj, env_info, task_info):
    """
    Verifies the resource leveling task.
    
    Criteria:
    1. Output file exists and is valid XML (20 pts)
    2. File was created during task session (5 pts)
    3. Alice's concurrent tasks (UID 3, 4) are staggered (20 pts)
    4. Emma's concurrent tasks (UID 8, 9) are staggered (20 pts)
    5. Project finish date is not earlier than original (ensures valid scheduling) (10 pts)
    6. Task count preserved (sanity check) (15 pts)
    7. VLM: Leveling dialog seen (10 pts)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    # Get Metadata
    metadata = task_info.get('metadata', {})
    conflicts = metadata.get('conflicts', [])
    min_task_count = metadata.get('min_task_count', 10)
    
    # 1. Retrieve JSON result
    result_data = {}
    with tempfile.NamedTemporaryFile(suffix='.json') as f:
        try:
            copy_from_env('/tmp/task_result.json', f.name)
            f.seek(0)
            result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Could not retrieve task result: {e}"}

    if not result_data.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Leveled project file not found."}

    # 2. Retrieve and Parse XML
    score = 0
    feedback = []
    
    xml_path = result_data.get('output_path')
    tree = None
    root = None
    
    with tempfile.NamedTemporaryFile(suffix='.xml') as xml_f:
        try:
            copy_from_env(xml_path, xml_f.name)
            xml_f.seek(0)
            tree = ET.parse(xml_f.name)
            root = tree.getroot()
            score += 20
            feedback.append("Valid XML file saved.")
        except ET.ParseError:
            return {"passed": False, "score": score, "feedback": "Saved file is not valid XML."}
        except Exception as e:
            return {"passed": False, "score": score, "feedback": f"Error reading XML: {e}"}

    # Anti-gaming check
    if result_data.get('file_modified_during_task'):
        score += 5
    else:
        feedback.append("Warning: File not modified during task time.")

    # 3. Analyze Tasks and Dates
    tasks = root.findall('.//p:Task', NS)
    task_map = {} # UID -> {Start, Finish, Name}
    
    for t in tasks:
        uid = t.findtext('p:UID', '', NS)
        name = t.findtext('p:Name', '', NS)
        start = parse_mspdi_date(t.findtext('p:Start', '', NS))
        finish = parse_mspdi_date(t.findtext('p:Finish', '', NS))
        
        if uid and start:
            task_map[uid] = {'name': name, 'start': start, 'finish': finish}

    # Check Task Count
    if len(task_map) >= min_task_count:
        score += 15
        feedback.append(f"Task count preserved ({len(task_map)} tasks).")
    else:
        feedback.append(f"Task count too low ({len(task_map)}), expected >{min_task_count}.")

    # 4. Check Conflicts (Staggering)
    # Logic: For each resource, the specified tasks must NOT have the same Start date
    # In the original file, they start exactly at the same time.
    # Leveling should push one out.
    
    # Alice (UID 3 & 4)
    alice_resolved = False
    try:
        t3 = task_map.get('3')
        t4 = task_map.get('4')
        if t3 and t4:
            if t3['start'] != t4['start']:
                alice_resolved = True
                score += 20
                feedback.append("Alice's tasks leveled (staggered start times).")
            else:
                feedback.append("Alice's tasks still start at the same time (conflict not resolved).")
    except Exception:
        pass

    # Emma (UID 8 & 9)
    emma_resolved = False
    try:
        t8 = task_map.get('8')
        t9 = task_map.get('9')
        if t8 and t9:
            if t8['start'] != t9['start']:
                emma_resolved = True
                score += 20
                feedback.append("Emma's tasks leveled (staggered start times).")
            else:
                feedback.append("Emma's tasks still start at the same time (conflict not resolved).")
    except Exception:
        pass

    # 5. Check Project Finish Date
    # Original finish was ~April 18 (2025-04-18)
    # Leveling usually extends the project.
    # We check if project finish >= original finish.
    # If they just deleted tasks or shortened durations, this might fail (depending on implementation),
    # but primarily we want to ensure valid scheduling logic.
    original_finish = datetime(2025, 4, 18)
    project_finish_elem = root.find('.//p:FinishDate', NS)
    current_finish = parse_mspdi_date(project_finish_elem.text) if project_finish_elem is not None else None
    
    if current_finish and current_finish >= original_finish:
        score += 10
        feedback.append("Project finish date is valid (schedule integrity maintained).")
    elif current_finish:
        feedback.append(f"Warning: Project finishes earlier than original ({current_finish}).")
    
    # 6. VLM Check (Leveling Dialog)
    # Optional but adds robustness.
    # We'll import standard VLM tools if available.
    try:
        from gym_anything.vlm import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = "Is a 'Resource Leveling' or 'Level Resources' dialog box visible in any of these frames?"
        vlm_res = query_vlm(images=frames, prompt=prompt)
        
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('answer', False):
            score += 10
            feedback.append("VLM confirmed usage of Leveling dialog.")
        else:
            # Fallback points if programmatic checks pass strongly
            if alice_resolved and emma_resolved:
                score += 10
                feedback.append("VLM inconclusive, but result verifies action.")
    except ImportError:
        # If VLM utils not available, grant points if result is good
        if alice_resolved and emma_resolved:
            score += 10

    # Final Verification
    passed = score >= 60 and (alice_resolved or emma_resolved)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }