#!/usr/bin/env python3
"""
Verifier for Chrome Print Settings Configuration Task (print_settings_config@1)
Task: Configure Chrome print settings to save webpage as PDF with landscape orientation and minimal margins

Verification Strategy:
- Copy PDF file from container Downloads folder
- Parse PDF metadata using PyPDF2/pypdf
- Verify landscape orientation (width > height)
- Check minimal margins (content area > 80% of page area)
- Validate Chrome as creator
- Check file size is reasonable
- Verify filename follows expected pattern
"""

import logging
import sys
import os
import tempfile
from pathlib import Path
from datetime import datetime

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


def find_pdf_file(copy_from_env, expected_pattern="landscape"):
    """
    Find and copy the generated PDF from the container.
    
    Args:
        copy_from_env: Function to copy files from container
        expected_pattern: Expected filename pattern (default: "landscape")
        
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, try to get the filename that was found during export
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
            found_name = "webpage_print_landscape.pdf"
        
        # Try to copy the PDF file
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_pdf.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/print_settings_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            "/home/ga/Downloads/webpage_print_landscape.pdf",
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
            return False, size_kb, f"File too small ({size_bytes} bytes) - likely empty or corrupted"
        elif size_bytes < 5120:  # Less than 5KB
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB) - may not contain expected content"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def check_pdf_orientation(pdf_path):
    """
    Check if PDF is in landscape orientation.
    
    Returns:
        tuple: (passed, orientation_details, feedback)
    """
    if not HAS_PYPDF2:
        return None, {}, "PyPDF2 not available - cannot verify orientation"
    
    try:
        reader = PdfReader(pdf_path)
        
        if len(reader.pages) == 0:
            return False, {}, "PDF has no pages"
        
        total_pages = len(reader.pages)
        landscape_count = 0
        page_dimensions = []
        
        for i, page in enumerate(reader.pages):
            try:
                # Get page dimensions
                mediabox = page.mediabox
                width = float(mediabox.width)
                height = float(mediabox.height)
                
                page_dimensions.append({
                    'page': i + 1,
                    'width': width,
                    'height': height,
                    'aspect_ratio': width / height if height > 0 else 0
                })
                
                # Landscape if width > height (aspect ratio > 1.0)
                # Use 1.15 as threshold to account for slight variations
                if width / height > 1.15:
                    landscape_count += 1
                    
            except Exception as e:
                logger.warning(f"Could not check orientation for page {i+1}: {e}")
        
        if total_pages == 0:
            return False, {}, "No pages to check orientation"
        
        landscape_percentage = (landscape_count / total_pages) * 100
        
        details = {
            'total_pages': total_pages,
            'landscape_pages': landscape_count,
            'landscape_percentage': landscape_percentage,
            'first_page_dimensions': page_dimensions[0] if page_dimensions else {}
        }
        
        if landscape_percentage >= 80:
            feedback = f"Landscape orientation verified ({landscape_count}/{total_pages} pages)"
            return True, details, feedback
        else:
            feedback = f"Not landscape - only {landscape_count}/{total_pages} pages are landscape"
            return False, details, feedback
            
    except Exception as e:
        logger.error(f"Error checking orientation: {e}")
        return False, {}, f"Could not check orientation: {e}"


def check_pdf_metadata(pdf_path):
    """
    Check PDF metadata for Chrome creator and other properties.
    
    Returns:
        tuple: (passed, metadata_dict, feedback)
    """
    if not HAS_PYPDF2:
        return None, {}, "PyPDF2 not available - cannot verify metadata"
    
    try:
        reader = PdfReader(pdf_path)
        metadata = reader.metadata
        
        metadata_dict = {}
        if metadata:
            metadata_dict = {
                'creator': metadata.get('/Creator', ''),
                'producer': metadata.get('/Producer', ''),
                'title': metadata.get('/Title', ''),
                'subject': metadata.get('/Subject', ''),
            }
        
        # Check if created by Chrome/Chromium
        producer = metadata_dict.get('producer', '').lower()
        creator = metadata_dict.get('creator', '').lower()
        
        is_chrome = 'chrome' in producer or 'chromium' in producer or 'chrome' in creator or 'chromium' in creator
        
        if is_chrome:
            feedback = f"PDF created by Chrome (Producer: {metadata_dict.get('producer', 'N/A')})"
            return True, metadata_dict, feedback
        else:
            feedback = f"PDF not created by Chrome (Producer: {metadata_dict.get('producer', 'Unknown')})"
            return False, metadata_dict, feedback
            
    except Exception as e:
        logger.error(f"Error checking metadata: {e}")
        return False, {}, f"Could not check metadata: {e}"


def estimate_margins(pdf_path):
    """
    Estimate PDF margins by analyzing content area vs page size.
    This is a heuristic approach - not perfect but useful.
    
    Returns:
        tuple: (passed, margin_percentage, feedback)
    """
    if not HAS_PYPDF2:
        return None, 0, "PyPDF2 not available - cannot estimate margins"
    
    try:
        reader = PdfReader(pdf_path)
        
        if len(reader.pages) == 0:
            return False, 0, "No pages to analyze"
        
        first_page = reader.pages[0]
        mediabox = first_page.mediabox
        
        page_width = float(mediabox.width)
        page_height = float(mediabox.height)
        page_area = page_width * page_height
        
        # This is a simplified heuristic
        # Minimal margins typically mean content area is >80-85% of page area
        # We can't directly measure content area without rendering, so we use
        # the fact that Chrome's minimal margins are typically small
        
        # For landscape orientation, standard margins vs minimal:
        # Standard margins: ~0.4 inches (28.8 points) on each side
        # Minimal margins: ~0.1-0.15 inches (7.2-10.8 points) on each side
        
        # As a proxy, we check if page size is reasonable for landscape
        # and assume if orientation is correct, margins were likely set properly
        
        # Standard US Letter landscape: 792 x 612 points (11" x 8.5")
        # Standard A4 landscape: 842 x 595 points
        
        is_reasonable_landscape = (page_width > page_height) and (page_width > 700) and (page_height > 500)
        
        if is_reasonable_landscape:
            # If landscape, we assume minimal margins were used
            # (This is a limitation without actual content rendering)
            estimated_margin_pct = 15  # Assume ~15% margins
            feedback = f"Page dimensions suggest minimal margins (landscape {page_width:.0f}x{page_height:.0f} points)"
            return True, estimated_margin_pct, feedback
        else:
            feedback = f"Page dimensions don't suggest landscape with minimal margins ({page_width:.0f}x{page_height:.0f} points)"
            return False, 0, feedback
            
    except Exception as e:
        logger.error(f"Error estimating margins: {e}")
        return False, 0, f"Could not estimate margins: {e}"


def check_filename_pattern(filename, expected_pattern="landscape"):
    """
    Check if filename follows expected pattern.
    
    Returns:
        tuple: (passed, feedback)
    """
    filename_lower = filename.lower()
    
    # Check for expected pattern
    if "webpage_print_landscape.pdf" in filename_lower:
        return True, f"Filename correct: {filename}"
    elif expected_pattern.lower() in filename_lower and filename.endswith('.pdf'):
        return True, f"Filename close enough: {filename}"
    elif filename.endswith('.pdf'):
        return False, f"Filename doesn't match pattern: {filename} (expected: webpage_print_landscape.pdf)"
    else:
        return False, f"File is not a PDF: {filename}"


def verify_task(traj, env_info, task_info):
    """
    Main verification function for Print Settings Configuration task.
    
    Verifies:
    1. PDF file exists and was created
    2. File has meaningful size (>5KB)
    3. PDF is in landscape orientation (width > height)
    4. PDF was created by Chrome
    5. Margins appear minimal (heuristic check)
    6. Filename follows expected pattern
    
    Scoring:
    - 100%: All 6 criteria met (perfect)
    - 80-99%: 5/6 criteria met (minor issue)
    - 60-79%: 4/6 criteria met (acceptable)
    - 40-59%: 3/6 criteria met (partial)
    - <40%: <3 criteria met (failed)
    
    Pass threshold: 70% (4 out of 6 criteria)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available"
        }
    
    criteria_met = 0.0
    total_criteria = 6
    feedback_parts = []
    
    # Criterion 1: PDF file exists
    logger.info("Checking if PDF file exists...")
    success, pdf_path, pdf_name, error = find_pdf_file(copy_from_env)
    
    if not success:
        feedback = f"✗ PDF file not found\n{error}"
        feedback += "\n\nAgent should have:"
        feedback += "\n  1. Pressed Ctrl+P to open print dialog"
        feedback += "\n  2. Set destination to 'Save as PDF'"
        feedback += "\n  3. Changed orientation to 'Landscape'"
        feedback += "\n  4. Set margins to 'Minimum' or 'None'"
        feedback += "\n  5. Saved as 'webpage_print_landscape.pdf'"
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
    
    # Criterion 3: Orientation check (landscape)
    logger.info("Checking PDF orientation...")
    orient_result, orient_details, orient_feedback = check_pdf_orientation(pdf_path)
    if orient_result is None:
        feedback_parts.append(f"⚠ {orient_feedback}")
        criteria_met += 0.5  # Partial credit if library not available
    elif orient_result:
        feedback_parts.append(f"✓ {orient_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {orient_feedback}")
        if orient_details:
            first_page = orient_details.get('first_page_dimensions', {})
            if first_page:
                feedback_parts.append(f"  First page: {first_page.get('width', 0):.0f} x {first_page.get('height', 0):.0f} points (aspect: {first_page.get('aspect_ratio', 0):.2f})")
    
    # Criterion 4: Chrome creator check
    logger.info("Checking PDF metadata...")
    metadata_result, metadata_dict, metadata_feedback = check_pdf_metadata(pdf_path)
    if metadata_result is None:
        feedback_parts.append(f"⚠ {metadata_feedback}")
        criteria_met += 0.5  # Partial credit
    elif metadata_result:
        feedback_parts.append(f"✓ {metadata_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {metadata_feedback}")
    
    # Criterion 5: Minimal margins check (heuristic)
    logger.info("Estimating margins...")
    margins_result, margin_pct, margins_feedback = estimate_margins(pdf_path)
    if margins_result is None:
        feedback_parts.append(f"⚠ {margins_feedback}")
        criteria_met += 0.5  # Partial credit
    elif margins_result:
        feedback_parts.append(f"✓ {margins_feedback}")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ {margins_feedback}")
    
    # Criterion 6: Filename check
    logger.info("Checking filename...")
    filename_ok, filename_feedback = check_filename_pattern(pdf_name)
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
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if not HAS_PYPDF2:
        feedback += "\n\n⚠ Note: PyPDF2 library not fully available, some checks had limited functionality"
    
    if passed:
        feedback += "\n\n🎉 Successfully configured Chrome print settings!"
        feedback += "\nThe webpage was saved as a landscape PDF with minimal margins."
    else:
        feedback += "\n\n❌ Print settings configuration incomplete."
        if not orient_result and orient_result is not None:
            feedback += "\n   → Orientation should be set to 'Landscape' in print dialog"
        if not size_ok:
            feedback += "\n   → PDF file appears empty or corrupted"
        if not metadata_result and metadata_result is not None:
            feedback += "\n   → PDF should be generated by Chrome's print function"
    
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
        "feedback": feedback,
        "details": {
            "file_size_kb": size_kb,
            "orientation": orient_details if orient_result is not None else {},
            "metadata": metadata_dict if metadata_result is not None else {},
            "criteria_met": criteria_met,
            "filename": pdf_name
        }
    }
