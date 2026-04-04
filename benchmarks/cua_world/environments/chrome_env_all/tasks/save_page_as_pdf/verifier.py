#!/usr/bin/env python3
"""
Verifier for Chrome Save Page as PDF Task (save_page_as_pdf@1)
Task: Save customer support chat webpage as PDF for documentation purposes

Verification Strategy:
1. Check if PDF file exists in Downloads folder
2. Verify PDF has substantial content (file size > 50KB)
3. Validate PDF format (can be opened and parsed)
4. Extract and verify content contains expected keywords from source page
5. Check filename is descriptive (not generic like "Untitled.pdf")
6. Verify PDF has multiple pages (transcript is long enough)

Scoring:
- 100%: All 6 criteria met (perfect save)
- 85-99%: 5/6 criteria met (minor issue like generic filename)
- 75-84%: 4/6 criteria met (passing but needs improvement)
- 50-74%: 3/6 criteria met (partial success)
- 0-49%: <3 criteria met (task failed)

Pass threshold: 75% (requires at least 4 out of 6 criteria)
"""

import logging
import sys
import os
import tempfile
import re
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
        logger.warning("PyPDF2/pypdf not available, PDF content analysis will be limited")

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info):
    """
    Main verification function for save_page_as_pdf@1 task.
    
    Verifies that the user successfully saved the support chat webpage as a PDF
    with appropriate filename and complete content.
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with passed (bool), score (int 0-100), and feedback (str)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    try:
        # Find and retrieve the PDF file
        pdf_info = find_and_copy_pdf(copy_from_env)
        
        if not pdf_info['success']:
            return {
                "passed": False,
                "score": 0,
                "feedback": pdf_info['error']
            }
        
        pdf_path = pdf_info['local_path']
        pdf_filename = pdf_info['filename']
        
        # Run all verification checks
        verification_results = run_all_checks(pdf_path, pdf_filename)
        
        # Calculate score and generate feedback
        result = calculate_final_result(verification_results, pdf_filename)
        
        # Clean up temporary files
        try:
            if pdf_path and os.path.exists(pdf_path):
                os.unlink(pdf_path)
        except:
            pass
        
        cleanup_verification_temp()
        
        return result
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        cleanup_verification_temp()
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }


def find_and_copy_pdf(copy_from_env):
    """
    Find and copy the generated PDF from the container.
    
    Returns:
        Dict with success, local_path, filename, and error keys
    """
    try:
        # First, try to read the filename that was found
        temp_filename_file = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        temp_filename_path = temp_filename_file.name
        temp_filename_file.close()
        
        found_pdf_name = None
        try:
            copy_from_env("/tmp/pdf_save_verification/found_pdf.txt", temp_filename_path)
            with open(temp_filename_path, 'r') as f:
                found_pdf_name = f.read().strip()
            os.unlink(temp_filename_path)
            
            if found_pdf_name == "none" or not found_pdf_name:
                return {
                    'success': False,
                    'local_path': None,
                    'filename': None,
                    'error': "No PDF file was found in Downloads folder. Did you complete the save operation?"
                }
        except Exception as e:
            logger.warning(f"Could not read found_pdf.txt: {e}")
            # Will try to find PDF by other means
        
        # Create temp file for PDF
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_pdf_path = temp_pdf.name
        temp_pdf.close()
        
        # Try multiple possible locations to copy the PDF
        possible_paths = []
        
        if found_pdf_name:
            possible_paths.extend([
                f"/tmp/pdf_save_verification/{found_pdf_name}",
                f"/home/ga/Downloads/{found_pdf_name}",
            ])
        
        # Also try common generic names
        possible_paths.extend([
            "/tmp/pdf_save_verification/*.pdf",
            "/home/ga/Downloads/support*.pdf",
            "/home/ga/Downloads/customer*.pdf",
            "/home/ga/Downloads/chat*.pdf",
            "/home/ga/Downloads/CS-*.pdf",
            "/home/ga/Downloads/*.pdf",
        ])
        
        for container_path in possible_paths:
            try:
                if '*' in container_path:
                    # For glob patterns, we can't copy directly
                    # Skip to next iteration
                    continue
                    
                logger.info(f"Attempting to copy PDF from: {container_path}")
                copy_from_env(container_path, temp_pdf_path)
                
                # Check if file has content
                if os.path.exists(temp_pdf_path) and Path(temp_pdf_path).stat().st_size > 0:
                    filename = os.path.basename(container_path)
                    logger.info(f"✓ Successfully copied PDF: {filename}")
                    return {
                        'success': True,
                        'local_path': temp_pdf_path,
                        'filename': filename,
                        'error': None
                    }
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_pdf_path)
        
        # Try to get diagnostic info
        try:
            temp_listing = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/pdf_save_verification/downloads_listing.txt", temp_listing.name)
            with open(temp_listing.name, 'r') as f:
                downloads_content = f.read()
            os.unlink(temp_listing.name)
            
            return {
                'success': False,
                'local_path': None,
                'filename': None,
                'error': f"PDF file not found. Downloads folder contents:\n{downloads_content[:500]}"
            }
        except:
            pass
        
        return {
            'success': False,
            'local_path': None,
            'filename': None,
            'error': "PDF file could not be located in any expected location"
        }
        
    except Exception as e:
        logger.error(f"Error in find_and_copy_pdf: {e}", exc_info=True)
        return {
            'success': False,
            'local_path': None,
            'filename': None,
            'error': f"Error finding PDF: {str(e)}"
        }


def run_all_checks(pdf_path, pdf_filename):
    """
    Run all verification checks on the PDF.
    
    Returns:
        Dict with results for each criterion
    """
    results = {
        'file_exists': True,  # If we got here, file exists
        'file_size_ok': False,
        'valid_pdf': False,
        'content_keywords': False,
        'descriptive_filename': False,
        'has_multiple_pages': False,
    }
    
    # Check 1: File size
    try:
        file_size = Path(pdf_path).stat().st_size
        size_kb = file_size / 1024
        logger.info(f"PDF file size: {size_kb:.1f} KB")
        
        if file_size > 50 * 1024:  # More than 50KB
            results['file_size_ok'] = True
            logger.info("✓ File size check passed")
        else:
            logger.info(f"✗ File too small: {size_kb:.1f} KB (need > 50 KB)")
    except Exception as e:
        logger.error(f"Error checking file size: {e}")
    
    # Check 2-4: PDF validity and content (requires PyPDF2)
    if HAS_PYPDF2:
        try:
            reader = PdfReader(pdf_path)
            results['valid_pdf'] = True
            logger.info("✓ PDF format is valid")
            
            # Check page count
            page_count = len(reader.pages)
            logger.info(f"PDF has {page_count} page(s)")
            
            if page_count >= 2:
                results['has_multiple_pages'] = True
                logger.info("✓ PDF has multiple pages")
            else:
                logger.info(f"✗ PDF has only {page_count} page(s), expected 2+")
            
            # Extract text and check for keywords
            text_content = ""
            for page in reader.pages:
                try:
                    page_text = page.extract_text()
                    if page_text:
                        text_content += page_text + "\n"
                except Exception as e:
                    logger.warning(f"Could not extract text from a page: {e}")
            
            if text_content:
                text_lower = text_content.lower()
                
                # Expected keywords from the support chat
                expected_keywords = [
                    "customer support",
                    "cs-2024-8472",
                    "ref-2024-9382",
                    "sarah mitchell",
                    "duplicate charge",
                    "refund",
                    "ord-5839"
                ]
                
                found_keywords = [kw for kw in expected_keywords if kw in text_lower]
                keyword_match_rate = len(found_keywords) / len(expected_keywords)
                
                logger.info(f"Found {len(found_keywords)}/{len(expected_keywords)} expected keywords")
                logger.info(f"Keywords found: {found_keywords[:5]}")  # Log first 5
                
                if keyword_match_rate >= 0.5:  # At least 50% of keywords
                    results['content_keywords'] = True
                    logger.info("✓ Content keywords check passed")
                else:
                    logger.info(f"✗ Insufficient keywords ({len(found_keywords)}/{len(expected_keywords)})")
            else:
                logger.info("✗ Could not extract any text from PDF")
                
        except Exception as e:
            logger.error(f"Error validating PDF: {e}")
            results['valid_pdf'] = False
    else:
        logger.warning("PyPDF2 not available - skipping PDF content checks")
        # Give partial credit if we can't check
        results['valid_pdf'] = None
        results['has_multiple_pages'] = None
        results['content_keywords'] = None
    
    # Check 5: Descriptive filename
    filename_lower = pdf_filename.lower()
    
    generic_names = [
        "untitled.pdf",
        "document.pdf",
        "print.pdf",
        "download.pdf",
        "output.pdf",
        "file.pdf",
        "page.pdf"
    ]
    
    is_generic = filename_lower in generic_names
    
    # Check if filename contains relevant keywords
    relevant_keywords = ["support", "chat", "transcript", "cs-2024", "customer", "service"]
    has_relevant_keywords = any(kw in filename_lower for kw in relevant_keywords)
    
    if not is_generic and has_relevant_keywords:
        results['descriptive_filename'] = True
        logger.info(f"✓ Filename is descriptive: {pdf_filename}")
    elif not is_generic:
        results['descriptive_filename'] = 0.5  # Partial credit for non-generic
        logger.info(f"⚠ Filename not generic but lacks relevant keywords: {pdf_filename}")
    else:
        results['descriptive_filename'] = False
        logger.info(f"✗ Filename is generic: {pdf_filename}")
    
    return results


def calculate_final_result(verification_results, pdf_filename):
    """
    Calculate final score and generate feedback based on verification results.
    
    Returns:
        Dict with passed, score, and feedback
    """
    # Count criteria met (with partial credit handling)
    criteria_scores = []
    
    for key, value in verification_results.items():
        if value is True:
            criteria_scores.append(1.0)
        elif value is False:
            criteria_scores.append(0.0)
        elif value is None:
            criteria_scores.append(0.5)  # Partial credit if check couldn't run
        elif isinstance(value, float):
            criteria_scores.append(value)  # Partial credit (e.g., 0.5)
        else:
            criteria_scores.append(0.0)
    
    total_score = sum(criteria_scores)
    max_possible = len(criteria_scores)
    score_percentage = (total_score / max_possible) * 100
    
    passed = score_percentage >= 75
    
    # Generate detailed feedback
    feedback_lines = []
    feedback_lines.append(f"PDF Save Verification Results:")
    feedback_lines.append(f"{'='*50}")
    
    # Criterion-by-criterion feedback
    feedback_lines.append(f"✓ PDF file found: {pdf_filename}")
    
    if verification_results['file_size_ok']:
        feedback_lines.append(f"✓ File size adequate (>50 KB)")
    else:
        feedback_lines.append(f"✗ File size too small (<50 KB) - may be incomplete")
    
    if verification_results['valid_pdf'] is True:
        feedback_lines.append(f"✓ Valid PDF format")
    elif verification_results['valid_pdf'] is False:
        feedback_lines.append(f"✗ PDF format invalid or corrupted")
    elif verification_results['valid_pdf'] is None:
        feedback_lines.append(f"⚠ PDF format check skipped (library unavailable)")
    
    if verification_results['has_multiple_pages'] is True:
        feedback_lines.append(f"✓ PDF has multiple pages")
    elif verification_results['has_multiple_pages'] is False:
        feedback_lines.append(f"✗ PDF has insufficient pages")
    elif verification_results['has_multiple_pages'] is None:
        feedback_lines.append(f"⚠ Page count check skipped")
    
    if verification_results['content_keywords'] is True:
        feedback_lines.append(f"✓ Content contains expected keywords")
    elif verification_results['content_keywords'] is False:
        feedback_lines.append(f"✗ Content missing expected keywords")
    elif verification_results['content_keywords'] is None:
        feedback_lines.append(f"⚠ Content check skipped")
    
    if verification_results['descriptive_filename'] is True:
        feedback_lines.append(f"✓ Filename is descriptive and relevant")
    elif verification_results['descriptive_filename'] == 0.5:
        feedback_lines.append(f"⚠ Filename is acceptable but could be more descriptive")
    else:
        feedback_lines.append(f"✗ Filename is generic (e.g., 'Untitled.pdf')")
    
    feedback_lines.append(f"")
    feedback_lines.append(f"Score: {total_score:.1f}/{max_possible} criteria met ({score_percentage:.0f}%)")
    
    if passed:
        feedback_lines.append(f"Result: ✅ PASSED - PDF successfully saved with adequate content")
    else:
        feedback_lines.append(f"Result: ❌ FAILED - PDF missing or incomplete")
        feedback_lines.append(f"")
        feedback_lines.append(f"Tip: Make sure to:")
        feedback_lines.append(f"  1. Press Ctrl+P to open print dialog")
        feedback_lines.append(f"  2. Select 'Save as PDF' as destination")
        feedback_lines.append(f"  3. Use a descriptive filename")
        feedback_lines.append(f"  4. Ensure the page fully loaded before saving")
    
    if not HAS_PYPDF2:
        feedback_lines.append(f"")
        feedback_lines.append(f"Note: PDF content analysis limited - PyPDF2 library not available")
    
    feedback = "\n".join(feedback_lines)
    
    return {
        "passed": passed,
        "score": int(score_percentage),
        "feedback": feedback,
        "details": {
            "filename": pdf_filename,
            "criteria_met": total_score,
            "max_criteria": max_possible,
            "verification_results": verification_results
        }
    }
