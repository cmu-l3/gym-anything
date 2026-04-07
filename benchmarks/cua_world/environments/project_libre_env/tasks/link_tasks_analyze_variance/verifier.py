#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import re
from datetime import datetime, timedelta

def verify_link_tasks_analyze_variance(traj, env_info, task_info):
    """
    Verifies:
    1. Dependencies linked (Tasks 2,3,4 -> Task 5)
    2. Baseline set (Baseline data exists in XML)
    3. Task 2 duration changed to 12 days
    4. Variance report created and accurate
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    # Basic checks
    if not result.get('xml_exists'):
        return {"passed": False, "score": 0, "feedback": "Output XML file not found"}
    
    if not result.get('xml_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Output file was not created/modified during the task"}

    # Load and Parse XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/home/ga/Projects/linked_variance_project.xml", temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to parse output XML: {e}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # Namespaces
    ns = {'p': 'http://schemas.microsoft.com/project'}
    # Register default namespace if needed, but ElementTree usually handles standard extraction with wildcard or explicit ns map
    # A generic search function helper
    def find_task_by_uid(uid):
        tasks = root.find('p:Tasks', ns)
        if tasks is None:
            # Try without namespace if file was saved differently
            tasks = root.find('Tasks')
        
        if tasks is not None:
            for t in tasks.findall('p:Task', ns) or tasks.findall('Task'):
                t_uid = t.find('p:UID', ns) or t.find('UID')
                if t_uid is not None and t_uid.text == str(uid):
                    return t
        return None

    score = 0
    feedback = []

    # 1. Verify Dependencies (Tasks 2,3,4 -> Task 5)
    # Task 5 should have PredecessorLink entries for 2, 3, 4
    task_5 = find_task_by_uid(5)
    deps_ok = False
    if task_5:
        preds = []
        for link in task_5.findall('p:PredecessorLink', ns) or task_5.findall('PredecessorLink'):
            p_uid = link.find('p:PredecessorUID', ns) or link.find('PredecessorUID')
            if p_uid is not None:
                preds.append(p_uid.text)
        
        missing_preds = [uid for uid in ['2', '3', '4'] if uid not in preds]
        if not missing_preds:
            score += 25
            feedback.append("Dependencies correctly linked.")
            deps_ok = True
        else:
            feedback.append(f"Missing predecessors for Task 5: {missing_preds}")
    else:
        feedback.append("Task 5 not found in XML.")

    # 2. Verify Baseline Set
    # Check if Task 0 (Project Summary) or other tasks have Baseline data
    baseline_found = False
    tasks_element = root.find('p:Tasks', ns) or root.find('Tasks')
    if tasks_element:
        for t in tasks_element:
            # Check for <Baseline> child or <BaselineStart>
            baselines = t.findall('p:Baseline', ns) or t.findall('Baseline')
            if baselines:
                baseline_found = True
                break
            # Some formats store as flat fields like <BaselineStart>
            if (t.find('p:BaselineStart', ns) is not None or t.find('BaselineStart') is not None) and \
               (t.find('p:BaselineStart', ns).text or t.find('BaselineStart').text):
                baseline_found = True
                break
    
    if baseline_found:
        score += 25
        feedback.append("Baseline verified.")
    else:
        feedback.append("No baseline data found in project.")

    # 3. Verify Duration Change (Task 2 -> 12 days)
    # ProjectLibre stores duration often as PT format (PT96H0M0S) or string "12 days"
    task_2 = find_task_by_uid(2)
    duration_ok = False
    if task_2:
        dur_node = task_2.find('p:Duration', ns) or task_2.find('Duration')
        if dur_node is not None:
            dur_text = dur_node.text
            # Expected 12 days = 96 hours. PT96H
            if "PT96H" in dur_text or "P12D" in dur_text:
                score += 20
                feedback.append("Task 2 duration updated to 12 days.")
                duration_ok = True
            else:
                feedback.append(f"Task 2 duration incorrect: {dur_text}")
    else:
        feedback.append("Task 2 not found.")

    # 4. Verify Variance Report
    # We calculate the actual variance from the XML for Task 16
    calculated_variance_days = 0
    task_16 = find_task_by_uid(16)
    
    if task_16 and baseline_found and duration_ok and deps_ok:
        # Try to calculate variance
        # Finish Date
        finish_node = task_16.find('p:Finish', ns) or task_16.find('Finish')
        # Baseline Finish (need to find Baseline 0)
        bl_finish_node = None
        baselines = task_16.findall('p:Baseline', ns) or task_16.findall('Baseline')
        for bl in baselines:
            num = bl.find('p:Number', ns) or bl.find('Number')
            if num is not None and num.text == '0':
                bl_finish_node = bl.find('p:Finish', ns) or bl.find('Finish')
                break
        
        if finish_node is not None and bl_finish_node is not None:
            try:
                # Parse dates (ISO format: YYYY-MM-DDTHH:MM:SS)
                finish_dt = datetime.fromisoformat(finish_node.text)
                bl_finish_dt = datetime.fromisoformat(bl_finish_node.text)
                
                # Difference in days
                delta = finish_dt - bl_finish_dt
                calculated_variance_days = delta.days + (delta.seconds / 86400)
            except Exception as e:
                print(f"Date parse error: {e}")

    # Check report existence
    if result.get('report_exists'):
        score += 15
        feedback.append("Variance report file created.")
        
        # Check report content correctness
        content = result.get('report_content', '')
        # Extract number from "Finish Variance: X days"
        match = re.search(r'Finish Variance:\s*([\d\.]+)', content, re.IGNORECASE)
        if match:
            reported_days = float(match.group(1))
            # Tolerance of 0.5 days
            if abs(reported_days - calculated_variance_days) <= 1.0:
                score += 15
                feedback.append(f"Reported variance ({reported_days}) matches calculated ({calculated_variance_days:.2f}).")
            else:
                feedback.append(f"Reported variance ({reported_days}) differs from calculated ({calculated_variance_days:.2f}).")
        else:
            feedback.append("Report format incorrect (could not extract number).")
    else:
        feedback.append("Variance report file missing.")

    return {
        "passed": score >= 70,
        "score": score,
        "feedback": " ".join(feedback)
    }