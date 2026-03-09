#!/usr/bin/env python3
"""
Verifier for Create Chart task.
Checks that a chart object exists in the spreadsheet and validates chart properties.
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
    verify_chart_exists
)

logging.basicConfig(level=logging.DEBUG)
logger = logging.getLogger(__name__)


def analyze_ods_chart(filepath):
    """
    Analyze chart details from ODS file.

    Returns:
        dict: Chart information including type, data range, count
    """
    try:
        chart_info = {
            'count': 0,
            'types': [],
            'has_data_range': False,
            'details': []
        }

        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            # Read content.xml
            if 'content.xml' not in ods_zip.namelist():
                return chart_info

            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)

            # Define namespaces
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'draw': 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'chart': 'urn:oasis:names:tc:opendocument:xmlns:chart:1.0'
            }

            # Look for chart objects
            frames = root.findall('.//draw:frame', namespaces)
            for frame in frames:
                chart_objects = frame.findall('.//draw:object', namespaces)
                for obj in chart_objects:
                    # Check if this is a chart object
                    href = obj.get('{http://www.w3.org/1999/xlink}href', '')
                    if './Object' in href or 'Chart' in href:
                        chart_info['count'] += 1

                        # Try to get chart details from embedded chart file
                        chart_path = href.strip('./').strip('/')
                        chart_content_path = f"{chart_path}/content.xml"

                        if chart_content_path in ods_zip.namelist():
                            try:
                                chart_xml = ods_zip.read(chart_content_path)
                                chart_root = ET.fromstring(chart_xml)

                                # Find chart type
                                chart_elem = chart_root.find('.//chart:chart', namespaces)
                                if chart_elem is not None:
                                    chart_class = chart_elem.get('{urn:oasis:names:tc:opendocument:xmlns:chart:1.0}class', '')
                                    chart_info['types'].append(chart_class)

                                # Check for data range
                                plot_area = chart_root.find('.//chart:plot-area', namespaces)
                                if plot_area is not None:
                                    table_range = plot_area.get('{urn:oasis:names:tc:opendocument:xmlns:table:1.0}cell-range-address')
                                    if table_range:
                                        chart_info['has_data_range'] = True
                                        chart_info['details'].append(f"Data range: {table_range}")

                            except Exception as e:
                                logger.debug(f"Could not parse chart details: {e}")

        return chart_info

    except Exception as e:
        logger.error(f"Error analyzing chart: {e}", exc_info=True)
        return {'count': 0, 'types': [], 'has_data_range': False, 'details': []}


def check_create_chart(traj, env_info, task_info):
    """
    Verify chart creation task:
    1. Chart object exists in ODS file
    2. Chart is of appropriate type (bar/column)
    3. Chart has data range
    4. Data is preserved
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/chart_result.ods"
    success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
    if not success:
        container_path = "/home/ga/Documents/sales_data.csv"
        success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
        if not success:
            container_path = "/home/ga/Documents/sales_data.ods"
            success, file_info, error = setup_calc_verification(copy_from_env, container_path, ['ods'])
            if not success:
                return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}

    if not success:
        return {"passed": False, "score": 0, "feedback": f"Setup failed: {error}"}

    try:
        feedback_parts = []
        criteria_met = 0
        total_criteria = 4

        # 1. Check chart exists
        chart_info = analyze_ods_chart(file_info['file_path'])
        has_chart = chart_info['count'] > 0

        if has_chart:
            criteria_met += 1
            feedback_parts.append(f"✅ Chart object found ({chart_info['count']} chart(s))")
        else:
            feedback_parts.append("❌ No chart found in spreadsheet")

        # 2. Check chart type (bar or column chart)
        if chart_info['types']:
            chart_type = chart_info['types'][0].lower()
            # Common chart types: chart:bar, chart:column, chart:line, chart:pie
            if 'bar' in chart_type or 'column' in chart_type:
                criteria_met += 1
                feedback_parts.append(f"✅ Appropriate chart type: {chart_info['types'][0]}")
            else:
                feedback_parts.append(f"⚠️ Chart type is {chart_info['types'][0]} (expected bar/column)")
                # Still give partial credit if a chart exists
                criteria_met += 0.5
        elif has_chart:
            feedback_parts.append("⚠️ Could not determine chart type")

        # 3. Check chart has data range
        if chart_info['has_data_range']:
            criteria_met += 1
            feedback_parts.append("✅ Chart has data range configured")
            if chart_info['details']:
                logger.info(f"Chart details: {chart_info['details']}")
        elif has_chart:
            feedback_parts.append("⚠️ Chart may not have data range configured")

        # 4. Check data exists
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

            if row_count >= 6:  # Header + 6 months of data
                criteria_met += 1
                feedback_parts.append("✅ Sales data preserved (6+ rows)")
            else:
                feedback_parts.append(f"❌ Data missing or incomplete ({row_count} rows)")
        else:
            feedback_parts.append("❌ No sheets found in workbook")

        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 75  # Need 3/4 criteria

        if passed and score >= 90:
            feedback_parts.append("🎉 Chart created successfully!")
        elif passed:
            feedback_parts.append("✅ Chart task completed")
        else:
            feedback_parts.append("❌ Chart task requirements not met")

        return {
            "passed": passed,
            "score": score,
            "feedback": " | ".join(feedback_parts),
            "subscores": {
                "chart_exists": has_chart,
                "chart_type_correct": 'bar' in str(chart_info['types']).lower() or 'column' in str(chart_info['types']).lower(),
                "has_data_range": chart_info['has_data_range'],
                "data_preserved": row_count >= 6 if sheet_names else False
            }
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}

    finally:
        cleanup_verification_temp(file_info.get('temp_dir'))
