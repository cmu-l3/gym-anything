#!/usr/bin/env python3
"""
Verifier for Chrome PDF Viewer Navigation and Search Task (pdf_viewer_navigate_search@1)
Task: Open PDF, search for 'hypothesis', navigate to 3rd occurrence on page 7

Verification Strategy:
- Check PDF is open in Chrome (URL pattern matching)
- Verify page navigation occurred (URL fragment or heuristics)
- Check PDF file exists and contains expected content
- Validate task completion through multi-criteria analysis
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from urllib.parse import urlparse, unquote
from typing import Dict, List, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Try to import PDF libraries
try:
    from PyPDF2 import PdfReader
    HAS_PYPDF = True
except ImportError:
    try:
        import pypdf
        from pypdf import PdfReader
        HAS_PYPDF = True
    except ImportError:
        HAS_PYPDF = False
        logger.warning("PyPDF2/pypdf not available, PDF content analysis will be limited")

# Add utilities to path
sys.path.insert(0, os.path.join(os.path.abspath(__file__), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    def cleanup_verification_temp():
        pass


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for pdf_viewer_navigate_search@1 task.
    
    Verifies:
    1. PDF file is open in Chrome
    2. PDF contains expected content (search term exists)
    3. Navigation occurred (page number changed from default)
    4. URL indicates target page (if fragment present)
    5. Evidence of search interaction
    
    Args:
        traj: Trajectory data (not used for this verification)
        env_info: Environment information including copy_from_env function
        task_info: Task configuration information
        
    Returns:
        Dict with 'passed', 'score', and 'feedback' keys
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "Copy function not available - cannot verify task"
        }

    # Task parameters
    expected_pdf_name = "research_methodology.pdf"
    search_term = "hypothesis"
    target_page = 7
    target_occurrence = 3
    
    try:
        # Get verification data from container
        verification_data = get_verification_data(copy_from_env)
        
        # Perform multi-criteria verification
        result = verify_pdf_navigation_search(
            verification_data,
            expected_pdf_name,
            search_term,
            target_page,
            target_occurrence
        )
        
        # Clean up
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


def get_verification_data(copy_from_env) -> Dict[str, Any]:
    """
    Retrieve verification data from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Dict containing active_url, title, page_number, pdf_path, etc.
    """
    data = {
        "active_url": "",
        "active_title": "",
        "page_number": None,
        "url_fragment": "",
        "pdf_path": None,
        "screenshot_path": None
    }
    
    # Helper function to copy and read text file
    def copy_and_read(container_path: str) -> str:
        try:
            temp_file = tempfile.NamedTemporaryFile(delete=False, mode='w+')
            temp_file.close()
            copy_from_env(container_path, temp_file.name)
            with open(temp_file.name, 'r') as f:
                content = f.read().strip()
            os.unlink(temp_file.name)
            return content
        except Exception as e:
            logger.debug(f"Could not read {container_path}: {e}")
            return ""
    
    # Get active URL
    data["active_url"] = copy_and_read("/tmp/active_url.txt")
    logger.info(f"Active URL: {data['active_url']}")
    
    # Get active title
    data["active_title"] = copy_and_read("/tmp/active_title.txt")
    logger.info(f"Active Title: {data['active_title']}")
    
    # Get URL fragment (if exists)
    data["url_fragment"] = copy_and_read("/tmp/url_fragment.txt")
    if data["url_fragment"]:
        logger.info(f"URL Fragment: {data['url_fragment']}")
    
    # Get page number (if extracted)
    page_num_str = copy_and_read("/tmp/page_number.txt")
    if page_num_str and page_num_str.isdigit():
        data["page_number"] = int(page_num_str)
        logger.info(f"Extracted Page Number: {data['page_number']}")
    
    # Copy PDF file for content verification
    try:
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_pdf.close()
        copy_from_env("/tmp/research_methodology.pdf", temp_pdf.name)
        if Path(temp_pdf.name).stat().st_size > 0:
            data["pdf_path"] = temp_pdf.name
            logger.info(f"✓ PDF file copied for verification")
        else:
            os.unlink(temp_pdf.name)
    except Exception as e:
        logger.warning(f"Could not copy PDF file: {e}")
    
    # Copy screenshot (optional, for debugging)
    try:
        temp_screenshot = tempfile.NamedTemporaryFile(delete=False, suffix='.png')
        temp_screenshot.close()
        copy_from_env("/tmp/final_screenshot.png", temp_screenshot.name)
        if Path(temp_screenshot.name).stat().st_size > 0:
            data["screenshot_path"] = temp_screenshot.name
            logger.info(f"✓ Screenshot copied for verification")
        else:
            os.unlink(temp_screenshot.name)
    except Exception as e:
        logger.debug(f"Could not copy screenshot: {e}")
    
    return data


def verify_pdf_navigation_search(
    verification_data: Dict[str, Any],
    expected_pdf_name: str,
    search_term: str,
    target_page: int,
    target_occurrence: int
) -> Dict[str, Any]:
    """
    Verify PDF navigation and search task completion.
    
    Criteria:
    1. Correct PDF is open (URL contains expected filename)
    2. PDF content verified (file exists, contains search term)
    3. Page navigation detected (not on page 1)
    4. Target page reached (page 7 indicated in URL or close to it)
    5. Evidence of search interaction (URL fragment or page change)
    
    Args:
        verification_data: Data retrieved from container
        expected_pdf_name: Expected PDF filename
        search_term: Term to search for
        target_page: Expected page number
        target_occurrence: Expected occurrence number
        
    Returns:
        Verification result with passed, score, and detailed feedback
    """
    active_url = verification_data.get("active_url", "")
    active_title = verification_data.get("active_title", "")
    page_number = verification_data.get("page_number")
    url_fragment = verification_data.get("url_fragment", "")
    pdf_path = verification_data.get("pdf_path")
    
    criteria_results = []
    feedback_parts = []
    
    # Criterion 1: Correct PDF is open
    pdf_open = expected_pdf_name.lower() in active_url.lower()
    if pdf_open:
        feedback_parts.append(f"✓ Correct PDF open: {expected_pdf_name}")
        criteria_results.append(True)
        logger.info("Criterion 1 PASS: Correct PDF open")
    else:
        feedback_parts.append(f"✗ Expected PDF not open (URL: {active_url[:60]}...)")
        criteria_results.append(False)
        logger.info("Criterion 1 FAIL: PDF not open")
    
    # Criterion 2: PDF content verification
    pdf_content_ok = False
    search_term_count = 0
    if pdf_path and HAS_PYPDF:
        try:
            reader = PdfReader(pdf_path)
            total_pages = len(reader.pages)
            
            # Count occurrences of search term
            for page in reader.pages:
                try:
                    text = page.extract_text()
                    if text:
                        search_term_count += text.lower().count(search_term.lower())
                except Exception as e:
                    logger.warning(f"Could not extract text from a page: {e}")
            
            if search_term_count >= target_occurrence:
                pdf_content_ok = True
                feedback_parts.append(f"✓ PDF contains '{search_term}' ({search_term_count} occurrences, {total_pages} pages)")
                logger.info(f"Criterion 2 PASS: PDF content verified ({search_term_count} occurrences)")
            else:
                feedback_parts.append(f"✗ PDF has insufficient occurrences of '{search_term}' ({search_term_count} found, need {target_occurrence})")
                logger.info(f"Criterion 2 FAIL: Insufficient occurrences")
            
            # Clean up PDF file
            os.unlink(pdf_path)
        except Exception as e:
            feedback_parts.append(f"⚠ Could not verify PDF content: {e}")
            logger.warning(f"Criterion 2 PARTIAL: Error verifying content - {e}")
            pdf_content_ok = None  # Partial credit
    elif pdf_path:
        feedback_parts.append(f"⚠ PDF found but PyPDF not available for content verification")
        pdf_content_ok = None  # Partial credit
        logger.warning("Criterion 2 PARTIAL: PyPDF not available")
    else:
        feedback_parts.append(f"✗ PDF file not available for verification")
        logger.info("Criterion 2 FAIL: PDF file not available")
        pdf_content_ok = False
    
    criteria_results.append(pdf_content_ok if pdf_content_ok is not None else 0.5)
    
    # Criterion 3: Page navigation detected (not on default page 1)
    navigation_detected = False
    if page_number is not None and page_number > 1:
        navigation_detected = True
        feedback_parts.append(f"✓ Page navigation detected (page {page_number})")
        logger.info(f"Criterion 3 PASS: Navigation detected to page {page_number}")
    elif url_fragment and ("page=" in url_fragment or "search=" in url_fragment):
        navigation_detected = True
        feedback_parts.append(f"✓ URL fragment indicates interaction: {url_fragment}")
        logger.info(f"Criterion 3 PASS: URL fragment indicates navigation")
    else:
        feedback_parts.append(f"✗ No evidence of page navigation (still on page 1 or no URL changes)")
        logger.info("Criterion 3 FAIL: No navigation detected")
    
    criteria_results.append(navigation_detected)
    
    # Criterion 4: Target page reached (page 7 or close)
    target_page_reached = False
    if page_number is not None:
        page_diff = abs(page_number - target_page)
        if page_number == target_page:
            target_page_reached = True
            feedback_parts.append(f"✓ Exact target page reached: page {page_number}")
            logger.info(f"Criterion 4 PASS: Exact target page {target_page}")
        elif page_diff <= 1:
            target_page_reached = True
            feedback_parts.append(f"✓ Close to target page: page {page_number} (target: {target_page})")
            logger.info(f"Criterion 4 PASS: Close to target (page {page_number})")
        elif page_diff <= 2:
            target_page_reached = 0.5  # Partial credit
            feedback_parts.append(f"⚠ Near target page: page {page_number} (target: {target_page}, off by {page_diff})")
            logger.info(f"Criterion 4 PARTIAL: Near target (page {page_number})")
        else:
            feedback_parts.append(f"✗ Wrong page: page {page_number} (target: {target_page}, off by {page_diff})")
            logger.info(f"Criterion 4 FAIL: Wrong page {page_number}")
    else:
        # Try to parse from URL fragment
        if url_fragment:
            match = re.search(r'page=(\d+)', url_fragment)
            if match:
                extracted_page = int(match.group(1))
                page_diff = abs(extracted_page - target_page)
                if page_diff == 0:
                    target_page_reached = True
                    feedback_parts.append(f"✓ Target page in URL: page {extracted_page}")
                    logger.info(f"Criterion 4 PASS: Target page in URL")
                elif page_diff <= 2:
                    target_page_reached = 0.5
                    feedback_parts.append(f"⚠ Near target page in URL: page {extracted_page} (target: {target_page})")
                    logger.info(f"Criterion 4 PARTIAL: Near target in URL")
                else:
                    feedback_parts.append(f"✗ Wrong page in URL: page {extracted_page} (target: {target_page})")
                    logger.info(f"Criterion 4 FAIL: Wrong page in URL")
            else:
                feedback_parts.append(f"✗ No page number found in URL")
                logger.info("Criterion 4 FAIL: No page number in URL")
        else:
            feedback_parts.append(f"✗ Cannot determine current page (no URL fragment or page number)")
            logger.info("Criterion 4 FAIL: Cannot determine page")
    
    criteria_results.append(target_page_reached if isinstance(target_page_reached, (int, float)) else (1.0 if target_page_reached else 0.0))
    
    # Criterion 5: Evidence of search interaction
    search_interaction = False
    if "search=" in url_fragment.lower() or search_term.lower() in url_fragment.lower():
        search_interaction = True
        feedback_parts.append(f"✓ Search interaction detected in URL")
        logger.info("Criterion 5 PASS: Search in URL")
    elif page_number and page_number >= 5:
        # If navigated to a later page, likely performed search
        search_interaction = 0.7  # Probable but not certain
        feedback_parts.append(f"⚠ Likely search performed (reached page {page_number} in multi-page doc)")
        logger.info("Criterion 5 PROBABLE: Page navigation suggests search")
    else:
        feedback_parts.append(f"✗ No clear evidence of search interaction")
        logger.info("Criterion 5 FAIL: No search evidence")
    
    criteria_results.append(search_interaction if isinstance(search_interaction, (int, float)) else (1.0 if search_interaction else 0.0))
    
    # Calculate score
    total_possible = 5.0
    total_achieved = sum(criteria_results)
    score = int((total_achieved / total_possible) * 100)
    passed = score >= 75  # Need at least 3.75/5 criteria
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nCriteria achieved: {total_achieved:.1f}/{total_possible}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if passed:
        feedback += f"\n\n✅ Task completed successfully!"
        feedback += f"\nAgent demonstrated PDF viewer navigation and search skills."
    else:
        feedback += f"\n\n❌ Task incomplete."
        feedback += f"\nAgent needs to: (1) open PDF, (2) search for '{search_term}', "
        feedback += f"(3) navigate to occurrence {target_occurrence}, and (4) reach page {target_page}."
    
    if not HAS_PYPDF:
        feedback += "\n\n⚠ Note: PyPDF library not available, content verification was limited"
    
    logger.info(f"Verification complete: passed={passed}, score={score}, criteria={total_achieved:.1f}/5")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "active_url": active_url,
            "page_number": page_number,
            "url_fragment": url_fragment,
            "search_term_count": search_term_count,
            "criteria_achieved": total_achieved,
            "individual_criteria": {
                "pdf_open": criteria_results[0],
                "pdf_content": criteria_results[1],
                "navigation": criteria_results[2],
                "target_page": criteria_results[3],
                "search_interaction": criteria_results[4]
            }
        }
    }
