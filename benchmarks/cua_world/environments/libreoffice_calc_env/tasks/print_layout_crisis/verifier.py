#!/usr/bin/env python3
"""
Verifier for Print Layout Crisis task.
Analyzes ODS file to verify print configuration is optimized for reasonable page layout.
"""

import sys
import os
import logging
import zipfile
import xml.etree.ElementTree as ET
import math
import re

# Add utils to path (relative path for host machine execution)
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_verification_environment,
    cleanup_verification_environment
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ODF namespaces for XML parsing
NS = {
    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0',
    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
    'svg': 'urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0'
}


def convert_to_inches(dimension_str):
    """Convert dimension string (e.g., '2cm', '0.75in', '1.905cm') to inches"""
    if not dimension_str:
        return 1.0
    
    dimension_str = dimension_str.strip()
    
    try:
        if 'cm' in dimension_str:
            value = float(dimension_str.replace('cm', ''))
            return value / 2.54
        elif 'in' in dimension_str:
            value = float(dimension_str.replace('in', ''))
            return value
        elif 'mm' in dimension_str:
            value = float(dimension_str.replace('mm', ''))
            return value / 25.4
        else:
            # Try to parse as numeric (assume cm as default)
            value = float(dimension_str)
            return value / 2.54
    except (ValueError, TypeError):
        logger.warning(f"Could not parse dimension: {dimension_str}")
        return 1.0


def parse_ods_print_config(ods_path):
    """
    Extract page layout and print configuration from ODS file.
    
    Returns:
        dict: Configuration including orientation, scaling, margins, column widths
    """
    config = {
        'orientation': 'portrait',
        'scale_percent': 100,
        'scale_to_pages': None,
        'scale_to_pages_x': None,
        'scale_to_pages_y': None,
        'margin_top': '2cm',
        'margin_bottom': '2cm',
        'margin_left': '2cm',
        'margin_right': '2cm',
        'column_widths': [],
        'page_width': '21cm',  # A4 default
        'page_height': '29.7cm'
    }
    
    try:
        with zipfile.ZipFile(ods_path, 'r') as ods_zip:
            # Parse styles.xml for page layout
            if 'styles.xml' in ods_zip.namelist():
                try:
                    styles_xml = ods_zip.read('styles.xml')
                    styles_root = ET.fromstring(styles_xml)
                    
                    # Find automatic-styles and office:master-styles
                    for page_layout in styles_root.findall('.//style:page-layout', NS):
                        props = page_layout.find('style:page-layout-properties', NS)
                        if props is not None:
                            # Orientation
                            orientation = props.get(f"{{{NS['style']}}}print-orientation")
                            if orientation:
                                config['orientation'] = orientation
                            
                            # Page dimensions
                            page_width = props.get(f"{{{NS['fo']}}}page-width")
                            page_height = props.get(f"{{{NS['fo']}}}page-height")
                            if page_width:
                                config['page_width'] = page_width
                            if page_height:
                                config['page_height'] = page_height
                            
                            # Margins
                            config['margin_top'] = props.get(f"{{{NS['fo']}}}margin-top", config['margin_top'])
                            config['margin_bottom'] = props.get(f"{{{NS['fo']}}}margin-bottom", config['margin_bottom'])
                            config['margin_left'] = props.get(f"{{{NS['fo']}}}margin-left", config['margin_left'])
                            config['margin_right'] = props.get(f"{{{NS['fo']}}}margin-right", config['margin_right'])
                            
                            # Scaling
                            scale = props.get(f"{{{NS['style']}}}scale-to")
                            if scale:
                                config['scale_percent'] = int(scale.rstrip('%'))
                            
                            scale_to_pages = props.get(f"{{{NS['style']}}}scale-to-pages")
                            if scale_to_pages:
                                config['scale_to_pages'] = int(scale_to_pages)
                            
                            # Scale to X and Y pages (more specific)
                            scale_to_x = props.get(f"{{{NS['style']}}}scale-to-X")
                            scale_to_y = props.get(f"{{{NS['style']}}}scale-to-Y")
                            if scale_to_x:
                                config['scale_to_pages_x'] = int(scale_to_x)
                            if scale_to_y:
                                config['scale_to_pages_y'] = int(scale_to_y)
                
                except Exception as e:
                    logger.warning(f"Could not parse styles.xml: {e}")
            
            # Parse content.xml for column widths
            if 'content.xml' in ods_zip.namelist():
                try:
                    content_xml = ods_zip.read('content.xml')
                    content_root = ET.fromstring(content_xml)
                    
                    # Look for automatic-styles with column widths
                    column_styles = {}
                    for style_elem in content_root.findall('.//style:style[@style:family="table-column"]', NS):
                        style_name = style_elem.get(f"{{{NS['style']}}}name")
                        props = style_elem.find('style:table-column-properties', NS)
                        if props is not None:
                            width = props.get(f"{{{NS['style']}}}column-width")
                            if width and style_name:
                                column_styles[style_name] = width
                    
                    # Extract column widths from table
                    for table in content_root.findall('.//table:table', NS):
                        for col in table.findall('table:table-column', NS):
                            style_name = col.get(f"{{{NS['table']}}}style-name")
                            width_str = None
                            
                            if style_name and style_name in column_styles:
                                width_str = column_styles[style_name]
                            
                            if width_str:
                                width_in = convert_to_inches(width_str)
                                config['column_widths'].append(width_in)
                        
                        # Only process first table
                        break
                
                except Exception as e:
                    logger.warning(f"Could not parse content.xml: {e}")
    
    except Exception as e:
        logger.error(f"Error parsing ODS file: {e}", exc_info=True)
    
    return config


def check_landscape_orientation(config):
    """Verify landscape orientation is set (20 points)"""
    orientation = config.get('orientation', 'portrait')
    is_landscape = orientation == 'landscape'
    
    score = 20 if is_landscape else 0
    feedback = f"Orientation: {orientation}"
    
    logger.info(f"{'✅' if is_landscape else '❌'} {feedback} ({score}/20 pts)")
    return is_landscape, score, feedback


def check_scaling_configuration(config):
    """Verify appropriate scaling is configured (25 points)"""
    scale_percent = config.get('scale_percent', 100)
    scale_to_pages = config.get('scale_to_pages')
    scale_to_x = config.get('scale_to_pages_x')
    
    # Good scaling: 70-95% OR scale-to-pages/scale-to-X configured
    has_percent_scaling = 70 <= scale_percent <= 95
    has_page_scaling = (scale_to_pages is not None) or (scale_to_x is not None and scale_to_x <= 2)
    
    if has_percent_scaling and has_page_scaling:
        score = 25  # Perfect
        feedback = f"Scaling: {scale_percent}% + fit-to-pages"
    elif has_percent_scaling:
        score = 25
        feedback = f"Scaling: {scale_percent}%"
    elif has_page_scaling:
        score = 20  # Good but could be better
        feedback = f"Scaling: fit-to-pages (X={scale_to_x})"
    elif 95 < scale_percent < 100:
        score = 10  # Partial credit for minor scaling
        feedback = f"Scaling: {scale_percent}% (needs more reduction)"
    else:
        score = 0
        feedback = f"Scaling: {scale_percent}% (no optimization)"
    
    logger.info(f"{'✅' if score >= 20 else '❌'} {feedback} ({score}/25 pts)")
    return score >= 20, score, feedback


def check_column_widths(config):
    """Verify column widths are optimized - no excessively wide columns (20 points)"""
    column_widths = config.get('column_widths', [])
    
    if not column_widths or len(column_widths) < 3:
        logger.warning("Could not extract sufficient column width data")
        return False, 10, "Column widths: insufficient data"
    
    max_width = max(column_widths)
    avg_width = sum(column_widths) / len(column_widths)
    
    # Check for excessive widths
    # Original had 6cm (~2.36") and 3.5cm (~1.38") columns
    # After optimization, no column should be >5" or >2.5x average
    has_excessive = max_width > 5.0 or max_width > (avg_width * 2.5)
    is_optimized = not has_excessive
    
    if is_optimized:
        score = 20
        feedback = f"Column widths: optimized (max={max_width:.2f}in, avg={avg_width:.2f}in)"
    elif max_width > 5.0:
        score = 0
        feedback = f"Column widths: excessive (max={max_width:.2f}in > 5in limit)"
    else:
        score = 10  # Partial credit
        feedback = f"Column widths: unbalanced (max={max_width:.2f}in, avg={avg_width:.2f}in)"
    
    logger.info(f"{'✅' if is_optimized else '❌'} {feedback} ({score}/20 pts)")
    return is_optimized, score, feedback


def check_margins(config):
    """Verify margins are reasonable (0.5-1.0 inches) (15 points)"""
    margin_left_in = convert_to_inches(config.get('margin_left', '2cm'))
    margin_right_in = convert_to_inches(config.get('margin_right', '2cm'))
    margin_top_in = convert_to_inches(config.get('margin_top', '2cm'))
    margin_bottom_in = convert_to_inches(config.get('margin_bottom', '2cm'))
    
    avg_margin = (margin_left_in + margin_right_in + margin_top_in + margin_bottom_in) / 4
    
    # Reasonable margins: 0.4" to 1.1" (allowing slight tolerance)
    # Default is usually 2cm = 0.787", which is fine
    # We want to reward reducing to 0.5-0.75" range
    is_reasonable = 0.4 <= avg_margin <= 1.1
    is_optimized = 0.5 <= avg_margin <= 0.9
    
    if is_optimized:
        score = 15
        feedback = f"Margins: optimized (avg={avg_margin:.2f}in)"
    elif is_reasonable:
        score = 12
        feedback = f"Margins: acceptable (avg={avg_margin:.2f}in)"
    elif avg_margin > 1.1:
        score = 5
        feedback = f"Margins: too large (avg={avg_margin:.2f}in, wastes space)"
    else:
        score = 5
        feedback = f"Margins: too small (avg={avg_margin:.2f}in, may clip)"
    
    logger.info(f"{'✅' if score >= 12 else '⚠️'} {feedback} ({score}/15 pts)")
    return is_reasonable, score, feedback


def estimate_horizontal_pages(config):
    """Estimate number of pages wide the printout will be (20 points)"""
    column_widths = config.get('column_widths', [])
    
    if not column_widths or len(column_widths) < 3:
        logger.warning("Cannot estimate horizontal pages without column data")
        return False, 10, "Horizontal pages: cannot estimate"
    
    # Determine effective page width based on orientation
    orientation = config.get('orientation', 'portrait')
    page_width_str = config.get('page_width', '21cm')
    page_height_str = config.get('page_height', '29.7cm')
    
    page_width_in = convert_to_inches(page_width_str)
    page_height_in = convert_to_inches(page_height_str)
    
    # Effective page width is the wider dimension for landscape
    if orientation == 'landscape':
        effective_page_width = max(page_width_in, page_height_in)
    else:
        effective_page_width = min(page_width_in, page_height_in)
    
    # Subtract margins
    margin_left_in = convert_to_inches(config.get('margin_left', '2cm'))
    margin_right_in = convert_to_inches(config.get('margin_right', '2cm'))
    
    usable_width = effective_page_width - margin_left_in - margin_right_in
    
    # Apply scaling
    scale_percent = config.get('scale_percent', 100)
    scale_to_x = config.get('scale_to_pages_x')
    
    # If scale-to-X is set, honor it
    if scale_to_x is not None:
        horizontal_pages = scale_to_x
    else:
        # Calculate based on scaling percentage
        effective_usable_width = usable_width / (scale_percent / 100.0)
        total_content_width = sum(column_widths)
        horizontal_pages = math.ceil(total_content_width / effective_usable_width)
    
    is_acceptable = horizontal_pages <= 2
    
    if horizontal_pages == 1:
        score = 20
        feedback = f"Horizontal pages: {horizontal_pages} (excellent!)"
    elif horizontal_pages == 2:
        score = 18
        feedback = f"Horizontal pages: {horizontal_pages} (good)"
    elif horizontal_pages == 3:
        score = 5
        feedback = f"Horizontal pages: {horizontal_pages} (needs more optimization)"
    else:
        score = 0
        feedback = f"Horizontal pages: {horizontal_pages} (poor layout)"
    
    logger.info(f"{'✅' if is_acceptable else '❌'} {feedback} ({score}/20 pts)")
    return is_acceptable, score, feedback


def check_print_layout_crisis(traj, env_info, task_info):
    """
    Main verification function for Print Layout Crisis task.
    
    Checks:
    1. Landscape orientation (20 pts)
    2. Appropriate scaling (25 pts)
    3. Optimized column widths (20 pts)
    4. Reasonable margins (15 pts)
    5. Acceptable horizontal pages ≤2 (20 pts)
    
    Total: 100 points, Pass threshold: 75
    """
    logger.info("="*60)
    logger.info("Print Layout Crisis Verifier")
    logger.info("="*60)
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available"
        }
    
    # Setup verification environment
    container_path = "/home/ga/Documents/results/print_optimized_inventory.ods"
    success, result = setup_verification_environment(
        copy_from_env,
        container_path,
        expected_formats=['ods']
    )
    
    if not success:
        # Fallback: try original location
        container_path = "/home/ga/Documents/inventory_to_print.ods"
        success, result = setup_verification_environment(
            copy_from_env,
            container_path,
            expected_formats=['ods']
        )
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not load result file: {result.get('error')}"
            }
    
    try:
        ods_path = result['filepath']
        
        # Parse ODS print configuration
        logger.info("Parsing ODS print configuration...")
        config = parse_ods_print_config(ods_path)
        
        if not config:
            return {
                "passed": False,
                "score": 0,
                "feedback": "Could not parse ODS configuration"
            }
        
        # Log parsed configuration
        logger.info(f"Configuration: orientation={config['orientation']}, "
                   f"scale={config['scale_percent']}%, "
                   f"columns={len(config['column_widths'])}")
        
        # Run all verification checks
        total_score = 0
        feedback_parts = []
        checks_details = {}
        
        # 1. Landscape orientation (20 points)
        landscape_ok, landscape_score, landscape_fb = check_landscape_orientation(config)
        total_score += landscape_score
        feedback_parts.append(landscape_fb)
        checks_details['landscape'] = landscape_ok
        
        # 2. Scaling configuration (25 points)
        scaling_ok, scaling_score, scaling_fb = check_scaling_configuration(config)
        total_score += scaling_score
        feedback_parts.append(scaling_fb)
        checks_details['scaling'] = scaling_ok
        
        # 3. Column width optimization (20 points)
        columns_ok, columns_score, columns_fb = check_column_widths(config)
        total_score += columns_score
        feedback_parts.append(columns_fb)
        checks_details['columns'] = columns_ok
        
        # 4. Reasonable margins (15 points)
        margins_ok, margins_score, margins_fb = check_margins(config)
        total_score += margins_score
        feedback_parts.append(margins_fb)
        checks_details['margins'] = margins_ok
        
        # 5. Horizontal page count (20 points)
        pages_ok, pages_score, pages_fb = estimate_horizontal_pages(config)
        total_score += pages_score
        feedback_parts.append(pages_fb)
        checks_details['horizontal_pages'] = pages_ok
        
        # Calculate final pass/fail
        passed = total_score >= 75
        
        # Generate detailed feedback
        feedback = " | ".join(feedback_parts)
        
        # Add summary message
        if total_score >= 90:
            summary = "🎉 Excellent print layout optimization!"
        elif total_score >= 75:
            summary = "✅ Print layout fixed successfully"
        elif total_score >= 50:
            summary = "⚠️ Partial optimization, needs improvement"
        else:
            summary = "❌ Print layout still problematic"
        
        full_feedback = f"{summary} | {feedback}"
        
        logger.info("")
        logger.info("="*60)
        logger.info(f"FINAL SCORE: {total_score}/100")
        logger.info(f"PASSED: {passed}")
        logger.info("="*60)
        
        return {
            "passed": passed,
            "score": total_score,
            "feedback": full_feedback,
            "subscores": {
                "landscape_orientation": landscape_score,
                "scaling_config": scaling_score,
                "column_widths": columns_score,
                "margins": margins_score,
                "horizontal_pages": pages_score
            },
            "details": {
                "orientation": config.get('orientation'),
                "scale_percent": config.get('scale_percent'),
                "scale_to_pages_x": config.get('scale_to_pages_x'),
                "column_count": len(config.get('column_widths', [])),
                "checks_passed": checks_details
            }
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    
    finally:
        cleanup_verification_environment(result.get('temp_dir'))


# Entry point for gym-anything framework
def verify(traj, env_info, task_info):
    """Wrapper for framework compatibility"""
    return check_print_layout_crisis(traj, env_info, task_info)
