#!/usr/bin/env python3
"""
Verifier for local_election_guide@1 task
Checks if the voter guide document meets requirements
"""

import sys
import os
import logging
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '../../', 'utils'))
from onlyoffice_verification_utils import (
    copy_and_parse_document,
    get_document_text,
    count_tables,
    cleanup_temp_dir
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_task(traj, env_info, task_info):
    """
    Verify the voter guide document meets all requirements.
    
    Scoring:
    - File exists and valid (10 points)
    - Title presence with relevant keywords (15 points)
    - Table structure: 4+ columns, 4+ rows (20 points)
    - All 3 candidate names present (20 points)
    - At least 3/4 key issues covered (15 points)
    - Bold formatting present (10 points)
    - Footer/context section (10 points)
    
    Total: 100 points
    Passing: 70 points
    
    Returns:
        dict with keys: passed (bool), score (float 0-1), feedback (str)
    """
    
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {
            "passed": False,
            "score": 0.0,
            "feedback": "❌ Copy function not available"
        }

    expected_path = "/home/ga/Documents/TextDocuments/voter_guide.docx"
    temp_dir = tempfile.mkdtemp(prefix='onlyoffice_verify_election_')
    
    feedback_parts = []
    score = 0
    max_score = 100
    
    try:
        # Attempt to copy and parse the document
        success, doc, error = copy_and_parse_document(
            expected_path, 
            copy_from_env, 
            file_format='docx'
        )
        
        if not success or doc is None:
            return {
                "passed": False,
                "score": 0.0,
                "feedback": f"❌ Could not open voter_guide.docx: {error}"
            }
        
        # Criterion 1: File Existence (10 points) - already verified by successful parse
        score += 10
        feedback_parts.append("✅ File exists and is valid DOCX (10/10)")
        
        # Get document text for analysis
        full_text = get_document_text(doc)
        full_text_lower = full_text.lower()
        
        # Log document length for debugging
        logger.info(f"Document has {len(doc.paragraphs)} paragraphs, {len(full_text)} characters")
        
        # Criterion 2: Title Presence (15 points)
        title_score = 0
        has_title = False
        title_keywords = [
            'district 4', 'city council', 'candidate', 
            'comparison', 'election', 'voter guide', 'voter information'
        ]
        
        # Check first few paragraphs for title
        if len(doc.paragraphs) > 0:
            first_three_paras = ' '.join([p.text.lower() for p in doc.paragraphs[:3]])
            
            # Check if any title keyword appears
            matching_keywords = [kw for kw in title_keywords if kw in first_three_paras]
            
            if matching_keywords:
                has_title = True
                title_score = 15
                score += title_score
                feedback_parts.append(f"✅ Document has appropriate title (15/15)")
            else:
                feedback_parts.append(f"❌ Missing or unclear title in first paragraphs (0/15)")
        else:
            feedback_parts.append("❌ Document appears empty (0/15)")
        
        # Criterion 3: Table Structure (20 points)
        table_score = 0
        num_tables = count_tables(doc)
        
        if num_tables >= 1:
            table = doc.tables[0]
            num_cols = len(table.columns)
            num_rows = len(table.rows)
            
            logger.info(f"Table found: {num_cols} columns, {num_rows} rows")
            
            # Check for proper structure
            if num_cols >= 4 and num_rows >= 5:  # 5 = header + 4 content rows
                table_score = 20
                feedback_parts.append(f"✅ Table structure excellent: {num_cols} cols, {num_rows} rows (20/20)")
            elif num_cols >= 4 and num_rows >= 4:  # 4 = header + 3 content rows (partial credit)
                table_score = 15
                feedback_parts.append(f"⚠️ Table structure good: {num_cols} cols, {num_rows} rows (15/20)")
            elif num_cols >= 3 and num_rows >= 3:  # Minimal acceptable
                table_score = 10
                feedback_parts.append(f"⚠️ Table structure minimal: {num_cols} cols, {num_rows} rows (10/20)")
            else:
                feedback_parts.append(f"❌ Table too small: {num_cols} cols, {num_rows} rows (0/20)")
            
            score += table_score
        else:
            feedback_parts.append("❌ No table found in document (0/20)")
        
        # Criterion 4: Candidate Names (20 points)
        candidates = [
            ('Sarah Chen', ['sarah chen', 'sarah', 'chen', 's. chen']),
            ('Miguel Rodriguez', ['miguel rodriguez', 'miguel', 'rodriguez', 'm. rodriguez']),
            ('James Wilson', ['james wilson', 'james', 'wilson', 'j. wilson'])
        ]
        
        candidates_found = 0
        missing_candidates = []
        found_candidates = []
        
        for candidate_name, variations in candidates:
            if any(var in full_text_lower for var in variations):
                candidates_found += 1
                found_candidates.append(candidate_name)
            else:
                missing_candidates.append(candidate_name)
        
        candidate_score = int((candidates_found / 3) * 20)
        score += candidate_score
        
        if candidates_found == 3:
            feedback_parts.append("✅ All three candidates mentioned (20/20)")
        elif candidates_found >= 2:
            feedback_parts.append(f"⚠️ Only {candidates_found}/3 candidates found (missing: {', '.join(missing_candidates)}) ({candidate_score}/20)")
        else:
            feedback_parts.append(f"❌ Only {candidates_found}/3 candidates found ({candidate_score}/20)")
        
        # Criterion 5: Issue Coverage (15 points)
        issues = [
            ('housing/development', ['housing', 'development', 'apartment', 'units', 'density']),
            ('parks', ['parks', 'park funding', 'park budget']),
            ('traffic/transportation', ['traffic', 'transportation', 'transit', 'congestion', 'main st']),
            ('budget/business', ['budget', 'business', 'tax', 'fees', 'permit'])
        ]
        
        issues_found = 0
        found_issue_names = []
        
        for issue_name, keywords in issues:
            if any(kw in full_text_lower for kw in keywords):
                issues_found += 1
                found_issue_names.append(issue_name)
        
        if issues_found >= 4:
            issue_score = 15
            feedback_parts.append(f"✅ Excellent issue coverage: all 4 issues mentioned (15/15)")
        elif issues_found >= 3:
            issue_score = 15
            feedback_parts.append(f"✅ Good issue coverage: {issues_found}/4 issues mentioned (15/15)")
        elif issues_found >= 2:
            issue_score = 10
            feedback_parts.append(f"⚠️ Partial issue coverage: {issues_found}/4 issues ({issue_score}/15)")
        else:
            issue_score = 0
            feedback_parts.append(f"❌ Insufficient issue coverage: {issues_found}/4 issues (0/15)")
        
        score += issue_score
        
        # Criterion 6: Formatting Quality (10 points)
        format_score = 0
        has_bold = False
        
        # Check for bold text in paragraphs
        for para in doc.paragraphs:
            for run in para.runs:
                if run.bold:
                    has_bold = True
                    break
            if has_bold:
                break
        
        # Also check table cells for bold (common for headers)
        if not has_bold and num_tables > 0:
            table = doc.tables[0]
            for row in table.rows:
                for cell in row.cells:
                    for para in cell.paragraphs:
                        for run in para.runs:
                            if run.bold:
                                has_bold = True
                                break
                        if has_bold:
                            break
                    if has_bold:
                        break
                if has_bold:
                    break
        
        if has_bold:
            format_score = 10
            feedback_parts.append("✅ Document has formatting (bold text found) (10/10)")
        else:
            feedback_parts.append("❌ No bold formatting detected (0/10)")
        
        score += format_score
        
        # Criterion 7: Footer/Context Section (10 points)
        context_score = 0
        has_context = False
        context_keywords = [
            'election', 'voting', 'vote', 'november', 'campaign', 
            'forum', 'debate', 'ballot', 'materials', 'sources'
        ]
        
        # Check last several paragraphs for context
        if len(doc.paragraphs) > 2:
            last_paras = ' '.join([p.text.lower() for p in doc.paragraphs[-5:]])
            
            matching_context = [kw for kw in context_keywords if kw in last_paras]
            
            if matching_context:
                has_context = True
                context_score = 10
                feedback_parts.append("✅ Context/footer information present (10/10)")
            else:
                # Check if context keywords appear anywhere in document
                matching_anywhere = [kw for kw in context_keywords if kw in full_text_lower]
                if matching_anywhere:
                    context_score = 5
                    feedback_parts.append("⚠️ Election context mentioned but not in footer section (5/10)")
                else:
                    feedback_parts.append("❌ No election context or voting information (0/10)")
        else:
            feedback_parts.append("❌ Document too short to have footer section (0/10)")
        
        score += context_score
        
        # Calculate final result
        normalized_score = score / max_score
        passed = score >= 70
        
        # Build final feedback
        summary = f"Score: {score}/{max_score} ({int(normalized_score * 100)}%)"
        if passed:
            summary += " ✅ PASSED"
        else:
            summary += " ❌ FAILED (need 70+)"
        
        feedback = summary + " | " + " | ".join(feedback_parts)
        
        logger.info(f"Verification complete: {summary}")
        
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


# Entry point for gym-anything
