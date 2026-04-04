#!/usr/bin/env python3
"""
Verifier for Chrome Print-to-PDF with Custom Settings Task
Task: Print webpage to PDF with landscape orientation, minimum margins, no headers/footers
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

try:
    import pdfplumber
    HAS_PDFPLUMBER = True
except ImportError:
    HAS_PDFPLUMBER = False
    logger.warning("pdfplumber not available, advanced analysis will be limited")


def find_pdf_file(copy_from_env, expected_name="custom_print.pdf"):
    """
    Find and copy the generated PDF from the container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found by export script
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
            f"/tmp/print_pdf_custom_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            f"/home/ga/Downloads/{expected_name}",
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


def check_pdf_orientation(pdf_path):
    """
    Check if PDF is in landscape orientation.
    
    Returns:
        tuple: (passed, landscape_percentage, dimensions_info, feedback)
    """
    if not HAS_PYPDF2:
        return None, 0, "", "PyPDF2 not available"
    
    try:
        reader = PdfReader(pdf_path)
        total_pages = len(reader.pages)
        
        if total_pages == 0:
            return False, 0, "", "PDF has no pages"
        
        landscape_count = 0
        dimension_details = []
        
        for i, page in enumerate(reader.pages):
            try:
                # Get page dimensions
                mediabox = page.mediabox
                width = float(mediabox.width)
                height = float(mediabox.height)
                
                dimension_details.append(f"Page {i+1}: {width:.0f}x{height:.0f} pts")
                
                # Landscape if width > height
                if width > height:
                    landscape_count += 1
                    
            except Exception as e:
                logger.warning(f"Could not check orientation for page {i+1}: {e}")
        
        landscape_pct = (landscape_count / total_pages) * 100
        dims_str = "; ".join(dimension_details[:3])  # First 3 pages
        
        if landscape_pct >= 80:
            return True, landscape_pct, dims_str, f"Landscape orientation detected ({landscape_pct:.0f}% of pages)"
        else:
            return False, landscape_pct, dims_str, f"Not landscape - only {landscape_pct:.0f}% of pages are landscape"
            
    except Exception as e:
        logger.error(f"Error checking orientation: {e}")
        return False, 0, "", f"Could not check orientation: {e}"


def check_pdf_margins(pdf_path):
    """
    Check if PDF has minimal margins by analyzing content positioning.
    
    Returns:
        tuple: (passed, min_margin, margin_details, feedback)
    """
    if not HAS_PDFPLUMBER:
        return None, 0, "", "pdfplumber not available for margin analysis"
    
    try:
        with pdfplumber.open(pdf_path) as pdf:
            if len(pdf.pages) == 0:
                return False, 0, "", "PDF has no pages"
            
            first_page = pdf.pages[0]
            words = first_page.extract_words()
            
            if not words:
                return False, 0, "", "Could not extract text for margin analysis"
            
            # Find bounding box of all text
            x_coords = [w['x0'] for w in words] + [w['x1'] for w in words]
            y_coords = [w['top'] for w in words] + [w['bottom'] for w in words]
            
            content_left = min(x_coords)
            content_right = max(x_coords)
            content_top = min(y_coords)
            content_bottom = max(y_coords)
            
            # Calculate margins in points
            left_margin = content_left
            right_margin = first_page.width - content_right
            top_margin = content_top
            bottom_margin = first_page.height - content_bottom
            
            min_margin = min(left_margin, right_margin, top_margin, bottom_margin)
            
            margin_details = f"L:{left_margin:.1f}, R:{right_margin:.1f}, T:{top_margin:.1f}, B:{bottom_margin:.1f} pts"
            
            # Minimum margins in Chrome are typically 18-30 points (~0.25-0.42 inches)
            # We'll allow up to 35 points to account for variations
            if min_margin <= 35:
                return True, min_margin, margin_details, f"Minimal margins detected (min: {min_margin:.1f} points)"
            else:
                return False, min_margin, margin_details, f"Margins too large (min: {min_margin:.1f} points, expected ≤35)"
    
    except Exception as e:
        logger.error(f"Error checking margins: {e}")
        return None, 0, "", f"Could not analyze margins: {e}"


def check_headers_footers(pdf_path):
    """
    Check if PDF has headers or footers (should not have any).
    
    Returns:
        tuple: (passed, found_issues, feedback)
    """
    if not HAS_PDFPLUMBER:
        return None, [], "pdfplumber not available for header/footer detection"
    
    try:
        with pdfplumber.open(pdf_path) as pdf:
            if len(pdf.pages) == 0:
                return False, [], "PDF has no pages"
            
            first_page = pdf.pages[0]
            page_height = first_page.height
            
            # Define header and footer regions (top/bottom 50 points)
            header_bbox = (0, 0, first_page.width, 50)
            footer_bbox = (0, page_height - 50, first_page.width, page_height)
            
            # Extract text from regions
            header_region = first_page.within_bbox(header_bbox)
            footer_region = first_page.within_bbox(footer_bbox)
            
            header_text = header_region.extract_text() or ""
            footer_text = footer_region.extract_text() or ""
            
            # Check for header indicators
            issues = []
            header_indicators = ["http", "file://", "https"]
            for indicator in header_indicators:
                if indicator in header_text.lower():
                    issues.append(f"URL in header ({indicator})")
                    break
            
            # Check for footer indicators (page numbers)
            footer_indicators = ["/", "page"]
            if any(ind in footer_text.lower() for ind in footer_indicators):
                # Additional check: page number patterns like "1", "1/1", "Page 1"
                import re
                if re.search(r'\b\d+\b|\bpage\s+\d+\b', footer_text.lower()):
                    issues.append("Page numbers in footer")
            
            # Check if there's any substantial text in header/footer regions
            if len(header_text.strip()) > 15:  # Arbitrary threshold
                if not any("URL" in issue for issue in issues):
                    issues.append("Substantial text in header region")
            
            if len(footer_text.strip()) > 10:
                if not any("Page" in issue or "/" in issue for issue in issues):
                    issues.append("Substantial text in footer region")
            
            if not issues:
                return True, [], "No headers or footers detected"
            else:
                return False, issues, f"Headers/footers found: {'; '.join(issues)}"
    
    except Exception as e:
        logger.error(f"Error checking headers/footers: {e}")
        return None, [], f"Could not check headers/footers: {e}"


def extract_pdf_text(pdf_path):
    """
    Extract text from PDF for content verification.
    
    Returns:
        str: Extracted text
    """
    text = ""
    
    # Try pdfplumber first (better extraction)
    if HAS_PDFPLUMBER:
        try:
            with pdfplumber.open(pdf_path) as pdf:
                for page in pdf.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text += page_text + "\n"
                return text
        except Exception as e:
            logger.warning(f"pdfplumber extraction failed: {e}")
    
    # Fallback to PyPDF2
    if HAS_PYPDF2 and not text:
        try:
            reader = PdfReader(pdf_path)
            for page in reader.pages:
                page_text = page.extract_text()
                if page_text:
                    text += page_text + "\n"
        except Exception as e:
            logger.warning(f"PyPDF2 extraction failed: {e}")
    
    return text


def check_pdf_content(pdf_path):
    """
    Check if PDF contains expected content from test page.
    
    Returns:
        tuple: (passed, matches, total_keywords, feedback)
    """
    # Expected keywords from the test page
    expected_keywords = [
        "test document",
        "print configuration",
        "landscape orientation",
        "minimum margins",
        "headers and footers",
        "custom settings",
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
    
    # Require at least 50% of keywords (3 out of 6)
    required_matches = max(3, int(len(expected_keywords) * 0.5))
    passed = matches >= required_matches
    
    if passed:
        feedback = f"Content verified ({matches}/{len(expected_keywords)} keywords found)"
    else:
        feedback = f"Insufficient content ({matches}/{len(expected_keywords)} keywords, need {required_matches})"
    
    return passed, matches, len(expected_keywords), feedback


def verify_task(traj, env_info, task_info):
    """
    Main verification function for Print-to-PDF with Custom Settings task.
    
    Verifies:
    1. PDF file exists
    2. PDF has landscape orientation (width > height)
    3. PDF has minimal margins (≤35 points)
    4. PDF has no headers or footers
    5. PDF contains expected content
    
    Scoring:
    - 100%: All 5 criteria met
    - 80%: 4/5 criteria met
    - 60%: 3/5 criteria met
    - 40%: 2/5 criteria met
    - <40%: <2 criteria met
    
    Pass threshold: 75% (at least 4 out of 5 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0
    total_criteria = 5
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
    
    # Check file size
    try:
        size_bytes = Path(pdf_path).stat().st_size
        size_kb = size_bytes / 1024
        if size_bytes < 5120:  # Less than 5KB
            feedback_parts.append(f"⚠ File size small ({size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"  File size: {size_kb:.1f} KB")
    except:
        pass
    
    # Criterion 2: Orientation check (landscape)
    logger.info("Checking orientation...")
    orient_ok, landscape_pct, dims_info, orient_feedback = check_pdf_orientation(pdf_path)
    if orient_ok is None:
        feedback_parts.append(f"⚠ {orient_feedback}")
        criteria_met += 0.3  # Partial credit
    elif orient_ok:
        feedback_parts.append(f"✓ {orient_feedback}")
        if dims_info:
            feedback_parts.append(f"  Dimensions: {dims_info}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {orient_feedback}")
        if dims_info:
            feedback_parts.append(f"  Dimensions: {dims_info}")
    
    # Criterion 3: Margins check (minimal)
    logger.info("Checking margins...")
    margin_ok, min_margin, margin_details, margin_feedback = check_pdf_margins(pdf_path)
    if margin_ok is None:
        feedback_parts.append(f"⚠ {margin_feedback}")
        criteria_met += 0.3  # Partial credit
    elif margin_ok:
        feedback_parts.append(f"✓ {margin_feedback}")
        if margin_details:
            feedback_parts.append(f"  Margins: {margin_details}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {margin_feedback}")
        if margin_details:
            feedback_parts.append(f"  Margins: {margin_details}")
    
    # Criterion 4: Headers/Footers check (should not exist)
    logger.info("Checking headers and footers...")
    hf_ok, issues, hf_feedback = check_headers_footers(pdf_path)
    if hf_ok is None:
        feedback_parts.append(f"⚠ {hf_feedback}")
        criteria_met += 0.3  # Partial credit
    elif hf_ok:
        feedback_parts.append(f"✓ {hf_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {hf_feedback}")
    
    # Criterion 5: Content check
    logger.info("Checking PDF content...")
    content_ok, matches, total_kw, content_feedback = check_pdf_content(pdf_path)
    if content_ok:
        feedback_parts.append(f"✓ {content_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {content_feedback}")
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not (HAS_PYPDF2 and HAS_PDFPLUMBER):
        feedback += "\n\n⚠ Note: Some PDF libraries not available, checks had limited functionality"
    
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
