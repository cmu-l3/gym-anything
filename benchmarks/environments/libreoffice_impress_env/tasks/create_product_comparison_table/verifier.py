#!/usr/bin/env python3
"""
Verifier for Create Product Comparison Table task.

Checks:
1. ODP file existence and validity.
2. Table structure (rows/cols).
3. Text content accuracy.
4. Conditional formatting (Red/Green colors).
5. Alignment (Center).
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET
from typing import Dict, Any, Tuple

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_comparison_table(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_path = metadata.get('expected_output_path', '/home/ga/Documents/Presentations/comparison.odp')

    # Copy result JSON
    task_result = {}
    with tempfile.NamedTemporaryFile(delete=False, suffix='.json') as f:
        temp_json_path = f.name
    
    try:
        copy_from_env("/tmp/task_result.json", temp_json_path)
        with open(temp_json_path, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read task result: {str(e)}"}
    finally:
        if os.path.exists(temp_json_path):
            os.unlink(temp_json_path)

    # Check basic file existence
    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file comparison.odp not found."}

    if not task_result.get('file_created_during_task', False):
        return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task."}

    # Retrieve and parse ODP file
    score = 20  # Base score for file existence
    feedback_parts = ["File saved"]
    
    with tempfile.NamedTemporaryFile(delete=False, suffix='.odp') as f:
        temp_odp_path = f.name
    
    try:
        copy_from_env(expected_path, temp_odp_path)
        
        # Verify ODP content
        content_score, content_feedback = verify_odp_content(temp_odp_path)
        score += content_score
        feedback_parts.append(content_feedback)

    except Exception as e:
        logger.error(f"Error verification ODP: {e}")
        return {"passed": False, "score": score, "feedback": f"Error parsing ODP file: {str(e)}"}
    finally:
        if os.path.exists(temp_odp_path):
            os.unlink(temp_odp_path)

    passed = score >= 75
    return {
        "passed": passed,
        "score": min(100, score),
        "feedback": " | ".join(feedback_parts)
    }

def verify_odp_content(filepath: str) -> Tuple[int, str]:
    """Parses ODP XML to verify table data and styles."""
    score = 0
    feedback = []
    
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            with z.open('content.xml') as f:
                tree = ET.parse(f)
                root = tree.getroot()
            
            # Namespaces
            ns = {
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
            }

            # 1. Check for Table existence
            tables = root.findall('.//table:table', ns)
            if not tables:
                return 0, "No table found in presentation"
            
            # Assume the comparison table is the one with roughly correct dimensions
            target_table = None
            for tbl in tables:
                rows = tbl.findall('table:table-row', ns)
                if len(rows) >= 5: # Allow extra rows
                    target_table = tbl
                    break
            
            if not target_table:
                return 0, "No table with sufficient rows (>=5) found"
            
            score += 10 # Table exists
            feedback.append("Table structure found")

            # 2. Check Content Accuracy
            # We look for key terms in the table
            rows = target_table.findall('table:table-row', ns)
            
            expected_content = {
                "Storage": False, "10 GB": False, "1 TB": False,
                "Encryption": False, "No": False, "Yes": False,
                "Support": False, "24/7 Phone": False
            }
            
            # Extract all text from table cells
            # Cells contain text:p
            cells_data = [] # List of (text_content, style_name)
            
            for row in rows:
                row_cells = row.findall('table:table-cell', ns)
                for cell in row_cells:
                    # Text might be in text:p or text:p/text:span
                    paragraphs = cell.findall('.//text:p', ns)
                    cell_text = ""
                    cell_style = None
                    
                    # Check for explicit style on paragraph
                    # Or on the span containing the text
                    
                    for p in paragraphs:
                        t = "".join(p.itertext())
                        cell_text += t
                        
                        # Style logic for text color:
                        # 1. Check paragraph style
                        # 2. Check span style if present
                        p_style = p.get(f"{{{ns['style']}}}style-name")
                        
                        # Look for spans
                        spans = p.findall('text:span', ns)
                        if spans:
                            # If spans exist, they likely hold the color
                            for span in spans:
                                span_text = "".join(span.itertext())
                                span_style = span.get(f"{{{ns['text']}}}style-name")
                                cells_data.append((span_text.strip(), span_style))
                        else:
                            # If no spans, use paragraph style
                            cells_data.append((t.strip(), p_style))

            # Verify presence of strings
            full_text_blob = " ".join([c[0] for c in cells_data])
            found_count = 0
            for term in expected_content:
                if term in full_text_blob:
                    expected_content[term] = True
                    found_count += 1
            
            if found_count >= len(expected_content) - 1: # Allow 1 miss
                score += 30
                feedback.append("Data content correct")
            else:
                score += int(30 * (found_count / len(expected_content)))
                feedback.append(f"Partial data match ({found_count}/{len(expected_content)})")

            # 3. Check Formatting (Styles)
            # We need to look up styles in automatic-styles
            auto_styles = root.find('office:automatic-styles', ns)
            styles_map = {} # name -> {property: value}
            
            if auto_styles:
                for style_node in auto_styles:
                    name = style_node.get(f"{{{ns['style']}}}name")
                    props = {}
                    
                    # Text properties (for color)
                    text_props = style_node.find('style:text-properties', ns)
                    if text_props is not None:
                        color = text_props.get(f"{{{ns['fo']}}}color")
                        if color: props['color'] = color
                    
                    # Paragraph properties (for alignment)
                    para_props = style_node.find('style:paragraph-properties', ns)
                    if para_props is not None:
                        align = para_props.get(f"{{{ns['fo']}}}text-align")
                        if align: props['align'] = align
                        
                    styles_map[name] = props

            # Check Colors (Red for No, Green for Yes)
            green_yes_found = False
            red_no_found = False
            
            for text_content, style_name in cells_data:
                if not style_name or style_name not in styles_map:
                    continue
                
                props = styles_map[style_name]
                color = props.get('color', '').lower()
                
                # Check Green Yes
                if text_content == "Yes" and color:
                    # Simple heuristic for green: starts with #00 or #...80...
                    # Or just check it's not red/black/white
                    if color.startswith('#00') or 'green' in color: 
                        green_yes_found = True
                
                # Check Red No
                if text_content == "No" and color:
                    if color.startswith('#ff00') or color.startswith('#cc00') or 'red' in color:
                        red_no_found = True

            if green_yes_found and red_no_found:
                score += 30
                feedback.append("Conditional coloring verified (Red/Green)")
            elif green_yes_found or red_no_found:
                score += 15
                feedback.append("Partial coloring verified")
            else:
                feedback.append("Conditional coloring NOT found")

            # Check Alignment
            # Harder to map specifically to columns without tracking cell indices strictly
            # But we can check if *any* "Basic Plan" or "10 GB" styled text has center align
            center_align_found = False
            
            # Look at paragraph styles for cells containing specific data
            # Note: cell alignment is often on the paragraph style inside the cell
            for text_content, style_name in cells_data:
                if text_content in ["Basic Plan", "Pro Plan", "10 GB", "1 TB"]:
                    if style_name in styles_map:
                        align = styles_map[style_name].get('align', '')
                        if align == 'center':
                            center_align_found = True
                            break
            
            if center_align_found:
                score += 10
                feedback.append("Center alignment verified")
            else:
                feedback.append("Center alignment not found")

    except Exception as e:
        logger.warning(f"Exception during content parsing: {e}")
        return 0, f"Error analyzing content: {str(e)}"

    return score, " | ".join(feedback)