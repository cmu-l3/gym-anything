#!/usr/bin/env python3
"""
Verifier for sales_report_chart_creation task.
Checks if a valid ODT file was created containing a properly configured chart.
"""

import json
import os
import zipfile
import xml.etree.ElementTree as ET
import tempfile
import logging
from typing import Dict, Any

# Setup logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF Namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'chart': 'urn:oasis:names:tc:opendocument:xmlns:chart:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
}

def verify_sales_report_chart(traj, env_info, task_info):
    """
    Verify the sales report chart creation task.
    
    Strategy:
    1. Check if output ODT exists and was created during the task.
    2. Unzip ODT and inspect content.xml to find a <draw:object> (the chart container).
    3. Locate the chart object directory (e.g., Object 1/) inside the ZIP.
    4. Parse the chart's content.xml to verify Title, Axis labels, and Type.
    5. Use VLM to visually confirm the chart is visible and positioned correctly.
    """
    
    # 1. Setup and Load Basic Info
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "System error: copy_from_env missing"}

    metadata = task_info.get('metadata', {})
    expected_title = metadata.get('expected_title', "2024 Regional Revenue Trends")
    expected_xaxis = metadata.get('expected_xaxis', "Region")
    expected_yaxis = metadata.get('expected_yaxis', "Revenue ($M)")
    
    # Load task result JSON
    result_json_path = tempfile.mktemp()
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)

    # 2. Check File Existence (20 pts)
    score = 0
    feedback = []
    
    if not task_result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Output file /home/ga/Documents/sales_report_final.odt not found."}
    
    if not task_result.get('file_created_during_task'):
        feedback.append("Warning: Output file timestamp indicates it wasn't modified during the task.")
        # We don't fail immediately, but it's suspicious.
    
    score += 10
    feedback.append("Output file exists.")

    # 3. Analyze ODT Structure (60 pts)
    odt_temp_path = tempfile.mktemp(suffix=".odt")
    chart_found = False
    title_correct = False
    xaxis_correct = False
    yaxis_correct = False
    
    try:
        copy_from_env("/home/ga/Documents/sales_report_final.odt", odt_temp_path)
        
        with zipfile.ZipFile(odt_temp_path, 'r') as z:
            # Step A: Find the object in the main content.xml
            # (LibreOffice embeds charts as OLE objects)
            main_content = z.read('content.xml')
            root = ET.fromstring(main_content)
            
            # Look for drawing objects
            draw_objects = root.findall('.//draw:object', NS)
            chart_href = None
            
            for obj in draw_objects:
                # We assume the first object or one with 'chart' in generic names
                href = obj.get('{http://www.w3.org/1999/xlink}href')
                if href and href.startswith('./'):
                    href = href[2:] # Remove ./
                
                # Check if this object is a chart directory in the zip
                # Usually it's like "Object 1/"
                if href and f"{href}/content.xml" in z.namelist():
                    # Read the object's content to confirm it's a chart
                    obj_content = z.read(f"{href}/content.xml")
                    if b'office:chart' in obj_content:
                        chart_href = href
                        break
            
            if chart_href:
                score += 20
                feedback.append("Chart object found embedded in document.")
                chart_found = True
                
                # Parse the chart XML
                chart_xml = z.read(f"{chart_href}/content.xml")
                chart_root = ET.fromstring(chart_xml)
                
                # Check Title
                titles = chart_root.findall('.//chart:title/text:p', NS)
                found_title = " ".join([t.text for t in titles if t.text])
                if expected_title.lower() in found_title.lower():
                    score += 20
                    title_correct = True
                    feedback.append(f"Chart title correct: '{found_title}'")
                else:
                    feedback.append(f"Chart title mismatch. Found: '{found_title}', Expected: '{expected_title}'")

                # Check Axis Labels
                # Note: Axes structure can be complex, searching all text:p inside axis elements
                axes = chart_root.findall('.//chart:axis', NS)
                axis_texts = []
                for axis in axes:
                    axis_title = axis.find('.//chart:title/text:p', NS)
                    if axis_title is not None and axis_title.text:
                        axis_texts.append(axis_title.text)
                
                found_x = any(expected_xaxis.lower() in t.lower() for t in axis_texts)
                found_y = any(expected_yaxis.lower() in t.lower() for t in axis_texts)
                
                if found_x:
                    score += 10
                    xaxis_correct = True
                    feedback.append(f"X-Axis label found: '{expected_xaxis}'")
                else:
                    feedback.append(f"X-Axis label missing. Found labels: {axis_texts}")
                
                if found_y:
                    score += 10
                    yaxis_correct = True
                    feedback.append(f"Y-Axis label found: '{expected_yaxis}'")
                else:
                    feedback.append(f"Y-Axis label missing. Found labels: {axis_texts}")
                    
            else:
                feedback.append("No embedded chart object found in the document structure.")

    except Exception as e:
        feedback.append(f"Error analyzing ODT file: {str(e)}")
    finally:
        if os.path.exists(odt_temp_path):
            os.remove(odt_temp_path)

    # 4. VLM Verification (20 pts)
    # Use the shared VLM utility to check the final screenshot
    from gym_anything.vlm import get_final_screenshot
    
    vlm_score = 0
    final_screenshot = get_final_screenshot(traj)
    
    if final_screenshot:
        query_vlm = env_info.get('query_vlm')
        if query_vlm:
            prompt = """
            Analyze this screenshot of LibreOffice Writer.
            1. Is there a bar or column chart visible?
            2. Is the chart title visible and does it look like "2024 Regional Revenue Trends"?
            3. Is the chart positioned below a data table?
            
            Respond in JSON: {"chart_visible": bool, "title_readable": bool, "positioned_below_table": bool}
            """
            try:
                vlm_res = query_vlm(prompt=prompt, image=final_screenshot)
                if vlm_res.get('success'):
                    parsed = vlm_res.get('parsed', {})
                    if parsed.get('chart_visible'):
                        vlm_score += 10
                        feedback.append("VLM confirmed chart visibility.")
                    if parsed.get('positioned_below_table'):
                        vlm_score += 10
                        feedback.append("VLM confirmed chart positioning.")
            except Exception as e:
                logger.warning(f"VLM check failed: {e}")
    
    score += vlm_score

    # Final logic
    passed = (chart_found and title_correct) and score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback)
    }