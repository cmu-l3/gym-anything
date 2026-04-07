"""
Verifier for research_deck_prep task.

Task: Director of Research Computing must fix an AI research overview presentation:
  1. Correct 3 wrong publication years (BERT 2019→2018, GPT-3 2021→2020, LLaMA 2022→2023)
  2. Remove 2 Computer Vision slides from the NLP research overview
  3. Export the corrected PPTX as a PDF

Original deck: 22 slides; corrected deck should have 20 slides (2 vision slides removed)

Scoring (100 pts total):
- 10 pts: Output PPTX /home/ga/Documents/AI_research_corrected.pptx exists
- 10 pts: Original AI_research_overview.pptx unchanged (22 slides)
- 10 pts each × 3 citation year corrections = 30 pts
- 15 pts each × 2 vision slides removed = 30 pts
- 20 pts: PDF /home/ga/Documents/AI_research_corrected.pdf exists and is ≥10 KB

Pass threshold: 65 pts
"""

import json
import os

RESULT_FILE = '/tmp/research_deck_prep_result.json'
MIN_PDF_SIZE = 10_240  # 10 KB

CITATION_CORRECTIONS = [
    ("BERT", "Devlin et al., 2019", "2018"),
    ("GPT-3", "Brown et al., 2021", "2020"),
    ("LLaMA", "Touvron et al., 2022", "2023"),
]


def verify_research_deck_prep(trajectory, env_info, task_info):
    local_tmp = '/tmp/_research_deck_prep_result_local.json'
    try:
        env_info['copy_from_env'](RESULT_FILE, local_tmp)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not retrieve result file: {e}. Export script may not have run.',
        }

    try:
        with open(local_tmp, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Could not parse result JSON: {e}',
        }

    if result.get('error') and not result.get('output_pptx_exists'):
        return {
            'passed': False,
            'score': 0,
            'feedback': f'Export error: {result["error"]}',
        }

    # Anti-gaming check
    try:
        with open('/tmp/research_deck_prep_start_ts', 'r') as f:
            task_start = int(f.read().strip())
        output_mtime = result.get('output_mtime', 0)
        if output_mtime and output_mtime <= task_start:
            return {
                'passed': False,
                'score': 0,
                'feedback': 'Output file was not created during this task.',
            }
    except Exception:
        pass

    score = 0
    feedback_parts = []

    # 1. Output PPTX exists (10 pts)
    if result.get('output_pptx_exists'):
        score += 10
        n = result.get('output_slide_count', 0)
        feedback_parts.append(f'✓ Output PPTX AI_research_corrected.pptx exists ({n} slides) (+10 pts)')
    else:
        return {
            'passed': False,
            'score': 0,
            'feedback': '\n'.join([
                'Score: 0/100',
                '✗ Output file not found at /home/ga/Documents/AI_research_corrected.pptx',
            ]),
        }

    # 2. Original unchanged (10 pts)
    if result.get('original_unchanged'):
        score += 10
        feedback_parts.append(
            f'✓ Original AI_research_overview.pptx unchanged '
            f'({result["original_slide_count"]} slides) (+10 pts)'
        )
    else:
        feedback_parts.append(
            f'✗ Original file modified (count={result.get("original_slide_count", "?")}). '
            f'Do not overwrite AI_research_overview.pptx (0 pts).'
        )

    # Anti-Pattern 11 guard: an empty PPTX trivially has no wrong citation years or vision slides.
    # Gate absence-based criteria on a minimum viable slide count.
    output_count = result.get('output_slide_count', 0)
    if output_count < 15:
        feedback_parts.append(
            f'✗ Output deck has only {output_count} slides — far too few for a valid research overview. '
            f'Do not mass-delete slides. Expected ~20 slides after removing 2 CV slides. '
            f'Citation and vision removal criteria cannot be scored. (0 pts)'
        )
        return {
            'passed': False,
            'score': score,
            'feedback': '\n'.join([f'Score: {score}/100  (pass threshold: 65)', ''] + feedback_parts),
        }

    # 3. Citation year corrections (10 pts each × 3 = 30 pts)
    citation_errors_remaining = result.get('citation_errors_remaining', [])
    num_citations_fixed = max(0, 3 - len(citation_errors_remaining))
    citation_pts = num_citations_fixed * 10
    score += citation_pts

    if num_citations_fixed == 3:
        feedback_parts.append(f'✓ All 3 citation year errors corrected (+30 pts)')
    elif num_citations_fixed > 0:
        still_wrong = [
            f'{r["paper"]} slide still says {r["wrong_year"]} (should be {r["correct_year"]})'
            for r in citation_errors_remaining
        ]
        feedback_parts.append(
            f'~ {num_citations_fixed}/3 citation years fixed (+{citation_pts} pts). '
            f'Remaining errors: {"; ".join(still_wrong)}'
        )
    else:
        feedback_parts.append(
            f'✗ No citation years corrected (0 pts). '
            f'Fix: BERT 2019→2018, GPT-3 2021→2020, LLaMA 2022→2023. '
            f'Use Find & Replace or manually edit each slide body text.'
        )

    # 4. Vision slides removed (15 pts each × 2 = 30 pts)
    vision_remaining = result.get('vision_slides_remaining', [])
    num_vision_removed = max(0, 2 - len(vision_remaining))
    vision_pts = num_vision_removed * 15
    score += vision_pts

    if num_vision_removed == 2:
        feedback_parts.append(f'✓ Both Computer Vision slides removed from NLP overview (+30 pts)')
    elif num_vision_removed == 1:
        remaining = [f'"{r["title"]}"' for r in vision_remaining]
        feedback_parts.append(
            f'~ 1/2 vision slides removed (+15 pts). '
            f'Still present: {"; ".join(remaining)}'
        )
    else:
        remaining = [f'"{r["title"]}"' for r in vision_remaining]
        feedback_parts.append(
            f'✗ No vision slides removed (0 pts). '
            f'Delete slides about ImageNet, DALL-E 2, and Stable Diffusion: {"; ".join(remaining)}'
        )

    # 5. PDF exists and is valid (20 pts)
    pdf_exists = result.get('pdf_exists', False)
    pdf_size = result.get('pdf_size_bytes', 0)
    pdf_mtime = result.get('pdf_mtime', 0)

    if pdf_exists:
        # Anti-gaming: PDF must be created during task
        try:
            with open('/tmp/research_deck_prep_start_ts', 'r') as f:
                task_start = int(f.read().strip())
            if pdf_mtime and pdf_mtime <= task_start:
                feedback_parts.append(
                    '✗ PDF file existed before task started — not exported during task (0 pts).'
                )
            elif pdf_size >= MIN_PDF_SIZE:
                score += 20
                feedback_parts.append(
                    f'✓ PDF exported to AI_research_corrected.pdf ({pdf_size:,} bytes) (+20 pts)'
                )
            else:
                score += 5
                feedback_parts.append(
                    f'~ PDF exists but is very small ({pdf_size:,} bytes < 10 KB) — '
                    f'may be corrupt or empty export (+5 pts partial). '
                    f'Use File > Export or File > Print > Print to PDF.'
                )
        except Exception:
            if pdf_size >= MIN_PDF_SIZE:
                score += 20
                feedback_parts.append(
                    f'✓ PDF exported ({pdf_size:,} bytes) (+20 pts)'
                )
    else:
        feedback_parts.append(
            '✗ PDF not found at /home/ga/Documents/AI_research_corrected.pdf (0 pts). '
            'Export using File > Export or File > Print > Save as PDF after correcting the PPTX.'
        )

    passed = score >= 65

    return {
        'passed': passed,
        'score': score,
        'feedback': '\n'.join([
            f'Score: {score}/100  (pass threshold: 65)',
            f'Output PPTX: {output_count} slides',
            f'Citation years fixed: {num_citations_fixed}/3',
            f'Vision slides removed: {num_vision_removed}/2',
            f'PDF: {"exists" if pdf_exists else "missing"} ({pdf_size:,} bytes)',
            '',
        ] + feedback_parts),
    }
