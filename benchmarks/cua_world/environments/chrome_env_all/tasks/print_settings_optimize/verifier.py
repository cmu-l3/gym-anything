#!/usr/bin/env python3
"""
Verifier for Chrome Print Settings Optimization Task (print_settings_optimize@1)
Task: Configure Chrome print settings for optimized webpage printing

Verification Strategy:
1. Check Chrome Preferences file for print settings (sticky settings)
2. Verify PDF file was created
3. Analyze PDF properties and content
4. Validate optimization indicators

Criteria (6 total, need 4+ to pass at 70%):
1. Headers/footers disabled
2. Background graphics disabled
3. Margins optimized (None or Minimum)
4. Scale adjusted appropriately (85-100%)
5. PDF created successfully with reasonable properties
6. Quality indicators (no URL headers in PDF, reasonable file size)
"""

import logging
import sys
import os
import json
import re
import tempfile
from pathlib import Path
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PDF libraries
try:
    from PyPDF2 import PdfReader
    HAS_PYPDF2 = True
except ImportError:
    try:
        import pypdf
        from pypdf import PdfReader
        HAS_PYPDF2 = True
    except ImportError:
        HAS_PYPDF2 = False
        logger.warning("PyPDF2/pypdf not available, PDF analysis will be limited")

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def get_print_settings_from_prefs(prefs_data: Dict) -> Dict[str, Any]:
    """
    Extract print settings from Chrome Preferences JSON.
    
    Chrome stores print settings in:
    printing.print_preview_sticky_settings.appState (JSON string)
    
    Returns:
        Dict with extracted print settings
    """
    try:
        # Navigate to print settings
        printing = prefs_data.get('printing', {})
        sticky_settings = printing.get('print_preview_sticky_settings', {})
        
        # appState is stored as a JSON string, need to parse it
        app_state_str = sticky_settings.get('appState', '{}')
        app_state = json.loads(app_state_str)
        
        # Extract relevant settings
        settings = {
            'headers_footers_enabled': app_state.get('headerFooterEnabled', True),
            'background_graphics_enabled': app_state.get('shouldPrintBackgrounds', True),
            'margins_type': app_state.get('marginsType', 0),  # 0=default, 1=none, 2=minimum
            'scaling': app_state.get('scaling', '100'),
            'is_landscape': app_state.get('isLandscapeEnabled', False),
            'color': app_state.get('color', 2),  # 1=black&white, 2=color
        }
        
        # Convert scaling to int if possible
        try:
            if isinstance(settings['scaling'], str):
                settings['scaling'] = int(settings['scaling'])
        except:
            settings['scaling'] = 100
        
        logger.info(f"Extracted print settings: {settings}")
        return settings
        
    except Exception as e:
        logger.error(f"Error extracting print settings: {e}")
        return {}


def find_and_copy_pdf(copy_from_env) -> Tuple[bool, str, str, str]:
    """
    Find and copy the generated PDF from container.
    
    Returns:
        Tuple of (success, local_path, pdf_name, error_message)
    """
    try:
        # First, get the filename that was recorded
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/pdf_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No PDF file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read pdf_filename.txt: {e}")
            found_name = "optimized_print.pdf"
        
        # Try to copy the PDF file
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/print_optimize_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            f"/home/ga/Downloads/optimized_print.pdf",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy PDF from: {container_path}")
                copy_from_env(container_path, temp_pdf.name)
                
                # Check if file has content
                if Path(temp_pdf.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied PDF from: {container_path}")
                    return True, temp_pdf.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_pdf.name)
        return False, "", "", "PDF file could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding PDF: {e}", exc_info=True)
        return False, "", "", f"Error finding PDF: {str(e)}"


def get_chrome_preferences(copy_from_env) -> Tuple[bool, Dict, str]:
    """
    Copy and parse Chrome Preferences file from container.
    
    Returns:
        Tuple of (success, prefs_dict, error_message)
    """
    try:
        temp_prefs = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
        
        # Try multiple locations
        possible_paths = [
            "/tmp/print_optimize_verification/chrome_preferences.json",
            "/tmp/chrome_preferences.json",
            "/home/ga/.config/google-chrome-cdp/Default/Preferences",
            "/home/ga/.config/google-chrome/Default/Preferences",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy Preferences from: {container_path}")
                copy_from_env(container_path, temp_prefs.name)
                
                # Try to parse
                with open(temp_prefs.name, 'r', encoding='utf-8') as f:
                    prefs_data = json.load(f)
                
                os.unlink(temp_prefs.name)
                logger.info(f"✓ Successfully loaded Preferences from: {container_path}")
                return True, prefs_data, ""
                
            except Exception as e:
                logger.debug(f"Could not load from {container_path}: {e}")
                continue
        
        os.unlink(temp_prefs.name)
        return False, {}, "Could not load Chrome Preferences from any location"
        
    except Exception as e:
        logger.error(f"Error getting preferences: {e}")
        return False, {}, f"Error: {str(e)}"


def analyze_pdf_properties(pdf_path: str) -> Dict[str, Any]:
    """
    Analyze PDF file properties.
    
    Returns:
        Dict with PDF analysis results
    """
    results = {
        'file_size_bytes': 0,
        'file_size_kb': 0,
        'page_count': 0,
        'has_text': False,
        'text_sample': '',
        'has_url_header': False,
        'analysis_success': False
    }
    
    try:
        # File size
        size_bytes = Path(pdf_path).stat().st_size
        results['file_size_bytes'] = size_bytes
        results['file_size_kb'] = size_bytes / 1024
        
        if not HAS_PYPDF2:
            logger.warning("PyPDF2 not available, skipping detailed PDF analysis")
            results['analysis_success'] = size_bytes > 0
            return results
        
        # Open and analyze PDF
        reader = PdfReader(pdf_path)
        results['page_count'] = len(reader.pages)
        
        # Extract text from first few pages
        text_sample = ""
        for i, page in enumerate(reader.pages[:3]):  # Check first 3 pages
            try:
                page_text = page.extract_text()
                if page_text:
                    text_sample += page_text + "\n"
            except Exception as e:
                logger.warning(f"Could not extract text from page {i}: {e}")
        
        results['has_text'] = len(text_sample) > 100
        results['text_sample'] = text_sample[:500]  # First 500 chars
        
        # Check for URL headers (indicators that headers/footers weren't disabled)
        text_lower = text_sample.lower()
        url_indicators = ['http://', 'https://', 'file:///', 'chrome://', 'about:']
        results['has_url_header'] = any(indicator in text_lower for indicator in url_indicators)
        
        results['analysis_success'] = True
        logger.info(f"PDF analysis: {results['page_count']} pages, {results['file_size_kb']:.1f} KB")
        
    except Exception as e:
        logger.error(f"Error analyzing PDF: {e}")
        results['analysis_success'] = False
    
    return results


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for print_settings_optimize@1 task.
    
    Verifies:
    1. Chrome print settings were configured correctly
    2. PDF was created
    3. PDF shows signs of optimization
    
    Scoring:
    - 100%: All 6 criteria met
    - 85-99%: 5/6 criteria met
    - 70-84%: 4/6 criteria met (pass threshold)
    - 50-69%: 3/6 criteria met
    - <50%: <3 criteria met
    
    Pass threshold: 70% (4 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 6
    feedback_parts = []
    
    # Step 1: Get Chrome Preferences
    logger.info("Step 1: Retrieving Chrome Preferences...")
    prefs_success, prefs_data, prefs_error = get_chrome_preferences(copy_from_env)
    
    if not prefs_success:
        feedback_parts.append(f"⚠ Warning: Could not load Chrome Preferences - {prefs_error}")
        feedback_parts.append("   Print settings verification will be limited")
        print_settings = {}
    else:
        print_settings = get_print_settings_from_prefs(prefs_data)
    
    # Criterion 1: Headers/footers disabled
    if print_settings:
        headers_disabled = not print_settings.get('headers_footers_enabled', True)
        if headers_disabled:
            feedback_parts.append("✓ Criterion 1: Headers/footers disabled")
            criteria_met += 1
        else:
            feedback_parts.append("✗ Criterion 1: Headers/footers still enabled")
    else:
        feedback_parts.append("? Criterion 1: Could not verify headers/footers setting")
    
    # Criterion 2: Background graphics disabled
    if print_settings:
        backgrounds_disabled = not print_settings.get('background_graphics_enabled', True)
        if backgrounds_disabled:
            feedback_parts.append("✓ Criterion 2: Background graphics disabled")
            criteria_met += 1
        else:
            feedback_parts.append("✗ Criterion 2: Background graphics still enabled")
    else:
        feedback_parts.append("? Criterion 2: Could not verify background graphics setting")
    
    # Criterion 3: Margins optimized (1=none, 2=minimum)
    if print_settings:
        margins_type = print_settings.get('margins_type', 0)
        margins_optimized = margins_type in [1, 2]
        if margins_optimized:
            margin_name = "None" if margins_type == 1 else "Minimum"
            feedback_parts.append(f"✓ Criterion 3: Margins optimized ({margin_name})")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Criterion 3: Margins not optimized (type={margins_type}, expected 1 or 2)")
    else:
        feedback_parts.append("? Criterion 3: Could not verify margins setting")
    
    # Criterion 4: Scale adjusted (85-100%)
    if print_settings:
        scale = print_settings.get('scaling', 100)
        # We want scale to be adjusted from default AND within reasonable range
        # Accept slight variations: 85-100 is optimal, but 80-105 is acceptable
        scale_ok = 80 <= scale <= 105 and scale != 100
        if scale_ok:
            feedback_parts.append(f"✓ Criterion 4: Scale adjusted to {scale}%")
            criteria_met += 1
        elif scale == 100:
            feedback_parts.append(f"✗ Criterion 4: Scale unchanged at default 100%")
        else:
            feedback_parts.append(f"✗ Criterion 4: Scale at {scale}% (expected 85-100%)")
    else:
        feedback_parts.append("? Criterion 4: Could not verify scale setting")
    
    # Step 2: Check for PDF file
    logger.info("Step 2: Looking for PDF file...")
    pdf_success, pdf_path, pdf_name, pdf_error = find_and_copy_pdf(copy_from_env)
    
    if not pdf_success:
        feedback_parts.append(f"✗ Criterion 5: PDF not found - {pdf_error}")
        feedback_parts.append("✗ Criterion 6: Cannot analyze PDF quality (file not found)")
        
        # Calculate final score without PDF criteria
        score = int((criteria_met / total_criteria) * 100)
        passed = score >= 70
        
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {score}%"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    # Criterion 5: PDF created successfully with reasonable properties
    logger.info("Step 3: Analyzing PDF properties...")
    pdf_analysis = analyze_pdf_properties(pdf_path)
    
    pdf_valid = (
        pdf_analysis['file_size_kb'] >= 10 and  # At least 10KB
        pdf_analysis['file_size_kb'] <= 5000 and  # Not unreasonably large
        (pdf_analysis['page_count'] >= 1 if pdf_analysis['page_count'] > 0 else True) and
        pdf_analysis['page_count'] <= 20  # Recipe shouldn't be more than 20 pages
    )
    
    if pdf_valid:
        feedback_parts.append(f"✓ Criterion 5: PDF created successfully ({pdf_analysis['file_size_kb']:.1f} KB, {pdf_analysis['page_count']} pages)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Criterion 5: PDF has issues (size: {pdf_analysis['file_size_kb']:.1f} KB, pages: {pdf_analysis['page_count']})")
    
    # Criterion 6: Quality indicators (no URL headers, reasonable size)
    quality_score = 0
    quality_reasons = []
    
    # Check 1: No URL headers in PDF text (indicates headers/footers were disabled)
    if not pdf_analysis['has_url_header']:
        quality_score += 0.5
        quality_reasons.append("no URL headers detected")
    else:
        quality_reasons.append("URL headers found (headers/footers may not be disabled)")
    
    # Check 2: File size suggests background graphics removed (smaller file)
    # Recipe with backgrounds would be 200-400KB, without should be 50-150KB
    if 20 <= pdf_analysis['file_size_kb'] <= 200:
        quality_score += 0.5
        quality_reasons.append("optimal file size")
    elif pdf_analysis['file_size_kb'] > 400:
        quality_reasons.append("large file size (backgrounds may be included)")
    
    quality_ok = quality_score >= 0.5
    if quality_ok:
        feedback_parts.append(f"✓ Criterion 6: Quality indicators positive ({', '.join(quality_reasons)})")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Criterion 6: Quality issues detected ({', '.join(quality_reasons)})")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nPrint Settings Summary:"
    if print_settings:
        feedback += f"\n  Headers/Footers: {'Disabled' if not print_settings.get('headers_footers_enabled', True) else 'Enabled'}"
        feedback += f"\n  Background Graphics: {'Disabled' if not print_settings.get('background_graphics_enabled', True) else 'Enabled'}"
        feedback += f"\n  Margins: Type {print_settings.get('margins_type', 0)} ({'None' if print_settings.get('margins_type') == 1 else 'Minimum' if print_settings.get('margins_type') == 2 else 'Default'})"
        feedback += f"\n  Scale: {print_settings.get('scaling', 100)}%"
    feedback += f"\n\nPDF Analysis:"
    feedback += f"\n  File: {pdf_name}"
    feedback += f"\n  Size: {pdf_analysis['file_size_kb']:.1f} KB"
    feedback += f"\n  Pages: {pdf_analysis['page_count']}"
    feedback += f"\n  Has URL Headers: {'Yes' if pdf_analysis['has_url_header'] else 'No'}"
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PYPDF2:
        feedback += "\n\n⚠ Note: PyPDF2 library not available, PDF analysis was limited"
    
    # Clean up temporary files
    try:
        if pdf_path and os.path.exists(pdf_path):
            os.unlink(pdf_path)
    except:
        pass
    
    cleanup_verification_temp()
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "print_settings": print_settings,
            "pdf_analysis": pdf_analysis
        }
    }
