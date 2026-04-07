#!/usr/bin/env python3
import json
import os
import tempfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_resource_cost_accrual(traj, env_info, task_info):
    """
    Verifies that the agent correctly set the Cost Accrual method for specific resources
    in the ProjectLibre XML output.
    """
    
    # 1. Setup and retrieve copy functionality
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('expected_output_path', '/home/ga/Projects/resource_costs.xml')
    
    # MSPDI Namespace is standard for Project XML
    NS = {'p': 'http://schemas.microsoft.com/project'}
    
    score = 0
    feedback = []
    passed = False

    # 2. Retrieve the result metadata JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f_meta:
        try:
            copy_from_env("/tmp/task_result.json", f_meta.name)
            f_meta.close() # Close so we can read
            with open(f_meta.name, 'r') as f:
                task_result = json.load(f)
        except Exception as e:
            logger.warning(f"Could not read task_result.json: {e}")
        finally:
            if os.path.exists(f_meta.name):
                os.unlink(f_meta.name)

    # 3. Check file existence and creation time (Anti-gaming)
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file not found at expected path."}

    if not task_result.get('file_created_during_task', False):
        feedback.append("Warning: Output file timestamp indicates it wasn't modified during the task.")
        # We generally fail or severely penalize this
        return {"passed": False, "score": 0, "feedback": "File was not created or modified during the task session."}

    score += 20 # Points for creating valid file
    feedback.append("Valid output file created.")

    # 4. Retrieve and Parse the XML file
    xml_temp = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    xml_temp.close()
    
    try:
        copy_from_env(expected_output_path, xml_temp.name)
        
        # Parse XML
        tree = ET.parse(xml_temp.name)
        root = tree.getroot()
        
        # 5. Check Resources
        # ProjectLibre/MSPDI structure: <Project><Resources><Resource>...</Resource></Resources></Project>
        # Note: ET findall requires namespace if present.
        
        resources = root.find('p:Resources', NS)
        if resources is None:
            # Fallback: try without namespace or local-name matching if NS issues arise
            resources = root.find('Resources')
        
        if resources is None:
             return {"passed": False, "score": score, "feedback": "Could not find <Resources> section in XML."}

        # Helper to find resource by name
        def get_resource_accrual(res_name):
            for res in resources.findall('p:Resource', NS):
                name_elem = res.find('p:Name', NS)
                if name_elem is not None and name_elem.text == res_name:
                    # Return the AccrueAt text (default is usually '3' if missing, but let's look for tag)
                    accrue = res.find('p:AccrueAt', NS)
                    return accrue.text if accrue is not None else None
            return None

        # Helper to check all resources for unintended changes
        def count_non_default_accruals(whitelist_names):
            count = 0
            for res in resources.findall('p:Resource', NS):
                name_elem = res.find('p:Name', NS)
                name = name_elem.text if name_elem is not None else ""
                
                if name in whitelist_names:
                    continue
                
                accrue = res.find('p:AccrueAt', NS)
                # 3 is Prorated (Default). If it's not 3 and not None, it's a change.
                if accrue is not None and accrue.text != '3':
                    count += 1
            return count

        # 6. Verify specific targets
        
        # Check David Brown (Expect Start = 1)
        david_val = get_resource_accrual("David Brown")
        if david_val == '1':
            score += 35
            feedback.append("David Brown set to Accrue at Start (Correct).")
        else:
            feedback.append(f"David Brown AccrueAt incorrect. Expected '1' (Start), found '{david_val}'.")

        # Check Emma Davis (Expect End = 2)
        emma_val = get_resource_accrual("Emma Davis")
        if emma_val == '2':
            score += 35
            feedback.append("Emma Davis set to Accrue at End (Correct).")
        else:
            feedback.append(f"Emma Davis AccrueAt incorrect. Expected '2' (End), found '{emma_val}'.")

        # 7. Verify Data Integrity (others should be unchanged/Prorated)
        changes = count_non_default_accruals(["David Brown", "Emma Davis"])
        if changes == 0:
            score += 10
            feedback.append("Other resources correctly left unchanged.")
        else:
            feedback.append(f"Penalty: {changes} other resources had modified accrual settings.")

    except ET.ParseError:
        return {"passed": False, "score": 0, "feedback": "Output file is not valid XML."}
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(xml_temp.name):
            os.unlink(xml_temp.name)

    passed = (score >= 90)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }