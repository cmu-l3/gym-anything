#!/usr/bin/env python3
"""
Verifier for embed_functional_spreadsheet@1

Verifies that a LibreOffice Calc OLE object is embedded in the ODP file,
contains the correct data, and uses formulas.
"""

import json
import os
import zipfile
import tempfile
import shutil
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces for ODF parsing
NS = {
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'xlink': 'http://www.w3.org/1999/xlink'
}

def verify_spreadsheet_embedding(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_path = metadata.get('target_file', '/home/ga/Documents/Presentations/it_budget_draft.odp')
    
    # Temp file for the ODP
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix=".odp")
    temp_odp.close()
    
    try:
        # 1. Copy file from env
        copy_from_env(target_path, temp_odp.name)
        
        # 2. Check if it's a valid zip (ODP is a zip)
        if not zipfile.is_zipfile(temp_odp.name):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Target file is not a valid ODP archive (possibly corrupted or not saved)."
            }
            
        score = 0
        feedback_parts = []
        
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            # 3. Check for OLE Object in main content
            # OLE objects usually appear as a <draw:object> inside a <draw:frame>
            # The actual object data is stored in a subfolder (e.g., "Object 1/")
            
            if 'content.xml' not in z.namelist():
                return {"passed": False, "score": 0, "feedback": "Invalid ODP: content.xml missing"}
                
            content_xml = z.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Find embedded objects
            # Look for <draw:object> elements
            objects = root.findall(".//draw:object", NS)
            
            if not objects:
                return {
                    "passed": False, 
                    "score": 0, 
                    "feedback": "No OLE objects found in the presentation. Did you insert a 'LibreOffice Spreadsheet' object?"
                }
            
            # Identify the path to the internal object
            # Usually xlink:href="./Object 1"
            object_paths = []
            for obj in objects:
                href = obj.get(f"{{{NS['xlink']}}}href")
                if href:
                    # Remove ./ prefix if present
                    path = href.lstrip('./')
                    # Standard ODP structure puts object content in a folder, e.g., "Object 1/content.xml"
                    if f"{path}/content.xml" in z.namelist():
                        object_paths.append(path)
            
            if not object_paths:
                return {
                    "passed": False, 
                    "score": 10, 
                    "feedback": "OLE object placeholder found, but internal content structure is missing."
                }
                
            score += 25
            feedback_parts.append("OLE Object detected")
            
            # 4. Verify Content of the Embedded Spreadsheet
            # We look for the required strings and formulas in the FIRST found object's content.xml
            # (Assuming the agent only inserted one, or the first one is the correct one)
            
            found_content = False
            found_formulas = False
            found_grand_total = False
            
            required_strings = metadata.get('required_strings', [])
            
            for obj_path in object_paths:
                inner_content = z.read(f"{obj_path}/content.xml")
                inner_root = ET.fromstring(inner_content)
                
                # Extract all text from table cells
                # <text:p> inside <table:table-cell>
                all_text = " ".join([elem.text for elem in inner_root.findall(".//text:p", NS) if elem.text])
                
                # Check for required strings
                missing = [s for s in required_strings if s not in all_text]
                if not missing:
                    found_content = True
                
                # Check for formulas
                # Formulas are attributes like table:formula="of:=..."
                # We can search for 'table:formula' in any element attributes
                formula_cells = inner_root.findall(".//*[@table:formula]", NS)
                if len(formula_cells) >= 3: # Expecting at least 3 rows + grand total
                    found_formulas = True
                
                # Check for Grand Total (71200)
                # It might be formatted text "71,200" or raw value
                # Check value attribute: office:value="71200"
                value_cells = inner_root.findall(".//*[@office:value='71200']", NS)
                if value_cells:
                    found_grand_total = True
                
                if found_content and found_formulas:
                    break
            
            # Scoring
            if found_content:
                score += 25
                feedback_parts.append("Hardware data entered correctly")
            else:
                feedback_parts.append(f"Missing hardware data strings: {missing}")
                
            if found_formulas:
                score += 30
                feedback_parts.append("Formulas detected in spreadsheet")
            else:
                feedback_parts.append("No formulas detected (did you type manual numbers?)")
                
            if found_grand_total:
                score += 20
                feedback_parts.append("Grand Total (71,200) correct")
            else:
                feedback_parts.append("Grand Total value 71,200 not found")
                
            return {
                "passed": score >= 75,
                "score": score,
                "feedback": " | ".join(feedback_parts)
            }

    except Exception as e:
        logger.error(f"Verification failed: {e}")
        return {
            "passed": False, 
            "score": 0, 
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)