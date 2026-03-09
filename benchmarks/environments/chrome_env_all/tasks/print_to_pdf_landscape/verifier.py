#!/usr/bin/env python3
"""
Verifier for Chrome Print-to-PDF Landscape Task
Task: Export webpage as PDF with landscape orientation
"""

import logging
import sys
import os
import tempfile
from pathlib import Path

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


def find_pdf_file(copy_from_env, expected_name="webpage_landscape_export.pdf"):
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
            f"/tmp/pdf_landscape_verification/{found_name}",
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
        elif size_bytes < 5120:  # Less than 5KB
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB)"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def check_pdf_orientation(pdf_path):
    """
    Check if PDF is in landscape orientation.
    
    Returns:
        tuple: (passed, landscape_percentage, width, height, feedback)
    """
    if not HAS_PYPDF2:
        return None, 0, 0, 0, "PyPDF2 not available"
    
    try:
        reader = PdfReader(pdf_path)
        total_pages = len(reader.pages)
        landscape_count = 0
        
        page_dimensions = []
        
        for page in reader.pages:
            try:
                # Get page dimensions
                mediabox = page.mediabox
                width = float(mediabox.width)
                height = float(mediabox.height)
                
                page_dimensions.append((width, height))
                
                # Landscape if width > height
                if width > height:
                    landscape_count += 1
                    
            except Exception as e:
                logger.warning(f"Could not check orientation for a page: {e}")
        
        if total_pages == 0:
            return False, 0, 0, 0, "No pages to check orientation"
        
        landscape_pct = (landscape_count / total_pages) * 100
        
        # Get first page dimensions for reporting
        first_width, first_height = page_dimensions[0] if page_dimensions else (0, 0)
        
        if landscape_pct >= 90:
            return True, landscape_pct, first_width, first_height, f"Landscape orientation ({landscape_pct:.0f}% of pages)"
        else:
            return False, landscape_pct, first_width, first_height, f"Not landscape ({landscape_pct:.0f}% landscape)"
            
    except Exception as e:
        logger.error(f"Error checking orientation: {e}")
        return False, 0, 0, 0, f"Could not check orientation: {e}"


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
    Check if PDF contains expected content from the data analysis guide.
    
    Returns:
        tuple: (passed, char_count, feedback)
    """
    text = extract_pdf_text(pdf_path)
    
    if not text:
        return False, 0, "Could not extract text from PDF"
    
    text_lower = text.lower()
    char_count = len(text)
    
    # Check for key content from the article
    expected_keywords = [
        "data analysis",
        "python",
        "statistical",
        "table",
        "best practices"
    ]
    
    matches = sum(1 for kw in expected_keywords if kw in text_lower)
    
    # Require at least 500 characters and 3+ keywords
    if char_count < 500:
        return False, char_count, f"Insufficient content ({char_count} chars)"
    elif matches < 3:
        return False, char_count, f"Content doesn't match expected article ({matches}/{len(expected_keywords)} keywords)"
    else:
        return True, char_count, f"Content verified ({char_count} chars, {matches}/{len(expected_keywords)} keywords)"


def check_filename_correctness(actual_name, expected_name="webpage_landscape_export.pdf"):
    """
    Check if the filename matches expected.
    
    Returns:
        tuple: (score_multiplier, feedback)
    """
    actual_lower = actual_name.lower()
    expected_lower = expected_name.lower()
    
    if actual_lower == expected_lower:
        return 1.0, f"✓ Filename correct: {actual_name}"
    elif "landscape" in actual_lower and ".pdf" in actual_lower:
        return 0.9, f"⚠ Filename close: {actual_name} (expected: {expected_name})"
    else:
        return 0.7, f"⚠ Filename differs: {actual_name} (expected: {expected_name})"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for Print-to-PDF Landscape task.
    
    Verifies:
    1. PDF file exists and was created
    2. File has meaningful size (>5KB)
    3. PDF is in landscape orientation (width > height)
    4. PDF contains expected content from article
    
    Scoring:
    - 100%: All criteria met with correct filename
    - 85-99%: All criteria met but filename differs
    - 70-84%: 3/4 criteria met
    - 50-69%: 2/4 criteria met
    - <50%: <2 criteria met
    
    Pass threshold: 70% (3 out of 4 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_results = []
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
    criteria_results.append(True)
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_kb, size_feedback = check_pdf_file_size(pdf_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        criteria_results.append(True)
    else:
        feedback_parts.append(f"✗ {size_feedback}")
        criteria_results.append(False)
    
    # Criterion 3: Orientation check (landscape) - MOST IMPORTANT
    logger.info("Checking orientation...")
    orient_ok, landscape_pct, width, height, orient_feedback = check_pdf_orientation(pdf_path)
    if orient_ok is None:
        feedback_parts.append(f"⚠ {orient_feedback}")
        criteria_results.append(False)  # Fail if can't verify orientation
        feedback_parts.append("⚠ Cannot verify landscape orientation without PyPDF2")
    elif orient_ok:
        feedback_parts.append(f"✓ {orient_feedback} (width={width:.1f}, height={height:.1f})")
        criteria_results.append(True)
    else:
        feedback_parts.append(f"✗ {orient_feedback} (width={width:.1f}, height={height:.1f})")
        criteria_results.append(False)
    
    # Criterion 4: Content check
    logger.info("Checking PDF content...")
    content_ok, char_count, content_feedback = check_pdf_content(pdf_path)
    if content_ok:
        feedback_parts.append(f"✓ {content_feedback}")
        criteria_results.append(True)
    else:
        feedback_parts.append(f"✗ {content_feedback}")
        criteria_results.append(False)
    
    # Check filename (affects score multiplier)
    logger.info("Checking filename...")
    filename_multiplier, filename_feedback = check_filename_correctness(pdf_name)
    feedback_parts.append(filename_feedback)
    
    # Calculate final score
    criteria_met = sum(criteria_results)
    base_score = (criteria_met / 4.0) * 100
    final_score = int(base_score * filename_multiplier)
    passed = final_score >= 70
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met}/4"
    feedback += f"\nBase score: {base_score:.0f}%"
    feedback += f"\nFinal score: {final_score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PYPDF2:
        feedback += "\n\n⚠ Note: PyPDF2 library not available, orientation check was limited"
    
    # Clean up temporary file
    try:
        if pdf_path and os.path.exists(pdf_path):
            os.unlink(pdf_path)
    except:
        pass
    
    logger.info(f"Verification complete: passed={passed}, score={final_score}")
    
    return {
        "passed": passed,
        "score": final_score,
        "feedback": feedback,
        "details": {
            "criteria_met": criteria_met,
            "filename": pdf_name,
            "size_kb": size_kb,
            "landscape": orient_ok,
            "has_content": content_ok
        }
    }
