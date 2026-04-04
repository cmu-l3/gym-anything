#!/usr/bin/env python3
"""
Verifier for Conditional Format task.
Checks if conditional formatting has been applied by parsing the ODS file structure.
"""

import logging
import sys
import os
import zipfile
from xml.etree import ElementTree as ET

# Do not use /workspace/utils, since the verification runs on the host machine, not the container.
# USE Relative path to the utils folder.
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))

from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_cell_value
)

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def check_ods_conditional_formatting(filepath):
    """
    Check if ODS file contains conditional formatting by parsing content.xml

    Returns:
        Tuple[bool, str]: (has_formatting, details)
    """
    try:
        # ODS files are ZIP archives
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml which contains formatting info
            if 'content.xml' in ods_zip.namelist():
                content_xml = ods_zip.read('content.xml')
                root = ET.fromstring(content_xml)

                # Define namespaces used in ODS files
                namespaces = {
                    'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                    'style': 'urn:oasis:names:tc:opendocument:xmlns:style:1.0',
                    'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                    'fo': 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0'
                }

                # Look for conditional styles or background colors
                # Check for style elements with background colors
                styles_found = []

                # Check automatic styles section
                auto_styles = root.findall('.//office:automatic-styles//style:style', namespaces)
                for style in auto_styles:
                    style_name = style.get('{urn:oasis:names:tc:opendocument:xmlns:style:1.0}name', '')
                    # Check for table-cell-properties with background color
                    cell_props = style.findall('.//style:table-cell-properties', namespaces)
                    for prop in cell_props:
                        bg_color = prop.get('{urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0}background-color')
                        if bg_color and bg_color != 'transparent':
                            styles_found.append((style_name, bg_color))

                # Check if cells actually use these styles
                cells_with_styles = root.findall('.//table:table-cell[@table:style-name]', namespaces)
                cells_with_bg_color = 0
                for cell in cells_with_styles:
                    style_name = cell.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}style-name')
                    if any(style_name == s[0] for s in styles_found):
                        cells_with_bg_color += 1

                if cells_with_bg_color >= 2:  # At least 2 cells should have formatting
                    details = f"Found {cells_with_bg_color} cells with background colors"
                    return True, details
                else:
                    return False, f"Only {cells_with_bg_color} cells with formatting (expected at least 2)"
            else:
                return False, "content.xml not found in ODS file"

    except zipfile.BadZipFile:
        return False, "File is not a valid ODS/ZIP file"
    except ET.ParseError as e:
        return False, f"XML parsing error: {str(e)}"
    except Exception as e:
        logger.error(f"Error checking conditional formatting: {e}", exc_info=True)
        return False, f"Error: {str(e)}"


def check_conditional_format(traj, env_info, task_info):
    """
    Verify conditional formatting task:
    1. Data integrity maintained
    2. File format is ODS (required for formatting)
    3. Conditional formatting actually applied (checks background colors)

    Task requirements:
    - Scores >= 80 should be highlighted (green)
    - Scores < 60 should be highlighted (red)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/formatted_scores.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    if not success:
        # File saving may have erred, let's load back the original file.
        container_path = "/home/ga/Documents/student_scores.csv"
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
        if not success:
            container_path = "/home/ga/Documents/student_scores.ods"
            success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
            if not success:
                return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}

    try:
        feedback_parts = []
        criteria_met = 0
        total_criteria = 4

        # 1. Check data integrity
        data = file_info['sheet_data']
        sheet_names = list(data.get('sheets', {}).keys())

        if sheet_names:
            sheet_name = sheet_names[0]
            sheet_rows = data['sheets'][sheet_name]
            # Count non-empty rows
            row_count = 0
            for row in sheet_rows:
                if any(cell.get('value') if isinstance(cell, dict) else cell for cell in row):
                    row_count += 1

            if row_count >= 6:
                criteria_met += 1
                feedback_parts.append("✅ Student data preserved (6+ rows)")
            else:
                feedback_parts.append(f"❌ Data missing or corrupted ({row_count} rows found)")
        else:
            feedback_parts.append("❌ No sheets found in workbook")

        # 2. Check file format is ODS (necessary for conditional formatting)
        if file_info['format'] == 'ods':
            criteria_met += 1
            feedback_parts.append("✅ Saved in ODS format")
        else:
            feedback_parts.append("⚠️ Not saved as ODS, formatting may be lost")

        # 3. Check if conditional formatting was applied
        has_formatting, format_details = check_ods_conditional_formatting(file_info['file_path'])

        if has_formatting:
            criteria_met += 2  # Worth 2 criteria since this is the main task
            feedback_parts.append(f"✅ Conditional formatting detected: {format_details}")
        else:
            feedback_parts.append(f"❌ No conditional formatting found: {format_details}")

        # Calculate score
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need at least 3/4 criteria

        if passed and score >= 90:
            feedback_parts.append("🎉 Perfect! Conditional formatting applied correctly")
        elif passed:
            feedback_parts.append("✅ Conditional formatting task completed")
        else:
            feedback_parts.append("❌ Task requirements not met")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "data_integrity": row_count >= 6 if sheet_names else False,
                "ods_format": file_info['format'] == 'ods',
                "formatting_applied": has_formatting
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
