#!/usr/bin/env python3
"""
Verifier for Detect Outbreak EARS task.

Verifies:
1. Canvas file existence and freshness.
2. XML content of the canvas file for correct configuration:
   - Data source connection string
   - Aberration gadget presence
   - Correct method (C2)
   - Correct variable mapping
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_detect_outbreak_ears(traj, env_info, task_info):
    """
    Verify the Epi Info 7 Aberration Detection task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_canvas_path = metadata.get('expected_canvas_path', r"C:\Users\Docker\Documents\Surveillance\DailyMonitoring.canvas")
    
    score = 0
    feedback_parts = []
    
    # 1. Retrieve Result JSON from Container
    # Note: container path is Windows path, but copy_from_env might need linux-style mount path or 
    # specific handling depending on the backend. Assuming standard path mapping.
    # Usually in Windows containers, C:\ mapped to /c/ or handled by the driver.
    # The setup script put json at C:\tmp\task_result.json.
    
    # Adjust path for copy_from_env based on typical Windows Docker behavior
    # or assume the tool handles "C:\" -> internal representation.
    # Safe bet: try the explicit path.
    
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Try copying the result JSON
        copy_from_env("C:\\tmp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        logger.error(f"Failed to copy/read result json: {e}")
        return {"passed": False, "score": 0, "feedback": "Could not retrieve task result from environment."}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    # 2. Verify File Existence (20 pts)
    if not result_data.get("canvas_exists"):
        return {"passed": False, "score": 0, "feedback": "Dashboard canvas file not found."}
    
    score += 20
    feedback_parts.append("Canvas file created.")

    # 3. Verify Anti-Gaming (File Freshness) (10 pts)
    if result_data.get("file_created_during_task"):
        score += 10
    else:
        feedback_parts.append("Warning: File timestamp indicates it wasn't created during this session.")

    # 4. Analyze Canvas Content (70 pts)
    # We need to copy the .canvas file out to parse it.
    temp_canvas = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_canvas_path, temp_canvas.name)
        
        # Parse XML
        # Epi Info Canvas files are XMLs usually containing <DashboardCanvas> ... <Gadgets> ...
        tree = ET.parse(temp_canvas.name)
        root = tree.getroot()
        
        # A. Verify Data Source (20 pts)
        # Look for connection string or data source element
        # This structure varies by Epi Info version but typically contains "DataSource"
        xml_str = open(temp_canvas.name, 'r', encoding='utf-8', errors='ignore').read()
        
        if "cook_county_daily.csv" in xml_str:
            score += 20
            feedback_parts.append("Data source linked correctly.")
        else:
            feedback_parts.append("Incorrect data source found in canvas.")

        # B. Verify Gadget Type (20 pts)
        # Look for the Aberration gadget
        # Often stored as <GadgetName>AberrationControl</GadgetName> or similar class name
        # We can search for the class name or the word "Aberration" in the XML content
        if "Aberration" in xml_str or "EarControl" in xml_str: # EarControl is the class for EARS
            score += 20
            feedback_parts.append("Aberration detection gadget found.")
        else:
            feedback_parts.append("No Aberration Detection gadget found.")

        # C. Verify Configuration (C2, Date, Cases) (30 pts)
        config_score = 0
        
        # Check for C2 method parameter
        # Typically <Method>C2</Method> or parameter
        if "C2" in xml_str:
            config_score += 10
            feedback_parts.append("Method C2 selected.")
        elif "C1" in xml_str or "C3" in xml_str:
            feedback_parts.append("Wrong method selected (Found C1/C3, expected C2).")
        else:
            feedback_parts.append("Method configuration unclear.")

        # Check for variable mappings
        # Look for field names in the XML
        if "cases" in xml_str.lower():
            config_score += 10
            feedback_parts.append("Count variable 'cases' mapped.")
        
        if "date" in xml_str.lower():
            config_score += 10
            feedback_parts.append("Date variable 'date' mapped.")

        score += config_score

    except Exception as e:
        logger.error(f"Failed to analyze canvas file: {e}")
        feedback_parts.append(f"Error parsing dashboard file: {str(e)}")
    finally:
        if os.path.exists(temp_canvas.name):
            os.unlink(temp_canvas.name)

    passed = score >= 80
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback_parts)
    }