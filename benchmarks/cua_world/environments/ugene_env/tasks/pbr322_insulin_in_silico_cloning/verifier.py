#!/usr/bin/env python3
"""
Verifier for pBR322 In Silico Cloning task.

This script runs on the host, uses Biopython to rigorously check the 
contents and structure of the recombinant GenBank file, and uses VLM 
to verify the agent actually interacted with the UGENE application.
"""

import json
import os
import sys
import tempfile
import logging
import subprocess
import re

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def ensure_biopython():
    """Ensure Biopython is installed on the host to parse GenBank files robustly."""
    try:
        import Bio
        from Bio import SeqIO
        return True
    except ImportError:
        logger.info("Installing biopython on the host for verification...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", "-q", "biopython"])
            return True
        except Exception as e:
            logger.error(f"Failed to install biopython: {e}")
            return False

def verify_in_silico_cloning(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Framework error: copy_from_env not available"}

    if not ensure_biopython():
        return {"passed": False, "score": 0, "feedback": "Framework error: could not install biopython"}
    
    from Bio import SeqIO

    metadata = task_info.get('metadata', {})
    insert_position = metadata.get('insert_position', 375)
    expected_pbr_length = metadata.get('expected_vector_length', 4361)

    score = 0
    feedback_parts = []
    
    # 1. Retrieve the base status JSON
    result_data = {}
    temp_res = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    try:
        copy_from_env("/tmp/task_result.json", temp_res.name)
        with open(temp_res.name, 'r') as f:
            result_data = json.load(f)
    except Exception as e:
        feedback_parts.append(f"Failed to read container status: {e}")
    finally:
        if os.path.exists(temp_res.name): os.unlink(temp_res.name)

    # 2. Setup paths to pull sequence files from the container
    pbr_path = "/home/ga/UGENE_Data/results/pBR322.gb"
    recomb_path = "/home/ga/UGENE_Data/results/pBR322_insulin_recombinant.gb"
    insulin_path = "/home/ga/UGENE_Data/human_insulin_gene.gb"
    report_path = "/home/ga/UGENE_Data/results/cloning_report.txt"

    tmp_dir = tempfile.mkdtemp()
    host_pbr = os.path.join(tmp_dir, "pbr.gb")
    host_recomb = os.path.join(tmp_dir, "recomb.gb")
    host_insulin = os.path.join(tmp_dir, "insulin.gb")
    host_report = os.path.join(tmp_dir, "report.txt")

    pbr_valid = False
    pbr_seq = ""
    insulin_seq = ""
    recomb_seq = ""

    # Check Vector Download (10 pts)
    try:
        copy_from_env(pbr_path, host_pbr)
        rec = SeqIO.read(host_pbr, "genbank")
        pbr_seq = str(rec.seq).upper()
        if len(pbr_seq) >= expected_pbr_length - 50 and len(pbr_seq) <= expected_pbr_length + 50:
            score += 10
            pbr_valid = True
            feedback_parts.append("Vector pBR322 downloaded and valid (+10)")
        else:
            feedback_parts.append(f"pBR322.gb has unexpected length: {len(pbr_seq)}")
    except Exception:
        feedback_parts.append("Vector pBR322.gb missing or invalid")

    # Read Insulin Sequence
    try:
        copy_from_env(insulin_path, host_insulin)
        ins_rec = SeqIO.read(host_insulin, "genbank")
        insulin_seq = str(ins_rec.seq).upper()
    except Exception:
        logger.warning("Could not parse insulin_path")

    # Check Recombinant File & Integrity (10 pts + 15 pts + 15 pts + 10 pts)
    if not pbr_valid or not insulin_seq:
        feedback_parts.append("Cannot verify recombinant logic without valid source files.")
    else:
        try:
            copy_from_env(recomb_path, host_recomb)
            recomb_rec = SeqIO.read(host_recomb, "genbank")
            recomb_seq = str(recomb_rec.seq).upper()
            
            score += 10
            feedback_parts.append("Recombinant file is valid GenBank (+10)")
            
            # Check exact sequence match
            expected_seq = pbr_seq[:insert_position] + insulin_seq + pbr_seq[insert_position:]
            
            if recomb_seq == expected_seq:
                score += 30 # 15 for insert, 15 for backbone
                feedback_parts.append("Insert and backbone sequence perfectly match expected recombinant (+30)")
            else:
                if insulin_seq in recomb_seq:
                    score += 15
                    feedback_parts.append("Insulin sequence found within recombinant (+15)")
                if pbr_seq[:insert_position] in recomb_seq and pbr_seq[insert_position:] in recomb_seq:
                    score += 15
                    feedback_parts.append("Both backbone segments found in recombinant (+15)")
                if insulin_seq not in recomb_seq and (pbr_seq[:insert_position] not in recomb_seq):
                    feedback_parts.append("Recombinant sequence incorrect.")

            # Feature Coordinate Shift Check (10 pts)
            # Find a feature in original pBR322 that is downstream of insert_position
            shifted_features_found = 0
            correctly_shifted = 0
            
            # Use original pBR322 record to find a test feature (like AmpR / bla gene)
            pbr_rec_orig = SeqIO.read(host_pbr, "genbank")
            for p_feat in pbr_rec_orig.features:
                if p_feat.type != "source" and p_feat.location is not None:
                    try:
                        p_start = int(p_feat.location.start)
                        if p_start > insert_position + 10:
                            shifted_features_found += 1
                            # Look for corresponding feature in recombinant
                            for r_feat in recomb_rec.features:
                                if r_feat.type == p_feat.type:
                                    r_start = int(r_feat.location.start)
                                    # Allow +/- 1 tolerance
                                    if abs(r_start - (p_start + len(insulin_seq))) <= 1:
                                        correctly_shifted += 1
                                        break
                    except Exception:
                        pass
            
            if correctly_shifted > 0:
                score += 10
                feedback_parts.append("Downstream feature coordinates correctly shifted (+10)")
            elif shifted_features_found > 0:
                feedback_parts.append("Downstream feature coordinates NOT shifted correctly")
            else:
                feedback_parts.append("No downstream features found to verify shift")

        except Exception as e:
            feedback_parts.append("Recombinant file missing or invalid GenBank format")

    # Check Cloning Report (10 pts)
    try:
        copy_from_env(report_path, host_report)
        with open(host_report, 'r') as f:
            report_text = f.read()
        nums = re.findall(r'\d+', report_text)
        if nums and pbr_valid and insulin_seq:
            expected_total_len = len(pbr_seq) + len(insulin_seq)
            reported_len = int(nums[0])
            if reported_len == expected_total_len:
                score += 10
                feedback_parts.append("Cloning report has correct total sequence length (+10)")
            else:
                feedback_parts.append(f"Cloning report length incorrect (Found {reported_len}, Expected {expected_total_len})")
        else:
            feedback_parts.append("Report missing valid numbers")
    except Exception:
        feedback_parts.append("Cloning report txt missing")

    # VLM Trajectory Verification (20 pts)
    # Ensure agent actually used the GUI and didn't cheat with a pure python script
    vlm_score = 0
    try:
        from vlm_utils import sample_trajectory_frames, query_vlm
        frames = sample_trajectory_frames(traj, n=5)
        
        prompt = (
            "You are evaluating an AI agent performing an 'in silico' cloning task in UGENE. "
            "Look closely at these screenshots from the agent's workflow.\n\n"
            "Did the agent actively use the UGENE bioinformatics software interface? "
            "Look for the UGENE main window, sequence viewers, NCBI import dialogs, "
            "or sequence editing/insertion toolbars.\n\n"
            "Respond in JSON format:\n"
            "{\n"
            "  \"used_ugene\": true/false,\n"
            "  \"reasoning\": \"brief explanation\"\n"
            "}"
        )
        vlm_res = query_vlm(images=frames, prompt=prompt)
        if vlm_res.get('success') and vlm_res.get('parsed', {}).get('used_ugene', False):
            vlm_score = 20
            feedback_parts.append("VLM confirmed UGENE GUI usage (+20)")
        else:
            feedback_parts.append("VLM did not confirm active UGENE GUI usage (0)")
    except Exception as e:
        logger.warning(f"VLM verification skipped/failed: {e}")
        # If VLM fails due to framework config, provide partial credit to not unfairly fail the agent
        vlm_score = 10
        feedback_parts.append("VLM verification fallback (+10)")
        
    score += vlm_score

    # Cleanup temp dir
    try:
        for f in [host_pbr, host_recomb, host_insulin, host_report]:
            if os.path.exists(f): os.remove(f)
        os.rmdir(tmp_dir)
    except Exception:
        pass

    passed = score >= 70
    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts)
    }