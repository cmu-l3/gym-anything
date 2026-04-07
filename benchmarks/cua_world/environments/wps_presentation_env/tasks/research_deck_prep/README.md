# Task: research_deck_prep

**Environment**: wps_presentation_env
**Difficulty**: very_hard
**Occupation**: Computer and Information Systems Managers
**Primary skill tested**: Research integrity, citation correction, slide deletion, PDF export

## Overview

The Director of Research Computing at a university AI research institute must fix an annual research overview presentation before it is shared with the Provost's office and research sponsors. A research integrity officer has flagged the 22-slide draft at `/home/ga/Documents/AI_research_overview.pptx` with three problems, described in a memo at `/home/ga/Desktop/research_integrity_memo.txt`.

**Original file**: `/home/ga/Documents/AI_research_overview.pptx` (22 slides — do not modify)
**Output PPTX**: `/home/ga/Documents/AI_research_corrected.pptx` (should have 20 slides)
**Output PDF**: `/home/ga/Documents/AI_research_corrected.pdf` (Provost's office archival requirement)

## What Makes This Very Hard

- The agent must read and interpret a research integrity memo written in academic AI terminology (BERT, GPT-3, LLaMA, ImageNet, diffusion models)
- Correcting citation years requires knowing the actual publication dates of seminal AI papers (BERT: Oct 2018, GPT-3: May 2020, LLaMA: Feb 2023) — not just finding and editing text
- Vision slides use realistic ML research language and are adjacent to legitimate vision-language multimodal content (Flamingo, CLIP), requiring the agent to distinguish pure CV content from NLP+vision content
- The task also requires a PDF export, combining editing with file format conversion

## Injected Errors

### Wrong Citation Years (slides 5, 8, 12)
| Paper | Wrong year in draft | Correct year | arXiv ID |
|-------|--------------------:|-------------:|----------|
| BERT (Devlin et al.) | 2019 | **2018** | arXiv:1810.04805 |
| GPT-3 (Brown et al.) | 2021 | **2020** | arXiv:2005.14165 |
| LLaMA (Touvron et al.) | 2022 | **2023** | arXiv:2302.13971 |

### Computer Vision Slides to Remove (slides 15, 18)
- "Computer Vision Benchmarks: ImageNet SOTA 2023"
- "Diffusion Models for Image Synthesis: DALL-E 2 and Stable Diffusion"

## Success Criteria

| Criterion | Points |
|-----------|--------|
| Output PPTX AI_research_corrected.pptx exists | 10 |
| Original AI_research_overview.pptx unchanged (22 slides) | 10 |
| Each citation year corrected (×3) | 10 each = 30 |
| Each vision slide removed (×2) | 15 each = 30 |
| PDF exported ≥10 KB | 20 |
| **Total** | **100** |
| **Pass threshold** | **65** |

## Data Sources (Real Published Papers)

- BERT: Devlin et al., "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding", arXiv:1810.04805, **October 11, 2018**
- GPT-3: Brown et al., "Language Models are Few-Shot Learners", arXiv:2005.14165, **May 28, 2020**
- LLaMA: Touvron et al., "LLaMA: Open and Efficient Foundation Language Models", arXiv:2302.13971, **February 27, 2023**
- T5: Raffel et al., "Exploring the Limits of Transfer Learning", JMLR 2020
- InstructGPT: Ouyang et al., arXiv:2203.02155, 2022
- SuperGLUE: Wang et al., NeurIPS 2019
- MMLU: Hendrycks et al., arXiv:2009.03300, 2021
- HumanEval: Chen et al., arXiv:2107.03374, 2021
- DALL-E 2: Ramesh et al., arXiv:2204.06125, 2022
- Stable Diffusion: Rombach et al., CVPR 2022

## Verification Strategy

`export_result.sh` parses the corrected PPTX and:
1. Searches each slide's text for citation patterns (paper name + author + year) and checks whether the wrong year remains
2. Scans for Computer Vision keywords (imagenet, dall-e 2, stable diffusion, image synthesis, computer vision benchmark) to detect remaining CV slides
3. Checks whether `/home/ga/Documents/AI_research_corrected.pdf` exists and is ≥10 KB
4. Verifies the original 22-slide file was not modified
