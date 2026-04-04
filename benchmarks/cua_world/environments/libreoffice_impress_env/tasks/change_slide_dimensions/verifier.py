#!/usr/bin/env python3
"""
Verifier for change_slide_dimensions task.
Checks that slide dimensions were changed to 16:9 widescreen
and that content was preserved.
"""

import json
import os
import tempfile
import logging
import zipfile
import xml.etree.ElementTree as ET
import sys

# Import shared verification utils if available, but define local fallbacks for robustness
try:
    sys.path.insert(0, '/workspace/utils')
    from impress_verification_utils import get_slide_count, verify_text_on_slide, parse_odp_file
    UTILS_AVAILABLE = True
except ImportError:
    UTILS_AVAILABLE = False

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def parse_cm_value(value_str):
    """Parse a dimension string like '25.4cm' or '33.867cm' to float cm value."""
    if not value_str:
        return None
    value_str = value_str.strip()
    if value_str.endswith('cm'):
        return float(value_str[:-2])
    elif value_str.endswith('in'):
        return float(value_str[:-2]) * 2.54
    elif value_str.endswith('mm'):
        return float(value_str[:-2]) / 10.0
    elif value_str.endswith('pt'):
        return float(value_str[:-2]) * 0.03528
    else:
        try:
            return float(value_str)
        except ValueError:
            return None

def get_page_dimensions_from_odp(filepath):
    """
    Extract page dimensions from ODP file by parsing styles.xml.
    Returns (width_cm, height_cm) or (None, None).
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as z:
            # Check both styles.xml and content.xml for page layout properties
            for xml_file in ['styles.xml', 'content.xml']:
                if xml_file not in z.namelist():
                    continue
                xml_content = z.read(xml_file)
                root = ET.fromstring(xml_content)

                # Namespace map
                namespaces = {
                    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
                }

                # Iterate through all elements to find page-layout-properties
                for elem in root.iter():
                    if 'page-layout-properties' in elem.tag:
                        # Extract attributes manually or via namespace
                        pw = elem.get(f'{{{namespaces["fo"]}}}page-width')
                        ph = elem.get(f'{{{namespaces["fo"]}}}page-height')
                        
                        if not pw: # Try without namespace if failed (robustness)
                            for k, v in elem.attrib.items():
                                if 'page-width' in k: pw = v
                                if 'page-height' in k: ph = v
                                
                        if pw and ph:
                            width_cm = parse_cm_value(pw)
                            height_cm = parse_cm_value(ph)
                            if width_cm and height_cm:
                                return width_cm, height_cm

        return None, None
    except Exception as e:
        logger.error(f"Error reading page dimensions: {e}")
        return None, None

def verify_change_slide_dimensions(traj, env_info, task_info):
    """
    Verify the slide dimensions task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    metadata = task_info.get('metadata', {})
    target_path = metadata.get('target_path', '/home/ga/Documents/Presentations/it_strategy_q4.odp')
    target_ratio = metadata.get('target_ratio', 1.778)
    ratio_tolerance = metadata.get('ratio_tolerance', 0.08)
    expected_titles = metadata.get('expected_titles', [])
    original_width = metadata.get('original_width_cm', 25.4)
    
    score = 0
    feedback_parts = []
    
    # 1. Get task result JSON
    result_json_path = tempfile.mktemp(suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", result_json_path)
        with open(result_json_path, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to retrieve result JSON: {str(e)}"}
    finally:
        if os.path.exists(result_json_path):
            os.remove(result_json_path)
            
    # 2. Check basic file status
    if not result_data.get('output_exists', False):
        return {"passed": False, "score": 0, "feedback": "Output presentation file not found"}
        
    score += 10
    feedback_parts.append("File exists")
    
    # 3. Check modification timestamp (Anti-gaming)
    if result_data.get('file_modified_during_task', False):
        score += 10
        feedback_parts.append("File modified during task")
    else:
        feedback_parts.append("Warning: File timestamp indicates no modification")
        
    # 4. Copy ODP file for analysis
    odp_local_path = tempfile.mktemp(suffix='.odp')
    try:
        copy_from_env(target_path, odp_local_path)
        
        # 5. Check Dimensions
        width, height = get_page_dimensions_from_odp(odp_local_path)
        
        if width and height:
            actual_ratio = width / height
            
            # Check aspect ratio (Target 16:9 approx 1.778)
            if abs(actual_ratio - target_ratio) <= ratio_tolerance:
                score += 35
                feedback_parts.append(f"Aspect ratio is 16:9 ({actual_ratio:.2f})")
            else:
                feedback_parts.append(f"Incorrect aspect ratio: {actual_ratio:.2f} (expected ~{target_ratio:.2f})")
                
            # Check that it actually changed from original (25.4cm)
            if abs(width - original_width) > 1.0: # 1cm tolerance
                score += 15
                feedback_parts.append("Dimensions changed from original")
            else:
                feedback_parts.append("Dimensions unchanged from original 4:3")
        else:
            feedback_parts.append("Could not extract dimensions from file")
            
        # 6. Check Content Preservation
        if UTILS_AVAILABLE:
            try:
                data = parse_odp_file(odp_local_path)
                slide_count = get_slide_count(data)
                
                if slide_count == 4:
                    score += 15
                    feedback_parts.append("Slide count preserved (4)")
                else:
                    feedback_parts.append(f"Slide count changed: {slide_count} (expected 4)")
                    
                # Check titles
                titles_found = 0
                for title in expected_titles:
                    found = False
                    for i in range(slide_count):
                        if verify_text_on_slide(data, i, title, case_sensitive=False):
                            found = True
                            break
                    if found:
                        titles_found += 1
                        
                if titles_found >= 3:
                    score += 15
                    feedback_parts.append(f"Content preserved ({titles_found}/4 titles found)")
                else:
                    feedback_parts.append(f"Content missing ({titles_found}/4 titles found)")
                    
            except Exception as e:
                feedback_parts.append(f"Content verification failed: {str(e)}")
        else:
            # Fallback if utils not available: simple XML string search
            with zipfile.ZipFile(odp_local_path, 'r') as z:
                content_xml = z.read('content.xml').decode('utf-8')
                titles_found = sum(1 for title in expected_titles if title in content_xml)
                if titles_found >= 3:
                    score += 30 # Combine slide count + text score for simple fallback
                    feedback_parts.append("Content text found in file")
    
    except Exception as e:
        feedback_parts.append(f"File analysis failed: {str(e)}")
    finally:
        if os.path.exists(odp_local_path):
            os.remove(odp_local_path)
            
    return {
        "passed": score >= 60,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }