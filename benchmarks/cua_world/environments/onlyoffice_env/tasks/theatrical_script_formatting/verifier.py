#!/usr/bin/env python3
"""
Verifier for Theatrical Script Formatting task.

Extracts the raw word/document.xml from the output DOCX to independently 
verify localized text styling (Bold, Italic, Alignment, and Font Size)
without relying on host-side dependencies like python-docx.
"""

import json
import os
import tempfile
import logging
import zipfile
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def analyze_docx_paragraphs(docx_path):
    """
    Parses the DOCX XML to retrieve a list of dictionaries 
    detailing the text content and styling for each paragraph.
    """
    ns = {'w': 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'}
    paragraphs = []
    
    try:
        with zipfile.ZipFile(docx_path) as z:
            xml_content = z.read('word/document.xml')
            root = ET.fromstring(xml_content)
            
            for p in root.findall('.//w:p', ns):
                p_text = "".join([t.text for t in p.findall('.//w:t', ns) if t.text])
                if not p_text.strip():
                    continue

                fmt = {
                    'text': p_text.strip(), 
                    'center': False, 
                    'bold': False, 
                    'italic': False, 
                    'sz24': False
                }

                # Evaluate paragraph alignment
                jc = p.find('.//w:pPr/w:jc', ns)
                if jc is not None and jc.get(f"{{{ns['w']}}}val") == 'center':
                    fmt['center'] = True

                # Evaluate text run properties
                for r in p.findall('.//w:r', ns):
                    r_text = "".join([t.text for t in r.findall('.//w:t', ns) if t.text])
                    if r_text.strip():
                        rPr = r.find('.//w:rPr', ns)
                        if rPr is not None:
                            if rPr.find('w:b', ns) is not None: 
                                fmt['bold'] = True
                            if rPr.find('w:i', ns) is not None: 
                                fmt['italic'] = True
                            sz = rPr.find('w:sz', ns)
                            if sz is not None and sz.get(f"{{{ns['w']}}}val") == '24':
                                fmt['sz24'] = True
                            szCs = rPr.find('w:szCs', ns)
                            if szCs is not None and szCs.get(f"{{{ns['w']}}}val") == '24':
                                fmt['sz24'] = True

                paragraphs.append(fmt)
    except Exception as e:
        logger.error(f"Error parsing DOCX internally: {e}")
        
    return paragraphs

def verify_theatrical_script_formatting(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    temp_docx = tempfile.NamedTemporaryFile(delete=False, suffix='.docx')

    try:
        # 1. Fetch JSON export
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)

        if not result.get('output_exists', False):
            return {
                "passed": False, 
                "score": 0, 
                "feedback": "Output DOCX file was not found at the expected location."
            }
            
        if not result.get('file_created_during_task', False):
            return {
                "passed": False,
                "score": 0,
                "feedback": "DOCX file exists but was not created/modified during the task window."
            }

        # 2. Fetch target DOCX
        target_docx_path = task_info.get('metadata', {}).get('expected_output_path', '/home/ga/Documents/TextDocuments/cherry_orchard_script.docx')
        copy_from_env(target_docx_path, temp_docx.name)

        # 3. Analyze Paragraphs
        paragraphs = analyze_docx_paragraphs(temp_docx.name)

        if not paragraphs:
            return {"passed": False, "score": 10, "feedback": "File created but DOCX is empty or unreadable."}

        score = 10  # 10 Base points for successfully creating the file
        feedback_parts = ["File created"]

        # 4. Target flags
        heading_found, heading_correct = False, False
        desc_found, desc_correct = False, False
        char_found, char_correct = False, False
        stage_found, stage_correct = False, False
        diag_found, diag_correct = False, False
        font_12pt_count = 0

        for p in paragraphs:
            text = p['text']
            
            if p['sz24']:
                font_12pt_count += 1

            # Criterion: Scene Heading (Bold, Centered)
            if "ACT I" in text:
                heading_found = True
                if p['bold'] and p['center']:
                    heading_correct = True

            # Criterion: Scene Description (Italicized)
            elif "A room, which has always been called" in text:
                desc_found = True
                if p['italic']:
                    desc_correct = True

            # Criterion: Character Names (Centered)
            elif text in ["LOPAKHIN", "DUNYASHA"]:
                char_found = True
                if p['center']:
                    char_correct = True

            # Criterion: Stage directions (Italicized)
            elif "[Yawns and stretches.]" in text or "[Puts out the candle.]" in text:
                stage_found = True
                if p['italic']:
                    stage_correct = True

            # Criterion/Anti-Game: Dialogue remains mostly untouched
            elif "The train is in, thank God." in text or "Nearly two." in text:
                diag_found = True
                if not p['center'] and not p['italic'] and not p['bold']:
                    diag_correct = True

        # 5. Tally points
        if heading_found and heading_correct:
            score += 15
            feedback_parts.append("Heading properly formatted")
            
        if desc_found and desc_correct:
            score += 15
            feedback_parts.append("Description properly formatted")
            
        if char_found and char_correct:
            score += 20
            feedback_parts.append("Character names centered")
            
        if stage_found and stage_correct:
            score += 15
            feedback_parts.append("Stage directions italicized")
            
        if diag_found and diag_correct:
            score += 15
            feedback_parts.append("Dialogue untouched (anti-game clear)")
        elif diag_found and not diag_correct:
            feedback_parts.append("Dialogue was incorrectly formatted (failed anti-gaming check)")

        if font_12pt_count > 0:
            score += 10
            feedback_parts.append("12pt font detected")

        # 6. Evaluation Threshold
        # Requires at least 70 points AND proves selective formatting by passing Dialogue isolation
        passed = (score >= 70 and char_correct and diag_correct)

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Error during verification: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)
        if os.path.exists(temp_docx.name):
            os.unlink(temp_docx.name)