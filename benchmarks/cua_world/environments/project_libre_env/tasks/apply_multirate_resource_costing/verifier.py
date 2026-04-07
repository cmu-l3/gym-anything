#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging
import sys

# Add VLM support if available in environment
try:
    from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot, query_vlm
    VLM_AVAILABLE = True
except ImportError:
    VLM_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

NS = "http://schemas.microsoft.com/project"

def verify_multirate_costing(traj, env_info, task_info):
    """
    Verifies that:
    1. Output XML file exists and is valid.
    2. Alice Johnson has a Rate Table B (index 1) with Rate 150.
    3. Alice is assigned to 'Security Audit'.
    4. The assignment uses Rate Table 1 (B).
    5. The assignment cost is correct ($6000).
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Projects/security_audit_costing.xml')
    
    # Load basic result info
    result_info = {}
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_info = json.load(f)
    except Exception:
        pass  # If file missing, handle below
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_info.get('file_exists', False):
        return {"passed": False, "score": 0, "feedback": f"Output file not found at {expected_path}"}

    if not result_info.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task session"}

    # Retrieve and Parse XML
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except ET.ParseError:
        return {"passed": False, "score": 10, "feedback": "Output file exists but is not valid XML"}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read output file: {str(e)}"}
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    score = 10  # Base score for valid file
    feedback = []

    # 1. Find Resources
    alice_uid = None
    rate_b_found = False
    rate_b_value = 0.0

    resources = root.find(f'{{{NS}}}Resources')
    if resources is not None:
        for res in resources.findall(f'{{{NS}}}Resource'):
            name = res.findtext(f'{{{NS}}}Name', '')
            if 'Alice Johnson' in name:
                alice_uid = res.findtext(f'{{{ns}}}UID') if 'ns' in locals() else res.findtext(f'{{{NS}}}UID')
                # Check rates
                for rate in res.findall(f'{{{NS}}}Rate'):
                    # MSPDI: RateTable 0=A, 1=B, etc.
                    table_idx = rate.findtext(f'{{{NS}}}RateTable')
                    std_rate = rate.findtext(f'{{{NS}}}StandardRate')
                    if table_idx == '1' and std_rate:
                        rate_b_found = True
                        try:
                            rate_b_value = float(std_rate)
                        except:
                            pass
                break
    
    if not alice_uid:
        return {"passed": False, "score": score, "feedback": "Resource 'Alice Johnson' not found in project"}

    if rate_b_found and abs(rate_b_value - 150.0) < 0.1:
        score += 25
        feedback.append("Rate Table B correctly configured ($150/hr)")
    elif rate_b_found:
        score += 10
        feedback.append(f"Rate Table B found but value is ${rate_b_value} (expected $150)")
    else:
        feedback.append("Rate Table B not defined for Alice Johnson")

    # 2. Find Task
    task_uid = None
    tasks = root.find(f'{{{NS}}}Tasks')
    if tasks is not None:
        for t in tasks.findall(f'{{{NS}}}Task'):
            if 'Security Audit' in t.findtext(f'{{{NS}}}Name', ''):
                task_uid = t.findtext(f'{{{NS}}}UID')
                break
    
    if not task_uid:
        return {"passed": False, "score": score, "feedback": "Task 'Security Audit' not found"}

    # 3. Check Assignment
    assignment_found = False
    rate_table_used = None
    cost = 0.0
    
    assignments = root.find(f'{{{NS}}}Assignments')
    if assignments is not None:
        for asn in assignments.findall(f'{{{NS}}}Assignment'):
            t_id = asn.findtext(f'{{{NS}}}TaskUID')
            r_id = asn.findtext(f'{{{NS}}}ResourceUID')
            if t_id == task_uid and r_id == alice_uid:
                assignment_found = True
                rate_table_used = asn.findtext(f'{{{NS}}}RateTable')
                try:
                    cost = float(asn.findtext(f'{{{NS}}}Cost', '0'))
                except:
                    pass
                break

    if assignment_found:
        score += 15
        feedback.append("Resource assigned to task correctly")
        
        # Check Rate Table Usage
        # Note: MSPDI uses '1' for Rate Table B (0-indexed usually, A=0, B=1)
        if rate_table_used == '1':
            score += 30
            feedback.append("Assignment uses Rate Table B")
        else:
            feedback.append(f"Assignment uses Rate Table {rate_table_used} (Expected '1' for Table B)")

        # Check Cost
        # 40 hours * $150 = 6000
        if abs(cost - 6000.0) < 10.0:
            score += 20
            feedback.append("Assignment cost matches expected $6,000")
        else:
            feedback.append(f"Assignment cost is ${cost} (Expected $6,000)")
    else:
        feedback.append("Alice Johnson is NOT assigned to 'Security Audit'")

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": "; ".join(feedback)
    }