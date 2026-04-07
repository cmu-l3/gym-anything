#!/usr/bin/env python3
"""Verifier for insulin_cpg_gc_profiling task.

Scoring breakdown (100 points total):
  Annotated GB file exists & valid:  10
  CpG annotations present in GB:     15
  CpG annotation count accurate:     15
  Report file exists:                10
  Sequence length reported:          10
  GC percentage reported:            15
  CpG count reported:                15
  Nucleotide counts present:         5
  CpG positions listed:              5
                             TOTAL = 100
"""

import json
import os
import re
import tempfile
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def verify_insulin_cpg_gc_profiling(traj, env_info, task_info):
    score = 0
    feedback_parts = []
    subscores = {}

    copy_from_env = env_info.get("copy_from_env")
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Load Ground Truth
    gt = {}
    tmp_gt = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_gt.close()
    try:
        copy_from_env("/tmp/insulin_cpg_gt.json", tmp_gt.name)
        with open(tmp_gt.name) as f:
            gt = json.load(f)
    except Exception as e:
        logger.error(f"Could not load GT: {e}")
    finally:
        os.unlink(tmp_gt.name)

    if not gt.get("success", False):
        # Fallback approximate GT if script failed
        gt = {
            "length": 4988, "a_count": 1083, "t_count": 1137, 
            "g_count": 1406, "c_count": 1362, "cg_count": 270, 
            "gc_pct": 55.49, "orig_features": 15
        }

    # 2. Load Bash Results Metadata
    result_meta = {}
    tmp_meta = tempfile.NamedTemporaryFile(delete=False, suffix=".json")
    tmp_meta.close()
    try:
        copy_from_env("/tmp/insulin_cpg_result.json", tmp_meta.name)
        with open(tmp_meta.name) as f:
            result_meta = json.load(f)
    except Exception as e:
        logger.error(f"Could not load bash result meta: {e}")
    finally:
        os.unlink(tmp_meta.name)

    task_start = result_meta.get("task_start_ts", 0)

    # 3. Analyze GB File
    c1, c2, c3 = 0, 0, 0
    if result_meta.get("gb_exists", False):
        if result_meta.get("gb_mtime", 0) > task_start:
            c1 += 5
            
            # Download and parse GB file
            tmp_gb = tempfile.NamedTemporaryFile(delete=False, suffix=".gb")
            tmp_gb.close()
            try:
                copy_from_env("/home/ga/UGENE_Data/cpg_results/insulin_cpg_annotated.gb", tmp_gb.name)
                with open(tmp_gb.name, "r", errors="ignore") as f:
                    gb_content = f.read()
                
                # Check format validity
                if "LOCUS" in gb_content and "FEATURES" in gb_content and "ORIGIN" in gb_content:
                    c1 += 5
                    feedback_parts.append("Valid GenBank file created (+10)")
                else:
                    feedback_parts.append("GB file exists but format invalid (+5)")
                    
                # Count features
                all_features = re.findall(r'\s{5}\w+\s+(?:complement\()?<?\d+\.\.>?\d+', gb_content)
                total_features = len(all_features)
                
                # Count CpG specific annotations
                cpg_mentions = len(re.findall(r'(?i)CpG', gb_content))
                cg_mentions = len(re.findall(r'(?i)pattern.*CG', gb_content))
                added_features = total_features - gt.get("orig_features", 0)
                
                if cpg_mentions >= 10 or cg_mentions >= 10 or added_features >= 10:
                    c2 = 15
                    feedback_parts.append("CpG annotations present (+15)")
                    
                    # Verify exact count
                    target_cg = gt.get("cg_count", 0)
                    if abs(added_features - target_cg) <= 5 or abs(cpg_mentions - target_cg) <= 10:
                        c3 = 15
                        feedback_parts.append(f"Annotation count matches exactly ({target_cg}) (+15)")
                    elif abs(added_features - target_cg) <= 30:
                        c3 = 10
                        feedback_parts.append(f"Annotation count is close (+10)")
                    else:
                        feedback_parts.append(f"Annotation count off (found ~{added_features}, expected {target_cg}) (0)")
                else:
                    feedback_parts.append("No CpG annotations found in GB file (0)")

            except Exception as e:
                logger.error(f"Error parsing GB: {e}")
                feedback_parts.append("Error parsing GB file (0)")
            finally:
                os.unlink(tmp_gb.name)
        else:
            feedback_parts.append("GB file exists but was created BEFORE task start (Anti-gaming) (0)")
    else:
        feedback_parts.append("Annotated GB file MISSING (0)")

    score += c1 + c2 + c3
    subscores["gb_exists"] = c1
    subscores["gb_annotations"] = c2
    subscores["gb_annot_count"] = c3

    # 4. Analyze Text Report
    c4, c5, c6, c7, c8, c9 = 0, 0, 0, 0, 0, 0
    if result_meta.get("report_exists", False):
        if result_meta.get("report_mtime", 0) > task_start:
            c4 = 10
            feedback_parts.append("Report file exists (+10)")
            
            # Download and parse report
            tmp_rep = tempfile.NamedTemporaryFile(delete=False, suffix=".txt")
            tmp_rep.close()
            try:
                copy_from_env("/home/ga/UGENE_Data/cpg_results/cpg_analysis_report.txt", tmp_rep.name)
                with open(tmp_rep.name, "r", errors="ignore") as f:
                    report_content = f.read()
                
                # Extract all numbers from the report for fuzzy matching
                all_numbers = [float(x) for x in re.findall(r'\d+(?:\.\d+)?', report_content)]
                
                # Length check
                target_len = gt.get("length", 0)
                if any(abs(n - target_len) <= 10 for n in all_numbers):
                    c5 = 10
                    feedback_parts.append("Sequence length correct (+10)")
                else:
                    feedback_parts.append("Sequence length missing or incorrect (0)")
                
                # GC % check
                target_gc = gt.get("gc_pct", 0)
                if any(abs(n - target_gc) <= 2.0 for n in all_numbers):
                    c6 = 15
                    feedback_parts.append("GC percentage correct (+15)")
                else:
                    feedback_parts.append("GC percentage missing or incorrect (0)")
                
                # CpG count check
                target_cg = gt.get("cg_count", 0)
                if any(abs(n - target_cg) <= 5 for n in all_numbers):
                    c7 = 15
                    feedback_parts.append("CpG count correct (+15)")
                else:
                    feedback_parts.append("CpG count missing or incorrect (0)")
                
                # Nucleotide counts check (A, T, G, C)
                nt_targets = [gt.get("a_count"), gt.get("t_count"), gt.get("g_count"), gt.get("c_count")]
                matches = 0
                for target in nt_targets:
                    if target and any(abs(n - target) <= 5 for n in all_numbers):
                        matches += 1
                if matches >= 3:
                    c8 = 5
                    feedback_parts.append("Individual nucleotide counts present (+5)")
                else:
                    feedback_parts.append("Individual nucleotide counts missing or incorrect (0)")
                
                # Position coordinates check
                # Check for list of numbers that look like coordinates
                pos_numbers = [n for n in all_numbers if 10 <= n <= target_len]
                if len(pos_numbers) >= 10:
                    c9 = 5
                    feedback_parts.append("CpG positions listed (+5)")
                else:
                    feedback_parts.append("Not enough CpG positions listed (0)")

            except Exception as e:
                logger.error(f"Error parsing Report: {e}")
                feedback_parts.append("Error parsing report file (0)")
            finally:
                os.unlink(tmp_rep.name)
        else:
            feedback_parts.append("Report exists but was created BEFORE task start (Anti-gaming) (0)")
    else:
        feedback_parts.append("Report file MISSING (0)")

    score += c4 + c5 + c6 + c7 + c8 + c9
    subscores["report_exists"] = c4
    subscores["report_len"] = c5
    subscores["report_gc"] = c6
    subscores["report_cpg_count"] = c7
    subscores["report_nt_counts"] = c8
    subscores["report_positions"] = c9

    passed = score >= 60 and c1 > 0 and c4 > 0

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(feedback_parts),
        "subscores": subscores
    }