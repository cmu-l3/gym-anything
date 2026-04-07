#!/usr/bin/env python3
"""
Verifier for insulin_antisense_probe_design task.

Scores out of 100 based on exact string matching, molecular biology operations (reverse complement),
and report content verification.

Scoring breakdown:
- Sense FASTA exists and valid DNA: 12 pts
- Antisense FASTA exists and valid DNA: 12 pts
- CDS length plausible (100-500nt): 10 pts
- Sense and antisense lengths match: 8 pts
- Exact Reverse Complement Correct: 20 pts (CRITICAL)
- Report file exists: 5 pts
- Report contains accurate CDS length: 8 pts
- Report contains accurate computed GC%: 10 pts
- Report contains first 30nt of both strands: 8 pts
- Report contains hybridization note: 7 pts

Total: 100 points
Pass threshold: 60 points, requiring reverse complement correctness.
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def reverse_complement(seq):
    """Generate the exact reverse complement of a DNA sequence."""
    complement = {'A': 'T', 'C': 'G', 'G': 'C', 'T': 'A', 'N': 'N'}
    return "".join(complement.get(base, base) for base in reversed(seq.upper()))


def verify_insulin_antisense_probe_design(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    metadata = task_info.get('metadata', {})
    min_len = metadata.get('expected_cds_min_len', 100)
    max_len = metadata.get('expected_cds_max_len', 500)

    # 1. Read exported results
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    sense_seq = result.get('sense_seq', '').upper()
    antisense_seq = result.get('antisense_seq', '').upper()
    report_text = result.get('report_text', '')
    
    # Validation helpers
    is_valid_dna = lambda s: bool(s) and set(s).issubset(set('ACGTN'))

    # Criterion 1: Sense FASTA exists and valid (12 pts)
    c1 = 0
    if result.get('sense_exists') and is_valid_dna(sense_seq):
        c1 = 12
        feedback_parts.append("Sense FASTA exists with valid DNA")
    elif result.get('sense_exists'):
        c1 = 4
        feedback_parts.append("Sense FASTA exists but contains invalid non-DNA characters")
    else:
        feedback_parts.append("Sense FASTA missing")
    score += c1

    # Criterion 2: Antisense FASTA exists and valid (12 pts)
    c2 = 0
    if result.get('antisense_exists') and is_valid_dna(antisense_seq):
        c2 = 12
        feedback_parts.append("Antisense FASTA exists with valid DNA")
    elif result.get('antisense_exists'):
        c2 = 4
        feedback_parts.append("Antisense FASTA exists but contains invalid characters")
    else:
        feedback_parts.append("Antisense FASTA missing")
    score += c2

    # Criterion 3: CDS length plausible (10 pts)
    c3 = 0
    s_len = len(sense_seq)
    if min_len <= s_len <= max_len:
        c3 = 10
        feedback_parts.append(f"CDS length plausible ({s_len} nt)")
    elif s_len > 0:
        c3 = 2
        feedback_parts.append(f"CDS length out of expected range ({s_len} nt)")
    score += c3

    # Criterion 4: Sense/antisense same length (8 pts)
    c4 = 0
    a_len = len(antisense_seq)
    if s_len > 0 and s_len == a_len:
        c4 = 8
        feedback_parts.append("Sense and antisense strands have identical lengths")
    elif s_len > 0 and a_len > 0:
        feedback_parts.append(f"Strand length mismatch (Sense: {s_len}, Antisense: {a_len})")
    score += c4

    # Criterion 5: Exact Reverse Complement Correct (20 pts)
    c5 = 0
    revcomp_correct = False
    if s_len > 0 and a_len > 0 and s_len == a_len:
        expected_antisense = reverse_complement(sense_seq)
        if antisense_seq == expected_antisense:
            c5 = 20
            revcomp_correct = True
            feedback_parts.append("Antisense sequence is the EXACT reverse complement of sense sequence")
        elif antisense_seq == sense_seq[::-1]:
            c5 = 5
            feedback_parts.append("Antisense sequence is only reversed, NOT complemented")
        else:
            feedback_parts.append("Antisense sequence is not the correct reverse complement")
    score += c5

    # Criterion 6: Report exists (5 pts)
    c6 = 0
    if result.get('report_exists') and len(report_text.strip()) > 0:
        c6 = 5
        feedback_parts.append("Report file exists")
    score += c6

    # Criterion 7: Report contains accurate CDS length (8 pts)
    c7 = 0
    if c6 > 0 and s_len > 0:
        if str(s_len) in report_text:
            c7 = 8
            feedback_parts.append("Report accurately states CDS length")
        else:
            feedback_parts.append("Report missing accurate CDS length")
    score += c7

    # Criterion 8: Report contains accurate computed GC% (10 pts)
    c8 = 0
    if c6 > 0 and s_len > 0:
        actual_gc = (sense_seq.count('G') + sense_seq.count('C')) / s_len * 100
        # Find all numbers in report
        numbers_in_report = re.findall(r'\d+\.?\d*', report_text)
        gc_found = False
        for num_str in numbers_in_report:
            try:
                num = float(num_str)
                # Check if report number is within ±2% of actual GC
                if abs(num - actual_gc) <= 2.0 and num > 0:
                    gc_found = True
                    break
            except ValueError:
                continue
        
        if gc_found:
            c8 = 10
            feedback_parts.append(f"Report accurately contains GC% (~{actual_gc:.1f}%)")
        else:
            feedback_parts.append("Report missing accurate GC%")
    score += c8

    # Criterion 9: Report contains first 30nt of both strands (8 pts)
    c9 = 0
    if c6 > 0 and s_len >= 30 and a_len >= 30:
        sense_30 = sense_seq[:30]
        anti_30 = antisense_seq[:30]
        
        # Remove whitespace/newlines from report text for sequence matching
        clean_report = re.sub(r'\s+', '', report_text.upper())
        
        if sense_30 in clean_report and anti_30 in clean_report:
            c9 = 8
            feedback_parts.append("Report contains first 30nt of both strands")
        elif sense_30 in clean_report or anti_30 in clean_report:
            c9 = 4
            feedback_parts.append("Report contains first 30nt of only one strand")
        else:
            feedback_parts.append("Report missing first 30nt sequences")
    score += c9

    # Criterion 10: Report hybridization note (7 pts)
    c10 = 0
    if c6 > 0:
        note_keywords = ['hybridization', 'suitable', 'good', 'acceptable', 'range', 'optimal', 'ideal']
        report_lower = report_text.lower()
        if any(kw in report_lower for kw in note_keywords) and ('gc' in report_lower or 'content' in report_lower):
            c10 = 7
            feedback_parts.append("Report discusses GC suitability for hybridization")
        else:
            feedback_parts.append("Report lacks hybridization suitability note")
    score += c10

    # Determine pass/fail
    passed = (score >= 60) and revcomp_correct

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "details": {
            "sense_len": s_len,
            "antisense_len": a_len,
            "revcomp_correct": revcomp_correct
        }
    }