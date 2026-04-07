#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_duplicate_retesting_phase(traj, env_info, task_info):
    """
    Verifies that the agent duplicated specific tasks, renamed them,
    and established the correct dependency chain.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Define expectations
    EXPECTED_FILE = "/home/ga/Projects/extended_project.xml"
    TARGET_TASK_1 = "Integration Retesting"
    TARGET_TASK_2 = "Performance Retesting"
    # Original durations in MSPDI format (PT80H = 80 hours, PT40H = 40 hours)
    DURATION_1_HOURS = 80.0
    DURATION_2_HOURS = 40.0
    ANCHOR_MILESTONE_UID = "16" # Project Completion Milestone

    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve verification data: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get("file_exists"):
        return {"passed": False, "score": 0, "feedback": "Output file extended_project.xml was not created."}

    if not result_data.get("created_during_task"):
        return {"passed": False, "score": 0, "feedback": "Output file timestamp indicates it was not created during the task session."}

    # 2. Retrieve and Parse XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(EXPECTED_FILE, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 10, "feedback": f"Failed to parse output XML: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Namespace handling for MSPDI
    ns = {'p': 'http://schemas.microsoft.com/project'}
    
    # Helper to find tasks
    tasks = root.findall(".//p:Task", ns)
    
    task_map = {} # UID -> Task Element
    name_map = {} # Name -> Task Element
    
    for t in tasks:
        uid = t.findtext("p:UID", default="", namespaces=ns)
        name = t.findtext("p:Name", default="", namespaces=ns)
        task_map[uid] = t
        if name:
            name_map[name] = t

    score = 10
    feedback = ["File valid."]

    # Check existence of new tasks
    t1 = name_map.get(TARGET_TASK_1)
    t2 = name_map.get(TARGET_TASK_2)
    
    if t1 is None or t2 is None:
        return {"passed": False, "score": score, "feedback": f"Missing required tasks. Found {TARGET_TASK_1}: {t1 is not None}, {TARGET_TASK_2}: {t2 is not None}"}
    
    score += 20
    feedback.append("New tasks found.")

    # Check durations
    def parse_duration(dur_str):
        # Format usually PT80H0M0S
        try:
            if 'H' in dur_str:
                return float(dur_str.split('PT')[1].split('H')[0])
            return 0.0
        except:
            return 0.0

    d1 = parse_duration(t1.findtext("p:Duration", "", ns))
    d2 = parse_duration(t2.findtext("p:Duration", "", ns))

    dur_ok = True
    if abs(d1 - DURATION_1_HOURS) > 0.1:
        feedback.append(f"{TARGET_TASK_1} duration mismatch (Expected {DURATION_1_HOURS}H, got {d1}H).")
        dur_ok = False
    if abs(d2 - DURATION_2_HOURS) > 0.1:
        feedback.append(f"{TARGET_TASK_2} duration mismatch (Expected {DURATION_2_HOURS}H, got {d2}H).")
        dur_ok = False
        
    if dur_ok:
        score += 20
        feedback.append("Durations correct.")

    # Check Dependencies
    # Chain: Milestone(16) -> T1 -> T2
    
    def get_predecessors(task_elem):
        preds = []
        for link in task_elem.findall("p:PredecessorLink", ns):
            p_uid = link.findtext("p:PredecessorUID", "", ns)
            preds.append(p_uid)
        return preds

    t1_preds = get_predecessors(t1)
    t2_preds = get_predecessors(t2)
    t1_uid = t1.findtext("p:UID", "", ns)
    
    # Check T1 Predecessor (Should be 16)
    if ANCHOR_MILESTONE_UID in t1_preds:
        score += 15
        feedback.append(f"{TARGET_TASK_1} correctly linked to Milestone.")
    else:
        feedback.append(f"{TARGET_TASK_1} NOT linked to Project Milestone (UID {ANCHOR_MILESTONE_UID}). Found: {t1_preds}")

    # Check T2 Predecessor (Should be T1)
    if t1_uid in t2_preds:
        score += 15
        feedback.append(f"{TARGET_TASK_2} correctly linked to {TARGET_TASK_1}.")
    else:
        feedback.append(f"{TARGET_TASK_2} NOT linked to {TARGET_TASK_1} (UID {t1_uid}). Found: {t2_preds}")

    # Anti-gaming: Ensure these are NEW tasks, not the originals renamed
    # Originals were 9 and 10.
    t1_actual_uid = t1.findtext("p:UID", "", ns)
    t2_actual_uid = t2.findtext("p:UID", "", ns)
    
    if t1_actual_uid in ["9", "10"] or t2_actual_uid in ["9", "10"]:
        score = 0
        feedback.append("Anti-gaming failure: You renamed the original tasks instead of duplicating them.")
    else:
        # Check if originals still exist
        orig1 = task_map.get("9")
        orig2 = task_map.get("10")
        if orig1 is not None and orig2 is not None:
             # Basic check to see if originals are preserved
             score += 20
             feedback.append("Original tasks preserved.")
        else:
             feedback.append("Original tasks missing.")

    passed = score >= 75
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }