#!/usr/bin/env python3
"""
Verifier for transcript_style_chaining task.

Verifies:
1. Output ODT file exists and is valid.
2. "Speaker Label" style exists (Bold, Keep with Next, Next Style -> Minute Text).
3. "Minute Text" style exists (Indented, Next Style -> Speaker Label).
4. Content paragraphs have the correct styles applied.
"""

import json
import os
import zipfile
import tempfile
import logging
import shutil
from xml.etree import ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Namespaces in ODT XML
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
}

def verify_transcript_style_chaining(traj, env_info, task_info):
    """
    Verify the ODT document for correct style definitions and application.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Setup
    output_path = task_info.get('metadata', {}).get('output_file', '/home/ga/Documents/council_minutes_formatted.odt')
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "result.odt")
    
    feedback_parts = []
    score = 0
    
    try:
        # Copy file
        try:
            copy_from_env(output_path, local_odt)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Output file not found"}

        if not os.path.exists(local_odt) or os.path.getsize(local_odt) == 0:
            return {"passed": False, "score": 0, "feedback": "Output file is empty or missing"}
            
        score += 10 # File exists
        
        # Unzip ODT
        try:
            with zipfile.ZipFile(local_odt, 'r') as z:
                z.extractall(temp_dir)
        except zipfile.BadZipFile:
            return {"passed": False, "score": score, "feedback": "Output is not a valid ODT/Zip file"}

        # Parse XMLs
        styles_xml_path = os.path.join(temp_dir, "styles.xml")
        content_xml_path = os.path.join(temp_dir, "content.xml")
        
        if not os.path.exists(content_xml_path):
            return {"passed": False, "score": score, "feedback": "Invalid ODT: missing content.xml"}

        # Load Styles
        # Styles can be in styles.xml (common) or content.xml (automatic)
        # We need to look for style:style elements with style:family="paragraph"
        
        styles_tree = ET.parse(styles_xml_path) if os.path.exists(styles_xml_path) else None
        content_tree = ET.parse(content_xml_path)
        
        # ---------------------------------------------------------
        # 1. VERIFY STYLE DEFINITIONS
        # ---------------------------------------------------------
        
        speaker_style_name = "Speaker Label"
        text_style_name = "Minute Text"
        
        # Helper to find style node by display name
        def find_style_node(name):
            # LibreOffice stores user styles in styles.xml usually
            # Look in styles.xml first
            if styles_tree:
                for s in styles_tree.findall(".//style:style", NS):
                    if s.get(f"{{{NS['style']}}}name") == name or s.get(f"{{{NS['style']}}}display-name") == name:
                        return s
            # Then content.xml
            for s in content_tree.findall(".//style:style", NS):
                if s.get(f"{{{NS['style']}}}name") == name or s.get(f"{{{NS['style']}}}display-name") == name:
                    return s
            return None

        speaker_node = find_style_node(speaker_style_name)
        text_node = find_style_node(text_style_name)
        
        speaker_valid = False
        text_valid = False
        chain_valid = False
        
        # Verify Speaker Style
        if speaker_node is not None:
            score += 10
            feedback_parts.append(f"Style '{speaker_style_name}' found")
            speaker_valid = True
            
            # Check properties
            props = speaker_node.find("style:text-properties", NS)
            para_props = speaker_node.find("style:paragraph-properties", NS)
            
            # Check Bold
            is_bold = False
            if props is not None:
                fw = props.get(f"{{{NS['fo']}}}font-weight")
                if fw == "bold":
                    is_bold = True
            
            if is_bold:
                score += 10
                feedback_parts.append("Speaker style is Bold")
            else:
                feedback_parts.append("Speaker style missing Bold")
                
            # Check Keep with Next (optional but requested)
            # fo:keep-with-next="always"
            
            # Check Next Style
            next_style = speaker_node.get(f"{{{NS['style']}}}next-style-name")
            if next_style == text_style_name:
                chain_valid = True # Part 1 of chain
                feedback_parts.append("Speaker next-style correct")
            else:
                feedback_parts.append(f"Speaker next-style incorrect (found: {next_style})")
        else:
            feedback_parts.append(f"Style '{speaker_style_name}' NOT found")

        # Verify Text Style
        if text_node is not None:
            score += 10
            feedback_parts.append(f"Style '{text_style_name}' found")
            text_valid = True
            
            # Check properties
            para_props = text_node.find("style:paragraph-properties", NS)
            
            # Check Indent
            is_indented = False
            if para_props is not None:
                ml = para_props.get(f"{{{NS['fo']}}}margin-left")
                # Expecting ~0.5in or 1.27cm. XML might have "0.5in" or "1.27cm"
                if ml and (("in" in ml and float(ml.replace("in","")) >= 0.4) or 
                           ("cm" in ml and float(ml.replace("cm","")) >= 1.0)):
                    is_indented = True
            
            if is_indented:
                score += 10
                feedback_parts.append("Text style is Indented")
            else:
                feedback_parts.append("Text style missing Indent")

            # Check Next Style (Loop back)
            next_style = text_node.get(f"{{{NS['style']}}}next-style-name")
            if next_style == speaker_style_name:
                if chain_valid: 
                    score += 30 # Full chain bonus
                    feedback_parts.append("Style Chain Loop verified")
                else:
                    score += 15 # Partial chain
            else:
                feedback_parts.append(f"Text next-style incorrect (found: {next_style})")
        else:
            feedback_parts.append(f"Style '{text_style_name}' NOT found")

        # ---------------------------------------------------------
        # 2. VERIFY CONTENT APPLICATION
        # ---------------------------------------------------------
        
        # We need to check if the paragraphs in content.xml actually use these styles
        # Structure: <office:body><office:text><text:p text:style-name="...">Content</text:p>
        
        body = content_tree.find(".//office:body/office:text", NS)
        paragraphs = body.findall("text:p", NS)
        
        speaker_lines_correct = 0
        speaker_lines_total = 0
        text_lines_correct = 0
        text_lines_total = 0
        
        for p in paragraphs:
            text_content = "".join(p.itertext()).strip()
            if not text_content:
                continue
                
            style_attr = p.get(f"{{{NS['text']}}}style-name")
            
            # Identify if it should be speaker or text
            if text_content.endswith(":"):
                speaker_lines_total += 1
                # Check if style matches (handling potential internal renaming by LO)
                # LO might rename "Speaker Label" to "Speaker_20_Label" internally
                # But strict check first
                if style_attr == speaker_style_name:
                    speaker_lines_correct += 1
                elif speaker_node is not None and style_attr == speaker_node.get(f"{{{NS['style']}}}name"):
                    speaker_lines_correct += 1
            else:
                text_lines_total += 1
                if style_attr == text_style_name:
                    text_lines_correct += 1
                elif text_node is not None and style_attr == text_node.get(f"{{{NS['style']}}}name"):
                    text_lines_correct += 1

        # Score Application
        app_score = 0
        if speaker_lines_total > 0:
            pct = speaker_lines_correct / speaker_lines_total
            if pct > 0.8: app_score += 10
        
        if text_lines_total > 0:
            pct = text_lines_correct / text_lines_total
            if pct > 0.8: app_score += 10
            
        score += app_score
        feedback_parts.append(f"Applied Styles: Speaker({speaker_lines_correct}/{speaker_lines_total}), Text({text_lines_correct}/{text_lines_total})")

        return {
            "passed": score >= 70 and chain_valid,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.exception("Verification failed")
        return {"passed": False, "score": score, "feedback": f"Verification error: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)