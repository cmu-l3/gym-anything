#!/usr/bin/env python3
"""
Verifier for Pathogen Pareto Dashboard task.

Verification Strategy:
1. File Existence: Check if .cvs7 (dashboard) and .png (chart) exist.
2. Content Verification (XML Parsing):
   - Parse the .cvs7 dashboard file (XML format).
   - Verify Data Source is linked.
   - Verify Filter: Check for 'Source' and 'Blood' in selection criteria.
   - Verify Gadget: Check for 'Pareto' gadget type analyzing 'Organism'.
3. Anti-Gaming: Ensure image was created during the task.
"""

import json
import os
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_pathogen_pareto_dashboard(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_dashboard = metadata.get('output_dashboard', 'C:\\Users\\Docker\\Documents\\EpiAnalysis\\bsi_dashboard.cvs7')
    
    # Convert Windows path to Linux path for copy_from_env if necessary? 
    # Usually copy_from_env handles the container path format. 
    # Since it's a Windows container, paths are likely C:\...
    # The gym-anything framework usually accepts the path as seen inside the guest.
    
    dashboard_path = "C:\\Users\\Docker\\Documents\\EpiAnalysis\\bsi_dashboard.cvs7"
    result_json_path = "C:\\tmp\\task_result.json"

    score = 0
    feedback_parts = []
    
    # Temporary files for extraction
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_dashboard = tempfile.NamedTemporaryFile(delete=False, suffix='.xml') # .cvs7 is XML
    
    try:
        # 1. Get Result JSON
        try:
            copy_from_env(result_json_path, temp_result.name)
            with open(temp_result.name, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}

        # Check Output Files
        if result_data.get('dashboard_exists'):
            score += 20
            feedback_parts.append("Dashboard file saved.")
        else:
            feedback_parts.append("Dashboard file NOT found.")

        if result_data.get('image_exists'):
            score += 10
            feedback_parts.append("Chart image saved.")
            if result_data.get('image_created_during_task'):
                score += 10
                feedback_parts.append("Image created during task.")
            else:
                feedback_parts.append("Image timestamp too old.")
        else:
            feedback_parts.append("Chart image NOT found.")

        # 2. Analyze Dashboard Content (.cvs7)
        if result_data.get('dashboard_exists'):
            try:
                copy_from_env(dashboard_path, temp_dashboard.name)
                
                # Parse XML
                # Epi Info 7 .cvs7 files are XML.
                # Structure usually involves <DashboardCanvas> ... <Gadgets> ...
                
                tree = ET.parse(temp_dashboard.name)
                root = tree.getroot()
                xml_str = ET.tostring(root, encoding='utf8').decode('utf8')
                
                # Check for Data Filter
                # Filters in Epi Info Dashboard often appear in <FilterSelection> or <GadgetFilter>
                # We look for simple string presence of the logic if structure is complex, 
                # or try to find specific tags.
                # Logic: "Source" and "Blood" should be close or in a condition.
                
                has_filter = False
                if 'Source' in xml_str and 'Blood' in xml_str:
                    # stricter check
                    # Look for <FriendlyFilterCriteria> or similar
                    if 'Source is equal to Blood' in xml_str or 'Source = "Blood"' in xml_str or 'Source = \'Blood\'' in xml_str:
                        has_filter = True
                    elif 'Source' in xml_str and 'Blood' in xml_str:
                        # Fallback for XML variations
                        has_filter = True
                
                if has_filter:
                    score += 30
                    feedback_parts.append("Filter for 'Blood' detected.")
                else:
                    feedback_parts.append("Filter for 'Source = Blood' NOT detected in dashboard file.")

                # Check for Pareto Gadget
                # <Gadget> ... <GadgetType>ParetoChart</GadgetType> ... <MainVariable>Organism</MainVariable>
                # Note: Gadget type might be "Pareto Chart" or "Pareto"
                
                gadgets = root.findall(".//Gadget")
                pareto_found = False
                variable_correct = False
                
                for gadget in gadgets:
                    # Check type - often in <Name> or specialized tag depending on version
                    # Usually checking the full string content of the gadget node is safer for version variance
                    g_str = ET.tostring(gadget, encoding='utf8').decode('utf8')
                    
                    if "Pareto" in g_str:
                        pareto_found = True
                        if "Organism" in g_str:
                            variable_correct = True
                        break
                
                if pareto_found:
                    score += 20
                    feedback_parts.append("Pareto Chart gadget found.")
                else:
                    feedback_parts.append("Pareto Chart gadget NOT found.")
                    
                if variable_correct:
                    score += 10
                    feedback_parts.append("Correct variable 'Organism' selected.")
                else:
                    if pareto_found:
                        feedback_parts.append("Pareto chart found but variable 'Organism' not detected.")

            except Exception as e:
                feedback_parts.append(f"Failed to parse dashboard file: {str(e)}")

    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_dashboard.name):
            os.unlink(temp_dashboard.name)

    passed = score >= 80
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }