#!/usr/bin/env python3
"""
Verifier for fix_typos_and_language task.
Checks:
1. File was modified.
2. Typos "distrubution", "paitents", "barriar" are GONE.
3. Corrections "distribution", "patients", "barrier" are PRESENT.
4. French text "Nous devons collaborer" has language set to French (fr).
"""

import json
import os
import zipfile
import tempfile
import logging
import xml.etree.ElementTree as ET

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF XML Namespaces
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0',
    'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
}

def verify_typos_and_language(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    typos = metadata.get('typos', ["distrubution", "paitents", "barriar"])
    corrections = metadata.get('corrections', ["distribution", "patients", "barrier"])
    french_fragment = metadata.get('french_fragment', "Nous devons collaborer")
    
    # 1. Get result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to load result JSON: {e}"}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    if not result.get('output_exists'):
        return {"passed": False, "score": 0, "feedback": "Presentation file not found"}

    if not result.get('file_modified'):
        return {"passed": False, "score": 0, "feedback": "Presentation file was not modified (did you save?)"}

    # 2. Get ODP file
    temp_odp = tempfile.NamedTemporaryFile(delete=False, suffix='.odp')
    try:
        copy_from_env(result['output_path'], temp_odp.name)
        
        # 3. Parse ODP content
        try:
            with zipfile.ZipFile(temp_odp.name, 'r') as z:
                content_xml = z.read('content.xml')
                # Sometimes styles are in styles.xml, but automatic styles are often in content.xml
                # We'll check content.xml first
                
            root = ET.fromstring(content_xml)
        except Exception as e:
            return {"passed": False, "score": 10, "feedback": f"Failed to parse ODP file: {e}"}

        # --- Check 1: Typos & Corrections ---
        all_text_elements = root.findall('.//text:p', NS)
        all_text = " ".join([" ".join(elem.itertext()) for elem in all_text_elements])
        
        score = 10  # Base score for valid file mod
        feedback_parts = []
        
        # Check typos gone
        typos_found = [t for t in typos if t in all_text]
        if not typos_found:
            score += 30
            feedback_parts.append("✅ All typos removed")
        else:
            feedback_parts.append(f"❌ Typos still present: {', '.join(typos_found)}")

        # Check corrections present
        corrections_missing = [c for c in corrections if c not in all_text]
        if not corrections_missing:
            score += 15
            feedback_parts.append("✅ Corrections verified")
        else:
            feedback_parts.append(f"❌ Corrections missing: {', '.join(corrections_missing)}")

        # --- Check 2: Language Setting ---
        # Strategy: Find the paragraph containing the French text, get its style name,
        # find the style definition, check for fo:language="fr"
        
        french_lang_set = False
        target_style_name = None
        
        # Find the text element containing the fragment
        for elem in all_text_elements:
            elem_text = "".join(elem.itertext())
            if french_fragment in elem_text:
                # Get the style name
                target_style_name = elem.get(f"{{{NS['text']}}}style-name")
                
                # Also check direct formatting (span)
                # If user selected text and applied language, it might be in a text:span inside text:p
                for span in elem.findall('.//text:span', NS):
                    if french_fragment in "".join(span.itertext()):
                        span_style = span.get(f"{{{NS['text']}}}style-name")
                        if span_style:
                            target_style_name = span_style
                break
        
        if target_style_name:
            # Find the style definition
            # Styles can be in <office:automatic-styles> or <office:styles>
            # Language is usually an automatic style if applied directly
            
            style_found = False
            
            # Helper to check style node
            def check_style_node(style_node):
                text_props = style_node.find('style:text-properties', NS)
                if text_props is not None:
                    lang = text_props.get(f"{{{NS['fo']}}}language")
                    country = text_props.get(f"{{{NS['fo']}}}country")
                    # Accept 'fr' language, or 'fr' country if language is missing (rare)
                    if (lang and lang.lower() == 'fr') or (country and country.lower() in ['fr', 'ca', 'be']):
                        return True
                return False

            # Search in automatic styles
            auto_styles = root.find('office:automatic-styles', NS)
            if auto_styles is not None:
                for style_node in auto_styles.findall('style:style', NS):
                    if style_node.get(f"{{{NS['style']}}}name") == target_style_name:
                        if check_style_node(style_node):
                            french_lang_set = True
                        style_found = True
                        break
            
            # Search in common styles (if not found in automatic)
            if not style_found:
                common_styles = root.find('office:styles', NS)
                if common_styles is not None:
                    for style_node in common_styles.findall('style:style', NS):
                        if style_node.get(f"{{{NS['style']}}}name") == target_style_name:
                            if check_style_node(style_node):
                                french_lang_set = True
                            break
                            
            if french_lang_set:
                score += 45
                feedback_parts.append("✅ French language metadata correctly set")
            else:
                feedback_parts.append("❌ French text found, but language metadata not set to French")
        else:
             feedback_parts.append("❌ Could not locate the French text paragraph in structure")

        # Determine pass/fail
        passed = (len(typos_found) == 0) and (len(corrections_missing) == 0) and french_lang_set
        
        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts)
        }

    except Exception as e:
        logger.error(f"Error during ODP verification: {e}")
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    finally:
        if os.path.exists(temp_odp.name):
            os.unlink(temp_odp.name)