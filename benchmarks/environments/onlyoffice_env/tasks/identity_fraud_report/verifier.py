#!/usr/bin/env python3
"""
Verifier for Identity Fraud Report task

Verifies that the agent created a professional, comprehensive fraud report
with all required sections, transactions, formatting, and details.
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    check_text_formatting,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_identity_fraud_report(traj, env_info, task_info):
    """
    Verify the identity fraud report document
    
    Scoring breakdown (100 points total, 70 to pass):
    - File exists and valid: 10 points
    - Header with title/account/name: 10 points
    - All 5 transactions: 25 points (5 each)
    - Total amount: 5 points
    - Timeline: 15 points
    - Last legitimate transaction: 5 points
    - Declaration: 5 points
    - Professional tone: 5 points
    - Title formatting: 5 points
    - Section headings: 7 points
    - Emphasis (dates/amounts): 8 points
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    doc_path = "/home/ga/Documents/TextDocuments/fraud_report.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_fraud_')
    
    score = 0
    max_score = 100
    feedback_parts = []
    
    try:
        # Copy and parse document
        success, doc, error = copy_and_parse_document(doc_path, copy_from_env, 'docx')
        
        if not success:
            return {
                "passed": False,
                "score": 0,
                "feedback": f"Failed to load document: {error}"
            }
        
        # File exists and is valid (10 points)
        score += 10
        feedback_parts.append("✅ Document exists and is valid DOCX format")
        
        # Extract full text for content checking
        full_text = get_document_text(doc).lower()
        
        # ===== CONTENT VERIFICATION (70 points) =====
        
        # 1. Header section (10 points)
        header_score = 0
        if "fraud report" in full_text or "fraud statement" in full_text:
            header_score += 3
            feedback_parts.append("✅ Document title present")
        else:
            feedback_parts.append("❌ Missing formal fraud report title")
            
        if "7834" in full_text:
            header_score += 3
            feedback_parts.append("✅ Credit card account number included")
        else:
            feedback_parts.append("❌ Missing credit card account number (7834)")
            
        if "alex rivera" in full_text:
            header_score += 4
            feedback_parts.append("✅ Cardholder name included")
        else:
            feedback_parts.append("❌ Missing cardholder name (Alex Rivera)")
            
        score += header_score
        
        # 2. All five fraudulent transactions (25 points - 5 each)
        transactions_found = 0
        
        # Transaction 1: GameStopPlus $249.99
        if ("gamestop" in full_text or "game stop" in full_text) and "249" in full_text:
            score += 5
            transactions_found += 1
            feedback_parts.append("✅ GameStopPlus transaction ($249.99)")
        else:
            feedback_parts.append("❌ Missing GameStopPlus ($249.99, May 19)")
        
        # Transaction 2: Premium_Kicks_NYC $389.00
        if (("premium" in full_text and "kick" in full_text) or "premium_kicks" in full_text or "premiumkicks" in full_text) and "389" in full_text:
            score += 5
            transactions_found += 1
            feedback_parts.append("✅ Premium_Kicks_NYC transaction ($389.00)")
        else:
            feedback_parts.append("❌ Missing Premium_Kicks_NYC ($389.00, May 19)")
        
        # Transaction 3: DigiKeys Electronics $156.43
        if (("digikey" in full_text or "electronics" in full_text) and "156" in full_text):
            score += 5
            transactions_found += 1
            feedback_parts.append("✅ DigiKeys Electronics transaction ($156.43)")
        else:
            feedback_parts.append("❌ Missing DigiKeys Electronics ($156.43, May 20)")
        
        # Transaction 4: FastGas Station $75.00
        if (("fastgas" in full_text or "fast gas" in full_text or "gas station" in full_text) and "75" in full_text):
            score += 5
            transactions_found += 1
            feedback_parts.append("✅ FastGas Station transaction ($75.00)")
        else:
            feedback_parts.append("❌ Missing FastGas Station ($75.00, May 21)")
        
        # Transaction 5: LuxuryFragrance.com $212.88
        if (("luxury" in full_text and "fragrance" in full_text) or "luxuryfragrance" in full_text) and "212" in full_text:
            score += 5
            transactions_found += 1
            feedback_parts.append("✅ LuxuryFragrance.com transaction ($212.88)")
        else:
            feedback_parts.append("❌ Missing LuxuryFragrance.com ($212.88, May 21)")
        
        # 3. Total fraudulent amount (5 points)
        if "1,083" in full_text or "1083" in full_text:
            score += 5
            feedback_parts.append("✅ Total fraudulent amount ($1,083.30)")
        else:
            feedback_parts.append("❌ Missing total amount ($1,083.30)")
        
        # 4. Timeline of response (15 points)
        timeline_score = 0
        
        # Discovery time
        if ("may 22" in full_text or "may 22nd" in full_text or "5/22" in full_text) and ("7:15" in full_text or "715" in full_text or "morning" in full_text or "email" in full_text or "discovered" in full_text):
            timeline_score += 3
            feedback_parts.append("✅ Discovery time documented")
        else:
            feedback_parts.append("⚠️ Should include discovery time (May 22)")
        
        # Bank reference number
        full_text_no_space = full_text.replace(" ", "").replace("_", "").replace("-", "")
        if "fr202405" in full_text_no_space and "8834" in full_text:
            timeline_score += 4
            feedback_parts.append("✅ Bank reference number included")
        elif "8834" in full_text:
            timeline_score += 2
            feedback_parts.append("⚠️ Reference number partial (8834)")
        else:
            feedback_parts.append("❌ Missing reference number (FR-2024-05-8834)")
        
        # Card deactivation
        if "deactivated" in full_text or "deactivate" in full_text or "blocked" in full_text or "canceled" in full_text:
            timeline_score += 3
            feedback_parts.append("✅ Card deactivation noted")
        else:
            feedback_parts.append("⚠️ Should mention card deactivation")
        
        # Response actions
        actions_count = 0
        if "dispute" in full_text or "filed" in full_text:
            actions_count += 1
        if "password" in full_text:
            actions_count += 1
        if "credit bureau" in full_text or "fraud alert" in full_text:
            actions_count += 1
        
        if actions_count >= 2:
            timeline_score += 5
            feedback_parts.append("✅ Response actions documented")
        elif actions_count >= 1:
            timeline_score += 2
            feedback_parts.append("⚠️ Some actions mentioned")
        else:
            feedback_parts.append("❌ Missing response actions")
        
        score += timeline_score
        
        # 5. Last legitimate transaction (5 points)
        if ("safeway" in full_text or "grocery" in full_text) and ("87" in full_text) and ("may 18" in full_text or "5/18" in full_text):
            score += 5
            feedback_parts.append("✅ Last legitimate transaction documented")
        elif ("safeway" in full_text or "grocery" in full_text) or ("may 18" in full_text and "87" in full_text):
            score += 3
            feedback_parts.append("⚠️ Last transaction partially mentioned")
        else:
            feedback_parts.append("❌ Missing last legitimate transaction")
        
        # 6. Declaration/signature section (5 points)
        has_declaration = any(word in full_text for word in ["declare", "declaration", "perjury", "truthful", "accurate", "certify"])
        has_signature = any(word in full_text for word in ["signed", "signature", "sign:", "date:"])
        
        if has_declaration and has_signature:
            score += 5
            feedback_parts.append("✅ Declaration and signature section")
        elif has_declaration or has_signature:
            score += 3
            feedback_parts.append("⚠️ Partial declaration/signature")
        else:
            feedback_parts.append("❌ Missing declaration/signature")
        
        # 7. Professional tone and completeness (5 points)
        word_count = len(full_text.split())
        formal_words = sum(1 for word in ["unauthorized", "investigation", "statement", "request", "reversal", "formal"] if word in full_text)
        
        if word_count > 400 and formal_words >= 3:
            score += 5
            feedback_parts.append("✅ Professional and complete")
        elif word_count > 300 and formal_words >= 2:
            score += 3
            feedback_parts.append("⚠️ Reasonable content")
        elif word_count > 200:
            score += 2
            feedback_parts.append("⚠️ Brief content")
        else:
            feedback_parts.append("❌ Too brief or unprofessional")
        
        # ===== FORMATTING VERIFICATION (20 points) =====
        
        # 8. Title formatting - bold (5 points)
        title_bold = (check_text_formatting(doc, "FRAUD REPORT", bold=True) or
                     check_text_formatting(doc, "fraud report", bold=True) or
                     check_text_formatting(doc, "FRAUD STATEMENT", bold=True) or
                     check_text_formatting(doc, "fraud statement", bold=True))
        
        if title_bold:
            score += 5
            feedback_parts.append("✅ Title is bold")
        else:
            feedback_parts.append("❌ Title should be bold")
        
        # 9. Section headings formatted (7 points)
        headings = ["fraud", "transaction", "timeline", "declaration", "statement", "unauthorized", "discovery", "response", "personal"]
        bold_headings = sum(1 for h in headings if check_text_formatting(doc, h, bold=True))
        
        if bold_headings >= 3:
            score += 7
            feedback_parts.append("✅ Section headings bold")
        elif bold_headings >= 2:
            score += 4
            feedback_parts.append("⚠️ Some headings bold")
        elif bold_headings >= 1:
            score += 2
            feedback_parts.append("⚠️ Minimal heading formatting")
        else:
            feedback_parts.append("❌ Headings should be bold")
        
        # 10. Emphasis on key information (8 points)
        dates = ["May 19", "May 20", "May 21", "May 22", "May 23"]
        bold_dates = sum(1 for d in dates if check_text_formatting(doc, d, bold=True))
        
        total_bold = (check_text_formatting(doc, "1,083", bold=True) or
                     check_text_formatting(doc, "1083", bold=True) or
                     check_text_formatting(doc, "Total", bold=True))
        
        emphasis_score = 0
        if bold_dates >= 3:
            emphasis_score += 5
            feedback_parts.append("✅ Dates formatted (bold)")
        elif bold_dates >= 1:
            emphasis_score += 2
            feedback_parts.append("⚠️ Some dates bold")
        else:
            feedback_parts.append("⚠️ Dates should be bold")
        
        if total_bold:
            emphasis_score += 3
            feedback_parts.append("✅ Total amount emphasized")
        else:
            feedback_parts.append("⚠️ Total should be bold")
        
        score += emphasis_score
        
        # ===== FINAL EVALUATION =====
        
        passed = score >= 70
        
        feedback = " | ".join(feedback_parts)
        
        return {
            "passed": passed,
            "score": score / max_score,
            "feedback": f"Score: {score}/{max_score}. {feedback}"
        }
        
    except Exception as e:
        logger.error(f"Verification error: {e}", exc_info=True)
        return {
            "passed": False,
            "score": 0,
            "feedback": f"Verification error: {str(e)}"
        }
    finally:
        cleanup_temp_dir(temp_dir)