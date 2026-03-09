#!/usr/bin/env python3
"""
Verifier for API Documentation Styling Task.
Checks for correct creation and application of styles in an ODT file.
"""

import json
import os
import logging
import tempfile
import zipfile
from xml.dom import minidom

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_api_documentation_styling(traj, env_info, task_info):
    """
    Verifies the ODT file for:
    1. Existence of 'Code Block' paragraph style with specific properties (Language=None is critical).
    2. Existence of 'Inline Code' character style.
    3. Application of these styles to the correct content.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_output_path = metadata.get('output_path', '/home/ga/Documents/hyperion_api_formatted.odt')
    
    # Load basic result info
    temp_result_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_result_file.name)
        with open(temp_result_file.name, 'r') as f:
            task_result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load task result: {e}"}
    finally:
        if os.path.exists(temp_result_file.name):
            os.unlink(temp_result_file.name)

    if not task_result.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output file hyperion_api_formatted.odt not found"}

    # Copy the ODT file for analysis
    temp_odt = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
    try:
        copy_from_env(expected_output_path, temp_odt.name)
        
        # ODT is a zip file. We need to parse content.xml and styles.xml
        try:
            with zipfile.ZipFile(temp_odt.name, 'r') as z:
                content_xml = z.read('content.xml')
                styles_xml = z.read('styles.xml') # Some user styles might be here or in content.xml
        except zipfile.BadZipFile:
            return {"passed": False, "score": 0, "feedback": "Output file is not a valid ODT/Zip file"}
            
        # Parse XML
        dom_content = minidom.parseString(content_xml)
        
        # Scoring Criteria
        score = 0
        feedback = []
        
        # 1. Check for 'Code Block' style definition
        # Styles can be in office:automatic-styles or office:styles
        # We need to find a style with name "Code Block" (or close match if user renamed it, but instructions said 'Code Block')
        
        styles_nodes = dom_content.getElementsByTagName('style:style')
        code_block_style = None
        
        for s in styles_nodes:
            name = s.getAttribute('style:name')
            family = s.getAttribute('style:family')
            if "Code Block" in name and family == "paragraph":
                code_block_style = s
                break
                
        # Also check styles.xml if not found in content.xml
        if not code_block_style:
            try:
                dom_styles = minidom.parseString(styles_xml)
                styles_nodes_2 = dom_styles.getElementsByTagName('style:style')
                for s in styles_nodes_2:
                    name = s.getAttribute('style:name')
                    family = s.getAttribute('style:family')
                    if "Code Block" in name and family == "paragraph":
                        code_block_style = s
                        break
            except Exception:
                pass

        if code_block_style:
            score += 20
            feedback.append("Found 'Code Block' paragraph style.")
            
            # Check properties
            # Need to look into <style:paragraph-properties> and <style:text-properties>
            para_props = code_block_style.getElementsByTagName('style:paragraph-properties')
            text_props = code_block_style.getElementsByTagName('style:text-properties')
            
            # Check Background/Border
            if para_props:
                bg = para_props[0].getAttribute('fo:background-color')
                border = para_props[0].getAttribute('fo:border')
                if bg and bg != 'transparent' and bg != 'none':
                    score += 5
                    feedback.append("Code Block background set.")
                else:
                    feedback.append("Code Block missing background color.")
                    
                if border and border != 'none':
                    score += 5
                    feedback.append("Code Block border set.")
                else:
                    feedback.append("Code Block missing border.")
            
            # Check Language (Anti-spellcheck) - CRITICAL
            # fo:language="zxx" or "none"
            spellcheck_disabled = False
            if text_props:
                lang = text_props[0].getAttribute('fo:language')
                country = text_props[0].getAttribute('fo:country')
                if lang in ['zxx', 'none'] or country in ['none', 'zxx']:
                    spellcheck_disabled = True
            
            if spellcheck_disabled:
                score += 20
                feedback.append("Spellcheck correctly disabled for Code Block.")
            else:
                feedback.append("FAIL: Spellcheck NOT disabled for Code Block (Language should be None).")
                
            # Check Font (Monospace)
            if text_props:
                font_name = text_props[0].getAttribute('style:font-name')
                if any(x in font_name.lower() for x in ['mono', 'courier', 'console', 'terminal']):
                    score += 5
                    feedback.append("Code Block font appears monospaced.")
                    
        else:
            feedback.append("FAIL: 'Code Block' paragraph style not found.")

        # 2. Check for 'Inline Code' character style
        inline_style = None
        # Re-scan styles for character style
        all_style_sources = [dom_content]
        if 'dom_styles' in locals(): all_style_sources.append(dom_styles)
        
        for dom in all_style_sources:
            for s in dom.getElementsByTagName('style:style'):
                name = s.getAttribute('style:name')
                family = s.getAttribute('style:family')
                if "Inline Code" in name and family == "text":
                    inline_style = s
                    break
            if inline_style: break
            
        if inline_style:
            score += 10
            feedback.append("Found 'Inline Code' character style.")
            
            # Check highlight
            text_props = inline_style.getElementsByTagName('style:text-properties')
            if text_props:
                bg = text_props[0].getAttribute('fo:background-color') # For char style, sometimes it's this or style:text-background-color
                if not bg: bg = text_props[0].getAttribute('style:text-background-color')
                
                if bg and bg != 'transparent' and bg != 'none':
                    score += 5
                    feedback.append("Inline Code highlight set.")
                else:
                    feedback.append("Inline Code missing highlight color.")
        else:
            feedback.append("FAIL: 'Inline Code' character style not found.")

        # 3. Check Application of Styles
        # Count paragraphs using Code Block
        paras = dom_content.getElementsByTagName('text:p')
        code_block_count = 0
        for p in paras:
            style_name = p.getAttribute('text:style-name')
            if "Code Block" in style_name:
                code_block_count += 1
        
        # There are roughly 15-20 lines of code in the snippets
        if code_block_count >= 5:
            score += 15
            feedback.append(f"Code Block style applied to {code_block_count} paragraphs (Good).")
        elif code_block_count > 0:
            score += 5
            feedback.append(f"Code Block style applied to only {code_block_count} paragraphs (Expected > 5).")
        else:
            feedback.append("FAIL: Code Block style not applied to any text.")

        # Count spans using Inline Code
        spans = dom_content.getElementsByTagName('text:span')
        inline_count = 0
        target_terms = ["api_key", "Authorization", "Content-Type", "HTTP 200"]
        found_terms = set()
        
        for s in spans:
            style_name = s.getAttribute('text:style-name')
            if "Inline Code" in style_name:
                # Check text content
                text_content = ""
                for child in s.childNodes:
                    if child.nodeType == child.TEXT_NODE:
                        text_content += child.data
                
                if any(term in text_content for term in target_terms):
                    inline_count += 1
                    for term in target_terms:
                        if term in text_content:
                            found_terms.add(term)

        if inline_count >= 3:
            score += 15
            feedback.append(f"Inline Code style applied to {inline_count} instances.")
            if len(found_terms) >= 2:
                feedback.append(f"Terms found styled: {', '.join(found_terms)}")
        else:
            feedback.append(f"Inline Code style applied sparingly or not at all ({inline_count} instances).")

        # 4. Check File Creation Timestamp (Anti-Gaming)
        if task_result.get('file_created_during_task', False):
            score += 5
            feedback.append("File modification verified during task window.")
        else:
            feedback.append("WARNING: File not modified during task.")

        return {
            "passed": score >= 70,
            "score": score,
            "feedback": " | ".join(feedback)
        }

    except Exception as e:
        import traceback
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}\n{traceback.format_exc()}"}
    finally:
        if os.path.exists(temp_odt.name):
            os.unlink(temp_odt.name)