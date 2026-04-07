#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import datetime
from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot

def verify_perform_earned_value_analysis(traj, env_info, task_info):
    """
    Verifies that the agent performed the EVM workflow correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_status_date = metadata.get('expected_status_date', '2025-02-10')
    progress_reqs = metadata.get('progress_requirements', {})
    
    score = 0
    feedback = []
    
    # 1. Retrieve Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify PDF Report Existence (15 pts)
    pdf_info = result_data.get('pdf_report', {})
    if pdf_info.get('exists') and pdf_info.get('created_during_task'):
        score += 15
        feedback.append("Earned Value PDF report generated.")
    elif pdf_info.get('exists'):
        score += 5 # Partial credit if old file (unlikely) or timestamps weird
        feedback.append("PDF report exists but timestamp matches pre-task.")
    else:
        feedback.append("Earned Value PDF report NOT found.")

    # 3. Verify XML File Existence (15 pts)
    xml_info = result_data.get('xml_file', {})
    if not xml_info.get('exists'):
        return {"passed": False, "score": score, "feedback": "Project XML file NOT saved. " + " ".join(feedback)}
    
    score += 15
    feedback.append("Project XML file saved.")

    # 4. Parse XML Content
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env("/tmp/result_project.xml", temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
        
        # XML Namespace usually http://schemas.microsoft.com/project
        # But we handle namespace broadly
        ns = {'p': 'http://schemas.microsoft.com/project'}
        
        # A. Verify Status Date (20 pts)
        # Format usually YYYY-MM-DDTHH:MM:SS
        status_date_elem = root.find('.//p:StatusDate', ns)
        if status_date_elem is None:
            # Try without namespace if failed
            status_date_elem = root.find('.//StatusDate')
            
        status_date_correct = False
        if status_date_elem is not None and status_date_elem.text:
            sd_text = status_date_elem.text
            if expected_status_date in sd_text:
                score += 20
                status_date_correct = True
                feedback.append(f"Status date correct ({expected_status_date}).")
            else:
                feedback.append(f"Status date incorrect. Found: {sd_text}, Expected: {expected_status_date}.")
        else:
            feedback.append("Status date not set in project.")

        # B. Verify Baseline Existence (20 pts)
        # Check if tasks have Baseline data. 
        # Structure: <Task>...<Baseline><Number>0</Number>...</Baseline>...</Task>
        # We check if at least 5 tasks have baselines
        baseline_count = 0
        tasks = root.findall('.//p:Task', ns)
        if not tasks:
            tasks = root.findall('.//Task')
            
        for t in tasks:
            baselines = t.findall('.//p:Baseline', ns) or t.findall('.//Baseline')
            if baselines:
                baseline_count += 1
        
        if baseline_count > 5:
            score += 20
            feedback.append("Project baseline verification passed.")
        else:
            feedback.append("Project baseline NOT found (or insufficient tasks baselined).")

        # C. Verify Progress Updates (30 pts)
        # 100% Tasks: 1, 2, 3, 4, 5, 8
        # 70% Tasks: 6, 7
        progress_score = 0
        total_checks = len(progress_reqs.get("100", [])) + len(progress_reqs.get("70", []))
        passed_checks = 0
        
        for uid in progress_reqs.get("100", []):
            task_found = False
            for t in tasks:
                t_uid = t.find('p:UID', ns) if t.find('p:UID', ns) is not None else t.find('UID')
                if t_uid is not None and t_uid.text == str(uid):
                    pct = t.find('p:PercentComplete', ns) if t.find('p:PercentComplete', ns) is not None else t.find('PercentComplete')
                    if pct is not None and int(pct.text) == 100:
                        passed_checks += 1
                    task_found = True
                    break
        
        for uid in progress_reqs.get("70", []):
            task_found = False
            for t in tasks:
                t_uid = t.find('p:UID', ns) if t.find('p:UID', ns) is not None else t.find('UID')
                if t_uid is not None and t_uid.text == str(uid):
                    pct = t.find('p:PercentComplete', ns) if t.find('p:PercentComplete', ns) is not None else t.find('PercentComplete')
                    # Allow slight tolerance if manual entry (e.g., 69-71)
                    if pct is not None and 69 <= int(pct.text) <= 71:
                        passed_checks += 1
                    task_found = True
                    break

        # Calculate progress score
        if total_checks > 0:
            progress_score = int((passed_checks / total_checks) * 30)
            score += progress_score
            feedback.append(f"Progress updates: {passed_checks}/{total_checks} tasks correct.")

    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Saved XML file is corrupted/invalid."}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error verifying XML: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 5. Pass Threshold
    # Must have Status Date + Baseline + Report + Some Progress
    passed = score >= 70 and status_date_correct and baseline_count > 5
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }