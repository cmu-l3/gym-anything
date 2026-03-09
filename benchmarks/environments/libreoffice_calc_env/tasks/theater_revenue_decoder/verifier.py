#!/usr/bin/env python3
"""
Verifier for Theater Revenue Decoder task.
Checks documentation quality, comments, labels, error fixes, and content.
"""

import sys
import os
import logging
import zipfile
from xml.etree import ElementTree as ET

# Add utils to path - use relative path for host execution
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from calc_verification_utils import (
    setup_calc_verification,
    cleanup_verification_temp,
    get_sheet_names,
    get_cell_value,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def count_cell_annotations(filepath):
    """
    Count cell annotations (comments) in ODS file.
    
    Returns:
        int: Number of annotations found
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return 0
            
            content_xml = ods_zip.read('content.xml')
            root = ET.fromstring(content_xml)
            
            # Define namespaces
            namespaces = {
                'office': 'urn:oasis:names:tc:opendocument:xmlns:office:1.0',
                'table': 'urn:oasis:names:tc:opendocument:xmlns:table:1.0',
                'text': 'urn:oasis:names:tc:opendocument:xmlns:text:1.0'
            }
            
            # Count annotation elements (cell comments)
            annotations = root.findall('.//office:annotation', namespaces)
            
            # Also check for table:annotation
            table_annotations = root.findall('.//table:annotation', namespaces)
            
            total_count = len(annotations) + len(table_annotations)
            logger.info(f"Found {total_count} cell annotations/comments")
            
            return total_count
            
    except Exception as e:
        logger.error(f"Error counting annotations: {e}", exc_info=True)
        return 0


def check_for_ref_errors(filepath):
    """
    Count #REF! errors in ODS file.
    
    Returns:
        int: Number of #REF! errors found
    """
    try:
        with zipfile.ZipFile(filepath, 'r') as ods_zip:
            if 'content.xml' not in ods_zip.namelist():
                return 0
            
            content_xml = ods_zip.read('content.xml')
            content_str = content_xml.decode('utf-8', errors='ignore')
            
            # Count occurrences of #REF! or Err:502 (ODS error code for reference error)
            ref_count = content_str.count('#REF!')
            err502_count = content_str.count('Err:502')
            
            total_errors = ref_count + err502_count
            logger.info(f"Found {total_errors} reference errors (#REF! or Err:502)")
            
            return total_errors
            
    except Exception as e:
        logger.error(f"Error checking for #REF! errors: {e}", exc_info=True)
        return 999  # Return high number on error to avoid false positive


def analyze_documentation_sheet(data, sheet_name):
    """
    Analyze documentation sheet content quality.
    
    Returns:
        dict with keys: has_content, content_length, keywords_found, quality_score
    """
    try:
        if sheet_name not in data['sheets']:
            return {'has_content': False, 'content_length': 0, 'keywords_found': [], 'quality_score': 0}
        
        sheet_rows = data['sheets'][sheet_name]
        
        # Concatenate all text content
        all_text = []
        for row in sheet_rows:
            for cell in row:
                if isinstance(cell, dict):
                    value = cell.get('value')
                else:
                    value = cell
                
                if value and isinstance(value, str):
                    all_text.append(value.lower())
        
        combined_text = ' '.join(all_text)
        content_length = len(combined_text)
        
        # Check for important keywords
        required_keywords = [
            'purpose', 'input', 'formula', 'assumption', 'instruction',
            'ticket', 'revenue', 'price', 'sales', 'calculate'
        ]
        
        keywords_found = [kw for kw in required_keywords if kw in combined_text]
        
        # Check for specific content sections
        has_purpose = 'purpose' in combined_text
        has_inputs = 'input' in combined_text or 'cell' in combined_text
        has_formulas = 'formula' in combined_text
        has_assumptions = 'assumption' in combined_text or 'hardcoded' in combined_text or '8%' in combined_text or '2500' in combined_text
        
        # Quality score based on content
        quality_score = 0
        if content_length > 500:
            quality_score += 25
        elif content_length > 300:
            quality_score += 15
        elif content_length > 100:
            quality_score += 5
        
        if has_purpose:
            quality_score += 20
        if has_inputs:
            quality_score += 15
        if has_formulas:
            quality_score += 20
        if has_assumptions:
            quality_score += 20
        
        return {
            'has_content': content_length > 100,
            'content_length': content_length,
            'keywords_found': keywords_found,
            'quality_score': min(quality_score, 100),
            'has_purpose': has_purpose,
            'has_inputs': has_inputs,
            'has_formulas': has_formulas,
            'has_assumptions': has_assumptions
        }
        
    except Exception as e:
        logger.error(f"Error analyzing documentation: {e}", exc_info=True)
        return {'has_content': False, 'content_length': 0, 'keywords_found': [], 'quality_score': 0}


def check_label_improvements(data, sheet_name):
    """
    Check if descriptive labels were added to improve clarity.
    
    Returns:
        bool: True if improvements detected
    """
    try:
        if sheet_name not in data['sheets']:
            return False
        
        sheet_rows = data['sheets'][sheet_name]
        
        # Look for full descriptive words
        descriptive_terms = [
            'senior', 'general', 'student', 'complimentary', 'gross', 'overhead',
            'net', 'proceeds', 'break-even', 'ticket', 'price', 'discount',
            'processing fee', 'venue', 'rental', 'base price', 'sales'
        ]
        
        found_count = 0
        for row in sheet_rows[:15]:  # Check first 15 rows
            for cell in row:
                if isinstance(cell, dict):
                    value = cell.get('value')
                else:
                    value = cell
                
                if value and isinstance(value, str):
                    value_lower = value.lower()
                    for term in descriptive_terms:
                        if term in value_lower:
                            found_count += 1
                            break
        
        # If we find 3+ descriptive terms, assume labels were improved
        return found_count >= 3
        
    except Exception as e:
        logger.error(f"Error checking labels: {e}", exc_info=True)
        return False


def verify_theater_revenue_decoder(traj, env_info, task_info):
    """
    Verify theater revenue decoder task completion.
    
    Checks:
    1. Documentation sheet exists with substantive content
    2. Cell comments added (6+ comments)
    3. Labels improved (descriptive terms added)
    4. #REF! errors reduced or addressed
    5. Formula explanations present
    6. Assumptions documented
    7. Content quality (length, keywords)
    
    Scoring weights:
    - Documentation sheet: 15%
    - Comments: 20%
    - Labels: 15%
    - Errors: 15%
    - Formula explanations: 15%
    - Assumptions: 10%
    - Content quality: 10%
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}
    
    # Try documented version first, fallback to original
    success = False
    temp_dir = None
    
    for path in [
        "/home/ga/Documents/GalaTicketRevenue_Documented.ods",
        "/home/ga/Documents/GalaTicketRevenue.ods"
    ]:
        success, file_info, error = setup_calc_verification(
            copy_from_env,
            path,
            expected_formats=['ods']
        )
        if success:
            logger.info(f"Successfully loaded file: {path}")
            break
    
    if not success:
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Failed to load spreadsheet: {error}"
        }
    
    try:
        data = file_info['sheet_data']
        filepath = file_info['file_path']
        temp_dir = file_info.get('temp_dir')
        
        sheets = get_sheet_names(data)
        logger.info(f"Found sheets: {sheets}")
        
        # Initialize scoring
        total_score = 0
        max_score = 100
        feedback_parts = []
        criteria_met = []
        
        # Criterion 1: Documentation sheet exists (15 points)
        doc_sheets = [s for s in sheets if 'document' in s.lower() or 'readme' in s.lower() or 'doc' in s.lower()]
        has_doc_sheet = len(doc_sheets) > 0
        
        if has_doc_sheet:
            doc_analysis = analyze_documentation_sheet(data, doc_sheets[0])
            
            if doc_analysis['has_content'] and doc_analysis['content_length'] > 200:
                total_score += 15
                criteria_met.append('documentation_sheet')
                feedback_parts.append(f"✅ Documentation sheet created ('{doc_sheets[0]}', {doc_analysis['content_length']} chars)")
            elif doc_analysis['has_content']:
                total_score += 8
                feedback_parts.append(f"⚠️ Documentation sheet exists but sparse ({doc_analysis['content_length']} chars)")
            else:
                feedback_parts.append(f"❌ Documentation sheet exists but empty")
        else:
            feedback_parts.append("❌ No documentation sheet found")
        
        # Criterion 2: Cell comments added (20 points)
        comment_count = count_cell_annotations(filepath)
        
        if comment_count >= 6:
            total_score += 20
            criteria_met.append('comments_added')
            feedback_parts.append(f"✅ Cell comments added ({comment_count} comments)")
        elif comment_count >= 4:
            total_score += 13
            criteria_met.append('comments_partial')
            feedback_parts.append(f"⚠️ Some cell comments added ({comment_count} comments, need 6+)")
        elif comment_count >= 2:
            total_score += 7
            feedback_parts.append(f"⚠️ Few cell comments added ({comment_count} comments, need 6+)")
        else:
            feedback_parts.append(f"❌ No or minimal cell comments ({comment_count} comments)")
        
        # Criterion 3: Labels improved (15 points)
        main_sheet = sheets[0] if sheets else None
        labels_improved = False
        
        if main_sheet:
            labels_improved = check_label_improvements(data, main_sheet)
        
        if labels_improved:
            total_score += 15
            criteria_met.append('labels_improved')
            feedback_parts.append("✅ Descriptive labels added")
        else:
            feedback_parts.append("❌ Labels not significantly improved")
        
        # Criterion 4: Errors reduced (15 points)
        ref_error_count = check_for_ref_errors(filepath)
        
        # Original has at least 1 error, so any reduction or documentation counts
        if ref_error_count == 0:
            total_score += 15
            criteria_met.append('errors_fixed')
            feedback_parts.append("✅ #REF! errors resolved")
        elif ref_error_count <= 1 and has_doc_sheet:
            # If error still exists but documented
            total_score += 10
            criteria_met.append('errors_documented')
            feedback_parts.append("⚠️ Error documented (1 #REF! remains)")
        else:
            feedback_parts.append(f"❌ Reference errors not addressed ({ref_error_count} errors)")
        
        # Criterion 5: Formula explanations (15 points)
        formula_explanations = False
        if has_doc_sheet:
            doc_analysis = analyze_documentation_sheet(data, doc_sheets[0])
            formula_explanations = doc_analysis.get('has_formulas', False)
        
        if formula_explanations:
            total_score += 15
            criteria_met.append('formulas_explained')
            feedback_parts.append("✅ Formula logic explained")
        elif comment_count >= 4:
            # If good comments, give partial credit
            total_score += 8
            feedback_parts.append("⚠️ Formulas documented via comments but not in documentation sheet")
        else:
            feedback_parts.append("❌ Formula logic not adequately explained")
        
        # Criterion 6: Assumptions documented (10 points)
        assumptions_documented = False
        if has_doc_sheet:
            doc_analysis = analyze_documentation_sheet(data, doc_sheets[0])
            assumptions_documented = doc_analysis.get('has_assumptions', False)
        
        if assumptions_documented:
            total_score += 10
            criteria_met.append('assumptions_documented')
            feedback_parts.append("✅ Hardcoded assumptions documented")
        else:
            feedback_parts.append("❌ Assumptions not documented (e.g., 8% fee, $2500 venue)")
        
        # Criterion 7: Content quality (10 points)
        if has_doc_sheet:
            doc_analysis = analyze_documentation_sheet(data, doc_sheets[0])
            
            if doc_analysis['content_length'] >= 500:
                total_score += 10
                criteria_met.append('quality_good')
                feedback_parts.append(f"✅ Comprehensive documentation ({doc_analysis['content_length']} chars)")
            elif doc_analysis['content_length'] >= 300:
                total_score += 6
                feedback_parts.append(f"⚠️ Moderate documentation ({doc_analysis['content_length']} chars)")
            elif doc_analysis['content_length'] >= 150:
                total_score += 3
                feedback_parts.append(f"⚠️ Brief documentation ({doc_analysis['content_length']} chars)")
        
        # Calculate final results
        score = min(total_score, 100)
        passed = score >= 70
        
        # Summary
        criteria_count = len(criteria_met)
        if passed and score >= 85:
            feedback_parts.insert(0, f"🎉 Excellent documentation work! ({criteria_count}/7 criteria met)")
        elif passed:
            feedback_parts.insert(0, f"✅ Good documentation effort ({criteria_count}/7 criteria met)")
        else:
            feedback_parts.insert(0, f"❌ Insufficient documentation ({criteria_count}/7 criteria met, need 5+)")
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback,
            "subscores": {
                "documentation_sheet": has_doc_sheet,
                "comments_count": comment_count,
                "labels_improved": labels_improved,
                "errors_addressed": ref_error_count <= 1,
                "formulas_explained": formula_explanations,
                "assumptions_documented": assumptions_documented,
                "content_quality": doc_analysis.get('content_length', 0) if has_doc_sheet else 0,
                "criteria_met": criteria_count
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
        if temp_dir:
            cleanup_verification_temp(temp_dir)
