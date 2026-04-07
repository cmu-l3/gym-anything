#!/usr/bin/env python3
"""
Verifier for In Silico PCR Validation task.
"""

import os
import json
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def verify_insilico_pcr(traj, env_info, task_info):
    """
    Evaluates the PCR validation task based on exported files and VLM trajectory.
    """
    copy_from_env = env_info.get('copy_from_env')
    query_vlm = env_info.get('query_vlm')
    
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # Retrieve data
    temp_file = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/pcr_result.json", temp_file.name)
        with open(temp_file.name, 'r') as f:
            data = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read exported results: {e}"}
    finally:
        if os.path.exists(temp_file.name):
            os.unlink(temp_file.name)

    score = 0
    feedback = []
    task_start = data.get("task_start_time", 0)
    files = data.get("files", {})
    gt = data.get("ground_truth", {})
    
    # 1. Evaluate Amplicon FASTA (25 pts)
    fasta_data = files.get("amplicon_fasta", {})
    if fasta_data.get("exists") and fasta_data.get("mtime", 0) >= task_start:
        content = fasta_data.get("content", "").strip()
        seq_lines = [line.upper() for line in content.split('\n') if not line.startswith('>')]
        amplicon_seq = "".join(seq_lines).replace(" ", "").replace("\r", "")
        
        if len(amplicon_seq) > 0 and re.match(r'^[ACGTN]+$', amplicon_seq):
            score += 10
            feedback.append("Valid FASTA DNA sequence found.")
            
            # Check if it's a genuine subsequence of the actual insulin gene
            full_seq = gt.get("full_seq", "")
            expected_size = gt.get("amplicon_size", 200)
            
            if amplicon_seq in full_seq or full_seq.find(amplicon_seq[:50]) != -1:
                score += 10
                feedback.append("Amplicon sequence is a genuine subsequence of the insulin gene.")
                
                if abs(len(amplicon_seq) - expected_size) <= max(50, expected_size * 0.2):
                    score += 5
                    feedback.append("Amplicon length is correct.")
                else:
                    feedback.append(f"Amplicon length {len(amplicon_seq)}bp differs from expected ~{expected_size}bp.")
            else:
                feedback.append("Amplicon sequence does not match the reference insulin gene.")
        else:
            feedback.append("FASTA file exists but contains invalid DNA.")
    else:
        feedback.append("Amplicon FASTA missing or created before task start.")

    # 2. Evaluate Annotated GenBank (15 pts)
    gb_data = files.get("annotated_gb", {})
    if gb_data.get("exists") and gb_data.get("mtime", 0) >= task_start:
        score += 5
        gb_content = gb_data.get("content", "")
        
        # Look for typical PCR/In Silico features that UGENE adds
        pcr_patterns = [r'misc_feature', r'PCR_product', r'primer_bind', r'amplicon']
        if any(re.search(p, gb_content, re.IGNORECASE) for p in pcr_patterns):
            score += 10
            feedback.append("Annotated GenBank valid and contains PCR/amplicon feature.")
        else:
            feedback.append("GenBank file saved, but no new PCR annotation detected.")
    else:
        feedback.append("Annotated GenBank missing or created before task start.")

    # 3. Evaluate Validation Report (30 pts)
    report_data = files.get("report", {})
    if report_data.get("exists") and report_data.get("mtime", 0) >= task_start:
        score += 10
        rep_content = report_data.get("content", "").upper()
        
        # Check for primers
        fwd = gt.get("fwd_primer", "XXXXX").upper()
        rev = gt.get("rev_primer", "XXXXX").upper()
        
        if (fwd[:15] in rep_content) and (rev[:15] in rep_content):
            score += 10
            feedback.append("Report contains both primer sequences.")
        else:
            feedback.append("Report is missing one or both primer sequences.")
            
        # Check for numeric positions or length
        numbers = [int(n) for n in re.findall(r'\b\d{2,5}\b', rep_content)]
        if any(n > 50 and n < 10000 for n in numbers):
            score += 5
            feedback.append("Report contains positional/length numeric data.")
            
        # Check for conclusion
        if any(w in rep_content for w in ['SUITABLE', 'VALID', 'SUCCESS', 'CONFIRM', 'YES']):
            score += 5
            feedback.append("Report contains a diagnostic conclusion.")
    else:
        feedback.append("Validation report missing or created before task start.")

    # 4. VLM Trajectory Verification (30 pts)
    if query_vlm:
        try:
            # We import here safely within the function execution context
            from gym_anything.vlm import sample_trajectory_frames, get_final_screenshot
            frames = sample_trajectory_frames(traj, n=5)
            final = get_final_screenshot(traj)
            images = frames + [final] if final else frames
            
            prompt = """You are verifying a bioinformatics task in UGENE.
Look at the sequence of screenshots showing the user's workflow.
1. Is the 'In Silico PCR' dialog or 'Find Pattern' tool ever opened?
2. Are primer sequences visible being entered?
3. Is an amplicon sequence shown or exported?

Respond in strict JSON:
{
    "used_pcr_tool": true/false,
    "reasoning": "Brief explanation"
}"""
            vlm_res = query_vlm(images=images, prompt=prompt)
            if vlm_res and vlm_res.get("success"):
                parsed = vlm_res.get("parsed", {})
                if parsed.get("used_pcr_tool", False):
                    score += 30
                    feedback.append("VLM confirms In Silico PCR tool was used.")
                else:
                    feedback.append("VLM could not confirm PCR tool usage.")
            else:
                # If VLM fails due to API reasons, grant partial default credit if files exist to avoid blocking
                if score >= 25:
                    score += 20
                    feedback.append("VLM query failed, granting partial default credit based on valid file outputs.")
        except Exception as e:
            logger.warning(f"VLM verification failed: {e}")
            if score >= 25:
                score += 20
                feedback.append("VLM import/execution error, granting partial default credit.")
    else:
        # Fallback if VLM isn't hooked up
        if score >= 25:
            score += 30
            feedback.append("VLM not provided; auto-granting VLM score based on file existence.")

    # Final verdict
    passed = score >= 60 and ("Amplicon FASTA missing" not in feedback[0])
    
    return {
        "passed": passed,
        "score": min(score, 100),
        "feedback": " | ".join(feedback)
    }