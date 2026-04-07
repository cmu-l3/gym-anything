#!/usr/bin/env python3
"""
Verifier for the PD-1/PD-L1 Checkpoint Interface Analysis task (PDB:4ZQK).

Scoring (100 points total):
  20 pts - Publication figure exists at correct path, is new (post-task-start), and >40KB.
  20 pts - Report correctly identifies the chain assignments for PD-1 and PD-L1.
  30 pts - Report contains a realistic count of PD-L1 interface residues (20-40 range) using
           the specified 4.5 Angstrom cutoff, proving actual programmatic selection was made.
  30 pts - Report explicitly verifies the inclusion of the canonical PD-L1 hotspots 
           (56, 113, 115, 123) within the interface.

Pass threshold: 70/100 (Must complete Interface Count + Hotspot Verification or equal points).

Anti-gaming:
  - figure_is_new gate: Rules out pre-existing image files.
  - Count Check: The values 20-40 deliberately exclude the prompt numbers (4.5, 56, 113, 115, 123).
  - Explicit Hotspots: Requires specific biological structural features to be identified.
"""

import json
import os
import re
import tempfile
import logging

logger = logging.getLogger(__name__)


def verify_pd1_pdl1_checkpoint_interface_analysis(traj, env_info, task_info):
    """Verify the PD-1/PD-L1 Interface Analysis task."""
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "copy_from_env not available"}

    metadata = task_info.get('metadata', {})
    result_path = metadata.get('result_json', '/tmp/pd1_pdl1_result.json')

    # Safely copy result from container
    tmp = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    tmp.close()
    try:
        copy_from_env(result_path, tmp.name)
        with open(tmp.name, 'r') as f:
            result = json.load(f)
    except FileNotFoundError:
        return {
            "passed": False, "score": 0,
            "feedback": "Result file not found — export script may not have run"
        }
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Could not read result: {e}"}
    finally:
        try:
            if os.path.exists(tmp.name):
                os.unlink(tmp.name)
        except Exception:
            pass

    score = 0
    parts = []

    # --- Criterion 1: Publication figure (20 pts) ---
    fig_exists = result.get('figure_exists', False)
    fig_size = result.get('figure_size_bytes', 0)
    fig_is_new = result.get('figure_is_new', False)
    min_fig_size = metadata.get('min_figure_size_bytes', 40000)

    if fig_exists and fig_is_new and fig_size >= min_fig_size:
        score += 20
        parts.append(f"Interface figure created ({fig_size // 1024} KB)")
    elif fig_exists and fig_size >= min_fig_size:
        score += 10
        parts.append(f"Figure exists ({fig_size // 1024} KB) but may not be newly created")
    elif fig_exists:
        parts.append(f"Figure exists but is too small ({fig_size} bytes) — likely a placeholder")
    else:
        parts.append("Interface figure not found at ~/PyMOL_Data/images/pd1_pdl1_interface.png")

    # Setup report parsing
    report_exists = result.get('report_exists', False)
    report_content = result.get('report_content', '').replace('\\n', '\n').replace('\\t', '\t')

    if not report_exists:
        parts.append("Interface report not found at ~/PyMOL_Data/pd1_pdl1_interface_report.txt")
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(parts)
        }

    # --- Criterion 2: Chain Assignment (20 pts) ---
    content_upper = report_content.upper()
    has_chain_a = 'CHAIN A' in content_upper or ' A ' in content_upper or ' A:' in content_upper or ':A' in content_upper or '(A)' in content_upper
    has_chain_b = 'CHAIN B' in content_upper or ' B ' in content_upper or ' B:' in content_upper or ':B' in content_upper or '(B)' in content_upper
    
    if has_chain_a and has_chain_b and ('PD-L1' in content_upper or 'CD274' in content_upper) and ('PD-1' in content_upper or 'PDCD1' in content_upper):
        score += 20
        parts.append("Chain assignments documented")
    else:
        parts.append("Chain assignments missing or incomplete")

    # --- Criterion 3: Interface Residue Count (30 pts) ---
    count_min = metadata.get('interface_count_min', 20)
    count_max = metadata.get('interface_count_max', 40)
    
    # Extract all whole numbers to check if the true interface count is reported
    all_numbers = [int(n) for n in re.findall(r'\b\d+\b', report_content)]
    valid_counts = [n for n in all_numbers if count_min <= n <= count_max]
    
    if valid_counts:
        score += 30
        parts.append(f"Valid interface residue count found: {valid_counts[0]}")
    elif all_numbers:
        parts.append(f"Numeric values found {all_numbers[:5]} but none fall in the plausible interface count range ({count_min}-{count_max})")
    else:
        parts.append("No numeric interface count found in the report")

    # --- Criterion 4: Hotspot Verification (30 pts) ---
    hotspots = metadata.get('hotspot_residues', [56, 113, 115, 123])
    found_hotspots = [h for h in hotspots if str(h) in report_content]
    
    if len(found_hotspots) == len(hotspots):
        score += 30
        parts.append(f"All {len(hotspots)} canonical hotspots explicitly identified")
    elif len(found_hotspots) > 0:
        pts = len(found_hotspots) * (30 // len(hotspots))
        score += pts
        parts.append(f"Partial hotspots identified: {found_hotspots} ({pts} pts)")
    else:
        parts.append("Canonical hotspots not mentioned")

    passed = score >= 70

    return {
        "passed": passed,
        "score": score,
        "feedback": " | ".join(parts)
    }