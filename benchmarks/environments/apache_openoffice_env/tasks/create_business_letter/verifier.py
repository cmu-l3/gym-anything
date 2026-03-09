#!/usr/bin/env python3
"""Verifier for create_business_letter task.

This verifier checks that a business letter was created with:
1. Proper structure (letterhead -> date -> recipient -> salutation -> body -> closing -> signature)
2. Correct company data (Red Hat, IBM, real executives)
3. Minimum content requirements (body length, address presence)
"""

import json
import tempfile
import os
import re
import logging
import zipfile

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def extract_odt_text(odt_path: str) -> str:
    """Extract text content from an ODT file."""
    try:
        with zipfile.ZipFile(odt_path, 'r') as zf:
            content_xml = zf.read('content.xml').decode('utf-8')
            # Remove XML tags to get plain text
            text = re.sub(r'<[^>]+>', ' ', content_xml)
            # Clean up whitespace
            text = re.sub(r'\s+', ' ', text).strip()
            return text
    except Exception as e:
        logger.warning(f"Failed to extract ODT text: {e}")
        return ""


def check_letter_structure(text: str) -> dict:
    """
    Check that the letter has proper structure with elements in correct order.
    Returns dict with structure analysis results.
    """
    text_lower = text.lower()

    # Find positions of key elements
    positions = {}

    # Sender company (Red Hat)
    red_hat_match = re.search(r'red\s*hat', text_lower)
    if red_hat_match:
        positions['sender_company'] = red_hat_match.start()

    # Sender address (Raleigh or Davie Street)
    sender_addr_match = re.search(r'(raleigh|davie\s*street|nc\s*27601)', text_lower)
    if sender_addr_match:
        positions['sender_address'] = sender_addr_match.start()

    # Date (February 2026)
    date_match = re.search(r'february\s*\d+,?\s*2026', text_lower)
    if date_match:
        positions['date'] = date_match.start()

    # Recipient name (Arvind Krishna)
    recipient_match = re.search(r'(arvind|krishna)', text_lower)
    if recipient_match:
        positions['recipient_name'] = recipient_match.start()

    # Recipient company (IBM) - use word boundary to avoid matching substrings
    ibm_match = re.search(r'\bibm\b', text_lower)
    if ibm_match:
        positions['recipient_company'] = ibm_match.start()

    # Recipient address (Armonk or New Orchard)
    recipient_addr_match = re.search(r'(armonk|new\s*orchard|ny\s*10504)', text_lower)
    if recipient_addr_match:
        positions['recipient_address'] = recipient_addr_match.start()

    # Salutation (Dear Mr. Krishna)
    salutation_match = re.search(r'dear\s+mr\.?\s+krishna', text_lower)
    if salutation_match:
        positions['salutation'] = salutation_match.start()
        positions['salutation_end'] = salutation_match.end()

    # Closing (Respectfully) - must appear AFTER salutation
    closing_match = re.search(r'respectfully', text_lower)
    if closing_match:
        positions['closing'] = closing_match.start()

    # Signer (Matt Hicks)
    signer_match = re.search(r'matt\s*hicks', text_lower)
    if signer_match:
        positions['signer'] = signer_match.start()

    # Check structural order
    structure_valid = True
    order_issues = []

    # Expected order: sender -> date -> recipient -> salutation -> closing -> signer
    expected_order = [
        ('sender_company', 'date'),
        ('date', 'recipient_name'),
        ('recipient_name', 'salutation'),
        ('salutation', 'closing'),
        ('closing', 'signer'),
    ]

    for first, second in expected_order:
        if first in positions and second in positions:
            if positions[first] > positions[second]:
                structure_valid = False
                order_issues.append(f"{first} appears after {second}")
        elif first not in positions or second not in positions:
            # If critical elements are missing, note it but don't mark as order issue
            pass

    # Additional check: closing must appear after salutation (positional validation)
    closing_after_salutation = True
    if 'salutation' in positions and 'closing' in positions:
        if positions['closing'] <= positions.get('salutation_end', positions['salutation']):
            closing_after_salutation = False
            if 'salutation appears after closing' not in order_issues:
                order_issues.append("closing not in proper position after body")

    return {
        'positions': positions,
        'structure_valid': structure_valid and closing_after_salutation,
        'order_issues': order_issues,
        'elements_found': [k for k in positions.keys() if k != 'salutation_end'],
        'closing_after_salutation': closing_after_salutation
    }


def check_body_content(text: str) -> dict:
    """
    Check that the letter body has sufficient content about the right topic.
    """
    text_lower = text.lower()

    # Find body section (between salutation and closing)
    salutation_match = re.search(r'dear\s+mr\.?\s+krishna[,.]?', text_lower)
    closing_match = re.search(r'respectfully[,.]?', text_lower)

    if not salutation_match or not closing_match:
        return {
            'body_found': False,
            'body_length': 0,
            'sentence_count': 0,
            'topic_relevant': False,
            'closing_position_valid': False
        }

    # Validate that closing appears AFTER salutation
    if closing_match.start() <= salutation_match.end():
        return {
            'body_found': False,
            'body_length': 0,
            'sentence_count': 0,
            'topic_relevant': False,
            'closing_position_valid': False,
            'error': 'closing appears before or at salutation'
        }

    body_start = salutation_match.end()
    body_end = closing_match.start()
    body_text = text[body_start:body_end].strip()

    # Count sentences (rough approximation)
    sentences = re.split(r'[.!?]+', body_text)
    sentences = [s.strip() for s in sentences if len(s.strip()) > 10]

    # Check for topic relevance (open source, collaboration, enterprise, Linux, cloud)
    topic_keywords = ['open source', 'collaboration', 'enterprise', 'linux', 'cloud',
                      'kubernetes', 'container', 'partnership', 'technology', 'software']
    topic_count = sum(1 for kw in topic_keywords if kw in body_text.lower())

    return {
        'body_found': True,
        'body_length': len(body_text),
        'word_count': len(body_text.split()),
        'sentence_count': len(sentences),
        'topic_relevant': topic_count >= 2,
        'topic_keywords_found': topic_count,
        'closing_position_valid': True
    }


def check_closing_position(text: str) -> dict:
    """
    Verify that "Respectfully" appears in the correct position as a closing,
    not just anywhere in the document (e.g., in the body).

    Returns dict with closing validation results.
    """
    text_lower = text.lower()

    # Find salutation position
    salutation_match = re.search(r'dear\s+mr\.?\s+krishna[,.]?', text_lower)

    # Find ALL occurrences of "respectfully"
    respectfully_matches = list(re.finditer(r'respectfully', text_lower))

    if not respectfully_matches:
        return {
            'closing_found': False,
            'closing_valid': False,
            'error': 'No "Respectfully" found'
        }

    if not salutation_match:
        return {
            'closing_found': True,
            'closing_valid': False,
            'error': 'No salutation found to validate closing position'
        }

    # Find the signer (Matt Hicks) position
    signer_match = re.search(r'matt\s*hicks', text_lower)

    # The valid closing should be:
    # 1. After the salutation
    # 2. Before the signer (if signer exists)
    # 3. Not part of a sentence in the body (check if preceded by sentence-ending punctuation or newline-like content)

    valid_closing = None
    for match in respectfully_matches:
        closing_pos = match.start()

        # Must be after salutation
        if closing_pos <= salutation_match.end():
            continue

        # If signer exists, must be before signer
        if signer_match and closing_pos >= signer_match.start():
            continue

        # Check context: closing should typically be preceded by blank line or end of sentence
        # and followed by comma or nothing significant before signer
        preceding_text = text[max(0, closing_pos - 50):closing_pos].lower()
        following_text = text_lower[match.end():match.end() + 20]

        # Valid closing patterns:
        # - Preceded by period/newline-equivalent and whitespace
        # - Followed by comma and/or whitespace and then signature block
        is_preceded_properly = bool(re.search(r'[.!?\s]{2,}$', preceding_text) or
                                    preceding_text.strip().endswith('.') or
                                    preceding_text.strip().endswith('!') or
                                    preceding_text.strip().endswith('?'))
        is_followed_properly = bool(re.match(r'[,.]?\s*$', following_text[:5]) or
                                    re.match(r'[,.]?\s+\w', following_text))

        if is_preceded_properly:
            valid_closing = match
            break

    if valid_closing:
        return {
            'closing_found': True,
            'closing_valid': True,
            'closing_position': valid_closing.start()
        }
    else:
        return {
            'closing_found': True,
            'closing_valid': False,
            'error': '"Respectfully" found but not in valid closing position'
        }


def verify_business_letter(traj, env_info, task_info):
    """
    Verify that a business letter was created correctly with proper structure
    and real company data.

    Checks:
    1. Output file exists and has reasonable size
    2. Contains sender company (Red Hat, Inc.) with address
    3. Contains recipient (Arvind Krishna, IBM) with address
    4. Contains proper date format
    5. Contains proper salutation (Dear Mr. Krishna)
    6. Contains proper closing (Respectfully) IN CORRECT POSITION
    7. Contains signer (Matt Hicks)
    8. Letter has proper structural order
    9. Body has sufficient content (3+ sentences, topic relevant)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_file = metadata.get('output_file', '/home/ga/Documents/partnership_letter.odt')

    criteria_results = {}
    feedback_parts = []

    # First, try to read the task result JSON
    temp_json = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_json.name)
        with open(temp_json.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        logger.warning(f"Failed to read task result JSON: {e}")
        result = {}
    finally:
        if os.path.exists(temp_json.name):
            os.unlink(temp_json.name)

    file_found = result.get('file_found', False)
    file_path = result.get('file_path', '')
    file_size = result.get('file_size_bytes', 0)
    doc_preview = result.get('document_content_preview', '')

    # === CRITERION 1: File exists ===
    if file_found:
        criteria_results['file_exists'] = True
        feedback_parts.append(f"File created: {os.path.basename(file_path)}")
    else:
        criteria_results['file_exists'] = False
        feedback_parts.append("File NOT created")
        return {
            "passed": False,
            "score": 0,
            "feedback": " | ".join(feedback_parts) + " | Cannot verify without file",
            "criteria_results": criteria_results
        }

    # === CRITERION 2: File has reasonable size (at least 5KB for a proper letter) ===
    if file_size >= 5000:
        criteria_results['file_size'] = True
        feedback_parts.append(f"File size: {file_size} bytes")
    else:
        criteria_results['file_size'] = False
        feedback_parts.append(f"File too small: {file_size} bytes (expected >= 5000)")

    # Try to get full document text by copying file directly
    document_text = doc_preview
    if file_path:
        temp_doc = tempfile.NamedTemporaryFile(delete=False, suffix='.odt')
        try:
            copy_from_env(expected_file, temp_doc.name)
            document_text = extract_odt_text(temp_doc.name)
        except Exception as e:
            logger.warning(f"Failed to copy/extract document: {e}")
        finally:
            if os.path.exists(temp_doc.name):
                os.unlink(temp_doc.name)

    if not document_text:
        return {
            "passed": False,
            "score": 12,  # Only file exists criterion passed
            "feedback": "Could not extract document content",
            "criteria_results": criteria_results
        }

    document_text_lower = document_text.lower()

    # === CRITERION 3: Contains sender company (Red Hat, Inc.) ===
    if re.search(r'red\s*hat', document_text_lower):
        criteria_results['sender_company'] = True
        feedback_parts.append("Sender: Red Hat found")
    else:
        criteria_results['sender_company'] = False
        feedback_parts.append("Sender: Red Hat NOT found")

    # === CRITERION 4: Contains sender address (Raleigh, NC / Davie Street) ===
    if re.search(r'(raleigh|davie\s*street|nc\s*27601)', document_text_lower):
        criteria_results['sender_address'] = True
        feedback_parts.append("Sender address found")
    else:
        criteria_results['sender_address'] = False
        feedback_parts.append("Sender address NOT found")

    # === CRITERION 5: Contains recipient name (Arvind Krishna) ===
    if re.search(r'arvind.*krishna|krishna.*arvind|mr\.?\s*krishna', document_text_lower):
        criteria_results['recipient_name'] = True
        feedback_parts.append("Recipient: Arvind Krishna found")
    else:
        criteria_results['recipient_name'] = False
        feedback_parts.append("Recipient: Arvind Krishna NOT found")

    # === CRITERION 6: Contains recipient company (IBM Corporation) ===
    # Use word boundary regex to avoid matching substrings like "climbing"
    if re.search(r'\bibm\b', document_text_lower):
        criteria_results['recipient_company'] = True
        feedback_parts.append("IBM Corporation found")
    else:
        criteria_results['recipient_company'] = False
        feedback_parts.append("IBM Corporation NOT found")

    # === CRITERION 7: Contains recipient address (Armonk, NY) ===
    if re.search(r'(armonk|new\s*orchard|ny\s*10504)', document_text_lower):
        criteria_results['recipient_address'] = True
        feedback_parts.append("Recipient address found")
    else:
        criteria_results['recipient_address'] = False
        feedback_parts.append("Recipient address NOT found")

    # === CRITERION 8: Contains date (February 2026) ===
    if re.search(r'february\s*\d+,?\s*2026', document_text_lower):
        criteria_results['date'] = True
        feedback_parts.append("Date found")
    else:
        criteria_results['date'] = False
        feedback_parts.append("Date NOT found (expected February X, 2026)")

    # === CRITERION 9: Contains proper salutation (Dear Mr. Krishna) ===
    if re.search(r'dear\s+mr\.?\s+krishna', document_text_lower):
        criteria_results['salutation'] = True
        feedback_parts.append("Salutation found")
    else:
        criteria_results['salutation'] = False
        feedback_parts.append("Salutation NOT found (expected Dear Mr. Krishna)")

    # === CRITERION 10: Contains proper closing (Respectfully) IN CORRECT POSITION ===
    # Use positional validation to ensure "Respectfully" is actually a closing,
    # not just appearing anywhere in the document (e.g., "I respectfully submit...")
    closing_check = check_closing_position(document_text)
    if closing_check['closing_found'] and closing_check['closing_valid']:
        criteria_results['closing'] = True
        feedback_parts.append("Closing found in valid position")
    else:
        criteria_results['closing'] = False
        if not closing_check['closing_found']:
            feedback_parts.append("Closing NOT found (expected Respectfully)")
        else:
            feedback_parts.append(f"Closing invalid: {closing_check.get('error', 'not in proper position')}")

    # === CRITERION 11: Contains signer (Matt Hicks) ===
    if re.search(r'matt\s*hicks', document_text_lower):
        criteria_results['signer'] = True
        feedback_parts.append("Signer: Matt Hicks found")
    else:
        criteria_results['signer'] = False
        feedback_parts.append("Signer: Matt Hicks NOT found")

    # === CRITERION 12: Letter has proper structural order ===
    structure = check_letter_structure(document_text)
    # Require at least 7 elements found (not 6) to strengthen structure validation
    if structure['structure_valid'] and len(structure['elements_found']) >= 7:
        criteria_results['structure'] = True
        feedback_parts.append("Letter structure valid")
    else:
        criteria_results['structure'] = False
        if structure['order_issues']:
            feedback_parts.append(f"Structure issues: {', '.join(structure['order_issues'])}")
        else:
            feedback_parts.append(f"Structure incomplete: only {len(structure['elements_found'])} elements found (need 7+)")

    # === CRITERION 13: Body has sufficient content ===
    body_check = check_body_content(document_text)
    if body_check['body_found'] and body_check['sentence_count'] >= 3 and body_check['topic_relevant']:
        criteria_results['body_content'] = True
        feedback_parts.append(f"Body: {body_check['sentence_count']} sentences, topic relevant")
    else:
        criteria_results['body_content'] = False
        if not body_check['body_found']:
            feedback_parts.append("Body section not found")
        elif body_check['sentence_count'] < 3:
            feedback_parts.append(f"Body too short: {body_check['sentence_count']} sentences (need 3+)")
        else:
            feedback_parts.append("Body not topic-relevant (missing collaboration/technology keywords)")

    # Calculate score
    total_criteria = len(criteria_results)
    criteria_passed = sum(1 for v in criteria_results.values() if v)
    score = int((criteria_passed / total_criteria) * 100)

    # Pass requires:
    # - At least 11 of 13 criteria (85%)
    # - MUST include: file_exists, sender_company, recipient_name, salutation, closing, signer, structure
    required_criteria = ['file_exists', 'sender_company', 'recipient_name', 'salutation', 'closing', 'signer', 'structure']
    required_passed = all(criteria_results.get(c, False) for c in required_criteria)

    passed = criteria_passed >= 11 and required_passed

    feedback = " | ".join(feedback_parts)

    return {
        "passed": passed,
        "score": score,
        "feedback": feedback,
        "criteria_passed": criteria_passed,
        "total_criteria": total_criteria,
        "criteria_results": criteria_results,
        "required_criteria_met": required_passed
    }
