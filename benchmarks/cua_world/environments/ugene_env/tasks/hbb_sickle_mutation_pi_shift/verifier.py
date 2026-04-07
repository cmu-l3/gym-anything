#!/usr/bin/env python3
import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def extract_sequence(fasta_text):
    """Extracts purely the sequence string from FASTA format, ignoring header lines and whitespace."""
    lines = fasta_text.strip().split('\n')
    seq = ''.join([line.strip() for line in lines if not line.startswith('>')])
    return seq.upper()

def verify_hbb_sickle_mutation_pi_shift(traj, env_info, task_info):
    """
    Verifies the UGENE HBB mutation and pI calculation task.
    """
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    expected_wt = metadata.get('expected_wt_sequence', '')
    expected_sickle = metadata.get('expected_sickle_sequence', '')

    score = 0
    feedback_parts = []
    
    # Read result exported from the environment
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    task_start = result.get('task_start', 0)

    # ==========================================
    # 1. Check WT sequence extraction (20 pts)
    # ==========================================
    wt_exists = result.get('wt_exists', False)
    if wt_exists:
        wt_mtime = result.get('wt_mtime', 0)
        if wt_mtime >= task_start:
            wt_content = result.get('wt_content', '')
            parsed_wt = extract_sequence(wt_content)
            
            if parsed_wt == expected_wt:
                score += 20
                feedback_parts.append("WT sequence extracted correctly (+20)")
            elif len(parsed_wt) > 100 and (parsed_wt in expected_wt or expected_wt in parsed_wt):
                score += 10
                feedback_parts.append("WT sequence partially matches (+10)")
            else:
                feedback_parts.append("WT sequence does not match human HBB (0)")
        else:
            feedback_parts.append("wt_hbb.fasta was created before task start (Anti-gaming) (0)")
    else:
        feedback_parts.append("wt_hbb.fasta MISSING (0)")

    # ==========================================
    # 2. Check Sickle sequence mutation (30 pts)
    # ==========================================
    sickle_exists = result.get('sickle_exists', False)
    if sickle_exists:
        sickle_mtime = result.get('sickle_mtime', 0)
        if sickle_mtime >= task_start:
            sickle_content = result.get('sickle_content', '')
            parsed_sickle = extract_sequence(sickle_content)
            
            if parsed_sickle == expected_sickle:
                score += 30
                feedback_parts.append("Sickle sequence correctly mutated E7V (+30)")
            elif parsed_sickle == expected_wt:
                feedback_parts.append("Sickle sequence identical to WT, mutation missed (0)")
            elif len(parsed_sickle) == len(expected_wt):
                # Count exact differences if length is correct but sequence isn't perfectly expected_sickle
                diffs = sum(1 for a, b in zip(parsed_sickle, expected_wt) if a != b)
                if diffs == 1 and parsed_sickle[6] == 'V':
                    score += 30
                    feedback_parts.append("Sickle sequence correctly mutated E7V (+30)")
                else:
                    score += 10
                    feedback_parts.append("Sickle sequence has wrong length or incorrect mutations (+10)")
            else:
                feedback_parts.append("Sickle sequence invalid (0)")
        else:
            feedback_parts.append("sickle_hbb.fasta was created before task start (Anti-gaming) (0)")
    else:
        feedback_parts.append("sickle_hbb.fasta MISSING (0)")

    # ==========================================
    # 3. Check Biological Report (50 pts)
    # ==========================================
    report_exists = result.get('report_exists', False)
    if report_exists:
        report_mtime = result.get('report_mtime', 0)
        if report_mtime >= task_start:
            report_content = result.get('report_content', '').lower()
            
            # 3a. MW and pI values reported (20 pts)
            has_mw = bool(re.search(r'15[\.,]\d+|158\d\d|molecular weight|mw', report_content))
            has_pi = bool(re.search(r'6[\.,][789]|7[\.,][012]|isoelectric point|pi', report_content))
            
            if has_mw and has_pi:
                score += 20
                feedback_parts.append("Report contains MW and pI metrics (+20)")
            elif has_mw or has_pi:
                score += 10
                feedback_parts.append("Report contains partial metrics (+10)")
            else:
                feedback_parts.append("Report missing proper MW/pI values (0)")

            # 3b. pI shift logical deduction (15 pts)
            sickle_higher_pi = bool(re.search(r'(sickle|mutant).*higher|(higher|greater|more basic).*(sickle|mutant)|wt.*lower|lower.*wt', report_content))
            if sickle_higher_pi:
                score += 15
                feedback_parts.append("Report correctly concludes Sickle pI is higher (+15)")
            else:
                feedback_parts.append("Report misses correct pI comparison logic (0)")

            # 3c. Electrophoresis migration logic (15 pts)
            wt_faster = bool(re.search(r'(wt|wild[-\s]*type|normal).*faster|faster.*(wt|wild[-\s]*type|normal)|(wt|wild[-\s]*type|normal).*more negative|more negative.*(wt|wild[-\s]*type|normal)', report_content))
            if wt_faster:
                score += 15
                feedback_parts.append("Report correctly identifies WT migrates faster/is more negative (+15)")
            else:
                feedback_parts.append("Report misses electrophoresis migration logic (0)")

        else:
            feedback_parts.append("Report created before task start (Anti-gaming) (0)")
    else:
        feedback_parts.append("charge_analysis_report.txt MISSING (0)")

    # Determine final pass/fail
    passed = score >= 70
    
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }