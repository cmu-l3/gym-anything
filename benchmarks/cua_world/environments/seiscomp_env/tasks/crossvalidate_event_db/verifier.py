#!/usr/bin/env python3
"""
Verifier for crossvalidate_event_db task.
Analyzes the text report containing SeisComP earthquake properties
against programmatically extracted ground truth parameters.
"""

import os
import json
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_crossvalidate_event_db(traj, env_info, task_info):
    """
    Verify that the agent completely validated the target earthquake
    linkages and accurately transcribed values to the report.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve output payload aggregated by export_result.sh
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
            
    score = 0
    feedback_parts = []
    
    report_exists = result.get("report_exists", False)
    xml_exists = result.get("xml_exists", False)
    gt = result.get("ground_truth", {})
    
    if not report_exists:
        return {"passed": False, "score": 0, "feedback": "Validation report file not found."}
        
    score += 5
    feedback_parts.append("Report file generated")
    
    # Parse the line-delimited report format
    temp_report = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
    report_data = {}
    try:
        copy_from_env("/home/ga/earthquake_validation_report.txt", temp_report.name)
        with open(temp_report.name, 'r') as f:
            for line in f:
                if ':' in line:
                    k, v = line.split(':', 1)
                    report_data[k.strip().upper()] = v.strip()
    except Exception as e:
        feedback_parts.append(f"Failed to read report file contents: {e}")
    finally:
        if os.path.exists(temp_report.name):
            os.unlink(temp_report.name)
            
    # CRITERIA 1: Check presence of all 14 requested keys (15 pts)
    req_keys = [
        "EVENT_ID", "ORIGIN_ID", "MAGNITUDE_ID", "ORIGIN_TIME", 
        "LATITUDE", "LONGITUDE", "DEPTH_KM", "MAGNITUDE_VALUE", 
        "MAGNITUDE_TYPE", "ORIGIN_REF_VALID", "MAG_ORIGIN_LINK_VALID", 
        "PREFERRED_ORIGIN_EXISTS", "PREFERRED_MAG_EXISTS", "OVERALL_VALID"
    ]
    
    missing_keys = [k for k in req_keys if k not in report_data]
    if not missing_keys:
        score += 15
        feedback_parts.append("All 14 required fields mapped")
    else:
        feedback_parts.append(f"Missing {len(missing_keys)} required field(s)")
        
    # CRITERIA 2: Core Identifier match (8 pts)
    if report_data.get("EVENT_ID") and gt.get("event_id") and report_data.get("EVENT_ID") == gt.get("event_id"):
        score += 8
    else:
        feedback_parts.append("EVENT_ID invalid/mismatched")
        
    # CRITERIA 3: Origin coordinates match within tolerance (Lat: 7 pts, Lon: 7 pts, Depth: 5 pts)
    try:
        if abs(float(report_data.get("LATITUDE", 0)) - gt.get("latitude", 0)) <= 0.1: score += 7
    except: pass
    
    try:
        if abs(float(report_data.get("LONGITUDE", 0)) - gt.get("longitude", 0)) <= 0.1: score += 7
    except: pass
    
    try:
        if abs(float(report_data.get("DEPTH_KM", 0)) - gt.get("depth", 0)) <= 1.0: score += 5
    except: pass
    
    # CRITERIA 4: Magnitude variables (Val: 7 pts, Type: 3 pts)
    try:
        if abs(float(report_data.get("MAGNITUDE_VALUE", 0)) - gt.get("magnitude_value", 0)) <= 0.1: score += 7
    except: pass
    
    if report_data.get("MAGNITUDE_TYPE", "").lower() == gt.get("magnitude_type", "").lower() and gt.get("magnitude_type"):
        score += 3
        
    # CRITERIA 5: Time matching string heuristic (5 pts)
    gt_time = gt.get("time", "")
    if gt_time and (gt_time[:10] in report_data.get("ORIGIN_TIME", "") or gt_time in report_data.get("ORIGIN_TIME", "")):
        score += 5
        
    # CRITERIA 6: Explicit logical validations mapping to 'YES' string output (21 pts combined)
    if report_data.get("ORIGIN_REF_VALID", "").upper() == "YES": score += 5
    if report_data.get("MAG_ORIGIN_LINK_VALID", "").upper() == "YES": score += 5
    if report_data.get("PREFERRED_ORIGIN_EXISTS", "").upper() == "YES": score += 3
    if report_data.get("PREFERRED_MAG_EXISTS", "").upper() == "YES": score += 3
    if report_data.get("OVERALL_VALID", "").upper() == "YES": score += 2
    
    # CRITERIA 7: Evaluate the XML dump artifacts (15 pts)
    if xml_exists and result.get("xml_size", 0) > 500:
        temp_xml = tempfile.NamedTemporaryFile(delete=False, suffix='.xml')
        try:
            copy_from_env("/home/ga/event_dump.xml", temp_xml.name)
            with open(temp_xml.name, 'r', encoding='utf-8') as f:
                xml_content = f.read(500000) # Buffer to limit mem payload footprint
            
            # Scxmldump namespace check 
            if 'eventParameters' in xml_content or 'seiscomp' in xml_content:
                score += 5
                
                # Minimum presence check to verify data was successfully dumped
                if 'origin' in xml_content and 'magnitude' in xml_content:
                    score += 10
                    feedback_parts.append("XML data dump validated")
                else:
                    feedback_parts.append("XML dump missing origins/magnitudes hierarchy")
            else:
                feedback_parts.append("Invalid XML dump root/namespace format")
        except Exception as e:
            feedback_parts.append("Failed to evaluate XML payload contents")
        finally:
            if os.path.exists(temp_xml.name):
                os.unlink(temp_xml.name)
                
    # CRITERIA 8: Check temporal file metadata against Task session timestamp to catch arbitrary copy/pasting (5 pts)
    if result.get("report_created_during_task") and report_data.get("EVENT_ID") == gt.get("event_id") and gt.get("event_id"):
        score += 5
        feedback_parts.append("Temporal execution checks passed")
        
    passed = score >= 60 and report_exists and xml_exists and ("EVENT_ID" in report_data)
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }