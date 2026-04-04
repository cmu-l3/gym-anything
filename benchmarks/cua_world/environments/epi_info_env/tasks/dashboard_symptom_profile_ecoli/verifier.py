#!/usr/bin/env python3
"""
Verifier for dashboard_symptom_profile_ecoli task.
Parses the Epi Info 7 Dashboard XML file (.cvs7) to verify configuration.
"""

import json
import os
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_dashboard_symptom_profile(traj, env_info, task_info):
    """
    Verify the Epi Info 7 Dashboard file.
    
    Criteria:
    1. File exists and created during task (10 pts)
    2. Data source is correct (EColi) (10 pts)
    3. Data filter 'Ill = Yes' is applied (30 pts)
    4. Combined Frequency gadget used (20 pts)
    5. Correct symptoms selected (20 pts)
    6. Sorting and Title correct (10 pts)
    """
    
    # Setup
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    required_symptoms = set([s.lower() for s in metadata.get('required_symptoms', [])])
    
    score = 0
    feedback_parts = []
    
    # 1. Get JSON result from export script
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    # Check file existence
    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Dashboard file 'SymptomProfile.cvs7' not found."}
        
    if not task_result.get('file_created_during_task'):
        feedback_parts.append("Warning: File timestamp indicates it wasn't modified during this session.")
    else:
        score += 10
        feedback_parts.append("Dashboard file created/saved successfully.")

    # 2. Retrieve and Parse the .cvs7 file (It's XML)
    temp_cvs = tempfile.NamedTemporaryFile(delete=False, suffix='.cvs7')
    try:
        copy_from_env("C:\\Users\\Docker\\Documents\\Epi_Info\\Dashboards\\SymptomProfile.cvs7", temp_cvs.name)
        
        # Parse XML
        tree = ET.parse(temp_cvs.name)
        root = tree.getroot()
        
        # --- Check Data Source (10 pts) ---
        # Look for connection info. Usually in <DashboardHelper> or gadget config.
        # Simple check: Does the file content reference EColi?
        with open(temp_cvs.name, 'r', encoding='utf-8', errors='ignore') as f:
            content = f.read()
            if 'EColi' in content or 'FoodHistory' in content:
                score += 10
                feedback_parts.append("Data source verified (EColi).")
            else:
                feedback_parts.append("Could not verify data source connection to EColi.")

        # --- Check Gadget Configuration ---
        # Find the Combined Frequency Gadget
        # XML path typically: Dashboard > Gadgets > CombinedFrequencyGadget
        # Note: Namespace handling might be needed, or generic search
        
        gadget = None
        # Iterate all elements to find CombinedFrequencyGadget (ignoring namespace complexity)
        for elem in root.iter():
            if 'CombinedFrequencyGadget' in elem.tag:
                gadget = elem
                break
        
        if gadget is None:
            feedback_parts.append("Combined Frequency gadget not found in dashboard.")
        else:
            score += 20
            feedback_parts.append("Combined Frequency gadget found.")
            
            # --- Check Variables (20 pts) ---
            # <MainVariable> tags contain field names
            found_vars = set()
            for var_node in gadget.findall(".//MainVariable"):
                if var_node.text:
                    found_vars.add(var_node.text.lower())
            
            # Check overlap
            common = found_vars.intersection(required_symptoms)
            if len(common) >= 4: # Allow missing 1-2
                score += 20
                feedback_parts.append(f"Symptom variables verified ({len(common)}/{len(required_symptoms)} found).")
            elif len(common) > 0:
                partial = int(20 * (len(common) / len(required_symptoms)))
                score += partial
                feedback_parts.append(f"Partial symptom variables found ({len(common)}).")
            else:
                feedback_parts.append("No required symptom variables selected.")

            # --- Check Data Filter (30 pts) ---
            # Filter is typically stored in <DataFilter> or <Selection> tags
            # We look for the filter string "Ill" and "Yes" or "(+)" or "true"
            filter_node = gadget.find(".//DataFilter")
            filter_text = ""
            if filter_node is not None and filter_node.text:
                filter_text = filter_node.text
            
            # Filters in Epi Info XML are often encoded conditions
            if 'Ill' in filter_text and ('Yes' in filter_text or '(+)' in filter_text or 'true' in filter_text.lower()):
                score += 30
                feedback_parts.append("Data filter (Ill=Yes) verified.")
            else:
                # Fallback: Check global filter if not on gadget
                global_filter = root.find(".//DataFilter")
                if global_filter is not None and global_filter.text and 'Ill' in global_filter.text:
                    score += 30
                    feedback_parts.append("Global data filter verified.")
                else:
                    feedback_parts.append("Data filter for 'Illness' not found.")

            # --- Check Title & Sorting (10 pts) ---
            # Title in <GadgetTitle>
            title_node = gadget.find(".//GadgetTitle")
            title_ok = False
            if title_node is not None and title_node.text and "Symptom Profile" in title_node.text:
                title_ok = True
                
            # Sort setting (boolean or string)
            # Typically <UseHighToLowSort>true</UseHighToLowSort>
            sort_node = gadget.find(".//UseHighToLowSort")
            sort_ok = False
            if sort_node is not None and sort_node.text and sort_node.text.lower() == 'true':
                sort_ok = True
                
            if title_ok or sort_ok:
                score += 10
                feedback_parts.append("Title/Sorting configuration verified.")

    except ET.ParseError:
        return {"passed": False, "score": score, "feedback": "Failed to parse dashboard file (invalid XML)."}
    except Exception as e:
        return {"passed": False, "score": score, "feedback": f"Error parsing dashboard file: {e}"}
    finally:
        if os.path.exists(temp_cvs.name):
            os.unlink(temp_cvs.name)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }