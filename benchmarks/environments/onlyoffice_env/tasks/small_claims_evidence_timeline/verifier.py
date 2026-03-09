#!/usr/bin/env python3
"""
Verifier for Small Claims Evidence Timeline task
"""

import sys
import os
import logging
import tempfile
import re
from datetime import datetime

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_small_claims_evidence_timeline(traj, env_info, task_info):
    """
    Verify that the small claims evidence timeline document was created correctly.

    Checks:
    1. Document exists at specified path
    2. Header contains case information (Silva v. Martinez, case number)
    3. Table exists with evidence entries
    4. Chronological order (dates ascending)
    5. Date formatting (MM/DD/YYYY)
    6. Evidence references present (Photo, Receipt, Screenshot, Invoice)
    7. Summary section with financial amounts
    8. Sufficient number of evidence entries (at least 6 of 8)
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0.0, "feedback": "Copy function not available"}

    container_path = "/home/ga/Documents/TextDocuments/SmallClaims_Evidence_Timeline.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_evidence_')

    try:
        # Copy and parse the document
        success, doc, error = copy_and_parse_document(container_path, copy_from_env, 'docx')

        if not success:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Document not found or couldn't be parsed: {error}"
            }

        feedback_parts = []
        score = 0
        max_checks = 8

        # Get full document text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()

        # Check 1: Header contains case information
        has_evidence_timeline = "evidence timeline" in full_text_lower
        has_silva_martinez = "silva" in full_text_lower and "martinez" in full_text_lower
        has_case_number = "2024-sc-8847" in full_text_lower or "8847" in full_text

        if has_evidence_timeline and has_silva_martinez and has_case_number:
            score += 1
            feedback_parts.append("✅ Document header with case information present")
        else:
            missing = []
            if not has_evidence_timeline:
                missing.append("'Evidence Timeline'")
            if not has_silva_martinez:
                missing.append("'Silva v. Martinez'")
            if not has_case_number:
                missing.append("case number")
            feedback_parts.append(f"❌ Missing header elements: {', '.join(missing)}")

        # Check 2: Table exists
        num_tables = count_tables(doc)
        if num_tables >= 1:
            score += 1
            feedback_parts.append("✅ Evidence table created")

            # Get the table for detailed analysis
            table = doc.tables[0]
            rows = list(table.rows)

            # Check 3: Sufficient number of entries
            # Assuming first row is header, we need at least 6 evidence entries
            num_entries = len(rows) - 1 if len(rows) > 1 else 0
            if num_entries >= 6:
                score += 1
                feedback_parts.append(f"✅ Contains {num_entries} evidence entries (minimum 6 required)")
            else:
                feedback_parts.append(f"❌ Insufficient entries: found {num_entries}, need at least 6")

            # Check 4 & 5: Extract dates and verify chronological order + formatting
            dates_in_table = []
            date_strings = []
            date_pattern_mmddyyyy = r'\b(\d{1,2})[/-](\d{1,2})[/-](\d{4})\b'

            for idx, row in enumerate(rows[1:], start=1):  # Skip header row
                if len(row.cells) > 0:
                    cell_text = row.cells[0].text.strip()
                    date_match = re.search(date_pattern_mmddyyyy, cell_text)
                    if date_match:
                        date_str = date_match.group(0)
                        date_strings.append(date_str)
                        # Try to parse the date
                        try:
                            # Handle both / and - separators
                            for fmt in ['%m/%d/%Y', '%m-%d-%Y', '%-m/%-d/%Y', '%-m-%-d-%Y']:
                                try:
                                    parsed_date = datetime.strptime(date_str.replace('-', '/'), '%m/%d/%Y')
                                    dates_in_table.append(parsed_date)
                                    break
                                except ValueError:
                                    continue
                        except Exception as e:
                            logger.warning(f"Could not parse date '{date_str}': {e}")

            # Check chronological order
            if len(dates_in_table) >= 4:
                is_chronological = all(dates_in_table[i] <= dates_in_table[i+1]
                                      for i in range(len(dates_in_table)-1))
                if is_chronological:
                    score += 1
                    feedback_parts.append(f"✅ Evidence entries in chronological order ({len(dates_in_table)} dates verified)")
                else:
                    # Show which dates are out of order
                    feedback_parts.append(f"❌ Evidence entries not properly sorted by date")
            else:
                feedback_parts.append(f"❌ Could not verify chronological order (only {len(dates_in_table)} valid dates found)")

            # Check date formatting (MM/DD/YYYY with slash)
            properly_formatted_dates = [d for d in date_strings if re.match(r'^\d{2}/\d{2}/\d{4}$', d)]
            if len(properly_formatted_dates) >= 4:
                score += 1
                feedback_parts.append(f"✅ Dates properly formatted as MM/DD/YYYY ({len(properly_formatted_dates)} dates)")
            else:
                feedback_parts.append(f"❌ Dates not consistently formatted (found {len(properly_formatted_dates)} properly formatted)")

            # Check 6: Evidence references present
            evidence_keywords = {
                'receipt': False,
                'photo': False,
                'screenshot': False,
                'invoice': False
            }

            table_text_lower = ""
            for row in rows:
                for cell in row.cells:
                    table_text_lower += cell.text.lower() + " "

            for keyword in evidence_keywords:
                if keyword in table_text_lower:
                    evidence_keywords[keyword] = True

            # Also check for specific evidence markers
            has_zl_receipt = 'zl-' in table_text_lower or 'zl' in table_text_lower
            has_invoice_number = '#4422' in full_text or '4422' in full_text
            has_screenshots = table_text_lower.count('screenshot') >= 2

            evidence_count = sum(evidence_keywords.values())
            if evidence_count >= 3 or (has_zl_receipt and has_invoice_number and has_screenshots):
                score += 1
                feedback_parts.append(f"✅ Evidence references included ({evidence_count} types found)")
            else:
                feedback_parts.append(f"❌ Insufficient evidence references (found {evidence_count}, need at least 3)")

        else:
            feedback_parts.append("❌ No evidence table found")
            # Cannot check further table-based criteria
            feedback_parts.append("❌ Cannot verify chronological order without table")
            feedback_parts.append("❌ Cannot verify date formatting without table")
            feedback_parts.append("❌ Cannot verify evidence references without table")

        # Check 7: Summary section with financial amounts
        # Look for the key amounts: $3,500 (paid and claimed) and $2,800 (completion cost)
        has_3500 = ('3,500' in full_text or '3500' in full_text or '$3,500' in full_text)
        has_2800 = ('2,800' in full_text or '2800' in full_text or '$2,800' in full_text)

        # Look for summary-related keywords
        has_summary_keywords = any(keyword in full_text_lower for keyword in
                                   ['total paid', 'cost to complete', 'amount claimed', 'summary'])

        if (has_3500 and has_2800) or (has_summary_keywords and (has_3500 or has_2800)):
            score += 1
            feedback_parts.append("✅ Summary section with financial amounts present")
        else:
            feedback_parts.append("❌ Missing summary section with amounts ($3,500 and $2,800)")

        # Check 8: Document structure quality (has meaningful content beyond just numbers)
        # Verify key events are mentioned
        key_events = {
            'contract': 'contract' in full_text_lower or 'signed' in full_text_lower,
            'payment': 'payment' in full_text_lower or 'paid' in full_text_lower or 'zelle' in full_text_lower,
            'work_stopped': 'stopped' in full_text_lower or 'delay' in full_text_lower,
            'new_contractor': 'hired' in full_text_lower or 'new contractor' in full_text_lower or 'complete' in full_text_lower
        }

        events_mentioned = sum(key_events.values())
        if events_mentioned >= 3:
            score += 1
            feedback_parts.append(f"✅ Document contains key event descriptions ({events_mentioned}/4)")
        else:
            feedback_parts.append(f"❌ Missing key event descriptions ({events_mentioned}/4 found)")

        # Calculate final score
        normalized_score = score / max_checks
        passed = score >= 6  # Need 6 out of 8 checks to pass

        feedback = " | ".join(feedback_parts)
        feedback += f" || Final Score: {score}/{max_checks}"

        return {
            "passed": passed,
            "score": normalized_score,
            "feedback": feedback
        }

    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0.0,
            "feedback": f"❌ Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)
