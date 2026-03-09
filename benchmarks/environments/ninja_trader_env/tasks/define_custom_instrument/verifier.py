#!/usr/bin/env python3
"""
Verifier for define_custom_instrument task.

Verifies that:
1. An instrument export file (XML or ZIP) was created.
2. The file was created during the task window.
3. The XML content defines an instrument named "QUANTA".
4. The definition has the correct properties (TickSize=0.05, PointValue=1, etc).

Dependencies: xml.etree.ElementTree, zipfile
"""

import json
import tempfile
import os
import zipfile
import xml.etree.ElementTree as ET
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_instrument_xml(xml_content):
    """
    Parses NinjaTrader instrument export XML to find specific properties.
    Returns a dict of found properties or None.
    """
    try:
        root = ET.fromstring(xml_content)
        # Namespace handling might be needed depending on NT8 version, 
        # but usually it's standard XML.
        # Structure is roughly: <NinjaTrader><Instruments><Instrument><Name>...</Name>...</Instrument></Instruments></NinjaTrader>
        
        # Search for our specific instrument
        for instrument in root.findall(".//Instrument"):
            name_elem = instrument.find("Name")
            if name_elem is not None and name_elem.text == "QUANTA":
                props = {
                    "Name": "QUANTA",
                    "TickSize": None,
                    "PointValue": None,
                    "MasterInstrument": None,
                    "Currency": None
                }
                
                # Extract properties
                ts = instrument.find("TickSize")
                if ts is not None: props["TickSize"] = ts.text
                
                pv = instrument.find("PointValue")
                if pv is not None: props["PointValue"] = pv.text
                
                mi = instrument.find("MasterInstrument")
                if mi is not None:
                    # Sometimes MasterInstrument is an ID or Name inside it
                    # Try to find Name inside MasterInstrument, or just take the text
                    mi_name = mi.find("Name")
                    if mi_name is not None:
                        props["MasterInstrument"] = mi_name.text
                    else:
                        props["MasterInstrument"] = mi.text
                
                curr = instrument.find("Currency")
                if curr is not None: props["Currency"] = curr.text
                
                return props
                
        return None
    except Exception as e:
        logger.error(f"XML parsing error: {e}")
        return None

def verify_define_custom_instrument(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
        
    metadata = task_info.get('metadata', {})
    
    # 1. Retrieve Result JSON
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("C:/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task result: {str(e)}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    # Check basic file existence
    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "No export file found at expected location."}
        
    if not result.get('file_created_during_task'):
        return {"passed": False, "score": 0, "feedback": "Export file found but was not created during this task session."}
        
    output_path = result.get('output_path')
    
    # 2. Retrieve the actual export file
    # Path is Windows format in result, convert to posix for copy_from_env if needed, 
    # but usually copy_from_env handles the path string provided it matches the container.
    # We'll use the path exactly as returned by the windows script.
    
    temp_export = tempfile.NamedTemporaryFile(delete=False, suffix='_export.dat')
    try:
        copy_from_env(output_path, temp_export.name)
        
        # 3. Read content (Handle ZIP or XML)
        xml_content = ""
        is_zip = output_path.lower().endswith('.zip')
        
        if is_zip:
            try:
                with zipfile.ZipFile(temp_export.name, 'r') as z:
                    # Find the XML file inside
                    xml_files = [f for f in z.namelist() if f.endswith('.xml')]
                    if not xml_files:
                        return {"passed": False, "score": 30, "feedback": "Export ZIP found but contains no XML."}
                    with z.open(xml_files[0]) as zf:
                        xml_content = zf.read()
            except zipfile.BadZipFile:
                 return {"passed": False, "score": 30, "feedback": "Export file is corrupted or not a valid ZIP."}
        else:
            with open(temp_export.name, 'rb') as f:
                xml_content = f.read()
                
        # 4. Verify Content
        props = parse_instrument_xml(xml_content)
        
        if not props:
            return {"passed": False, "score": 40, "feedback": "Export file parsed, but instrument 'QUANTA' definition not found in XML."}
            
        score = 40 # Base score for file + name match
        feedback_parts = ["Instrument 'QUANTA' found"]
        
        # Check Tick Size (25 pts)
        tick_size = props.get("TickSize")
        if tick_size and abs(float(tick_size) - 0.05) < 0.0001:
            score += 25
            feedback_parts.append("Tick Size Correct (0.05)")
        else:
            feedback_parts.append(f"Tick Size Mismatch (Expected 0.05, Got {tick_size})")
            
        # Check Point Value (15 pts)
        point_value = props.get("PointValue")
        if point_value and abs(float(point_value) - 1.0) < 0.0001:
            score += 15
            feedback_parts.append("Point Value Correct (1.0)")
        else:
            feedback_parts.append(f"Point Value Mismatch (Expected 1, Got {point_value})")
            
        # Check Master Instrument (10 pts)
        master = props.get("MasterInstrument")
        if master and ("Stock" in master or "Equities" in master):
            score += 10
            feedback_parts.append("Master Instrument Correct")
        else:
            feedback_parts.append(f"Master Instrument Mismatch (Expected Stock, Got {master})")
            
        # Check Currency/Exchange (10 pts)
        currency = props.get("Currency")
        if currency and ("US" in currency or "Dollar" in currency or "USD" in currency):
             score += 10
             feedback_parts.append("Currency Correct")
        else:
             feedback_parts.append(f"Currency Mismatch (Got {currency})")

        passed = score >= 70
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_export.name):
            os.unlink(temp_export.name)