#!/usr/bin/env python3
import json
import os
import zlib
import base64
import urllib.parse
import xml.etree.ElementTree as ET
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def decode_drawio_xml(raw_content):
    """
    Decodes draw.io file content.
    Draw.io files can be:
    1. Plain XML
    2. Compressed XML (deflate) inside <diagram> tags
    3. URL encoded + Base64 + Deflate
    """
    try:
        # Attempt to parse as standard XML first
        root = ET.fromstring(raw_content)
        
        # If it's a mxfile, look for diagram content
        if root.tag == 'mxfile':
            diagram_node = root.find('diagram')
            if diagram_node is not None and diagram_node.text:
                # Decode: Base64 -> Inflate (Raw) -> URL Decode
                # Note: Draw.io usually does Base64 -> Inflate -> URLDecode for the text content
                try:
                    txt = diagram_node.text.strip()
                    data = base64.b64decode(txt)
                    # Attempt raw inflate (drop -15 for raw)
                    xml_str = zlib.decompress(data, -15).decode('utf-8')
                    # Need to URL decode the result? Usually inflate is enough for raw xml,
                    # but sometimes it's URL encoded before base64. 
                    # Let's try parsing the inflated string.
                    return ET.fromstring(urllib.parse.unquote(xml_str))
                except Exception as e:
                    logger.info(f"Compression decode failed, trying raw: {e}")
                    # Might be plain XML inside
                    return root
        return root
    except Exception as e:
        logger.error(f"Failed to parse XML: {e}")
        return None

def verify_transit_map_schematic_design(traj, env_info, task_info):
    """
    Verifies the transit map update task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Retrieve Artifacts
    temp_result_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_diagram = tempfile.NamedTemporaryFile(delete=False, suffix='.drawio')
    
    try:
        copy_from_env("/tmp/task_result.json", temp_result_json.name)
        copy_from_env("/tmp/final_diagram.drawio", temp_diagram.name)
        
        with open(temp_result_json.name, 'r') as f:
            result_data = json.load(f)
            
        with open(temp_diagram.name, 'rb') as f:
            diagram_content = f.read()
            
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve task artifacts: {str(e)}"}
    finally:
        os.unlink(temp_result_json.name)
        # We keep diagram temp file for a moment to read it, then delete
        if os.path.exists(temp_result_json.name): os.unlink(temp_result_json.name)

    # 2. Parse Diagram XML
    score = 0
    feedback = []
    
    # Check basics
    if result_data.get("pdf_exported"):
        score += 10
        feedback.append("PDF export found (+10).")
    else:
        feedback.append("PDF export missing.")

    if not result_data.get("diagram_modified"):
        return {"passed": False, "score": score, "feedback": "Diagram was not modified."}

    xml_root = decode_drawio_xml(diagram_content)
    if xml_root is None:
        return {"passed": False, "score": score, "feedback": "Could not parse diagram XML."}
    
    # cleanup temp diagram
    os.unlink(temp_diagram.name)

    # 3. Analyze Content
    # We look for mxCell elements
    cells = xml_root.findall(".//mxCell")
    
    # Criteria flags
    has_silver_line = False
    has_correct_width = False
    has_schematic_style = False
    bus_route_removed = True
    financial_district_exists = False
    market_st_gone = True
    wheelchair_icons = 0
    interchanges_found = 0
    
    # Specific attributes to look for
    silver_color = "#A0A0A0".lower()
    
    for cell in cells:
        style = cell.get("style", "").lower()
        value = cell.get("value", "")
        
        # Check Silver Line
        if "strokecolor=#a0a0a0" in style:
            has_silver_line = True
            if "strokewidth=12" in style:
                has_correct_width = True
            # Schematic check: edgeStyle=orthogonalEdgeStyle or similar indication of 90 deg
            if "orthogonal" in style or "elbow" in style:
                has_schematic_style = True
                
        # Check Bus Route Removal (Original had 'B1 Bus Route' in value)
        if "b1 bus route" in value:
            bus_route_removed = False
            
        # Check Renaming
        if "financial district" in value:
            financial_district_exists = True
        if "market st" in value:
            # Need to be careful, "Market St" might be part of "Financial District (Market St)" if they kept it?
            # Task said rename, implying replacement. Strict check:
            if "financial district" not in value: 
                market_st_gone = False
                
        # Check Accessibility Icons (Wheelchair)
        # Usually implies an image or a shape with 'wheelchair' or 'access' in style/value
        if "wheelchair" in style or "access" in style or "wheelchair" in value.lower():
            wheelchair_icons += 1
            
        # Check Interchanges (Shape change to ellipse/circle/capsule)
        # Original stations were text only or small rects. 
        # Interchanges usually imply "ellipse" or specific shape style.
        # We look for nodes near the known interchange locations (Stadium, Central) that are ellipses.
        if "ellipse" in style or "shape=ellipse" in style:
            interchanges_found += 1

    # Scoring Logic
    if bus_route_removed:
        score += 10
        feedback.append("Bus route removed (+10).")
    else:
        feedback.append("B1 Bus Route still present.")

    if has_silver_line:
        score += 20
        feedback.append("Silver Line created with correct color (+20).")
        if has_correct_width:
            score += 10
            feedback.append("Line width correct (+10).")
        else:
            feedback.append("Silver Line width incorrect.")
        if has_schematic_style:
            score += 10
            feedback.append("Schematic/Orthogonal style used (+10).")
        else:
            feedback.append("Silver Line edges are not orthogonal.")
    else:
        feedback.append("Silver Line not found (check color #A0A0A0).")

    if financial_district_exists:
        score += 10
        feedback.append("'Financial District' label found (+10).")
    else:
        feedback.append("'Financial District' label missing.")

    if wheelchair_icons >= 2:
        score += 15
        feedback.append("Accessibility icons added (+15).")
    elif wheelchair_icons == 1:
        score += 7
        feedback.append("Partial accessibility icons (+7).")
    else:
        feedback.append("Accessibility icons missing.")
        
    if interchanges_found >= 1: # Basic check for shape usage
        score += 15
        feedback.append("Interchange shapes changed (+15).")
    
    passed = score >= 65
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }