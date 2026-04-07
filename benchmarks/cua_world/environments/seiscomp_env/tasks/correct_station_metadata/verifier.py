#!/usr/bin/env python3
"""
Verifier for correct_station_metadata task.

VERIFICATION STRATEGY:
1. Database State (35 points) - BKB elevation must be exactly 50.0 in the DB.
2. Database Collateral Check (15 points) - Other GE stations must not have been modified.
3. SCML File Existence (10 points) - The exported inventory file must exist and have been created during the task.
4. SCML File Content (15 points) - The XML file must parse as valid SCML and contain BKB elevation 50.0.
5. Report File (25 points) - Text report exists, contains correct station ID, old value, and new value.

Mandatory pass condition: Database BKB elevation MUST be 50.0.
"""

import json
import os
import tempfile
import xml.etree.ElementTree as ET
import re
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_correct_station_metadata(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_elevation = metadata.get('expected_elevation', 50.0)
    target_station = metadata.get('target_station', 'BKB')
    
    score = 0
    feedback_parts = []
    
    # Load the main JSON result
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    initial_db = result.get('initial_db_elevations', {})
    final_db = result.get('final_db_elevations', {})
    
    old_bkb_elevation = initial_db.get(target_station)
    final_bkb_elevation = final_db.get(target_station)
    
    # -------------------------------------------------------------------------
    # Criterion 1: Database State Check (35 points)
    # -------------------------------------------------------------------------
    db_correct = False
    if final_bkb_elevation is not None and abs(final_bkb_elevation - expected_elevation) < 0.01:
        score += 35
        db_correct = True
        feedback_parts.append(f"DB updated: {target_station} elevation is {final_bkb_elevation}m")
    else:
        feedback_parts.append(f"DB check failed: {target_station} elevation is {final_bkb_elevation} (expected {expected_elevation})")
        
    # -------------------------------------------------------------------------
    # Criterion 2: Collateral Damage Check (15 points)
    # -------------------------------------------------------------------------
    other_stations = [s for s in initial_db.keys() if s != target_station]
    collateral_damage = False
    for st in other_stations:
        if initial_db.get(st) != final_db.get(st):
            collateral_damage = True
            feedback_parts.append(f"Collateral damage: Station {st} elevation changed!")
            
    if not collateral_damage and len(other_stations) > 0:
        score += 15
        feedback_parts.append("Other stations unharmed")

    # -------------------------------------------------------------------------
    # Criterion 3 & 4: SCML File Validation (25 points total)
    # -------------------------------------------------------------------------
    xml_info = result.get('xml_file', {})
    if xml_info.get('exists') and xml_info.get('size_bytes', 0) > 1000 and xml_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Inventory XML exported")
        
        # Pull the XML file to verify contents
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env(xml_info.get('path'), temp_xml.name)
            
            tree = ET.parse(temp_xml.name)
            root = tree.getroot()
            
            # SCML namespace handling
            ns = ''
            if '}' in root.tag:
                ns = root.tag.split('}')[0] + '}'
                
            bkb_xml_elevation = None
            for station in root.iter(f'{ns}station'):
                if station.get('code') == target_station:
                    elev_elem = station.find(f'{ns}elevation/{ns}value')
                    if elev_elem is None:
                        # Try without nested value if standard SCML format differs slightly
                        elev_elem = station.find(f'{ns}elevation')
                    
                    if elev_elem is not None and elev_elem.text:
                        try:
                            bkb_xml_elevation = float(elev_elem.text)
                        except ValueError:
                            pass
                            
            if bkb_xml_elevation is not None and abs(bkb_xml_elevation - expected_elevation) < 0.01:
                score += 15
                feedback_parts.append("XML contains correct BKB elevation")
            else:
                feedback_parts.append(f"XML has incorrect/missing BKB elevation: {bkb_xml_elevation}")
                
        except Exception as e:
            feedback_parts.append(f"Failed to parse XML: {str(e)}")
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)
    else:
        feedback_parts.append("Inventory XML missing or not updated during task")

    # -------------------------------------------------------------------------
    # Criterion 5: Text Report Check (25 points total)
    # -------------------------------------------------------------------------
    txt_info = result.get('txt_file', {})
    if txt_info.get('exists') and txt_info.get('created_during_task'):
        score += 10
        feedback_parts.append("Report file created")
        
        # Pull the TXT file to verify contents
        temp_txt = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env(txt_info.get('path'), temp_txt.name)
            with open(temp_txt.name, 'r') as f:
                report_content = f.read().lower()
                
            report_has_target = target_station.lower() in report_content
            
            # Check for old value (e.g. 132 or 132.0)
            old_val_str = str(old_bkb_elevation)
            old_val_int = str(int(old_bkb_elevation)) if old_bkb_elevation == int(old_bkb_elevation) else None
            
            report_has_old = False
            if old_val_str and old_val_str in report_content:
                report_has_old = True
            elif old_val_int and old_val_int in report_content:
                report_has_old = True
                
            # Check for new value (50 or 50.0)
            report_has_new = '50' in report_content or '50.0' in report_content
            
            if report_has_old:
                score += 10
                feedback_parts.append("Report contains old value")
            else:
                feedback_parts.append("Report missing old value")
                
            if report_has_new:
                score += 5
                feedback_parts.append("Report contains new value")
                
        except Exception as e:
            feedback_parts.append(f"Failed to read report: {str(e)}")
        finally:
            if os.path.exists(temp_txt.name):
                os.unlink(temp_txt.name)
    else:
        feedback_parts.append("Report file missing or not updated during task")

    # Pass condition: must have updated the DB correctly and achieved >= 60 points overall
    passed = db_correct and score >= 60

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }