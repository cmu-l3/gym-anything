#!/usr/bin/env python3
"""
Verifier for Chrome Lighthouse Accessibility Audit Task
Task: Run Lighthouse accessibility audit on test page and export results

Verification Strategy:
- Locate exported Lighthouse report (JSON or HTML) in Downloads
- Parse report to extract accessibility score
- Validate score meets minimum threshold (≥60%)
- Check audit completeness (≥10 accessibility audits)
- Verify correct URL was audited
- Validate report structure is valid
"""

import logging
import sys
import os
import json
import tempfile
from pathlib import Path
from typing import Dict, Any, Tuple, Optional

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Add utils to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../', 'utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
    UTILS_AVAILABLE = True
except ImportError:
    logger.warning("Chrome verification utilities not available, using fallback methods")
    UTILS_AVAILABLE = False
    def cleanup_verification_temp():
        pass

# Try to import BeautifulSoup for HTML parsing
try:
    from bs4 import BeautifulSoup
    HAS_BS4 = True
except ImportError:
    HAS_BS4 = False
    logger.warning("BeautifulSoup not available, HTML report parsing will be limited")


def find_lighthouse_report(copy_from_env) -> Tuple[bool, str, str, str]:
    """
    Find and copy the Lighthouse report from container.
    
    Returns:
        Tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, get the report filename that was found
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/lighthouse_verification/report_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No Lighthouse report file was found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read report_filename.txt: {e}")
            found_name = "accessibility_audit_report.json"
        
        # Determine if it's JSON or HTML
        is_json = found_name.endswith('.json')
        is_html = found_name.endswith('.html')
        
        if not is_json and not is_html:
            return False, "", "", f"Unknown report format: {found_name}"
        
        # Create temporary file for the report
        suffix = '.json' if is_json else '.html'
        temp_report = tempfile.NamedTemporaryFile(delete=False, suffix=suffix)
        temp_report.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/lighthouse_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
            "/home/ga/Downloads/accessibility_audit_report.json",
            "/home/ga/Downloads/accessibility_audit_report.html",
        ]
        
        for container_path in possible_paths:
            try:
                logger.info(f"Trying to copy from: {container_path}")
                copy_from_env(container_path, temp_report.name)
                
                # Check if file has content
                if Path(temp_report.name).stat().st_size > 0:
                    logger.info(f"✓ Successfully copied report from: {container_path}")
                    return True, temp_report.name, found_name, ""
            except Exception as e:
                logger.debug(f"Could not copy from {container_path}: {e}")
                continue
        
        # If we get here, none of the paths worked
        os.unlink(temp_report.name)
        return False, "", "", "Lighthouse report could not be copied from container"
        
    except Exception as e:
        logger.error(f"Error finding Lighthouse report: {e}", exc_info=True)
        return False, "", "", f"Error finding report: {str(e)}"


def parse_lighthouse_json(report_path: str) -> Dict[str, Any]:
    """Parse Lighthouse JSON report."""
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except Exception as e:
        logger.error(f"Error parsing JSON report: {e}")
        return {"error": str(e)}


def parse_lighthouse_html(report_path: str) -> Dict[str, Any]:
    """
    Parse Lighthouse HTML report to extract key information.
    Note: This is a fallback and provides limited information compared to JSON.
    """
    if not HAS_BS4:
        return {"error": "BeautifulSoup not available for HTML parsing"}
    
    try:
        with open(report_path, 'r', encoding='utf-8') as f:
            html_content = f.read()
        
        soup = BeautifulSoup(html_content, 'html.parser')
        
        # Try to find accessibility score in HTML
        # Lighthouse HTML has the score in various places, look for data attributes or specific classes
        score_elem = soup.find('div', class_='lh-category', attrs={'id': 'accessibility'})
        
        if score_elem:
            # Try to extract score from data attribute or text
            score_attr = score_elem.get('data-score', '')
            if score_attr:
                score = float(score_attr)
                return {
                    "categories": {
                        "accessibility": {
                            "score": score
                        }
                    },
                    "requestedUrl": "",  # Hard to extract from HTML
                    "lighthouseVersion": "unknown",
                    "audits": {}  # Can't reliably extract individual audits from HTML
                }
        
        # If we can't extract structured data, return error
        return {"error": "Could not extract accessibility score from HTML report"}
        
    except Exception as e:
        logger.error(f"Error parsing HTML report: {e}")
        return {"error": str(e)}


def extract_accessibility_score(report: Dict) -> Optional[float]:
    """
    Extract accessibility score from Lighthouse report (0-100 scale).
    
    Args:
        report: Parsed Lighthouse report dictionary
        
    Returns:
        Float score 0-100, or None if not found
    """
    try:
        # Score is in 0-1 range, convert to 0-100
        score = report.get('categories', {}).get('accessibility', {}).get('score')
        if score is not None:
            return float(score) * 100
        return None
    except Exception as e:
        logger.error(f"Error extracting score: {e}")
        return None


def count_accessibility_audits(report: Dict) -> int:
    """
    Count number of accessibility-related audits performed.
    
    Args:
        report: Parsed Lighthouse report dictionary
        
    Returns:
        Integer count of accessibility audits
    """
    try:
        audits = report.get('audits', {})
        # Common accessibility audit keys
        accessibility_audits = [
            'image-alt', 'color-contrast', 'document-title', 'html-has-lang',
            'aria-allowed-attr', 'aria-required-attr', 'button-name',
            'link-name', 'label', 'frame-title', 'meta-viewport',
            'heading-order', 'duplicate-id', 'list', 'listitem',
            'definition-list', 'dlitem', 'table-duplicate-name',
            'td-headers-attr', 'th-has-data-cells', 'valid-lang',
            'video-caption', 'object-alt', 'accesskeys', 'aria-valid-attr',
            'aria-valid-attr-value', 'input-image-alt', 'tabindex',
            'meta-refresh', 'logical-tab-order'
        ]
        return sum(1 for audit in accessibility_audits if audit in audits)
    except Exception as e:
        logger.error(f"Error counting audits: {e}")
        return 0


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for Lighthouse accessibility audit task.
    
    Verifies:
    1. Report file exists and was exported
    2. Report is valid JSON or HTML format
    3. Accessibility score is ≥60% (reasonable for test page with known issues)
    4. At least 10 accessibility audits were performed
    5. Correct URL was audited (W3C test page)
    
    Scoring:
    - 100%: All 5 criteria met
    - 80%: 4/5 criteria met (passing)
    - 60%: 3/5 criteria met
    - 40%: 2/5 criteria met
    - 0-20%: 0-1 criteria met
    
    Pass threshold: 80% (4 out of 5 criteria)
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
    
    # Expected test page URL
    expected_url = "https://www.w3.org/WAI/demos/bad/before/home.html"
    
    # Criterion 1: Report file exists
    logger.info("Checking if Lighthouse report file exists...")
    success, report_path, report_name, error = find_lighthouse_report(copy_from_env)
    
    if not success:
        feedback = f"✗ Lighthouse report not found\n{error}\n\n"
        feedback += "The agent should:\n"
        feedback += "1. Open DevTools (F12 or Ctrl+Shift+I)\n"
        feedback += "2. Navigate to Lighthouse tab\n"
        feedback += "3. Select Accessibility category\n"
        feedback += "4. Run audit\n"
        feedback += "5. Export/download the report as JSON or HTML"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ Report found: {report_name}")
    criteria_met += 1
    
    # Determine report format
    is_json = report_name.endswith('.json')
    is_html = report_name.endswith('.html')
    
    # Criterion 2: Report is valid format
    logger.info(f"Parsing {report_name}...")
    if is_json:
        report = parse_lighthouse_json(report_path)
    elif is_html:
        report = parse_lighthouse_html(report_path)
    else:
        report = {"error": "Unknown format"}
    
    if "error" in report:
        feedback_parts.append(f"✗ Failed to parse report: {report['error']}")
        
        # Clean up and return
        try:
            os.unlink(report_path)
        except:
            pass
        
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\nCriteria met: {criteria_met}/{total_criteria}"
        feedback += f"\nFinal score: {int((criteria_met/total_criteria)*100)}%"
        
        return {
            "passed": False,
            "score": int((criteria_met/total_criteria)*100),
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ Valid Lighthouse report format")
    criteria_met += 1
    
    # Criterion 3: Accessibility score ≥60%
    logger.info("Checking accessibility score...")
    accessibility_score = extract_accessibility_score(report)
    
    if accessibility_score is None:
        feedback_parts.append(f"✗ Could not extract accessibility score from report")
    elif accessibility_score >= 60:
        feedback_parts.append(f"✓ Accessibility score: {accessibility_score:.1f}% (≥60%)")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Accessibility score too low: {accessibility_score:.1f}% (expected ≥60%)")
    
    # Criterion 4: Audit completeness (≥10 audits)
    logger.info("Checking audit completeness...")
    audit_count = count_accessibility_audits(report)
    
    if is_html and audit_count == 0:
        # HTML parsing couldn't extract individual audits
        feedback_parts.append(f"⚠ Audit count unavailable from HTML report (partial credit)")
        criteria_met += 0.5  # Partial credit
    elif audit_count >= 10:
        feedback_parts.append(f"✓ Complete audit: {audit_count} accessibility checks performed")
        criteria_met += 1
    else:
        feedback_parts.append(f"✗ Incomplete audit: only {audit_count} checks (expected ≥10)")
    
    # Criterion 5: Correct URL was audited
    logger.info("Checking audited URL...")
    audited_url = report.get('requestedUrl', '') or report.get('finalUrl', '')
    
    if audited_url:
        # Normalize URLs for comparison
        audited_normalized = audited_url.lower().replace('http://', '').replace('https://', '').rstrip('/')
        expected_normalized = expected_url.lower().replace('http://', '').replace('https://', '').rstrip('/')
        
        if expected_normalized in audited_normalized:
            feedback_parts.append(f"✓ Correct URL audited: {audited_url}")
            criteria_met += 1
        else:
            feedback_parts.append(f"✗ Wrong URL audited: {audited_url}")
            feedback_parts.append(f"  Expected: {expected_url}")
    else:
        feedback_parts.append(f"⚠ Could not verify audited URL from report")
        # If HTML format, give partial credit since URL is hard to extract
        if is_html:
            criteria_met += 0.5
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 80
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    if accessibility_score is not None:
        feedback += f"\n\nAccessibility Score: {accessibility_score:.1f}/100"
        
        # Provide context about the score
        if accessibility_score < 60:
            feedback += "\nNote: The test page intentionally has accessibility issues."
            feedback += "\nA complete audit should score 50-75% on this page."
    
    if not is_json:
        feedback += "\n\n⚠ Note: HTML report format provides limited verification."
        feedback += "\nJSON format is preferred for complete verification."
    
    # Clean up temporary file
    try:
        if report_path and os.path.exists(report_path):
            os.unlink(report_path)
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
            "accessibility_score": accessibility_score,
            "audit_count": audit_count,
            "report_format": "json" if is_json else "html",
            "audited_url": audited_url
        }
    }
