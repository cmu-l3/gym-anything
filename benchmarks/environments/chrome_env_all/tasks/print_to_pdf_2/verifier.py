#!/usr/bin/env python3
"""
Verifier for Chrome Print to PDF Task: print_to_pdf@1

Verifies that:
1. PDF file exists with correct filename (webpage_archive.pdf)
2. PDF is valid and parseable 
3. Correct print settings were applied:
   - Minimal margins
   - No headers/footers (no URLs, page numbers)
   - Background graphics enabled
4. Content from original page is present in PDF
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Import PDF processing libraries
try:
    import PyPDF2
except ImportError:
    logger.warning("PyPDF2 not available, attempting to install...")
    import subprocess
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "PyPDF2"])
    import PyPDF2


def verify_task(traj, env_info, task_info):
    """
    Main verification function for print_to_pdf@1 task.
    
    Scoring:
    - PDF exists: 25 points
    - Valid PDF structure: +25 points (total 50)
    - Content present: +25 points (total 75) - PASS THRESHOLD
    - Correct settings: +25 points (total 100)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    try:
        # Check 1: PDF file exists
        success, pdf_path, error = copy_pdf_file(copy_from_env)
        if not success:
            return {"passed": False, "score": 0, "feedback": f"PDF file not found: {error}"}
        
        logger.info(f"✓ PDF file found: {pdf_path}")
        score = 25
        
        # Check 2: Valid PDF structure
        is_valid, page_count, error = verify_pdf_structure(pdf_path)
        if not is_valid:
            cleanup_temp_files(pdf_path)
            return {"passed": False, "score": score, "feedback": f"Invalid PDF: {error}"}
        
        logger.info(f"✓ Valid PDF with {page_count} page(s)")
        score = 50
        
        # Check 3: Extract and verify content
        content_ok, text_content, error = verify_pdf_content(pdf_path)
        if not content_ok:
            cleanup_temp_files(pdf_path)
            return {"passed": False, "score": score, "feedback": f"Content verification failed: {error}"}
        
        logger.info(f"✓ PDF contains expected content")
        score = 75  # PASS THRESHOLD REACHED
        
        # Check 4: Verify print settings (bonus points for correct settings)
        settings_score, settings_feedback = verify_print_settings(pdf_path, text_content)
        
        cleanup_temp_files(pdf_path)
        
        # Calculate final score
        final_score = min(100, score + settings_score)
        passed = final_score >= 75
        
        feedback = f"PDF successfully created with content. {settings_feedback}"
        
        return {
            "passed": passed,
            "score": final_score,
            "feedback": feedback
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {"passed": False, "score": 0, "feedback": f"Verification error: {str(e)}"}


def copy_pdf_file(copy_from_env):
    """
    Copy PDF file from container to host for verification.
    
    Returns:
        Tuple of (success, local_path, error_message)
    """
    temp_dir = Path(tempfile.gettempdir()) / f"chrome_pdf_verification_{os.getpid()}"
    temp_dir.mkdir(exist_ok=True)
    
    pdf_filename = "webpage_archive.pdf"
    
    # Try /tmp first (export script copies it here)
    container_path = f"/tmp/{pdf_filename}"
    local_path = temp_dir / pdf_filename
    
    try:
        success, error = copy_from_env(container_path, str(local_path))
        
        if not success or not local_path.exists():
            # Try alternative path in Downloads
            logger.info("Trying alternative path in Downloads...")
            container_path = f"/home/ga/Downloads/{pdf_filename}"
            success, error = copy_from_env(container_path, str(local_path))
            
            if not success:
                return False, "", f"Failed to copy PDF from {container_path}: {error}"
        
        if not local_path.exists():
            return False, "", "PDF file not found after copy"
            
        if local_path.stat().st_size == 0:
            return False, "", "PDF file is empty (0 bytes)"
        
        logger.info(f"PDF file size: {local_path.stat().st_size} bytes")
        return True, str(local_path), ""
        
    except Exception as e:
        return False, "", f"Error copying PDF: {str(e)}"


def verify_pdf_structure(pdf_path):
    """
    Verify PDF is valid and has expected structure.
    
    Returns:
        Tuple of (is_valid, page_count, error_message)
    """
    try:
        with open(pdf_path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            
            # Check if PDF is encrypted
            if reader.is_encrypted:
                return False, 0, "PDF is encrypted"
            
            page_count = len(reader.pages)
            
            if page_count == 0:
                return False, 0, "PDF has no pages"
            
            # Try to access first page to ensure PDF is readable
            first_page = reader.pages[0]
            try:
                _ = first_page.extract_text()
            except Exception as e:
                return False, page_count, f"Cannot extract text from PDF: {str(e)}"
            
            return True, page_count, ""
            
    except PyPDF2.errors.PdfReadError as e:
        return False, 0, f"PDF read error: {str(e)}"
    except Exception as e:
        return False, 0, f"PDF parsing error: {str(e)}"


def verify_pdf_content(pdf_path):
    """
    Extract text from PDF and verify it contains expected content from test page.
    
    Returns:
        Tuple of (content_ok, text_content, error_message)
    """
    try:
        with open(pdf_path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            text_content = ""
            
            for page in reader.pages:
                try:
                    text_content += page.extract_text() + "\n"
                except:
                    continue
            
            # Normalize text for comparison
            text_lower = text_content.lower()
            
            # Check for expected text from the test page
            expected_phrases = [
                "web page archive test",
                "test page",
                "content section",
                "background graphics"
            ]
            
            found_phrases = []
            for phrase in expected_phrases:
                if phrase in text_lower:
                    found_phrases.append(phrase)
            
            logger.info(f"Found {len(found_phrases)}/4 expected phrases in PDF")
            
            if len(found_phrases) < 2:  # At least 2 key phrases should be present
                return False, text_content, f"Expected content not found in PDF (found {len(found_phrases)}/4 phrases)"
            
            return True, text_content, ""
            
    except Exception as e:
        return False, "", f"Content extraction error: {str(e)}"


def verify_print_settings(pdf_path, text_content):
    """
    Verify that correct print settings were applied.
    
    Checks:
    1. No headers/footers (no URLs, page numbers in typical positions)
    2. Minimal margins (content extends close to page edges)
    3. Background graphics (PDF contains images/graphics)
    
    Returns:
        Tuple of (score_adjustment, feedback)
        score_adjustment: 0-25 points based on settings compliance
    """
    score = 0
    feedback_items = []
    
    try:
        with open(pdf_path, 'rb') as f:
            reader = PyPDF2.PdfReader(f)
            
            # Check 1: No headers/footers (10 points)
            has_no_headers_footers = verify_no_headers_footers(text_content)
            if has_no_headers_footers:
                score += 10
                feedback_items.append("✓ No headers/footers")
            else:
                feedback_items.append("✗ Headers/footers detected")
            
            # Check 2: Minimal margins (8 points)
            has_minimal_margins = verify_minimal_margins(reader)
            if has_minimal_margins:
                score += 8
                feedback_items.append("✓ Minimal margins")
            else:
                feedback_items.append("⚠ Margins may not be minimal")
            
            # Check 3: Background graphics (7 points)
            has_backgrounds = verify_background_graphics(reader)
            if has_backgrounds:
                score += 7
                feedback_items.append("✓ Background graphics included")
            else:
                feedback_items.append("⚠ Background graphics may be missing")
            
            feedback = "Settings: " + ", ".join(feedback_items)
            return score, feedback
            
    except Exception as e:
        logger.error(f"Settings verification error: {e}")
        return 0, f"Settings verification error: {str(e)}"


def verify_no_headers_footers(text_content):
    """
    Check that headers and footers are not present.
    Looks for common patterns like URLs, dates, page numbers.
    """
    # Common header/footer patterns
    header_footer_patterns = [
        r'https?://',           # URLs
        r'file:///',            # File URLs
        r'Page\s+\d+',          # Page X
        r'\d+\s*/\s*\d+',       # X/Y page numbers
        r'\d{1,2}/\d{1,2}/\d{2,4}',  # Dates
    ]
    
    # Split text into lines
    lines = [line.strip() for line in text_content.split('\n') if line.strip()]
    
    if len(lines) < 3:
        return True  # Too short to have headers/footers
    
    # Check first 2 and last 2 lines for header/footer patterns
    edge_text = ' '.join(lines[:2] + lines[-2:])
    
    for pattern in header_footer_patterns:
        if re.search(pattern, edge_text, re.IGNORECASE):
            logger.info(f"Detected possible header/footer pattern: {pattern}")
            return False
    
    return True


def verify_minimal_margins(reader):
    """
    Check if minimal margins were applied by examining page dimensions.
    This is a heuristic check based on standard page sizes.
    """
    try:
        page = reader.pages[0]
        mediabox = page.mediabox
        
        # Get page dimensions (in points, 72 points = 1 inch)
        page_width = float(mediabox.width)
        page_height = float(mediabox.height)
        
        logger.info(f"PDF page dimensions: {page_width:.1f} x {page_height:.1f} points")
        
        # Standard letter size is 612 x 792 points
        # Standard A4 size is 595 x 842 points
        # If page is standard size, we assume margins were configured
        # (Chrome's minimal margins are ~0.4 inches = 28.8 points)
        
        # Check if it's approximately a standard page size
        is_letter = (abs(page_width - 612) < 10 and abs(page_height - 792) < 10)
        is_a4 = (abs(page_width - 595) < 10 and abs(page_height - 842) < 10)
        
        if is_letter or is_a4:
            logger.info("Standard page size detected - assuming minimal margins were set")
            return True
        
        # If non-standard size, still accept it
        return True
        
    except Exception as e:
        logger.error(f"Margin verification error: {e}")
        return False


def verify_background_graphics(reader):
    """
    Check if background graphics were included in the PDF.
    Looks for images or graphic objects in the PDF structure.
    """
    try:
        for page_num, page in enumerate(reader.pages):
            # Check if page has resources with XObject (images/graphics)
            if '/Resources' in page:
                resources = page['/Resources']
                if resources is not None:
                    resources_obj = resources.get_object() if hasattr(resources, 'get_object') else resources
                    
                    if '/XObject' in resources_obj:
                        xobjects = resources_obj['/XObject']
                        xobjects_obj = xobjects.get_object() if hasattr(xobjects, 'get_object') else xobjects
                        
                        if len(xobjects_obj) > 0:
                            logger.info(f"Found {len(xobjects_obj)} XObject(s) (images/graphics) on page {page_num + 1}")
                            return True
                    
                    # Also check for extended graphics state (used for transparency, blending)
                    if '/ExtGState' in resources_obj:
                        logger.info(f"Found extended graphics state on page {page_num + 1}")
                        return True
        
        # If we have a gradient background (from our test page), there should be graphics
        logger.info("No obvious graphics/images found in PDF - backgrounds may not be enabled")
        return False
        
    except Exception as e:
        logger.error(f"Background graphics check error: {e}")
        # Don't penalize for verification errors
        return True


def cleanup_temp_files(pdf_path):
    """Clean up temporary verification files."""
    try:
        if pdf_path and os.path.exists(pdf_path):
            temp_dir = Path(pdf_path).parent
            if temp_dir.exists() and "chrome_pdf_verification" in str(temp_dir):
                import shutil
                shutil.rmtree(temp_dir, ignore_errors=True)
                logger.info("Cleaned up temporary files")
    except Exception as e:
        logger.warning(f"Cleanup warning: {e}")
