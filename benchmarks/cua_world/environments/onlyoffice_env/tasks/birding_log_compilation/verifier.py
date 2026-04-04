#!/usr/bin/env python3
"""
Verifier for Birding Log Compilation task

This verifier checks that the agent created a properly structured birding observation
log spreadsheet from rough field notes, handling uncertain identifications and missing
data appropriately.
"""

import sys
import os
import logging
import tempfile
import re
from pathlib import Path
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    parse_xlsx_file,
    get_sheet_data,
    copy_and_parse_document,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def find_birding_log_file(copy_from_env, search_dirs):
    """
    Search for birding log XLSX file in multiple directories.
    
    Returns: (success, workbook, filepath, error_message)
    """
    candidate_patterns = [
        r'bird',
        r'log',
        r'march',
        r'observation',
        r'field',
        r'riverside'
    ]
    
    for search_dir in search_dirs:
        logger.info(f"Searching for XLSX files in {search_dir}")
        
        # Try to list files in the directory
        temp_list_file = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.txt')
        temp_list_path = temp_list_file.name
        temp_list_file.close()
        
        try:
            # Create a script to list files
            list_script = f"""
#!/bin/bash
if [ -d "{search_dir}" ]; then
    find "{search_dir}" -maxdepth 2 -name "*.xlsx" -type f -mmin -15 2>/dev/null || true
fi
"""
            temp_script = tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.sh')
            temp_script.write(list_script)
            temp_script.close()
            
            # This is a workaround - we'll try common filenames
            common_names = [
                'Birding_Log_March2024.xlsx',
                'birding_log_march2024.xlsx',
                'bird_log.xlsx',
                'Bird_Log.xlsx',
                'birding_log.xlsx',
                'Birding_Log.xlsx',
                'march_2024_birds.xlsx',
                'field_observations.xlsx',
                'bird_observations.xlsx',
                'riverside_birds.xlsx'
            ]
            
            for filename in common_names:
                candidate_path = f"{search_dir}/{filename}"
                logger.info(f"Trying candidate file: {candidate_path}")
                
                try:
                    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.xlsx')
                    temp_file.close()
                    
                    copy_from_env(candidate_path, temp_file.name)
                    
                    if os.path.exists(temp_file.name) and os.path.getsize(temp_file.name) > 0:
                        wb = parse_xlsx_file(temp_file.name)
                        if wb:
                            logger.info(f"✅ Found and parsed: {candidate_path}")
                            return True, wb, candidate_path, ""
                    
                    os.unlink(temp_file.name)
                except Exception as e:
                    logger.debug(f"Failed to load {candidate_path}: {e}")
                    if os.path.exists(temp_file.name):
                        os.unlink(temp_file.name)
                    continue
            
            # Try to find any XLSX file with birding-related name
            try:
                # List all files in directory by trying to copy a directory listing
                pass
            except:
                pass
                
        except Exception as e:
            logger.debug(f"Error searching {search_dir}: {e}")
            continue
    
    return False, None, "", "No birding log XLSX file found in expected locations"


def validate_column_headers(header_row):
    """
    Validate that required column headers are present.
    Uses flexible keyword matching.
    
    Returns: {
        'valid': bool,
        'missing': list of missing column types,
        'indices': dict mapping column type to index
    }
    """
    if not header_row:
        return {'valid': False, 'missing': ['all'], 'indices': {}}
    
    # Convert headers to lowercase strings
    headers_lower = []
    for h in header_row:
        if h is None:
            headers_lower.append("")
        else:
            headers_lower.append(str(h).lower().strip())
    
    logger.info(f"Header row detected: {headers_lower}")
    
    # Define required columns with flexible keywords
    required_columns = {
        'date': ['date', 'day', 'when', 'obs date', 'observation date'],
        'species': ['species', 'bird', 'name', 'common name', 'bird name'],
        'count': ['count', 'number', 'quantity', 'how many', '#', 'num', 'amount'],
        'location': ['location', 'site', 'place', 'where', 'spot', 'park']
    }
    
    found_indices = {}
    missing = []
    
    for col_type, keywords in required_columns.items():
        found = False
        for idx, header in enumerate(headers_lower):
            # Check if any keyword appears in the header
            if any(keyword in header for keyword in keywords):
                found_indices[col_type] = idx
                found = True
                logger.info(f"Found '{col_type}' column at index {idx}: '{header}'")
                break
        
        if not found:
            missing.append(col_type)
            logger.warning(f"Missing '{col_type}' column")
    
    return {
        'valid': len(missing) == 0,
        'missing': missing,
        'indices': found_indices
    }


def validate_dates(rows, date_col_idx):
    """
    Validate date column has multiple dates.
    
    Returns: {
        'score': int (0-15),
        'feedback': str,
        'unique_dates': int
    }
    """
    dates_found = []
    
    for row in rows:
        if date_col_idx < len(row):
            date_val = row[date_col_idx]
            if date_val:
                # Handle various date formats
                date_str = str(date_val).strip()
                if date_str and date_str.lower() not in ['none', 'null', '']:
                    dates_found.append(date_str)
    
    # Get unique dates (as strings since they might be in various formats)
    unique_dates = set(dates_found)
    unique_count = len(unique_dates)
    
    logger.info(f"Found {len(dates_found)} date entries, {unique_count} unique dates")
    logger.info(f"Unique dates: {unique_dates}")
    
    if unique_count < 2:
        return {
            'score': 5,
            'feedback': f"⚠️ Only {unique_count} unique date(s), expected 2-3",
            'unique_dates': unique_count
        }
    elif unique_count == 2:
        return {
            'score': 12,
            'feedback': f"✅ Observations span {unique_count} dates (good)",
            'unique_dates': unique_count
        }
    else:
        return {
            'score': 15,
            'feedback': f"✅ Observations span {unique_count} dates (excellent)",
            'unique_dates': unique_count
        }


def validate_species_diversity(rows, species_col_idx):
    """
    Validate species diversity - should have at least 4 unique species.
    
    Returns: {
        'score': int (0-15),
        'feedback': str,
        'unique_species': int
    }
    """
    species_found = []
    
    for row in rows:
        if species_col_idx < len(row):
            species_val = row[species_col_idx]
            if species_val:
                species_str = str(species_val).strip().lower()
                if species_str and species_str not in ['none', 'null', '', 'n/a']:
                    # Normalize species name (remove ? and other markers for counting)
                    species_clean = re.sub(r'[?!~]', '', species_str).strip()
                    species_found.append(species_clean)
    
    unique_species = set(species_found)
    unique_count = len(unique_species)
    
    logger.info(f"Found {len(species_found)} species entries, {unique_count} unique species")
    logger.info(f"Unique species: {list(unique_species)[:10]}")
    
    if unique_count < 3:
        return {
            'score': 5,
            'feedback': f"❌ Only {unique_count} species found (need 4+)",
            'unique_species': unique_count
        }
    elif unique_count == 3:
        return {
            'score': 10,
            'feedback': f"⚠️ Only {unique_count} species (expected 4+)",
            'unique_species': unique_count
        }
    elif unique_count == 4:
        return {
            'score': 13,
            'feedback': f"✅ {unique_count} species recorded (meets minimum)",
            'unique_species': unique_count
        }
    else:
        return {
            'score': 15,
            'feedback': f"✅ Excellent species diversity: {unique_count} species",
            'unique_species': unique_count
        }


def check_data_quality_indicators(rows, col_indices, sheet_data):
    """
    Check if agent handled uncertain/missing data appropriately.
    Looks for markers like ?, sp., unknown, etc.
    
    Returns: {
        'score': int (0-10),
        'feedback': str
    }
    """
    # Collect all cell values as text
    all_values = []
    for row in sheet_data:  # Use full sheet data including headers
        for cell in row:
            if cell:
                all_values.append(str(cell))
    
    all_text = " ".join(all_values).lower()
    
    # Look for uncertainty indicators
    uncertainty_indicators = {
        '?': 'question mark',
        'sp.': 'genus-level ID',
        'sp': 'species uncertain',
        'unknown': 'unknown marker',
        'uncertain': 'uncertain marker',
        'maybe': 'maybe marker',
        'approx': 'approximate',
        '~': 'approximate symbol',
        'n/a': 'N/A marker',
        'not recorded': 'not recorded',
        'forgot': 'forgot marker',
        'unsure': 'unsure marker',
        '(?)': 'parenthetical question'
    }
    
    found_indicators = []
    for indicator, description in uncertainty_indicators.items():
        if indicator in all_text:
            found_indicators.append(description)
            logger.info(f"Found data quality indicator: {description}")
    
    # Check for empty cells (appropriate handling of missing data)
    empty_count = 0
    for row in rows:
        for cell in row:
            if cell is None or str(cell).strip() == '':
                empty_count += 1
    
    # Check if there are some missing times (expected based on field notes)
    time_col_idx = col_indices.get('time', None)
    has_missing_time = False
    if time_col_idx is not None:
        for row in rows:
            if time_col_idx < len(row):
                time_val = row[time_col_idx]
                if not time_val or str(time_val).strip() == '':
                    has_missing_time = True
                    break
    
    # Scoring
    score = 0
    feedback_parts = []
    
    if len(found_indicators) > 0:
        score += 6
        feedback_parts.append(f"uncertainty markers found ({', '.join(found_indicators[:2])})")
    
    if empty_count > 0 or has_missing_time:
        score += 4
        feedback_parts.append("appropriately left some data blank")
    
    if score >= 8:
        feedback = f"✅ Good data quality awareness: {', '.join(feedback_parts)}"
    elif score >= 4:
        feedback = f"⚠️ Some data quality indicators: {', '.join(feedback_parts)}"
    else:
        feedback = "⚠️ No clear data quality indicators (expected some uncertain/missing data)"
        score = 5  # Give partial credit
    
    return {
        'score': score,
        'feedback': feedback
    }


def verify_birding_log(traj, env_info, task_info):
    """
    Verify that agent created a proper birding observation log spreadsheet.
    
    Scoring breakdown:
    - File exists and parseable: 20 points
    - Proper column structure: 20 points  
    - Sufficient observations (5+): 20 points
    - Multiple dates: 15 points
    - Species diversity (4+): 15 points
    - Data quality awareness: 10 points
    
    Total: 100 points
    Pass threshold: 70 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_birding_')
    
    try:
        feedback_parts = []
        score = 0
        
        # Search for birding log file in multiple locations
        search_dirs = [
            "/home/ga/Documents/Spreadsheets",
            "/home/ga/Documents",
            "/home/ga/Desktop"
        ]
        
        success, wb, filepath, error = find_birding_log_file(copy_from_env, search_dirs)
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Could not find birding log XLSX file. Searched in: {', '.join(search_dirs)}. {error}"
            }
        
        logger.info(f"Found birding log at: {filepath}")
        score += 20
        feedback_parts.append("✅ File found and parsed")
        
        # Get first sheet data
        sheet_name = wb.sheetnames[0]
        data = get_sheet_data(wb, sheet_name, max_rows=50, max_cols=15)
        
        if len(data) < 2:
            return {
                "passed": False,
                "score": score,
                "feedback": " | ".join(feedback_parts) + " | ❌ Spreadsheet is empty or has only headers"
            }
        
        logger.info(f"Sheet has {len(data)} rows")
        
        # Validate column headers
        header_row = data[0]
        header_validation = validate_column_headers(header_row)
        
        if not header_validation['valid']:
            return {
                "passed": False,
                "score": score + 5,
                "feedback": " | ".join(feedback_parts) + f" | ❌ Missing required columns: {', '.join(header_validation['missing'])}"
            }
        
        score += 20
        feedback_parts.append("✅ Column structure valid")
        col_indices = header_validation['indices']
        
        # Get data rows (skip header)
        data_rows = data[1:]
        non_empty_rows = [row for row in data_rows if any(cell for cell in row if cell)]
        
        logger.info(f"Found {len(non_empty_rows)} non-empty data rows")
        
        # Check sufficient observations
        if len(non_empty_rows) < 4:
            feedback_parts.append(f"❌ Insufficient observations: {len(non_empty_rows)} (need 5)")
            score += 5
        elif len(non_empty_rows) == 4:
            feedback_parts.append(f"⚠️ Only {len(non_empty_rows)} observations (expected 5+)")
            score += 15
        elif len(non_empty_rows) == 5:
            feedback_parts.append(f"✅ Sufficient observations: {len(non_empty_rows)}")
            score += 20
        else:
            feedback_parts.append(f"✅ Excellent: {len(non_empty_rows)} observations")
            score += 20
        
        # Validate dates
        date_validation = validate_dates(non_empty_rows, col_indices['date'])
        score += date_validation['score']
        feedback_parts.append(date_validation['feedback'])
        
        # Validate species diversity
        species_validation = validate_species_diversity(non_empty_rows, col_indices['species'])
        score += species_validation['score']
        feedback_parts.append(species_validation['feedback'])
        
        # Check for data quality indicators
        quality_validation = check_data_quality_indicators(non_empty_rows, col_indices, data)
        score += quality_validation['score']
        feedback_parts.append(quality_validation['feedback'])
        
        # Cap score at 100
        score = min(score, 100)
        
        # Compile final feedback
        final_feedback = " | ".join(feedback_parts)
        passed = score >= 70
        
        logger.info(f"Final score: {score}, Passed: {passed}")
        
        return {
            "passed": passed,
            "score": score,
            "feedback": final_feedback
        }
    
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
