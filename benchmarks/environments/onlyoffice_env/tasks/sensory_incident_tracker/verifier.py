#!/usr/bin/env python3
"""
Verifier for Sensory Incident Tracker task
"""

import sys
import os
import logging
import tempfile
import re

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_cell_value,
    get_sheet_data,
    count_filled_cells,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_sensory_analysis(traj, env_info, task_info):
    """
    Verify sensory processing incident tracking and analysis task.
    
    Checks:
    1. Output file exists and is valid XLSX (10 pts)
    2. Data completeness: ≥12 incidents transferred (15 pts)
    3. Standardized severity: numeric 1-10 values (10 pts)
    4. Trigger categorization: ≥80% correct (20 pts)
    5. Frequency analysis: counts by trigger type (15 pts)
    6. Time-of-day grouping present (10 pts)
    7. Severity highlighting: incidents ≥7 marked (10 pts)
    8. Formula usage: evidence of calculations (10 pts)
    
    Passing threshold: ≥70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    expected_path = "/home/ga/Documents/Spreadsheets/sensory_analysis_for_OT.xlsx"
    temp_file = None
    
    result = {
        "passed": False,
        "score": 0,
        "feedback": "",
        "max_score": 100
    }
    
    feedback_parts = []
    score = 0
    
    try:
        # Create temp file for copying
        temp_file_obj = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
        temp_file = temp_file_obj.name
        temp_file_obj.close()
        
        # Try to copy the file
        try:
            copy_from_env(expected_path, temp_file)
        except Exception as e:
            feedback_parts.append(f"❌ Output file not found or inaccessible: {str(e)}")
            result["feedback"] = " | ".join(feedback_parts)
            result["score"] = 0
            return result
        
        # Check if file exists and has content
        if not os.path.exists(temp_file) or os.path.getsize(temp_file) == 0:
            feedback_parts.append("❌ Output file not found or empty")
            result["feedback"] = " | ".join(feedback_parts)
            result["score"] = 0
            return result
        
        score += 10
        feedback_parts.append("✅ File created successfully")
        
        # Parse workbook
        wb = parse_xlsx_file(temp_file)
        if not wb:
            feedback_parts.append("❌ Could not parse XLSX file")
            result["feedback"] = " | ".join(feedback_parts)
            result["score"] = score
            return result
        
        # Find the main data sheet
        sheet_names = wb.sheetnames
        data_sheet = None
        
        # Look for sheet with keywords suggesting organized data
        for name in sheet_names:
            name_lower = name.lower()
            if any(keyword in name_lower for keyword in ['incident', 'log', 'data', 'clean', 'organized', 'analysis']):
                data_sheet = wb[name]
                break
        
        # If no matching sheet found, use first sheet
        if not data_sheet and sheet_names:
            data_sheet = wb[sheet_names[0]]
        
        if not data_sheet:
            feedback_parts.append("❌ No data sheet found in workbook")
            result["feedback"] = " | ".join(feedback_parts)
            result["score"] = score
            return result
        
        # Get all data from the main sheet
        data = get_sheet_data(wb, data_sheet.title, max_rows=50, max_cols=20)
        
        if not data or len(data) < 2:
            feedback_parts.append("❌ Sheet contains no data")
            result["feedback"] = " | ".join(feedback_parts)
            result["score"] = score
            return result
        
        # === CRITERION 1: Data completeness (≥12 incidents) ===
        header_row = data[0] if data else []
        data_rows = data[1:] if len(data) > 1 else []
        
        # Count rows with meaningful data (at least 3 non-empty cells)
        filled_rows = sum(1 for row in data_rows if sum(1 for cell in row if cell) >= 3)
        
        if filled_rows >= 12:
            score += 15
            feedback_parts.append(f"✅ Data completeness: {filled_rows} incidents organized (≥12 required)")
        elif filled_rows >= 10:
            score += 10
            feedback_parts.append(f"⚠️ Partial data: {filled_rows} incidents (12 expected)")
        elif filled_rows >= 8:
            score += 5
            feedback_parts.append(f"⚠️ Incomplete data: {filled_rows} incidents (12 expected)")
        else:
            feedback_parts.append(f"❌ Insufficient data: {filled_rows} incidents (need ≥12)")
        
        # === CRITERION 2: Standardized severity (numeric 1-10) ===
        severity_column = None
        for idx, header in enumerate(header_row):
            if header and 'sever' in str(header).lower():
                severity_column = idx
                break
        
        if severity_column is not None:
            severity_values = [row[severity_column] for row in data_rows 
                             if len(row) > severity_column and row[severity_column]]
            numeric_severities = [v for v in severity_values 
                                if isinstance(v, (int, float)) and 1 <= v <= 10]
            
            if len(numeric_severities) >= 12:
                score += 10
                feedback_parts.append(f"✅ Severity standardized: {len(numeric_severities)} numeric values (1-10)")
            elif len(numeric_severities) >= 10:
                score += 7
                feedback_parts.append(f"⚠️ Partial severity: {len(numeric_severities)} numeric values")
            elif len(numeric_severities) >= 8:
                score += 4
                feedback_parts.append(f"⚠️ Some severity values: {len(numeric_severities)} numeric")
            else:
                feedback_parts.append(f"❌ Severity not standardized: {len(numeric_severities)} numeric values")
        else:
            feedback_parts.append("❌ No severity column found")
        
        # === CRITERION 3: Trigger categorization accuracy ===
        trigger_column = None
        for idx, header in enumerate(header_row):
            if header:
                header_lower = str(header).lower()
                if any(keyword in header_lower for keyword in ['trigger', 'category', 'type']):
                    trigger_column = idx
                    break
        
        if trigger_column is not None:
            trigger_values = [str(row[trigger_column]).lower() 
                            for row in data_rows 
                            if len(row) > trigger_column and row[trigger_column]]
            
            # Expected categories with flexible matching
            expected_keywords = {
                'auditory': ['auditory', 'audio', 'sound', 'noise', 'hearing'],
                'tactile': ['tactile', 'touch', 'texture', 'fabric', 'feel'],
                'visual': ['visual', 'sight', 'light', 'see'],
                'olfactory': ['olfactory', 'smell', 'scent', 'odor'],
                'multi': ['multi', 'multiple', 'combined', 'several']
            }
            
            categorized = 0
            for trigger_val in trigger_values:
                for category, keywords in expected_keywords.items():
                    if any(kw in trigger_val for kw in keywords):
                        categorized += 1
                        break
            
            categorization_rate = (categorized / len(trigger_values) * 100) if trigger_values else 0
            
            if categorized >= 10:  # ~80% of 12
                score += 20
                feedback_parts.append(f"✅ Trigger categorization: {categorized}/{len(trigger_values)} properly categorized ({categorization_rate:.0f}%)")
            elif categorized >= 8:
                score += 15
                feedback_parts.append(f"⚠️ Partial categorization: {categorized}/{len(trigger_values)} ({categorization_rate:.0f}%)")
            elif categorized >= 6:
                score += 10
                feedback_parts.append(f"⚠️ Some categorization: {categorized}/{len(trigger_values)} ({categorization_rate:.0f}%)")
            else:
                feedback_parts.append(f"❌ Insufficient categorization: {categorized}/{len(trigger_values)}")
        else:
            feedback_parts.append("❌ No trigger category column found")
        
        # === CRITERION 4: Frequency analysis present ===
        analysis_found = False
        trigger_counts_found = 0
        
        # Check all sheets for frequency analysis
        for sheet_name in sheet_names:
            sheet = wb[sheet_name]
            sheet_data = get_sheet_data(wb, sheet_name, max_rows=40, max_cols=15)
            
            # Look for trigger type labels with associated counts
            for row in sheet_data:
                if not row:
                    continue
                row_text = ' '.join([str(cell).lower() for cell in row if cell])
                
                # Check if this row mentions trigger categories
                if any(trigger_type in row_text for trigger_type in 
                      ['auditory', 'tactile', 'visual', 'olfactory', 'multi']):
                    # Check if there's a numeric count in the row
                    if any(isinstance(cell, (int, float)) and cell > 0 for cell in row):
                        trigger_counts_found += 1
                        analysis_found = True
        
        if trigger_counts_found >= 3:
            score += 15
            feedback_parts.append(f"✅ Frequency analysis: {trigger_counts_found} trigger types with counts")
        elif trigger_counts_found >= 2:
            score += 10
            feedback_parts.append(f"⚠️ Partial frequency analysis: {trigger_counts_found} trigger types")
        elif analysis_found:
            score += 5
            feedback_parts.append("⚠️ Some analysis present but incomplete")
        else:
            feedback_parts.append("❌ No frequency analysis found")
        
        # === CRITERION 5: Time-of-day analysis ===
        time_analysis_found = False
        time_periods = ['morning', 'midday', 'afternoon', 'evening']
        
        # Check main data sheet for time period column
        for idx, header in enumerate(header_row):
            if header:
                header_lower = str(header).lower()
                if any(keyword in header_lower for keyword in ['time', 'period', 'when', 'day']):
                    time_values = [str(row[idx]).lower() 
                                 for row in data_rows 
                                 if len(row) > idx and row[idx]]
                    if any(period in time_val for time_val in time_values 
                          for period in time_periods):
                        time_analysis_found = True
                        break
        
        # Also check other sheets for time period analysis
        if not time_analysis_found:
            for sheet_name in sheet_names:
                sheet_data = get_sheet_data(wb, sheet_name, max_rows=30, max_cols=10)
                for row in sheet_data:
                    if not row:
                        continue
                    row_text = ' '.join([str(cell).lower() for cell in row if cell])
                    if sum(1 for period in time_periods if period in row_text) >= 2:
                        time_analysis_found = True
                        break
                if time_analysis_found:
                    break
        
        if time_analysis_found:
            score += 10
            feedback_parts.append("✅ Time-of-day grouping present")
        else:
            feedback_parts.append("❌ No time-of-day analysis found")
        
        # === CRITERION 6: Severity highlighting (≥7) ===
        high_severity_indicators = 0
        
        if severity_column is not None:
            # Check for high severity values
            high_sev_rows = []
            for row_idx, row in enumerate(data_rows):
                if len(row) > severity_column:
                    sev = row[severity_column]
                    if isinstance(sev, (int, float)) and sev >= 7:
                        high_sev_rows.append((row_idx, sev))
            
            if high_sev_rows:
                # Check if there's a flag/highlight column or notes
                for row_idx, sev_val in high_sev_rows:
                    row = data_rows[row_idx]
                    # Look for flag indicators
                    row_text = ' '.join([str(cell).lower() for cell in row if cell])
                    if any(indicator in row_text for indicator in 
                          ['high', 'severe', 'critical', 'flag', 'alert', '!']):
                        high_severity_indicators += 1
                    # Even if no explicit flag, count the high severity value itself
                    elif sev_val >= 7:
                        high_severity_indicators += 0.5
        
        if high_severity_indicators >= 5:
            score += 10
            feedback_parts.append(f"✅ High severity incidents (≥7) highlighted or flagged")
        elif high_severity_indicators >= 3:
            score += 6
            feedback_parts.append(f"⚠️ Some severity highlighting present")
        elif high_severity_indicators >= 1:
            score += 3
            feedback_parts.append(f"⚠️ Minimal severity highlighting")
        else:
            feedback_parts.append("❌ No severity highlighting found")
        
        # === CRITERION 7: Formula usage ===
        # Check if analysis section exists (which implies formula usage)
        # Also look for patterns suggesting calculated values
        formula_evidence = 0
        
        if analysis_found:
            formula_evidence += 1
        
        # Check for calculated averages or totals
        for sheet_name in sheet_names:
            sheet_data = get_sheet_data(wb, sheet_name, max_rows=40, max_cols=15)
            for row in sheet_data:
                if not row:
                    continue
                row_text = ' '.join([str(cell).lower() for cell in row if cell])
                # Look for average/total/sum indicators
                if any(calc in row_text for calc in ['average', 'mean', 'total', 'sum', 'count']):
                    # Check if there's a numeric result
                    if any(isinstance(cell, (int, float)) for cell in row):
                        formula_evidence += 1
                        break
        
        if formula_evidence >= 2:
            score += 10
            feedback_parts.append("✅ Formula usage evident in analysis")
        elif formula_evidence >= 1:
            score += 5
            feedback_parts.append("⚠️ Some formula usage detected")
        else:
            feedback_parts.append("❌ No evidence of formula-based calculations")
        
        # === Final assessment ===
        result["score"] = score
        result["passed"] = score >= 70
        result["feedback"] = " | ".join(feedback_parts)
        
        if result["passed"]:
            result["feedback"] = f"✅ PASSED ({score}/100) - " + result["feedback"]
        else:
            result["feedback"] = f"❌ FAILED ({score}/100) - " + result["feedback"]
        
        logger.info(f"Verification complete. Score: {score}/100, Passed: {result['passed']}")
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        result["feedback"] = f"❌ Verification error: {str(e)}"
        result["score"] = score
    
    finally:
        # Cleanup temp file
        if temp_file and os.path.exists(temp_file):
            try:
                os.unlink(temp_file)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp file: {e}")
    
    return result