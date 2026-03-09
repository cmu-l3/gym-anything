#!/usr/bin/env python3
"""
Verifier for lab_data_ole_embedding task.
Checks for the presence of an embedded OLE spreadsheet object and correct data/formulas within it.
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

def verify_lab_data_ole_embedding(traj, env_info, task_info):
    """
    Verifies the OLE embedding task.
    
    Criteria:
    1. Output file exists and was modified.
    2. ODT structure contains an OLE object (draw:object).
    3. The embedded object content contains the correct data.
    4. The embedded object uses formulas for yield calculation.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Load basic result info
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        with open(temp_result_json.name, 'r') as f:
            basic_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_json.name):
            os.unlink(temp_result_json.name)

    if not basic_result.get("output_exists", False):
        return {"passed": False, "score": 0, "feedback": "Output file not found"}

    # Copy the ODT file for analysis
    output_odt_path = "/home/ga/Documents/batch_synthesis_report_complete.odt"
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    temp_extract_dir = tempfile.mkdtemp()
    
    score = 0
    feedback = []
    
    try:
        copy_from_env(output_odt_path, temp_odt.name)
        
        # 1. Check for OLE Object in main content.xml
        try:
            with zipfile.ZipFile(temp_odt.name, 'r') as z:
                z.extractall(temp_extract_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid ODT/ZIP file"}

        main_content_path = os.path.join(temp_extract_dir, "content.xml")
        if not os.path.exists(main_content_path):
            return {"passed": False, "score": 0, "feedback": "Invalid ODT: content.xml missing"}

        # Parse main content to find Object
        # Namespaces are tricky in ElementTree
        namespaces = {
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'xlink': 'http://www.w3.org/1999/xlink',
            'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
        }
        
        tree = ET.parse(main_content_path)
        root = tree.getroot()
        
        # Look for draw:object
        ole_objects = root.findall(".//draw:object", namespaces)
        
        has_ole = False
        embedded_path = None
        
        for obj in ole_objects:
            href = obj.get(f"{{{namespaces['xlink']}}}href")
            if href and not href.startswith("http"):
                # Ensure it's not just an image, check notify-on-update-of-ranges or look for spreadsheet representation
                # Usually href points to a directory like "./Object 1/"
                has_ole = True
                embedded_path = href.strip("./") 
                feedback.append("Found embedded OLE object.")
                break
        
        if not has_ole:
            # Check if they just made a normal table
            tables = root.findall(".//table:table", namespaces)
            if len(tables) > 0:
                feedback.append("Found a standard Writer table, but requested an Embedded Spreadsheet (OLE).")
                return {"passed": False, "score": 20, "feedback": "Task Failed: Created a standard table instead of embedding a spreadsheet object."}
            return {"passed": False, "score": 10, "feedback": "No embedded spreadsheet object found."}
            
        score += 30 # Points for successfully embedding the object

        # 2. Analyze Embedded Content
        # embedded_path is likely "Object 1/"
        embedded_content_xml = os.path.join(temp_extract_dir, embedded_path, "content.xml")
        if not os.path.exists(embedded_content_xml):
            # Sometimes it's a single file if flat? No, standard ODT uses directory.
            # Try searching manifest if href is obscure
            feedback.append("Could not locate internal content for embedded object.")
        else:
            # Parse the spreadsheet XML
            emb_tree = ET.parse(embedded_content_xml)
            emb_root = emb_tree.getroot()
            
            # Check Data
            required_data = [50.0, 42.5, 48.5, 39.2, 52.0, 49.8]
            found_data_count = 0
            
            # GetAll text in cells
            all_text = []
            # Also check values in office:value
            all_values = []
            
            cells = emb_root.findall(".//table:table-cell", namespaces)
            
            formulas_found = 0
            formatted_decimals = 0
            
            for cell in cells:
                # Check value
                val = cell.get(f"{{{namespaces['office']}}}value")
                if val:
                    try:
                        all_values.append(float(val))
                    except:
                        pass
                
                # Check text content
                p_tags = cell.findall(".//text:p", namespaces)
                for p in p_tags:
                    if p.text:
                        all_text.append(p.text)
                        
                # Check formula
                formula = cell.get(f"{{{namespaces['table']}}}formula")
                if formula:
                    formulas_found += 1
                    
            # Verify specific numbers exist
            for target in required_data:
                # Check if close enough (float)
                if any(abs(v - target) < 0.01 for v in all_values):
                    found_data_count += 1
            
            if found_data_count >= len(required_data):
                score += 30
                feedback.append("All required data values found in spreadsheet.")
            elif found_data_count > 0:
                score += int(30 * (found_data_count / len(required_data)))
                feedback.append(f"Some data values missing ({found_data_count}/{len(required_data)} found).")
            else:
                feedback.append("Required data values not found in embedded spreadsheet.")

            # Verify Formulas (Yield calculation)
            # We expect at least 3 formulas (one for each row)
            if formulas_found >= 3:
                score += 25
                feedback.append("Formulas detected in spreadsheet.")
            else:
                feedback.append(f"Formulas missing or insufficient ({formulas_found} found, expected 3).")
                
            # Verify Formatting (Decimal places)
            # This requires checking the style used by the cell
            # This is complex in XML. simpler proxy: Check if the VALUES or TEXT look like "85.0"
            # If the user typed 85, and formatted to 1 decimal, the text:p might show "85" or "85.0" depending on how ODF saves cached view.
            # However, looking for the specific yield values:
            # A: 42.5/50 = 0.85 -> 85.0
            # B: 39.2/48.5 = 0.8082 -> 80.8
            # C: 49.8/52.0 = 0.9576 -> 95.8
            
            expected_yields = [85.0, 80.8, 95.8]
            yield_matches = 0
            
            # Check the cached text strings for formatting evidence
            joined_text = " ".join(all_text)
            
            for y in expected_yields:
                # Look for the formatted string
                target_str = f"{y:.1f}"
                if target_str in joined_text:
                    yield_matches += 1
            
            if yield_matches >= 2:
                score += 15
                feedback.append("Yield formatting (1 decimal place) verified.")
            else:
                feedback.append("Yield formatting incorrect or values wrong.")

    except Exception as e:
        feedback.append(f"Verification error: {str(e)}")
        # Partial credit if file existed
        if basic_result.get("output_exists"):
            score = max(score, 10)

    finally:
        # Cleanup
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)
        if os.path.exists(temp_extract_dir):
            shutil.rmtree(temp_extract_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }