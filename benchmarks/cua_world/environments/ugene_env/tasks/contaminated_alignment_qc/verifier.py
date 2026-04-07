#!/usr/bin/env python3
"""
Verifier for contaminated_alignment_qc task.

Checks multiple programmatic signals based on the exported JSON:
1. Cleaned FASTA alignment valid & correct count
2. Cleaned Clustal ALN valid
3. Exact absence of the expected contaminant (P99999)
4. Exact presence of the hemoglobin targets
5. Sequence length matching (alignment verification)
6. Report presence and content analysis
"""

import json
import os
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_contaminated_alignment_qc(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Get metadata
    metadata = task_info.get('metadata', {})
    expected_contaminant = metadata.get('expected_contaminant', 'P99999')
    expected_hbb = metadata.get('expected_hemoglobins', [
        "P68871", "P02088", "P02112", "P02132", 
        "Q90485", "P02070", "P02062", "P02067"
    ])

    # Copy result JSON from container
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {"passed": False, "score": 0, "feedback": "Result file not found - export script failed or agent did nothing"}
    except json.JSONDecodeError as e:
        return {"passed": False, "score": 0, "feedback": f"Invalid JSON in result file: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback_parts = []
    
    fasta_exists = result.get("fasta_exists", False)
    aln_exists = result.get("aln_exists", False)
    report_exists = result.get("report_exists", False)
    
    if not (fasta_exists or aln_exists or report_exists):
        return {
            "passed": False,
            "score": 0,
            "feedback": "No output files (FASTA, ALN, or Report) were found in the results directory. Task not completed."
        }

    # CRITERION 1 & 2: Output formats exist (20 points total)
    if fasta_exists and result.get("fasta_created_during_task", False):
        score += 10
        feedback_parts.append("Cleaned FASTA exists (+10)")
    elif fasta_exists:
        score += 5
        feedback_parts.append("Cleaned FASTA exists but may not be newly generated (+5)")
    else:
        feedback_parts.append("Cleaned FASTA missing (0)")

    if aln_exists and result.get("aln_is_clustal", False):
        score += 10
        feedback_parts.append("Clustal ALN alignment exists (+10)")
    else:
        feedback_parts.append("Clustal ALN missing or invalid format (0)")

    # Analyze FASTA contents
    accs = result.get("fasta_accessions", [])
    seq_lengths = result.get("fasta_seq_lengths", [])
    
    # CRITERION 3: Exactly 8 sequences (15 points)
    if len(accs) == 8:
        score += 15
        feedback_parts.append("Exactly 8 sequences found in alignment (+15)")
    else:
        feedback_parts.append(f"Expected 8 sequences, found {len(accs)} (0)")

    # CRITERION 4: Contaminant absent (15 points)
    if fasta_exists and len(accs) > 0:
        if expected_contaminant not in accs:
            score += 15
            feedback_parts.append(f"Contaminant {expected_contaminant} successfully removed (+15)")
        else:
            feedback_parts.append(f"Contaminant {expected_contaminant} was NOT removed (0)")

    # CRITERION 5: Hemoglobin accessions present (10 points)
    missing_hbb = [acc for acc in expected_hbb if acc not in accs]
    if fasta_exists and len(accs) > 0:
        if not missing_hbb:
            score += 10
            feedback_parts.append("All expected homologous sequences preserved (+10)")
        else:
            partial = max(0, 10 - len(missing_hbb)*2)
            score += partial
            feedback_parts.append(f"Missing {len(missing_hbb)} legitimate sequences (+{partial})")

    # CRITERION 6: Sequences are properly aligned (10 points)
    # If sequences are aligned, they should all be exactly the same length (padded with gaps)
    if len(seq_lengths) > 1 and len(set(seq_lengths)) == 1:
        score += 10
        feedback_parts.append("Sequences are uniformly aligned (same length) (+10)")
    elif len(seq_lengths) > 0:
        feedback_parts.append("Sequences vary in length, not properly aligned (0)")

    # CRITERION 7, 8, 9: Report verification (30 points total)
    if report_exists:
        score += 5
        feedback_parts.append("QC report exists (+5)")
        
        report_text = result.get("report_content", "").lower()
        
        # Identifies contaminant
        if expected_contaminant.lower() in report_text:
            score += 15
            feedback_parts.append(f"Report correctly names {expected_contaminant} (+15)")
        else:
            feedback_parts.append("Report fails to name the correct accession (0)")
            
        # Explains reasoning
        reasoning_keywords = ["outlier", "divergent", "non-homolog", "contaminant", "cytochrome", 
                              "poor alignment", "gaps", "mismatch", "unrelated", "distinct"]
        if any(kw in report_text for kw in reasoning_keywords):
            score += 10
            feedback_parts.append("Report includes analytical reasoning (+10)")
        else:
            feedback_parts.append("Report lacks alignment reasoning (0)")
    else:
        feedback_parts.append("QC report missing (0)")

    # Determine overall pass
    # Must remove the contaminant, produce outputs, and score reasonably
    contaminant_removed = fasta_exists and (expected_contaminant not in accs) and len(accs) > 0
    passed = (score >= 60) and contaminant_removed

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }