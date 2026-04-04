#!/usr/bin/env python3
"""
Verifier for Version Diff Highlighter task.
Checks that changed cells between versions are correctly highlighted.
"""

import sys
import os
import logging
import json
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path - use relative path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def get_cell_background_colors_ods(filepath, sheet_name):
    """
    Extract background colors for all cells in a sheet from ODS file.
    
    Returns:
        dict: {(row_idx, col_idx): has_background_color}
    """
    try:
        cell_colors = {}
        
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            if 'content.xml' not in ods_zip.namelist():
                logger.error("content.xml not found in ODS")
                return cell_colors
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            ns = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
            }
            
            # Read styles.xml for style definitions
            styles_root = None
            if 'styles.xml' in ods_zip.namelist():
                styles_xml = ods_zip.read('styles.xml')
                styles_root = ET.fromstring(styles_xml)
            
            # Build style map: style_name -> has_background
            style_map = {}
            
            # Check automatic styles in content.xml
            auto_styles = root.find('.//office:automatic-styles', ns)
            if auto_styles is not None:
                for style in auto_styles.findall('.//style:style', ns):
                    style_name = style.get(f"{{{ns['style']}}}name")
                    if style_name:
                        # Check table-cell-properties for background color
                        cell_props = style.find('.//style:table-cell-properties', ns)
                        if cell_props is not None:
                            bg_color = cell_props.get(f"{{{ns['fo']}}}background-color")
                            # If background color exists and is not 'transparent' or default
                            if bg_color and bg_color.lower() not in ['transparent', 'none', '#ffffff', 'ffffff']:
                                style_map[style_name] = True
            
            # Find the target sheet
            spreadsheet = root.find('.//office:spreadsheet', ns)
            if spreadsheet is None:
                logger.error("Spreadsheet element not found")
                return cell_colors
            
            target_table = None
            for table in spreadsheet.findall('.//table:table', ns):
                table_name = table.get(f"{{{ns['table']}}}name")
                if table_name == sheet_name:
                    target_table = table
                    break
            
            if target_table is None:
                logger.error(f"Sheet '{sheet_name}' not found")
                return cell_colors
            
            # Iterate through rows and cells
            row_idx = 0
            for row in target_table.findall('.//table:table-row', ns):
                col_idx = 0
                for cell in row.findall('.//table:table-cell', ns):
                    # Check if cell has a style with background color
                    cell_style = cell.get(f"{{{ns['table']}}}style-name")
                    
                    # Check for direct background color attribute (less common)
                    direct_bg = False
                    cell_props = cell.find('.//style:table-cell-properties', ns)
                    if cell_props is not None:
                        bg_color = cell_props.get(f"{{{ns['fo']}}}background-color")
                        if bg_color and bg_color.lower() not in ['transparent', 'none', '#ffffff', 'ffffff']:
                            direct_bg = True
                    
                    # Check if style has background
                    has_background = direct_bg or (cell_style and style_map.get(cell_style, False))
                    
                    if has_background:
                        cell_colors[(row_idx, col_idx)] = True
                    
                    # Handle repeated columns
                    repeat = cell.get(f"{{{ns['table']}}}number-columns-repeated")
                    if repeat:
                        try:
                            repeat_count = int(repeat)
                            for r in range(1, repeat_count):
                                if has_background:
                                    cell_colors[(row_idx, col_idx + r)] = True
                            col_idx += repeat_count
                        except ValueError:
                            col_idx += 1
                    else:
                        col_idx += 1
                
                row_idx += 1
        
        return cell_colors
    
    except Exception as e:
        logger.error(f"Error extracting cell colors: {e}", exc_info=True)
        return {}


def verify_version_diff_highlighter(traj, env_info, task_info):
    """
    Verify version comparison task completion.
    
    Checks:
    1. Changed cells are highlighted (Recall >= 0.80)
    2. Highlighted cells are actually changed (Precision >= 0.80)
    3. F1 score >= 0.80
    4. Visual highlighting is present
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Load ground truth
    container_gt_path = "/home/ga/Documents/version_comparison_ground_truth.json"
    success, file_info, error = setup_calc_verification(copy_from_env, container_gt_path, ['json'])
    
    ground_truth = None
    if not success:
        logger.warning("Could not load ground truth, will use hardcoded values")
        # Fallback to hardcoded ground truth
        ground_truth = {
            'changed_cells': [
                (1, 3),  # P1001 price
                (3, 3),  # P1003 price
                (4, 4),  # P1004 quantity
                (6, 1),  # P1006 name
                (8, 2),  # P1008 category
                (9, 3),  # P1009 price
            ],
            'sheet_name': 'Version 2'
        }
    else:
        try:
            with open(file_info['filepath'], 'r') as f:
                ground_truth = json.load(f)
        except Exception as e:
            logger.error(f"Failed to parse ground truth: {e}")
            ground_truth = {
                'changed_cells': [(1, 3), (3, 3), (4, 4), (6, 1), (8, 2), (9, 3)],
                'sheet_name': 'Version 2'
            }
    
    # Load the result spreadsheet
    container_path = "/home/ga/Documents/version_comparison.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    
    if not success:
        return {"passed": False, "score": 0, "feedback": f"Failed to load spreadsheet: {error}"}
    
    try:
        sheet_name = ground_truth['sheet_name']
        expected_changed_cells = set(tuple(cell) for cell in ground_truth['changed_cells'])
        
        # Extract highlighted cells from the result
        highlighted_cells_dict = get_cell_background_colors_ods(file_info['filepath'], sheet_name)
        highlighted_cells = set(highlighted_cells_dict.keys())
        
        logger.info(f"Expected changed cells: {expected_changed_cells}")
        logger.info(f"Highlighted cells: {highlighted_cells}")
        
        # Calculate metrics
        true_positives = len(expected_changed_cells & highlighted_cells)
        false_positives = len(highlighted_cells - expected_changed_cells)
        false_negatives = len(expected_changed_cells - highlighted_cells)
        
        # Calculate precision, recall, F1
        precision = true_positives / (true_positives + false_positives) if (true_positives + false_positives) > 0 else 0
        recall = true_positives / (true_positives + false_negatives) if (true_positives + false_negatives) > 0 else 0
        f1_score = 2 * (precision * recall) / (precision + recall) if (precision + recall) > 0 else 0
        
        # Criteria scoring
        criteria_passed = 0
        total_criteria = 4
        feedback_parts = []
        
        # Criterion 1: High Recall (>=80%)
        recall_ok = recall >= 0.80
        if recall_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ High recall: {recall:.2%} ({true_positives}/{len(expected_changed_cells)} changes found)")
        else:
            feedback_parts.append(f"❌ Low recall: {recall:.2%} ({true_positives}/{len(expected_changed_cells)} changes found, need ≥80%)")
        
        # Criterion 2: High Precision (>=80%)
        precision_ok = precision >= 0.80
        if precision_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ High precision: {precision:.2%} ({true_positives}/{len(highlighted_cells)} highlights correct)")
        else:
            if len(highlighted_cells) > 0:
                feedback_parts.append(f"❌ Low precision: {precision:.2%} ({false_positives} false positives)")
            else:
                feedback_parts.append(f"❌ No cells highlighted")
        
        # Criterion 3: Visual highlighting present
        has_highlighting = len(highlighted_cells) > 0
        if has_highlighting:
            criteria_passed += 1
            feedback_parts.append(f"✅ Visual highlighting applied ({len(highlighted_cells)} cells)")
        else:
            feedback_parts.append("❌ No visual highlighting detected")
        
        # Criterion 4: F1 Score >= 0.80
        f1_ok = f1_score >= 0.80
        if f1_ok:
            criteria_passed += 1
            feedback_parts.append(f"✅ F1 score: {f1_score:.2%} (excellent balance)")
        else:
            feedback_parts.append(f"❌ F1 score: {f1_score:.2%} (need ≥80%)")
        
        # Additional helpful feedback
        if false_negatives > 0:
            missed = expected_changed_cells - highlighted_cells
            feedback_parts.append(f"⚠️ Missed changes at: {sorted(missed)[:3]}")  # Show first 3
        
        if false_positives > 0:
            incorrect = highlighted_cells - expected_changed_cells
            feedback_parts.append(f"⚠️ Incorrectly highlighted: {sorted(incorrect)[:3]}")  # Show first 3
        
        # Calculate final score
        # Weight F1 score heavily since it's the main metric
        if f1_score >= 0.80:
            score = int(75 + (f1_score - 0.80) * 125)  # 75-100 range
        else:
            score = int(f1_score * 75 / 0.80)  # 0-75 range
        
        score = min(100, max(0, score))
        
        # Pass if F1 >= 0.80 (which means recall and precision are reasonably high)
        passed = f1_score >= 0.80
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "recall": recall,
                "precision": precision,
                "f1_score": f1_score,
                "has_highlighting": has_highlighting,
                "true_positives": true_positives,
                "false_positives": false_positives,
                "false_negatives": false_negatives
            }
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}
    
    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
