#!/usr/bin/env python3
"""
Verifier for layout_window_envelope_address task.
"""

import json
import logging
import os
import shutil
import tempfile
import zipfile
import re
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Constants (1 inch = 914400 EMUs)
EMU_PER_INCH = 914400

def verify_layout_window_envelope(traj, env_info, task_info):
    """
    Verifies that the address block was moved to a text box and positioned correctly.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    target_x = metadata.get('target_x_inches', 1.0)
    target_y = metadata.get('target_y_inches', 2.0)
    tolerance = metadata.get('tolerance_inches', 0.15)
    
    temp_dir = tempfile.mkdtemp()
    
    try:
        # 1. Fetch Result JSON
        result_json_path = os.path.join(temp_dir, "task_result.json")
        try:
            copy_from_env("C:\\Users\\Docker\\task_result.json", result_json_path)
            with open(result_json_path, 'r') as f:
                result_data = json.load(f)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {str(e)}"}

        if not result_data.get('output_exists'):
            return {"passed": False, "score": 0, "feedback": "Output file 'Contract_Renewal_Letter_Fixed.docx' not found."}

        if not result_data.get('file_created_during_task'):
             # Anti-gaming check
            return {"passed": False, "score": 0, "feedback": "Output file was not modified during the task session."}

        # 2. Fetch Output DOCX
        docx_path = os.path.join(temp_dir, "output.docx")
        try:
            copy_from_env(result_data['output_path'], docx_path)
        except Exception as e:
            return {"passed": False, "score": 0, "feedback": f"Failed to retrieve output document: {str(e)}"}

        # 3. Analyze DOCX XML
        if not zipfile.is_zipfile(docx_path):
             return {"passed": False, "score": 0, "feedback": "Output file is not a valid DOCX/ZIP archive."}

        with zipfile.ZipFile(docx_path, 'r') as docx:
            try:
                document_xml = docx.read('word/document.xml').decode('utf-8')
            except KeyError:
                return {"passed": False, "score": 0, "feedback": "Invalid DOCX structure: missing word/document.xml"}

        # Score Breakdown
        score = 0
        feedback = []
        
        # Criteria 1: Address text is inside a drawing object (Text Box) (30 pts)
        # We search for the name inside a w:txbxContent block which resides in w:drawing or w:pict
        # Simplified check: Find "Sarah Jenkins" and ensure it's wrapped in drawing/textbox tags
        # <w:drawing> ... <w:txbxContent> ... Sarah Jenkins ... </w:txbxContent> ... </w:drawing>
        
        # Note: In Word 2010 compatibility, text boxes might use <w:pict> (VML) or <w:drawing> (DrawingML).
        # We need to be robust.
        
        # Strip namespaces to simplify regex
        xml_content = re.sub(r' xmlns:[\w]+="[^"]+"', '', document_xml)
        
        # Locate the text fragment
        name_pos = xml_content.find("Sarah Jenkins")
        if name_pos == -1:
            return {"passed": False, "score": 0, "feedback": "Critical: Recipient name 'Sarah Jenkins' deleted from document."}
            
        # Check if it's inside a text box
        # We look for <w:txbxContent> or <v:textbox> upstream from the name
        fragment_context = xml_content[max(0, name_pos-2000):min(len(xml_content), name_pos+2000)]
        
        is_in_textbox = False
        if "txbxContent" in fragment_context or "v:textbox" in fragment_context:
            is_in_textbox = True
            score += 30
            feedback.append("Address successfully moved to Text Box.")
        else:
            feedback.append("Address found in document body, not in a Text Box.")
            # If not in text box, we can't check positioning logic properly
            return {"passed": False, "score": score, "feedback": " ".join(feedback)}

        # Criteria 2 & 3: Position (Horizontal and Vertical) (25 pts each)
        # Need to parse XML to find the specific drawing object containing the text
        
        # Parse XML properly to handle complex nesting
        try:
            dom = minidom.parseString(document_xml.encode('utf-8'))
            
            # Find all anchors/shapes
            anchors = dom.getElementsByTagName('wp:anchor')
            inline_shapes = dom.getElementsByTagName('wp:inline') # Should not be inline for this task
            vml_shapes = dom.getElementsByTagName('v:shape') # VML (Word 2010 compatibility)

            target_shape = None
            
            # Helper to check if node contains text
            def node_contains_text(node, text):
                return text in node.toxml()

            # Search in DrawingML Anchors
            for anchor in anchors:
                if node_contains_text(anchor, "Sarah Jenkins"):
                    target_shape = anchor
                    break
            
            pos_x_emu = None
            pos_y_emu = None
            relative_x = None
            relative_y = None
            
            if target_shape:
                # Extract Position Data from DrawingML
                # Horizontal
                posH = target_shape.getElementsByTagName('wp:positionH')[0]
                relative_x = posH.getAttribute('relativeFrom') # Should be "page"
                posOffsetH = posH.getElementsByTagName('wp:posOffset')[0].firstChild.nodeValue
                pos_x_emu = int(posOffsetH)
                
                # Vertical
                posV = target_shape.getElementsByTagName('wp:positionV')[0]
                relative_y = posV.getAttribute('relativeFrom') # Should be "page"
                posOffsetV = posV.getElementsByTagName('wp:posOffset')[0].firstChild.nodeValue
                pos_y_emu = int(posOffsetV)
            
            # Check Horizontal
            target_x_emu = target_x * EMU_PER_INCH
            tolerance_emu = tolerance * EMU_PER_INCH
            
            if pos_x_emu is not None:
                # If relativeFrom is 'margin', we might need to adjust, but task asked for 'Page'.
                # We reward strictly if they followed instructions.
                if relative_x != 'page':
                    feedback.append(f"Horizontal position relative to '{relative_x}' instead of 'page'.")
                    # Penalty or flexible? Let's be strict on instruction "relative to Page"
                
                diff_x = abs(pos_x_emu - target_x_emu)
                if diff_x <= tolerance_emu:
                    score += 25
                    feedback.append(f"Horizontal position correct ({pos_x_emu/EMU_PER_INCH:.2f} in).")
                else:
                    feedback.append(f"Horizontal position incorrect ({pos_x_emu/EMU_PER_INCH:.2f} in). Target: {target_x} in.")
            else:
                feedback.append("Could not determine horizontal position (XML parsing failed or VML used).")

            # Check Vertical
            target_y_emu = target_y * EMU_PER_INCH
            
            if pos_y_emu is not None:
                if relative_y != 'page':
                    feedback.append(f"Vertical position relative to '{relative_y}' instead of 'page'.")
                
                diff_y = abs(pos_y_emu - target_y_emu)
                if diff_y <= tolerance_emu:
                    score += 25
                    feedback.append(f"Vertical position correct ({pos_y_emu/EMU_PER_INCH:.2f} in).")
                else:
                    feedback.append(f"Vertical position incorrect ({pos_y_emu/EMU_PER_INCH:.2f} in). Target: {target_y} in.")
            else:
                feedback.append("Could not determine vertical position.")

            # Criteria 4: Border Removed (20 pts)
            # Look for <a:ln> (line properties)
            # If <a:noFill/> exists inside <a:ln>, or if <a:ln> is missing (depends on default), or w="0"
            if target_shape:
                ln_nodes = target_shape.getElementsByTagName('a:ln')
                has_no_outline = False
                
                if not ln_nodes:
                    # Sometimes no <a:ln> means default line.
                    # Usually explicit "No Outline" results in <a:ln><a:noFill/></a:ln>
                    pass 
                else:
                    for ln in ln_nodes:
                        if ln.getElementsByTagName('a:noFill'):
                            has_no_outline = True
                            break
                        # Check for transparency
                        solid_fill = ln.getElementsByTagName('a:solidFill')
                        if solid_fill:
                             # Check alpha
                             pass

                # If we found explicit noFill, grant points
                if has_no_outline:
                    score += 20
                    feedback.append("Text Box border removed.")
                else:
                    # Fallback check: sometimes Word removes the ln tag completely for no line? 
                    # Actually for Shape Properties, usually it requires explicit NoFill.
                    feedback.append("Text Box border detected (expected No Outline).")

        except Exception as e:
            logger.error(f"XML Parsing Error: {e}")
            feedback.append("Error parsing detailed document structure.")

        passed = score >= 75
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"System error during verification: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)