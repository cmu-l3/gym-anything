#!/usr/bin/env python3
"""
Verifier for Chrome Lighthouse Audit Task (lighthouse_audit@1)
Task: Run Lighthouse audit, generate report, and save it

Verification Strategy:
- Locate Lighthouse report file in Downloads folder (HTML or JSON)
- Parse report structure (extract embedded JSON from HTML if needed)
- Validate Lighthouse data structure (required fields, version, etc.)
- Check for required audit categories (Performance, Accessibility)
- Verify category scores are present and valid (0-100 range)
- Check for key performance metrics (FCP, LCP, TBT, CLS, Speed Index)
- Ensure audit completed without errors
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

# Try to import BeautifulSoup for HTML parsing
try:
    from bs4 import BeautifulSoup
    HAS_BS4 = True
except ImportError:
    HAS_BS4 = False
    logger.warning("BeautifulSoup not available, HTML parsing will use regex fallback")

# Add Chrome utilities to path
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../../utils'))
try:
    from chrome_verification_utils import cleanup_verification_temp
except ImportError:
    logger.warning("Chrome verification utilities not available")
    def cleanup_verification_temp():
        pass


def find_lighthouse_report(copy_from_env) -> Tuple[bool, str, str, str]:
    """
    Find and copy Lighthouse report from container.
    
    Args:
        copy_from_env: Function to copy files from container
        
    Returns:
        Tuple of (success, local_path, filename, report_format, error_message)
    """
    try:
        # First, check if report was found during export
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/report_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "", "No Lighthouse report found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read report_filename.txt: {e}")
            found_name = None
        
        # Get report format if available
        report_format = "unknown"
        try:
            temp_format = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
            copy_from_env("/tmp/report_format.txt", temp_format.name)
            with open(temp_format.name, 'r') as f:
                report_format = f.read().strip()
            os.unlink(temp_format.name)
        except:
            pass
        
        # Try to copy the report file
        if found_name and found_name != "none":
            # Determine extension from format
            if report_format == "html":
                ext = ".html"
            elif report_format == "json":
                ext = ".json"
            else:
                # Try to infer from filename
                ext = ".html" if ".html" in found_name else ".json" if ".json" in found_name else ".html"
            
            temp_report = tempfile.NamedTemporaryFile(delete=False, suffix=ext)
            temp_report.close()
            
            # Try multiple possible locations
            possible_paths = [
                f"/tmp/lighthouse_verification/{found_name}",
                f"/tmp/{found_name}",
                f"/home/ga/Downloads/{found_name}",
            ]
            
            for container_path in possible_paths:
                try:
                    logger.info(f"Trying to copy report from: {container_path}")
                    copy_from_env(container_path, temp_report.name)
                    
                    # Check if file has content
                    if Path(temp_report.name).stat().st_size > 1000:  # Lighthouse reports are large
                        logger.info(f"✓ Successfully copied report from: {container_path}")
                        return True, temp_report.name, found_name, report_format, ""
                except Exception as e:
                    logger.debug(f"Could not copy from {container_path}: {e}")
                    continue
            
            os.unlink(temp_report.name)
        
        # If we get here, copy failed
        return False, "", "", "", "Could not copy Lighthouse report from container"
        
    except Exception as e:
        logger.error(f"Error finding report: {e}", exc_info=True)
        return False, "", "", "", f"Error finding report: {str(e)}"


def extract_lighthouse_json_from_html(html_path: str) -> Optional[Dict[str, Any]]:
    """
    Extract embedded Lighthouse JSON data from HTML report.
    
    Lighthouse HTML reports embed the full JSON data in a script tag or as a data attribute.
    
    Args:
        html_path: Path to HTML report file
        
    Returns:
        Parsed Lighthouse JSON data or None if extraction failed
    """
    try:
        with open(html_path, 'r', encoding='utf-8') as f:
            html_content = f.read()
        
        # Method 1: Try BeautifulSoup if available
        if HAS_BS4:
            soup = BeautifulSoup(html_content, 'lxml')
            
            # Look for script tag with type="application/json"
            json_scripts = soup.find_all('script', type='application/json')
            for script in json_scripts:
                if script.string and len(script.string) > 100:  # Lighthouse data is large
                    try:
                        data = json.loads(script.string)
                        if 'lighthouseVersion' in data or 'lhr' in data:
                            logger.info("✓ Extracted Lighthouse JSON from script tag (BeautifulSoup)")
                            # Handle wrapped format
                            return data.get('lhr', data)
                    except json.JSONDecodeError:
                        continue
        
        # Method 2: Regex fallback for script tag
        patterns = [
            r'<script[^>]*type="application/json"[^>]*>(.*?)</script>',
            r'<script[^>]*>(.*?"lighthouseVersion".*?)</script>',
            r'window\.__LIGHTHOUSE_JSON__\s*=\s*({.*?});',
        ]
        
        for pattern in patterns:
            matches = re.finditer(pattern, html_content, re.DOTALL)
            for match in matches:
                json_str = match.group(1).strip()
                if len(json_str) > 100:
                    try:
                        data = json.loads(json_str)
                        if 'lighthouseVersion' in data or 'lhr' in data:
                            logger.info(f"✓ Extracted Lighthouse JSON using regex pattern")
                            return data.get('lhr', data)
                    except json.JSONDecodeError:
                        continue
        
        logger.error("Could not extract Lighthouse JSON from HTML")
        return None
        
    except Exception as e:
        logger.error(f"Error extracting JSON from HTML: {e}")
        return None


def parse_lighthouse_report(report_path: str, report_format: str) -> Optional[Dict[str, Any]]:
    """
    Parse Lighthouse report and extract JSON data.
    
    Args:
        report_path: Path to report file
        report_format: Format of report ("html" or "json")
        
    Returns:
        Parsed Lighthouse JSON data or None if parsing failed
    """
    try:
        if report_format == "json":
            # Direct JSON file
            with open(report_path, 'r', encoding='utf-8') as f:
                data = json.load(f)
            logger.info("✓ Parsed JSON report directly")
            return data
        
        elif report_format == "html":
            # HTML with embedded JSON
            return extract_lighthouse_json_from_html(report_path)
        
        else:
            # Unknown format, try both
            logger.info("Unknown format, trying both JSON and HTML parsing")
            
            # Try as JSON first
            try:
                with open(report_path, 'r', encoding='utf-8') as f:
                    data = json.load(f)
                if 'lighthouseVersion' in data:
                    logger.info("✓ Successfully parsed as JSON")
                    return data
            except:
                pass
            
            # Try as HTML
            return extract_lighthouse_json_from_html(report_path)
        
    except Exception as e:
        logger.error(f"Error parsing report: {e}")
        return None


def validate_lighthouse_structure(data: Dict[str, Any]) -> Tuple[bool, str]:
    """
    Validate that data has required Lighthouse structure.
    
    Args:
        data: Parsed Lighthouse JSON data
        
    Returns:
        Tuple of (is_valid, error_message)
    """
    required_fields = ['lighthouseVersion', 'fetchTime', 'requestedUrl', 'categories']
    
    for field in required_fields:
        if field not in data:
            return False, f"Missing required field: {field}"
    
    if not isinstance(data['categories'], dict):
        return False, "Invalid categories structure"
    
    return True, ""


def extract_category_scores(data: Dict[str, Any]) -> Dict[str, Optional[float]]:
    """
    Extract category scores from Lighthouse data.
    
    Args:
        data: Parsed Lighthouse JSON data
        
    Returns:
        Dict mapping category names to scores (0-1 scale) or None
    """
    categories = data.get('categories', {})
    
    scores = {}
    for cat_id, cat_data in categories.items():
        if isinstance(cat_data, dict):
            score = cat_data.get('score')
            scores[cat_id] = score
    
    return scores


def extract_performance_metrics(data: Dict[str, Any]) -> Dict[str, Optional[float]]:
    """
    Extract key performance metrics from Lighthouse data.
    
    Args:
        data: Parsed Lighthouse JSON data
        
    Returns:
        Dict mapping metric names to values
    """
    audits = data.get('audits', {})
    
    metric_keys = [
        'first-contentful-paint',
        'largest-contentful-paint',
        'total-blocking-time',
        'cumulative-layout-shift',
        'speed-index',
        'interactive',
    ]
    
    metrics = {}
    for key in metric_keys:
        if key in audits:
            audit = audits[key]
            if isinstance(audit, dict):
                metrics[key] = audit.get('numericValue')
    
    return metrics


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for lighthouse_audit@1 task.
    
    Verifies:
    1. Lighthouse report file exists and can be parsed
    2. Report has valid Lighthouse structure
    3. Required categories present (Performance, Accessibility)
    4. Category scores are valid (0-1 range)
    5. Key performance metrics are captured
    6. Audit completed without errors
    
    Scoring:
    - 100%: All 6 criteria met with complete data
    - 85-99%: 5/6 criteria met (minor missing data)
    - 70-84%: 4/6 criteria met (acceptable)
    - 50-69%: 3/6 criteria met (partial)
    - <50%: <3 criteria met (failed)
    
    Pass threshold: 70% (4 out of 6 criteria)
    
    Args:
        traj: Trajectory data (unused)
        env_info: Environment info with copy_from_env function
        task_info: Task configuration
        
    Returns:
        Dict with passed, score, feedback, and details
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
    
    # Criterion 1: Report file exists
    logger.info("Searching for Lighthouse report...")
    success, report_path, report_name, report_format, error = find_lighthouse_report(copy_from_env)
    
    if not success:
        feedback = f"✗ Lighthouse report not found\n{error}\n\nPlease ensure you:\n"
        feedback += "1. Opened DevTools (F12)\n"
        feedback += "2. Navigated to Lighthouse tab\n"
        feedback += "3. Selected Performance and Accessibility\n"
        feedback += "4. Ran the audit (waited for completion)\n"
        feedback += "5. Exported the report to Downloads folder"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ Report found: {report_name} ({report_format})")
    criteria_met += 1
    
    # Check file size
    try:
        file_size = Path(report_path).stat().st_size
        size_kb = file_size / 1024
        if file_size < 10000:  # Less than 10KB is suspicious
            feedback_parts.append(f"⚠ Report file very small ({size_kb:.1f} KB)")
        else:
            feedback_parts.append(f"✓ Report size: {size_kb:.1f} KB")
    except:
        pass
    
    # Criterion 2: Parse report
    logger.info("Parsing Lighthouse report...")
    lighthouse_data = parse_lighthouse_report(report_path, report_format)
    
    if lighthouse_data is None:
        feedback = "\n".join(feedback_parts)
        feedback += "\n✗ Failed to parse Lighthouse report"
        feedback += "\nThe report file was found but could not be parsed. It may be corrupted or incomplete."
        
        # Clean up
        try:
            os.unlink(report_path)
        except:
            pass
        
        return {
            "passed": False,
            "score": int((criteria_met / total_criteria) * 100),
            "feedback": feedback
        }
    
    feedback_parts.append("✓ Report parsed successfully")
    criteria_met += 1
    
    # Criterion 3: Validate structure
    logger.info("Validating Lighthouse structure...")
    valid, struct_error = validate_lighthouse_structure(lighthouse_data)
    
    if not valid:
        feedback_parts.append(f"✗ Invalid Lighthouse structure: {struct_error}")
    else:
        feedback_parts.append("✓ Valid Lighthouse structure")
        criteria_met += 1
    
    # Criterion 4: Check required categories
    logger.info("Checking audit categories...")
    scores = extract_category_scores(lighthouse_data)
    
    has_performance = 'performance' in scores and scores['performance'] is not None
    has_accessibility = 'accessibility' in scores and scores['accessibility'] is not None
    
    if has_performance and has_accessibility:
        perf_score = int(scores['performance'] * 100) if scores['performance'] is not None else 0
        a11y_score = int(scores['accessibility'] * 100) if scores['accessibility'] is not None else 0
        feedback_parts.append(f"✓ Required categories present")
        feedback_parts.append(f"  - Performance: {perf_score}/100")
        feedback_parts.append(f"  - Accessibility: {a11y_score}/100")
        criteria_met += 1
    else:
        missing = []
        if not has_performance:
            missing.append("Performance")
        if not has_accessibility:
            missing.append("Accessibility")
        feedback_parts.append(f"✗ Missing required categories: {', '.join(missing)}")
    
    # Optional categories (informational only)
    optional_cats = ['best-practices', 'seo', 'pwa']
    found_optional = []
    for cat in optional_cats:
        if cat in scores and scores[cat] is not None:
            score_val = int(scores[cat] * 100)
            found_optional.append(f"{cat.replace('-', ' ').title()}: {score_val}/100")
    
    if found_optional:
        feedback_parts.append(f"  + Optional: {', '.join(found_optional)}")
    
    # Criterion 5: Check performance metrics
    logger.info("Checking performance metrics...")
    metrics = extract_performance_metrics(lighthouse_data)
    
    metrics_present = sum(1 for v in metrics.values() if v is not None)
    total_metrics = len(metrics)
    
    if metrics_present >= 4:  # At least 4 out of 6 key metrics
        feedback_parts.append(f"✓ Performance metrics captured ({metrics_present}/{total_metrics})")
        criteria_met += 1
        
        # Show some key metrics
        if metrics.get('first-contentful-paint'):
            fcp_ms = int(metrics['first-contentful-paint'])
            feedback_parts.append(f"  - FCP: {fcp_ms}ms")
        if metrics.get('largest-contentful-paint'):
            lcp_ms = int(metrics['largest-contentful-paint'])
            feedback_parts.append(f"  - LCP: {lcp_ms}ms")
    else:
        feedback_parts.append(f"⚠ Limited metrics captured ({metrics_present}/{total_metrics})")
        criteria_met += 0.5  # Partial credit
    
    # Criterion 6: Check for errors/warnings
    logger.info("Checking for audit errors...")
    run_warnings = lighthouse_data.get('runWarnings', [])
    has_errors = len(run_warnings) > 0
    
    if not has_errors:
        feedback_parts.append("✓ Audit completed without errors")
        criteria_met += 1
    else:
        feedback_parts.append(f"⚠ Audit had {len(run_warnings)} warning(s)")
        criteria_met += 0.5  # Partial credit
    
    # Calculate final score
    score = int((criteria_met / total_criteria) * 100)
    passed = score >= 70
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*50}"
    feedback += f"\nCriteria met: {criteria_met:.1f}/{total_criteria}"
    feedback += f"\nFinal score: {score}%"
    feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
    
    # Add educational note
    if passed:
        feedback += "\n\n✨ Excellent! You successfully ran a Lighthouse audit."
        feedback += "\nThis skill is essential for web performance optimization and quality assurance."
    else:
        feedback += "\n\nℹ️ To complete this task successfully:"
        feedback += "\n1. Open DevTools (F12) with the target page loaded"
        feedback += "\n2. Navigate to the Lighthouse tab"
        feedback += "\n3. Ensure Performance and Accessibility are checked"
        feedback += "\n4. Click 'Analyze page load' and wait for completion (10-30s)"
        feedback += "\n5. Export the report via the menu (⋮ icon)"
    
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
            "report_name": report_name,
            "report_format": report_format,
            "lighthouse_version": lighthouse_data.get('lighthouseVersion', 'unknown'),
            "audited_url": lighthouse_data.get('requestedUrl', 'unknown'),
            "criteria_met": criteria_met,
            "scores": {k: int(v * 100) if v is not None else None for k, v in scores.items()},
            "metrics_captured": metrics_present,
            "has_warnings": has_errors
        }
    }
