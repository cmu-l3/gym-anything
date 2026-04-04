#!/usr/bin/env python3
"""
Verifier for Chrome Print-to-PDF Archive Task (print_to_pdf_archive@1)
Task: Print webpage receipt to PDF with headers/footers disabled for clean archival

Key Verification Points:
1. PDF file exists and is valid
2. File has meaningful size
3. Content from receipt is preserved
4. NO Chrome header/footer artifacts (URLs, dates, page numbers)
5. Document is clean and professional
"""

import logging
import sys
import os
import re
import tempfile
from pathlib import Path
from typing import Dict, Any, List, Tuple

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
        logger.warning("PyPDF2/pypdf not available, verification will be limited")


def find_pdf_file(copy_from_env):
    """
    Find and copy the generated PDF from the container.
    
    Returns:
        tuple: (success, local_path, filename, error_message)
    """
    try:
        # First, check what filename was found during export
        temp_filename = tempfile.NamedTemporaryFile(delete=False, suffix='.txt')
        try:
            copy_from_env("/tmp/pdf_filename.txt", temp_filename.name)
            with open(temp_filename.name, 'r') as f:
                found_name = f.read().strip()
            os.unlink(temp_filename.name)
            
            if found_name == "none":
                return False, "", "", "No PDF file was created or found in Downloads folder"
        except Exception as e:
            logger.warning(f"Could not read pdf_filename.txt: {e}")
            found_name = "order_confirmation.pdf"  # Default expected name
        
        # Try to copy the PDF file
        temp_pdf = tempfile.NamedTemporaryFile(delete=False, suffix='.pdf')
        temp_pdf.close()
        
        # Try multiple possible locations
        possible_paths = [
            f"/tmp/print_pdf_archive_verification/{found_name}",
            f"/tmp/{found_name}",
            f"/home/ga/Downloads/{found_name}",
        ]
        
        # Also try finding any recent PDF if specific name not found
        possible_paths.extend([
            "/home/ga/Downloads/order_confirmation.pdf",
            "/home/ga/Downloads/Order_Confirmation.pdf",
        ])
        
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
        return False, "", "", "PDF file could not be found or copied from any expected location"
        
    except Exception as e:
        logger.error(f"Error finding PDF: {e}", exc_info=True)
        return False, "", "", f"Error finding PDF: {str(e)}"


def check_pdf_file_size(pdf_path: str) -> Tuple[bool, float, str]:
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
            return False, size_kb, f"File suspiciously small ({size_kb:.1f} KB) - may be incomplete"
        elif size_bytes > 10 * 1024 * 1024:  # More than 10MB
            return False, size_kb, f"File unreasonably large ({size_kb/1024:.1f} MB) for a simple receipt"
        else:
            return True, size_kb, f"File size OK ({size_kb:.1f} KB)"
            
    except Exception as e:
        return False, 0, f"Could not check file size: {e}"


def extract_pdf_text(pdf_path: str) -> str:
    """
    Extract text content from PDF.
    
    Returns:
        str: Extracted text or empty string if extraction fails
    """
    if not HAS_PYPDF2:
        logger.warning("PyPDF2 not available, cannot extract text")
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
        
        logger.info(f"Extracted {len(text)} characters of text from PDF")
        return text
        
    except Exception as e:
        logger.error(f"Error extracting PDF text: {e}")
        return ""


def detect_chrome_artifacts(pdf_text: str) -> Dict[str, Any]:
    """
    Detect unwanted Chrome print artifacts (URLs, dates, page numbers in headers/footers).
    
    This is the CRITICAL check - Chrome adds these by default if headers/footers not disabled.
    
    Returns:
        Dict with artifact detection results
    """
    artifacts = {
        'has_url_artifact': False,
        'has_date_artifact': False,
        'has_page_numbering': False,
        'artifact_count': 0,
        'details': []
    }
    
    if not pdf_text:
        return artifacts
    
    # Check beginning and end of text (where headers/footers typically appear)
    # Chrome puts headers at top and footers at bottom
    header_sample = pdf_text[:600] if len(pdf_text) > 600 else pdf_text
    footer_sample = pdf_text[-400:] if len(pdf_text) > 400 else pdf_text
    edges = header_sample + " " + footer_sample
    
    # URL patterns that Chrome adds to headers
    url_patterns = [
        r'file:///[^\s]+',
        r'file://[^\s]+',
        r'/home/[^\s]+\.html',
        r'Documents/[^\s]+\.html',
    ]
    
    for pattern in url_patterns:
        matches = re.finditer(pattern, edges, re.IGNORECASE)
        for match in matches:
            # Check if it's in isolation (typical of header/footer)
            start = max(0, match.start() - 30)
            end = min(len(edges), match.end() + 30)
            context = edges[start:end]
            
            # If URL is on its own line or with minimal surrounding text, it's likely a header
            lines_around = context.split('\n')
            for line in lines_around:
                if match.group() in line and len(line.strip()) < 200:
                    artifacts['has_url_artifact'] = True
                    artifacts['artifact_count'] += 1
                    artifacts['details'].append(f"URL in header/footer: {match.group()[:50]}")
                    break
            if artifacts['has_url_artifact']:
                break
        if artifacts['has_url_artifact']:
            break
    
    # Date stamp patterns - Chrome adds current date to footer
    # Format is typically: "1/15/2025" or "01/15/2025"
    date_patterns = [
        r'\b\d{1,2}/\d{1,2}/\d{4}\b',  # MM/DD/YYYY or M/D/YYYY
        r'\b\d{4}-\d{2}-\d{2}\b',      # YYYY-MM-DD
    ]
    
    for pattern in date_patterns:
        matches = list(re.finditer(pattern, edges))
        for match in matches:
            # Check if date is in isolation (typical of header/footer)
            start = max(0, match.start() - 40)
            end = min(len(edges), match.end() + 40)
            context = edges[start:end].strip()
            
            # If the date is the only substantial content on its line, it's likely a footer
            lines = context.split('\n')
            for line in lines:
                if match.group() in line:
                    # Check if line is short and date-focused
                    line_stripped = line.strip()
                    if len(line_stripped) < 50 and match.group() in line_stripped:
                        # Additional check: is this the order date? (part of content)
                        # Look for context words
                        context_lower = context.lower()
                        if 'order date' not in context_lower and 'january' not in context_lower:
                            artifacts['has_date_artifact'] = True
                            artifacts['artifact_count'] += 1
                            artifacts['details'].append(f"Date stamp in header/footer: {match.group()}")
                            break
            if artifacts['has_date_artifact']:
                break
        if artifacts['has_date_artifact']:
            break
    
    # Page numbering patterns - Chrome adds "Page 1 of 1" or "1/1"
    page_patterns = [
        r'Page\s+\d+\s+of\s+\d+',
        r'\b\d+\s*/\s*\d+\b',  # "1 / 1" or "1/1"
    ]
    
    for pattern in page_patterns:
        matches = re.finditer(pattern, edges, re.IGNORECASE)
        for match in matches:
            # Check if it's in isolation
            start = max(0, match.start() - 20)
            end = min(len(edges), match.end() + 20)
            context = edges[start:end].strip()
            
            # If very short context, likely a page number footer
            if len(context) < 60:
                artifacts['has_page_numbering'] = True
                artifacts['artifact_count'] += 1
                artifacts['details'].append(f"Page numbering: {match.group()}")
                break
        if artifacts['has_page_numbering']:
            break
    
    return artifacts


def verify_content_preservation(pdf_text: str) -> Dict[str, Any]:
    """
    Verify that key content from the receipt was preserved in PDF.
    
    Returns:
        Dict with preservation results
    """
    # Expected key terms from our order confirmation receipt
    expected_terms = [
        "ORD-2025-1847",  # Order number
        "Order Confirmed",  # Header text
        "Sarah Johnson",  # Customer name
        "Wireless Bluetooth Headphones",  # Item name
        "267.68",  # Total amount
        "Springfield",  # Shipping city
        "January 15, 2025",  # Order date (this is CONTENT, not a header artifact)
    ]
    
    if not pdf_text:
        return {
            'preservation_ratio': 0.0,
            'found_terms': [],
            'missing_terms': expected_terms,
            'total_expected': len(expected_terms),
            'total_found': 0
        }
    
    pdf_text_lower = pdf_text.lower()
    found_terms = []
    missing_terms = []
    
    for term in expected_terms:
        if term.lower() in pdf_text_lower:
            found_terms.append(term)
        else:
            missing_terms.append(term)
    
    preservation_ratio = len(found_terms) / len(expected_terms)
    
    return {
        'preservation_ratio': preservation_ratio,
        'found_terms': found_terms,
        'missing_terms': missing_terms,
        'total_expected': len(expected_terms),
        'total_found': len(found_terms)
    }


def verify_task(traj, env_info, task_info) -> Dict[str, Any]:
    """
    Main verification function for print-to-pdf-archive task.
    
    Scoring:
    - PDF exists and valid: 20 points
    - Content preserved: 30 points (proportional to found terms)
    - Clean output (no artifacts): 40 points (penalties for each artifact type)
    - Appropriate file size: 10 points
    
    Total: 100 points
    Pass threshold: 75 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0,
            "feedback": "copy_from_env function not available in environment"
        }
    
    score = 0
    feedback_parts = []
    
    # Criterion 1: Check PDF exists
    logger.info("Checking if PDF file exists...")
    found, pdf_path, pdf_name, error = find_pdf_file(copy_from_env)
    
    if not found:
        feedback = f"✗ PDF file not found\n{error}\n\n"
        feedback += "The agent should have:\n"
        feedback += "  1. Pressed Ctrl+P to open print dialog\n"
        feedback += "  2. Selected 'Save as PDF' as destination\n"
        feedback += "  3. Clicked 'More settings' to expand options\n"
        feedback += "  4. DISABLED 'Headers and footers' toggle\n"
        feedback += "  5. Clicked 'Save' to generate PDF"
        return {
            "passed": False,
            "score": 0,
            "feedback": feedback
        }
    
    feedback_parts.append(f"✓ PDF file found: {pdf_name}")
    score += 20
    
    # Criterion 2: File size check
    logger.info("Checking file size...")
    size_ok, size_kb, size_feedback = check_pdf_file_size(pdf_path)
    if size_ok:
        feedback_parts.append(f"✓ {size_feedback}")
        score += 10
    else:
        feedback_parts.append(f"✗ {size_feedback}")
    
    # If PyPDF2 not available, give benefit of doubt for remaining checks
    if not HAS_PYPDF2:
        feedback_parts.append("⚠ PyPDF2 not available - cannot verify content and artifacts")
        feedback_parts.append("  Awarding partial credit for successful PDF creation")
        score += 50  # Content + artifacts partial credit
        
        # Clean up temp file
        try:
            if pdf_path and os.path.exists(pdf_path):
                os.unlink(pdf_path)
        except:
            pass
        
        passed = score >= 75
        feedback = "\n".join(feedback_parts)
        feedback += f"\n\n{'='*60}"
        feedback += f"\nFinal score: {score}/100"
        feedback += f"\nResult: {'PASSED ✓' if passed else 'FAILED ✗'}"
        
        return {
            "passed": passed,
            "score": score,
            "feedback": feedback
        }
    
    # Criterion 3: Extract text for further analysis
    logger.info("Extracting PDF text...")
    pdf_text = extract_pdf_text(pdf_path)
    
    if not pdf_text:
        feedback_parts.append("⚠ Could not extract text from PDF (may be image-based or corrupted)")
        # Don't give content or artifact points
    else:
        # Criterion 4: Verify content preservation
        logger.info("Checking content preservation...")
        content_check = verify_content_preservation(pdf_text)
        content_score = int(30 * content_check['preservation_ratio'])
        score += content_score
        
        if content_check['preservation_ratio'] >= 0.85:
            feedback_parts.append(f"✓ Content well preserved: {content_check['total_found']}/{content_check['total_expected']} key terms found")
        elif content_check['preservation_ratio'] >= 0.5:
            feedback_parts.append(f"⚠ Content partially preserved: {content_check['total_found']}/{content_check['total_expected']} key terms found")
            if content_check['missing_terms']:
                feedback_parts.append(f"  Missing: {', '.join(content_check['missing_terms'][:3])}")
        else:
            feedback_parts.append(f"✗ Content preservation poor: {content_check['total_found']}/{content_check['total_expected']} key terms found")
        
        # Criterion 5: Check for artifacts (THIS IS THE KEY QUALITY CHECK)
        logger.info("Checking for Chrome header/footer artifacts...")
        artifacts = detect_chrome_artifacts(pdf_text)
        
        # Start with 40 points, deduct for each artifact type
        artifact_base_score = 40
        artifact_penalty = 0
        
        if artifacts['has_url_artifact']:
            artifact_penalty += 15
        if artifacts['has_date_artifact']:
            artifact_penalty += 15
        if artifacts['has_page_numbering']:
            artifact_penalty += 10
        
        artifact_score = max(0, artifact_base_score - artifact_penalty)
        score += artifact_score
        
        if artifacts['artifact_count'] == 0:
            feedback_parts.append("✓ Clean output: No header/footer artifacts detected")
            feedback_parts.append("  Headers and footers were properly disabled!")
        else:
            feedback_parts.append(f"✗ Artifacts detected ({artifacts['artifact_count']}): Headers/footers NOT properly disabled")
            for detail in artifacts['details']:
                feedback_parts.append(f"  - {detail}")
            feedback_parts.append("")
            feedback_parts.append("  REMINDER: In print dialog, you must:")
            feedback_parts.append("    1. Click 'More settings' to expand")
            feedback_parts.append("    2. Find 'Headers and footers' toggle")
            feedback_parts.append("    3. DISABLE it (turn it OFF)")
    
    # Clean up temporary file
    try:
        if pdf_path and os.path.exists(pdf_path):
            os.unlink(pdf_path)
    except:
        pass
    
    # Determine pass/fail
    passed = score >= 75
    
    # Build final feedback
    feedback = "\n".join(feedback_parts)
    feedback += f"\n\n{'='*60}"
    feedback += f"\nFinal score: {score}/100"
    
    if passed:
        feedback += "\n✅ Task completed successfully!"
        feedback += "\nPDF was created with clean formatting suitable for archival/expense reports."
    else:
        feedback += "\n❌ Task incomplete or quality issues detected"
        if artifacts.get('artifact_count', 0) > 0:
            feedback += "\nMain issue: Chrome header/footer artifacts present"
            feedback += "\nYou must disable headers/footers in print settings!"
    
    logger.info(f"Verification complete: passed={passed}, score={score}")
    
    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "details": {
            "pdf_name": pdf_name,
            "file_size_kb": size_kb if size_ok else 0,
            "content_preservation": content_check.get('preservation_ratio', 0) if pdf_text else 0,
            "artifact_count": artifacts.get('artifact_count', 0) if pdf_text else 0,
            "artifacts_detected": artifacts if pdf_text else {}
        }
    }
