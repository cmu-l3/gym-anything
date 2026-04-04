#!/usr/bin/env python3
"""
Verifier for Magazine Article Typesetting task.
Verifies ODT file structure for columns, drop caps, hyphenation, and text boxes.
"""

import json
import os
import zipfile
import logging
import shutil
import tempfile
from lxml import etree

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_magazine_layout(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Setup
    metadata = task_info.get('metadata', {})
    output_path = metadata.get('output_file', '/home/ga/Documents/article_layout.odt')
    pull_quote_text = metadata.get('pull_quote_text', 'tiny ecosystems')
    
    score = 0
    feedback = []
    
    # Create temp dir for analysis
    temp_dir = tempfile.mkdtemp()
    local_odt = os.path.join(temp_dir, "article_layout.odt")
    
    try:
        # Copy file
        try:
            copy_from_env(output_path, local_odt)
        except Exception:
            return {"passed": False, "score": 0, "feedback": "Output file not found"}
        
        if not os.path.exists(local_odt):
            return {"passed": False, "score": 0, "feedback": "Output file did not download correctly"}
            
        # Unzip ODT
        with zipfile.ZipFile(local_odt, 'r') as z:
            content_xml = z.read('content.xml')
            styles_xml = z.read('styles.xml')
            
        # Parse XML
        ns = {
            'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
            'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
            'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
            'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
            'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0'
        }
        
        root = etree.fromstring(content_xml)
        styles_root = etree.fromstring(styles_xml)
        
        # --- CHECK 1: Two-Column Layout (20 pts) ---
        # Look for a section style with column-count="2"
        # The section is usually in content.xml auto styles or styles.xml
        cols_found = False
        
        # Helper to check style roots
        for r in [root, styles_root]:
            # Find automatic styles or common styles
            for styles_container in r.findall('.//office:automatic-styles', ns) + r.findall('.//office:styles', ns):
                if styles_container is None: continue
                
                # Check section properties
                for style_node in styles_container.findall('style:style', ns):
                    if style_node.get(f'{{{ns["style"]}}}family') == 'section':
                        props = style_node.find('style:section-properties', ns)
                        if props is not None:
                            cols = props.find('style:columns', ns)
                            if cols is not None and cols.get(f'{{{ns["style"]}}}column-count') == '2':
                                cols_found = True
                                break
            if cols_found: break

        # Also check direct section definitions in body
        if not cols_found:
             # Sometimes sections are defined but verify if the text is actually inside a section
             sections = root.findall('.//text:section', ns)
             if len(sections) > 0:
                 # Check if any section refers to a style with 2 columns
                 pass # The style check above should cover this if we found the style name
        
        if cols_found:
            score += 20
            feedback.append("Two-column layout detected.")
        else:
            feedback.append("Two-column layout NOT detected.")

        # --- CHECK 2: Drop Cap (20 pts) ---
        # Look for drop-cap property in paragraph properties
        drop_cap_found = False
        for r in [root, styles_root]:
            for styles_container in r.findall('.//office:automatic-styles', ns) + r.findall('.//office:styles', ns):
                for style_node in styles_container.findall('style:style', ns):
                    if style_node.get(f'{{{ns["style"]}}}family') == 'paragraph':
                        props = style_node.find('style:paragraph-properties', ns)
                        if props is not None:
                            dc = props.find('style:drop-cap', ns)
                            if dc is not None:
                                lines = dc.get(f'{{{ns["style"]}}}lines')
                                if lines and int(lines) >= 2:
                                    drop_cap_found = True
                                    break
            if drop_cap_found: break
            
        if drop_cap_found:
            score += 20
            feedback.append("Drop cap detected.")
        else:
            feedback.append("Drop cap NOT detected.")

        # --- CHECK 3: Hyphenation (15 pts) ---
        hyphen_found = False
        for r in [root, styles_root]:
            for styles_container in r.findall('.//office:automatic-styles', ns) + r.findall('.//office:styles', ns):
                for style_node in styles_container.findall('style:style', ns):
                    props = style_node.find('style:paragraph-properties', ns)
                    if props is not None:
                        hyphen = props.get(f'{{{ns["fo"]}}}hyphenate')
                        if hyphen == 'true':
                            hyphen_found = True
                            break
            if hyphen_found: break
            
        if hyphen_found:
            score += 15
            feedback.append("Hyphenation enabled.")
        else:
            feedback.append("Hyphenation NOT detected.")
            
        # --- CHECK 4: Justified Alignment (15 pts) ---
        justify_found = False
        for r in [root, styles_root]:
            for styles_container in r.findall('.//office:automatic-styles', ns) + r.findall('.//office:styles', ns):
                for style_node in styles_container.findall('style:style', ns):
                    props = style_node.find('style:paragraph-properties', ns)
                    if props is not None:
                        align = props.get(f'{{{ns["fo"]}}}text-align')
                        if align == 'justify':
                            justify_found = True
                            break
            if justify_found: break
            
        if justify_found:
            score += 15
            feedback.append("Justified alignment detected.")
        else:
            feedback.append("Justified alignment NOT detected.")

        # --- CHECK 5: Pull Quote (30 pts split) ---
        # 1. Text exists (15)
        # 2. Inside a Frame/TextBox with Wrapping (15)
        
        # Find the text node containing the quote
        text_content = ""
        quote_fragment = "ecosystems can lower urban"
        quote_found_in_doc = False
        quote_in_frame = False
        wrapping_on = False
        
        # Iterate all text:p
        for p in root.iter(f'{{{ns["text"]}}}p'):
            if p.text and quote_fragment in p.text:
                quote_found_in_doc = True
                # Check ancestors for draw:text-box or draw:frame
                parent = p.getparent()
                while parent is not None:
                    if parent.tag == f'{{{ns["draw"]}}}text-box' or parent.tag == f'{{{ns["draw"]}}}frame':
                        quote_in_frame = True
                        
                        # If frame, check style for wrapping
                        if parent.tag == f'{{{ns["draw"]}}}frame':
                            style_name = parent.get(f'{{{ns["draw"]}}}style-name')
                            # Find this style
                            for r_style in [root, styles_root]:
                                for styles_cont in r_style.findall('.//office:automatic-styles', ns):
                                    style_node = styles_cont.find(f'style:style[@style:name="{style_name}"]', ns)
                                    if style_node is not None:
                                        g_props = style_node.find('style:graphic-properties', ns)
                                        if g_props is not None:
                                            wrap = g_props.get(f'{{{ns["style"]}}}wrap')
                                            if wrap in ['dynamic', 'parallel', 'left', 'right']:
                                                wrapping_on = True
                        break
                    parent = parent.getparent()
                break
        
        if quote_in_frame:
            score += 15
            feedback.append("Pull quote found inside a text box/frame.")
        elif quote_found_in_doc:
            score += 5
            feedback.append("Pull quote text found, but NOT in a text box/frame.")
        else:
            feedback.append("Pull quote text NOT found.")
            
        if wrapping_on:
            score += 15
            feedback.append("Text wrapping enabled on pull quote.")
        elif quote_in_frame:
             # Backup: sometimes wrap is default or inherited. If frame exists in middle of text, assumed ok?
             # No, strict check on attribute is safer.
             feedback.append("Text wrapping property not explicitly found (might be default or missing).")

    except Exception as e:
        logger.error(f"Verification error: {e}")
        return {"passed": False, "score": score, "feedback": f"Error during verification: {str(e)}"}
    finally:
        shutil.rmtree(temp_dir)

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " ".join(feedback)
    }