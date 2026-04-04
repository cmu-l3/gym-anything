#!/usr/bin/env python3
"""
Verifier for Chrome Print-to-PDF Task
Task: Print webpage to PDF with landscape orientation and minimal margins
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime, timedelta

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


def find_pdf_file(copy_from_env, expected_name="machine_learning_fundamentals.pdf"):
    """
    Find and copy the generated PDF from the container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found
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
            found_name = expected_name
        
        # Try to copy the PDF file from verification directory
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/print_pdf_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            f"/home/ga/Downloads/{expected_name}",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
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


def check_pdf_file_size(pdf_path):
    """
    Check if PDF has meaningful file size.
    
    Returns:
        tuple: (passed, size_kb, feedback)
    """
    try:
        size_bytes = Path(pdf_path).stat().st_size
        size_kb = size_bytes / 1024
        
        if size_bytes < 1024:  # Less than 1KB
            return False, size_kb, f"File too small ({size_bytes} bytes)"
        elif size_bytes < 10240:  # Less than 10KB
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB)"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def check_pdf_page_count(pdf_path):
    """
    Check PDF page count is reasonable.
    
    Returns:
        tuple: (passed, page_count, feedback)
    """
    if not HAS_PYPDF2:
        return None, 0, "PyPDF2 not available"
    
    try:
        reader = PdfReader(pdf_path)
        page_count = len(reader.pages)
        
        if page_count < 1:
            return False, page_count, "PDF has no pages"
        elif page_count < 2:
            return False, page_count, "PDF has only 1 page (content likely truncated)"
        elif page_count > 15:
            return False, page_count, f"PDF has too many pages ({page_count})"
        else:
            return True, page_count, f"Page count OK ({page_count} pages)"
            
    except Exception as e:
        logger.error(f"Error checking page count: {e}")
        return False, 0, f"Could not check page count: {e}"


def check_pdf_orientation(pdf_path):
    """
    Check if PDF is in landscape orientation.
    
    Returns:
        tuple: (passed, landscape_percentage, feedback)
    """
    if not HAS_PYPDF2:
        return None, 0, "PyPDF2 not available"
    
    try:
        reader = PdfReader(pdf_path)
        total_pages = len(reader.pages)
        landscape_count = 0
        
        for page in reader.pages:
            try:
                # Get page dimensions
                mediabox = page.mediabox
                width = float(mediabox.width)
                height = float(mediabox.height)
                
                # Landscape if width > height
                if width > height:
                    landscape_count += 1
                    
            except Exception as e:
                logger.warning(f"Could not check orientation for a page: {e}")
        
        if total_pages == 0:
            return False, 0, "No pages to check orientation"
        
        landscape_pct = (landscape_count / total_pages) * 100
        
        if landscape_pct >= 80:
            return True, landscape_pct, f"Landscape orientation detected ({landscape_pct:.0f}% of pages)"
        else:
            return False, landscape_pct, f"Not landscape ({landscape_pct:.0f}% landscape pages)"
            
    except Exception as e:
        logger.error(f"Error checking orientation: {e}")
        return False, 0, f"Could not check orientation: {e}"


def extract_pdf_text(pdf_path):
    """
    Extract text from PDF.
    
    Returns:
        str: Extracted text
    """
    if not HAS_PYPDF2:
        return ""
    
    try:
        reader = PdfReader(pdf_path)
        text = ""
        
        for page in reader.pages:
            try:
                page_text = page.extract_text()
                if page_text:
                    text += page_text + "\n"
            except Exception as e:
                logger.warning(f"Could not extract text from a page: {e}")
        
        return text
        
    except Exception as e:
        logger.error(f"Error extracting PDF text: {e}")
        return ""


def check_pdf_content(pdf_path):
    """
    Check if PDF contains expected content keywords.
    
    Returns:
        tuple: (passed, matches, total_keywords, feedback)
    """
    # Expected keywords from the machine learning article
    expected_keywords = [
        "machine learning",
        "algorithm",
        "neural network",
        "training",
        "model",
        "data",
        "supervised",
        "prediction",
        "classification",
        "regression"
    ]
    
    text = extract_pdf_text(pdf_path)
    
    if not text:
        return False, 0, len(expected_keywords), "Could not extract text from PDF"
    
    text_lower = text.lower()
    matches = 0
    found_keywords = []
    
    for keyword in expected_keywords:
        if keyword.lower() in text_lower:
            matches += 1
            found_keywords.append(keyword)
    
    # Require at least 60% of keywords
    required_matches = max(3, int(len(expected_keywords) * 0.6))
    passed = matches >= required_matches
    
    if passed:
        feedback = f"Content verified ({matches}/{len(expected_keywords)} keywords found)"
    else:
        feedback = f"Insufficient content ({matches}/{len(expected_keywords)} keywords, need {required_matches})"
    
    return passed, matches, len(expected_keywords), feedback


def check_filename_correctness(actual_name, expected_name="machine_learning_fundamentals.pdf"):
    """
    Check if the filename matches expected.
    
    Returns:
        tuple: (passed, feedback)
    """
    actual_lower = actual_name.lower()
    expected_lower = expected_name.lower()
    
    if actual_lower == expected_lower:
        return True, f"Filename correct: {actual_name}"
    elif "machine" in actual_lower and "learning" in actual_lower:
        return True, f"Filename close enough: {actual_name}"
    else:
        return False, f"Filename incorrect: {actual_name} (expected: {expected_name})"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for Print-to-PDF task.
    
    Verifies:
    1. PDF file exists and was created
    2. File has meaningful size (>10KB)
    3. PDF has reasonable page count (2-15 pages)
    4. PDF is in landscape orientation
    5. PDF contains expected content keywords
    6. Filename is correct or close
    
    Scoring:
    - 100%: All 6 criteria met
    - 85-99%: 5/6 criteria met
    - 70-84%: 4/6 criteria met
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
    
    # Criterion 1: PDF file exists
    logger.info("Checking if PDF file exists...")
    success, pdf_path, pdf_name, error = find_pdf_file(copy_from_env)
    
    if not success:
        feedback = f"✗ PDF file not found\n{error}"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ PDF found: {pdf_name}")
    criteria_met += 1
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_kb, size_feedback = check_pdf_file_size(pdf_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {size_feedback}")
    
    # Criterion 3: Page count check
    logger.info("Checking page count...")
    count_ok, page_count, count_feedback = check_pdf_page_count(pdf_path)
    if count_ok is None:
        feedback_parts.append(f"⚠ {count_feedback}")
        criteria_met += 0.3  # Partial credit if library not available
    elif count_ok:
        feedback_parts.append(f"✓ {count_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {count_feedback}")
    
    # Criterion 4: Orientation check (landscape)
    logger.info("Checking orientation...")
    orient_ok, landscape_pct, orient_feedback = check_pdf_orientation(pdf_path)
    if orient_ok is None:
        feedback_parts.append(f"⚠ {orient_feedback}")
        criteria_met += 0.3  # Partial credit if library not available
    elif orient_ok:
        feedback_parts.append(f"✓ {orient_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {orient_feedback}")
    
    # Criterion 5: Content check
    logger.info("Checking PDF content...")
    content_ok, matches, total_kw, content_feedback = check_pdf_content(pdf_path)
    if content_ok:
        feedback_parts.append(f"✓ {content_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {content_feedback}")
    
    # Criterion 6: Filename check
    logger.info("Checking filename...")
    filename_ok, filename_feedback = check_filename_correctness(pdf_name)
    if filename_ok:
        feedback_parts.append(f"✓ {filename_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ {filename_feedback}")
        criteria_met += 0.5  # Partial credit for wrong filename
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PYPDF2:
        feedback += "\n\n⚠ Note: PyPDF2 library not available, some checks had limited functionality"
    
    # Clean up temporary file
    try:
        if pdf_path and os.path.exists(pdf_path):
            os.unlink(pdf_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback
    }
