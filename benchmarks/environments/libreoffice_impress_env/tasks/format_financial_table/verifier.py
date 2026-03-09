#!/usr/bin/env python3
"""
Verifier for Format Financial Table task.
Parses the ODP XML directly to verify table cell merging and formatting styles.
"""

import json
import tempfile
import os
import logging
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_table_formatting(traj, env_info, task_info):
    """
    Verify that the table in Q4_Financials.odp has been formatted correctly.
    
    Criteria:
    1. File modified/saved.
    2. 'FY 2023' cell (Row 1, Col 1) spans 2 columns.
    3. 'FY 2024' cell (Row 1, Col 3 -> effectively Col 2 after merge) spans 2 columns.
    4. Header cells have centered text alignment.
    5. Bottom row (Total) has bold text.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_file = metadata.get('target_file', '/home/ga/Documents/Presentations/Q4_Financials.odp')
    
    score = 0
    feedback_parts = []
    
    # 1. Get Result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)
            
    if not result.get('file_modified', False):
        return {"passed": False, "score": 0, "feedback": "File was not saved/modified"}
    
    score += 10 # File saved
    feedback_parts.append("File saved")

    # 2. Get and Parse ODP File
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(target_file, temp_odp.name)
        
        # ODP is a zip file. We need to parse content.xml
        with zipfile.ZipFile(temp_odp.name, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml') # Styles might be here or content.xml
            
        # Parse XML
        # Register namespaces to make finding easier
        namespaces = {
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
            'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
        }
        
        root = ET.fromstring(content_xml)
        
        # Find the table on the second slide
        # Strategy: Find all tables, check content to identify correct one
        tables = root.findall('.//table:table', namespaces)
        target_table = None
        for tbl in tables:
            # Check if this table has our data
            txt = "".join(tbl.itertext())
            if "FY 2023" in txt and "Total" in txt:
                target_table = tbl
                break
        
        if target_table is None:
            return {"passed": False, "score": score, "feedback": "Could not find the financial table in the document"}
            
        # Analyze Rows
        rows = target_table.findall('table:table-row', namespaces)
        if not rows:
            return {"passed": False, "score": score, "feedback": "Table has no rows"}
            
        # --- Check Header Merging (Row 1) ---
        header_row = rows[0]
        cells = header_row.findall('table:table-cell', namespaces)
        
        # Check Cell 1 (FY 2023)
        # Note: In ODF, a spanned cell has 'number-columns-spanned' attribute.
        # The 'covered' cells might not appear or appear as covered-table-cell.
        
        fy23_merged = False
        fy24_merged = False
        
        # We need to find the cell containing "FY 2023"
        for cell in cells:
            cell_text = "".join(cell.itertext()).strip()
            span = cell.get(f"{{{namespaces['table']}}}number-columns-spanned", "1")
            
            if "FY 2023" in cell_text:
                if int(span) >= 2:
                    fy23_merged = True
                    # Check Alignment style
                    style_name = cell.get(f"{{{namespaces['table']}}}style-name")
                    # We need to lookup style to check alignment, but simplest check is just the merge first
            
            if "FY 2024" in cell_text:
                if int(span) >= 2:
                    fy24_merged = True
                    
        if fy23_merged:
            score += 20
            feedback_parts.append("FY 2023 header merged")
        else:
            feedback_parts.append("FY 2023 header NOT merged")
            
        if fy24_merged:
            score += 20
            feedback_parts.append("FY 2024 header merged")
        else:
            feedback_parts.append("FY 2024 header NOT merged")
            
        # --- Check Alignment (Centered Headers) ---
        # This requires style lookup. Styles are in office:automatic-styles in content.xml
        auto_styles = root.find('office:automatic-styles', namespaces)
        
        center_aligned = False
        # Find style used by FY 2023 cell
        # Re-find the cell
        for cell in cells:
            if "FY 2023" in "".join(cell.itertext()):
                style_name = cell.get(f"{{{namespaces['table']}}}style-name")
                if style_name and auto_styles:
                    # Look for <style:style style:name="...">
                    style_node = auto_styles.find(f".//style:style[@style:name='{style_name}']", namespaces)
                    if style_node:
                        # Check paragraph properties or cell properties?
                        # Usually text align is in paragraph properties <style:paragraph-properties fo:text-align="center"/>
                        # OR the cell contains a <text:p text:style-name="...">
                        
                        # Let's check the paragraph inside the cell first
                        p_node = cell.find('text:p', namespaces)
                        if p_node:
                            p_style_name = p_node.get(f"{{{namespaces['text']}}}style-name")
                            if p_style_name:
                                p_style = auto_styles.find(f".//style:style[@style:name='{p_style_name}']", namespaces)
                                if p_style:
                                    pp = p_style.find('style:paragraph-properties', namespaces)
                                    if pp is not None:
                                        align = pp.get(f"{{{namespaces['fo']}}}text-align")
                                        if align == "center":
                                            center_aligned = True

        if center_aligned:
            score += 15
            feedback_parts.append("Header text centered")
        else:
            feedback_parts.append("Header text NOT centered")

        # --- Check Bold Total Row (Last Row) ---
        # Last row index
        total_row = rows[-1]
        total_cells = total_row.findall('table:table-cell', namespaces)
        
        bold_found = False
        # Check the first cell "Total Revenue"
        for cell in total_cells:
            # Similar logic: check text properties for font-weight="bold"
            p_node = cell.find('text:p', namespaces)
            if p_node:
                p_style_name = p_node.get(f"{{{namespaces['text']}}}style-name")
                if p_style_name and auto_styles:
                    p_style = auto_styles.find(f".//style:style[@style:name='{p_style_name}']", namespaces)
                    if p_style:
                        tp = p_style.find('style:text-properties', namespaces)
                        if tp is not None:
                            weight = tp.get(f"{{{namespaces['fo']}}}font-weight")
                            if weight == "bold":
                                bold_found = True
                                break
                            
                            # Also check style:font-weight="bold" (alternative namespace)
                            weight_alt = tp.get(f"{{{namespaces['style']}}}font-weight-asian") # Impress often sets multiple
                            if weight_alt == "bold":
                                bold_found = True
                                break
        
        if bold_found:
            score += 25
            feedback_parts.append("Total row is bold")
        else:
            feedback_parts.append("Total row NOT bold")

        # Data integrity check (simple existence)
        txt = "".join(target_table.itertext())
        if "$2.5M" in txt and "Total Revenue" in txt:
            score += 10
            feedback_parts.append("Data preserved")
        else:
            feedback_parts.append("Data missing/corrupted")

    except Exception as e:
        logger.error(f"Error verification: {e}")
        return {"passed": False, "score": score, "feedback": f"Verification failed with error: {e}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)

    passed = score >= 75
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }