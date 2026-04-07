#!/usr/bin/env python3
"""
Verifier for add_calendar_holidays task.

Verification Strategy:
1. Programmatic:
   - Check if output XML file exists and was created during the task.
   - Parse XML to verify calendar exceptions for:
     - Feb 17, 2025 (Presidents' Day)
     - May 26, 2025 (Memorial Day)
   - Verify exceptions are marked as non-working (DayWorking=0).

2. VLM (Visual):
   - Analyze trajectory frames to confirm the "Calendar" or "Working Time" dialog was accessed.
   - Confirm agent navigated to specific months.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET
from datetime import datetime

# Import VLM utilities from the framework
from gym_anything.vlm import sample_trajectory_frames, query_vlm

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_project_xml(xml_path):
    """
    Parses MSPDI XML and extracts calendar exceptions.
    Returns a list of dicts: {'from': 'YYYY-MM-DD', 'working': bool, 'name': str}
    """
    exceptions = []
    try:
        tree = ET.parse(xml_path)
        root = tree.getroot()
        
        # Namespaces can be tricky in MSPDI; typically http://schemas.microsoft.com/project
        # We'll try to handle with and without explicit namespace
        ns = {'p': 'http://schemas.microsoft.com/project'}
        
        # Find all calendars. Usually there is a base calendar (Standard)
        # We search all exceptions in all calendars to be generous
        # (The project might define exceptions on the Resource or Project calendar)
        
        # Try finding elements with namespace
        all_exceptions = root.findall(".//p:Exception", ns)
        if not all_exceptions:
            # Try without namespace if parse failed to register it
            all_exceptions = root.findall(".//Exception")
            
        for exc in all_exceptions:
            # Extract FromDate
            from_date_node = exc.find("p:TimePeriod/p:FromDate", ns)
            if from_date_node is None:
                from_date_node = exc.find(".//FromDate")
            
            # Extract DayWorking
            day_working_node = exc.find("p:DayWorking", ns)
            if day_working_node is None:
                day_working_node = exc.find("DayWorking")
                
            # Extract Name (Optional)
            name_node = exc.find("p:Name", ns)
            if name_node is None:
                name_node = exc.find("Name")
                
            if from_date_node is not None and from_date_node.text:
                # MSPDI dates are usually YYYY-MM-DDTHH:MM:SS
                date_str = from_date_node.text.split('T')[0]
                
                is_working = False
                if day_working_node is not None and day_working_node.text == '1':
                    is_working = True
                
                name = name_node.text if name_node is not None else ""
                
                exceptions.append({
                    'date': date_str,
                    'working': is_working,
                    'name': name
                })
                
    except Exception as e:
        logger.error(f"Failed to parse XML: {e}")
        return None
        
    return exceptions

def verify_add_calendar_holidays(traj, env_info, task_info):
    """
    Main verification function.
    """
    # 1. Setup helpers
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    expected_holidays = metadata.get('expected_holidays', [])
    output_path = metadata.get('output_path', "/home/ga/Projects/output/project_with_holidays.xml")

    # 2. Copy artifacts from container
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    
    try:
        # Get metadata JSON
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_meta = json.load(f)
            
        # Get output XML
        xml_copied = False
        if result_meta.get("output_exists", False):
            try:
                copy_from_env(output_path, temp_xml.name)
                xml_copied = True
            except Exception as e:
                logger.error(f"Could not copy output XML despite existence: {e}")

        # 3. Evaluate Programmatic Criteria
        score = 0
        feedback = []
        
        # Criterion 1: Output file exists (10 pts)
        if result_meta.get("output_exists"):
            score += 10
            feedback.append("Output file exists.")
        else:
            feedback.append("Output file missing.")
            return {"passed": False, "score": 0, "feedback": "Output file not found."}

        # Criterion 2: Anti-gaming (File created during task) (10 pts)
        if result_meta.get("file_created_during_task"):
            score += 10
        else:
            feedback.append("Warning: Output file timestamp indicates it wasn't created during this session.")
            # We don't fail immediately but penalize score heavily

        # Criterion 3: Valid XML Content (20 pts each holiday)
        holidays_found = 0
        if xml_copied:
            found_exceptions = parse_project_xml(temp_xml.name)
            if found_exceptions is not None:
                for target in expected_holidays:
                    target_date = target['date']
                    # Look for a match
                    match = next((e for e in found_exceptions if e['date'] == target_date), None)
                    
                    if match:
                        if not match['working']:
                            score += 20
                            holidays_found += 1
                            feedback.append(f"✓ Correctly marked {target_date} ({target['name']}) as non-working.")
                        else:
                            feedback.append(f"✗ Found entry for {target_date}, but it is marked as WORKING time.")
                    else:
                        feedback.append(f"✗ No calendar exception found for {target_date}.")
            else:
                feedback.append("Output file is not valid XML or could not be parsed.")
        
        # 4. VLM Verification (Trajectory Analysis) (40 pts)
        # We want to verify the agent actually interacted with the calendar UI
        vlm_score = 0
        
        frames = sample_trajectory_frames(traj, n=4)
        if not frames:
            feedback.append("No trajectory frames available for VLM verification.")
        else:
            prompt = """
            Analyze these screenshots of the user using ProjectLibre.
            I am looking for evidence that the user modified the Project Calendar.
            
            Look for:
            1. A dialog box titled "Change Working Time", "Calendar", or similar.
            2. A calendar grid showing months (specifically February or May).
            3. Radio buttons or options for "Non-working time" or "Non-default working time".
            
            Did the user open a calendar/working-time settings dialog?
            Answer yes/no and provide confidence (low/medium/high).
            """
            
            try:
                vlm_resp = query_vlm(images=frames, prompt=prompt)
                parsed = vlm_resp.get("parsed", {})
                # Simple parsing fallback if specific VLM format differs
                content = str(vlm_resp).lower()
                
                if "yes" in content or parsed.get("answer", "").lower() == "yes":
                    vlm_score = 40
                    feedback.append("VLM confirms Calendar settings dialog was accessed.")
                else:
                    feedback.append("VLM did not observe Calendar settings dialog.")
            except Exception as e:
                logger.error(f"VLM error: {e}")
                # Fallback: if programmatic check passed perfectly, give VLM benefit of doubt
                if holidays_found == 2:
                    vlm_score = 40
        
        score += vlm_score

        # 5. Final Decision
        # Pass if both holidays are correct programmatically (50 pts from logic) + file existence checks
        # VLM helps boost to 100 but isn't strictly blocking if logic is perfect (robustness)
        passed = (holidays_found == 2) and (score >= 60)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
        
    finally:
        # Cleanup
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)