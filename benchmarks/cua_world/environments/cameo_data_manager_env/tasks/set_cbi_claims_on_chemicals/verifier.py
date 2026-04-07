#!/usr/bin/env python3
"""
Verifier for Set CBI Claims task in CAMEO Data Manager.

Verifies:
1. Agent exported a Tier II XML file.
2. The export file was created during the task session.
3. "Proprietary Cooling Blend X-40" is marked Trade Secret with correct generic name.
4. "Anhydrous Ammonia" is marked Location Confidential.
5. "Sulfuric Acid" is NOT marked CBI.
"""

import json
import os
import logging
import tempfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_set_cbi_claims(traj, env_info, task_info):
    """
    Verify the agent correctly set CBI claims and exported the data.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_export_path = metadata.get('export_file', 'C:\\Users\\Docker\\Desktop\\praxair_cbi_export.xml')
    
    # Define expected chemical states
    targets = {
        "68476-85-7": { # Cooling Blend
            "name_partial": "Proprietary", 
            "trade_secret": True, 
            "generic_name": "Refrigerant Gas Blend",
            "loc_confidential": False
        },
        "7664-41-7": { # Ammonia
            "name_partial": "Ammonia", 
            "trade_secret": False, 
            "generic_name": None,
            "loc_confidential": True
        },
        "7664-93-9": { # Sulfuric Acid
            "name_partial": "Sulfuric", 
            "trade_secret": False, 
            "generic_name": None,
            "loc_confidential": False
        }
    }

    # 1. Get the result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        # Note: Windows path inside container needs to be handled by copy_from_env
        # Assuming copy_from_env accepts the guest path string
        copy_from_env("C:\\Users\\Docker\\AppData\\Local\\Temp\\task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Failed to retrieve task result JSON: {e}. Did the agent run the export script?"
        }
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result_data.get('export_exists', False):
        return {
            "passed": False, 
            "score": 0, 
            "feedback": "Export file not found. You must export the Tier II data to Desktop\\praxair_cbi_export.xml."
        }

    # 2. Get the exported XML file
    temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
    try:
        copy_from_env(expected_export_path, temp_xml.name)
        tree = ET.parse(temp_xml.name)
        root = tree.getroot()
    except Exception as e:
        return {
            "passed": False, 
            "score": 10, 
            "feedback": f"Export file exists but could not be parsed as XML: {e}"
        }
    finally:
        if os.path.exists(temp_xml.name):
            os.unlink(temp_xml.name)

    # 3. Analyze XML Content
    score = 10 # Base score for creating file
    feedback = []
    
    # Helper to find chemical nodes (structure varies by export format, we'll search recursively)
    # Tier II XML usually has Facility -> ChemicalList -> Chemical
    chemicals_found = {}
    
    for chemical in root.findall(".//Chemical"):
        cas_node = chemical.find("CASNumber")
        name_node = chemical.find("ChemicalName")
        
        cas = cas_node.text.strip() if cas_node is not None else "Unknown"
        name = name_node.text.strip() if name_node is not None else "Unknown"
        
        # Check flags
        ts_node = chemical.find("TradeSecret")
        is_ts = ts_node is not None and ts_node.text.lower() == "true"
        
        lc_node = chemical.find("LocationConfidential")
        is_lc = lc_node is not None and lc_node.text.lower() == "true"
        
        # Check generic name (might be in a specific node or replaced ChemicalName)
        # In Tier II submit, if TS is true, ChemicalName usually holds the Generic Name or there is a GenericName tag
        # We'll check for a GenericName tag or if the Name itself matches
        gen_name_node = chemical.find("GenericName")
        generic_name = gen_name_node.text.strip() if gen_name_node is not None else ""
        
        chemicals_found[cas] = {
            "name": name,
            "trade_secret": is_ts,
            "location_confidential": is_lc,
            "generic_name": generic_name
        }

    # Verify each target
    for target_cas, criteria in targets.items():
        if target_cas not in chemicals_found:
            feedback.append(f"Missing chemical record for CAS {target_cas}")
            continue
            
        chem = chemicals_found[target_cas]
        chem_score = 0
        
        # Check Trade Secret
        if chem["trade_secret"] == criteria["trade_secret"]:
            chem_score += 10
        else:
            feedback.append(f"CAS {target_cas}: Trade Secret incorrect (Expected {criteria['trade_secret']}, Got {chem['trade_secret']})")

        # Check Location Confidential
        if chem["location_confidential"] == criteria["loc_confidential"]:
            chem_score += 10
        else:
            feedback.append(f"CAS {target_cas}: Location Confidential incorrect (Expected {criteria['loc_confidential']}, Got {chem['location_confidential']})")

        # Check Generic Name (only if TS expected)
        if criteria["trade_secret"]:
            # Accept if generic name tag is correct OR if chemical name field was replaced by generic name (common in some exports)
            if (criteria["generic_name"].lower() in chem["generic_name"].lower()) or \
               (criteria["generic_name"].lower() in chem["name"].lower()):
                chem_score += 10
            else:
                feedback.append(f"CAS {target_cas}: Generic Name mismatch (Expected '{criteria['generic_name']}')")
                
        score += chem_score

    # Anti-gaming: Check if file was actually created during task
    if result_data.get('file_created_during_task', False):
        score += 10
    else:
        feedback.append("Warning: Export file timestamp suggests it wasn't created during this session.")

    success = score >= 80  # Max is 10 + 3*20 + 10 (generic name) + 10 (timestamp) = 90?
                           # Wait: 
                           # File exists: 10
                           # Timestamp: 10
                           # Cooling Blend: TS(10) + LC(10) + Name(10) = 30
                           # Ammonia: TS(10) + LC(10) = 20
                           # Sulfuric: TS(10) + LC(10) = 20
                           # Total: 100
    
    return {
        "passed": success,
        "score": score,
        "feedback": " | ".join(feedback) if feedback else "All CBI claims verified correctly."
    }