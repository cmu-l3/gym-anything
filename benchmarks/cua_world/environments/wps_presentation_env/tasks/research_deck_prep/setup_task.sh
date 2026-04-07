#!/bin/bash
echo "=== Setting up research_deck_prep task ==="

source /workspace/scripts/task_utils.sh

kill_wps

pip3 install python-pptx lxml 2>/dev/null || true

rm -f /home/ga/Documents/AI_research_corrected.pptx
rm -f /home/ga/Documents/AI_research_corrected.pdf

date +%s > /tmp/research_deck_prep_start_ts

# Create the AI research overview presentation with injected errors
# Real data sources (NLP / LLM papers):
#   - BERT: Devlin et al., "BERT: Pre-training of Deep Bidirectional Transformers"
#     arXiv:1810.04805 — published October 11, 2018 (NOT 2019)
#     GLUE score: 80.5 (original BERT-Large)
#   - GPT-3: Brown et al., "Language Models are Few-Shot Learners"
#     arXiv:2005.14165 — published May 28, 2020 (NOT 2021)
#   - LLaMA: Touvron et al., "LLaMA: Open and Efficient Foundation Language Models"
#     arXiv:2302.13971 — published February 27, 2023 (NOT 2022)
#   - T5: Raffel et al., "Exploring the Limits of Transfer Learning" (JMLR 2020)
#   - GPT-2: Radford et al., 2019 (OpenAI)
#   - InstructGPT: Ouyang et al., 2022 (arXiv:2203.02155)
#   - RLHF/PPO: Schulman et al., 2017 (PPO paper)
#   - SuperGLUE benchmark: Wang et al., 2019 (NeurIPS 2019)
#   - MMLU: Hendrycks et al., 2021 (arXiv:2009.03300)
#   - HumanEval: Chen et al., 2021 (arXiv:2107.03374)
# CV papers (contaminating slides — not NLP):
#   - ImageNet: Russakovsky et al., IJCV 2015
#   - DALL-E 2: Ramesh et al., 2022 (arXiv:2204.06125)
#   - Stable Diffusion: Rombach et al., 2022 (CVPR 2022)
python3 << 'PYEOF'
import os
from pptx import Presentation
from pptx.util import Emu

PPTX_PATH = '/home/ga/Documents/AI_research_overview.pptx'
os.makedirs('/home/ga/Documents', exist_ok=True)

prs = Presentation()
prs.slide_width  = Emu(9144000)
prs.slide_height = Emu(6858000)

def get_layout(prs):
    for layout in prs.slide_layouts:
        phs = {ph.placeholder_format.idx for ph in layout.placeholders}
        if 0 in phs and 1 in phs:
            return layout
    return prs.slide_layouts[1]

def add_slide(prs, title_text, body_lines):
    layout = get_layout(prs)
    slide = prs.slides.add_slide(layout)
    for ph in slide.placeholders:
        if ph.placeholder_format.idx == 0:
            ph.text = title_text
        elif ph.placeholder_format.idx == 1:
            tf = ph.text_frame
            tf.clear()
            for i, line in enumerate(body_lines):
                if i == 0:
                    tf.paragraphs[0].text = line
                else:
                    p = tf.add_paragraph()
                    p.text = line
    return slide

# 22 slides:
# Slide 5:  WRONG YEAR — BERT (2019 should be 2018)
# Slide 8:  WRONG YEAR — GPT-3 (2021 should be 2020)
# Slide 12: WRONG YEAR — LLaMA (2022 should be 2023)
# Slide 15: VISION SLIDE (ImageNet benchmarks — not NLP)
# Slide 18: VISION SLIDE (DALL-E 2 / Stable Diffusion — not NLP)

slides_data = [
    # Slide 1
    ("FY2023 Annual Research Overview\nNatural Language Processing & Foundation Models",
     ["University AI Research Institute",
      "Presented to: Provost's Office and Research Sponsors",
      "March 2024 | CONFIDENTIAL",
      "Research group: 18 faculty, 94 PhD students, $12.4M in sponsored research",
      "Focus areas: Large Language Models, RLHF, AI Safety, Code Generation"]),

    # Slide 2
    ("Institute Research Portfolio FY2023",
     ["Active research grants: 34 (NSF: 12, DARPA: 8, NIH: 4, Industry: 10)",
      "Total sponsored research revenue FY2023: $12.4M (+18% YoY)",
      "Publications: 48 peer-reviewed papers (NeurIPS: 11, ICML: 9, EMNLP: 8, ACL: 7)",
      "PhD students graduated FY2023: 14 (8 to industry, 6 to faculty positions)",
      "Patents filed: 3 (pending); technology licenses: 2 executed"]),

    # Slide 3
    ("Research Theme 1: Large Language Model Alignment",
     ["RLHF (Reinforcement Learning from Human Feedback) for LLM safety",
      "InstructGPT approach (Ouyang et al., 2022, arXiv:2203.02155): SFT + RM + PPO pipeline",
      "Our contribution: novel reward model calibration reducing reward hacking by 34%",
      "Collaboration with: Stanford Center for Human-Compatible AI (CHAI)",
      "Grant: NSF #2312345 — $1.2M FY2023-2025"]),

    # Slide 4
    ("The Transformer Architecture: Foundational Context",
     ["Attention Is All You Need (Vaswani et al., 2017, NeurIPS 2017)",
      "Self-attention mechanism enables parallel computation vs. RNN sequential bottleneck",
      "Encoder-decoder for seq2seq; encoder-only for classification; decoder-only for generation",
      "Scaled dot-product attention: O(n²) memory complexity — key bottleneck at long context",
      "Our work: linear attention approximation (accepted ICML 2024)"]),

    # Slide 5 — WRONG YEAR: BERT published 2018, NOT 2019
    ("BERT and the Pretraining Paradigm",
     ["BERT (Devlin et al., 2019) achieved GLUE score 80.5, surpassing all prior NLP benchmarks",
      "BERT: Bidirectional Encoder Representations from Transformers (arXiv:1810.04805)",
      "Masked language modeling + next sentence prediction → transferable representations",
      "GLUE benchmark (Wang et al., 2018): 9 NLU tasks; BERT-Large score: 80.5",
      "Fine-tuning paradigm: single architecture for QA, NLI, sentiment, NER"]),

    # Slide 6
    ("T5 and the Text-to-Text Framework",
     ["T5 (Raffel et al., 2020, JMLR 2020): framed all NLP tasks as text-to-text generation",
      "Explored: model size, pre-training objectives, multi-task learning, fine-tuning strategies",
      "Concluded: scale + span-corruption pretraining most effective for transfer",
      "T5-11B: state-of-the-art at publication across GLUE, SuperGLUE, SQuAD, CNN/DM",
      "Introduced C4 dataset (Colossal Clean Crawled Corpus) — 750 GB of clean text"]),

    # Slide 7
    ("GPT-2 and Zero-Shot Generalization",
     ["GPT-2 (Radford et al., 2019, OpenAI Technical Report): 1.5B parameter autoregressive LM",
      "Key result: zero-shot performance competitive with supervised models on reading comprehension",
      "WebText dataset: 40 GB of high-quality web text (Reddit upvotes as quality filter)",
      "Initial release withheld citing misuse concerns — first major AI release controversy",
      "Influenced: staged model releases, model cards, and AI policy discussions at OpenAI"]),

    # Slide 8 — WRONG YEAR: GPT-3 published 2020, NOT 2021
    ("GPT-3 and Few-Shot Learning",
     ["GPT-3 (Brown et al., 2021) introduced few-shot learning via in-context examples",
      "arXiv:2005.14165 — 175B parameters; trained on 300B tokens (Common Crawl + books + web)",
      "Few-shot prompting: examples in context window replace task-specific fine-tuning",
      "MMLU (Hendrycks et al., 2021, arXiv:2009.03300): 5-shot GPT-3 scores 43.9% (57.1% is human avg)",
      "Impact: API-first AI product model; spawned the 'foundation model' terminology"]),

    # Slide 9
    ("InstructGPT and RLHF",
     ["InstructGPT (Ouyang et al., 2022, arXiv:2203.02155): aligning LLMs with human intent",
      "Pipeline: SFT (supervised fine-tuning) → RM (reward model training) → PPO optimization",
      "PPO (Schulman et al., 2017): Proximal Policy Optimization for stable RL training",
      "Human annotators preferred InstructGPT (1.3B) over GPT-3 (175B) 85% of the time",
      "Foundation for ChatGPT, Claude, and all major instruction-tuned models"]),

    # Slide 10
    ("Evaluation: GLUE, SuperGLUE, MMLU",
     ["GLUE (Wang et al., 2018): General Language Understanding Evaluation — 9 tasks",
      "SuperGLUE (Wang et al., 2019, NeurIPS 2019): harder successor; 8 tasks including WinoGrad",
      "MMLU (Hendrycks et al., 2021, arXiv:2009.03300): 57 academic subjects; tests world knowledge",
      "HumanEval (Chen et al., 2021, arXiv:2107.03374): code generation; 164 Python problems",
      "Our benchmark contributions: EduBench (submitted NeurIPS 2024), SafetyEval (ICLR 2024)"]),

    # Slide 11
    ("Code Generation and Programming Benchmarks",
     ["HumanEval (Chen et al., 2021): 164 hand-crafted Python problems with unit tests",
      "pass@k metric: probability that at least k samples contain a correct solution",
      "Codex (Chen et al., 2021): GPT-based, 12B params; pass@1=28.8%, pass@100=77.4%",
      "MBPP (Austin et al., 2021, arXiv:2108.07732): 374 crowd-sourced Python problems",
      "Our work: fine-tuned LLaMA-2 for scientific Python; pass@1=41.3% on SciCodeBench"]),

    # Slide 12 — WRONG YEAR: LLaMA published 2023, NOT 2022
    ("LLaMA and Efficient Open-Source LLMs",
     ["LLaMA (Touvron et al., 2022) demonstrated competitive performance with fewer parameters",
      "arXiv:2302.13971 — LLaMA-13B outperforms GPT-3 (175B) on most benchmarks",
      "Training data: CommonCrawl, C4, GitHub, Wikipedia, Books, ArXiv, StackExchange",
      "Open weights enabled: Alpaca (Stanford), Vicuna (LMSYS), WizardLM — fine-tuning ecosystem",
      "LLaMA-2 (Touvron et al., 2023): 7B/13B/70B, safety-tuned, commercially licensed"]),

    # Slide 13
    ("Mixture of Experts and Efficient Scaling",
     ["Sparse MoE: activate only a subset of parameters per token — reduces compute at inference",
      "Switch Transformer (Fedus et al., 2022, JMLR 2022): 1.6T parameters; sparse routing",
      "Mixtral-8x7B (Mistral AI, 2023): 8 experts, 2 active per token; outperforms LLaMA-2-70B",
      "Our lab: developed load-balancing auxiliary loss for MoE training stability",
      "Compute savings: MoE achieves comparable quality at ~3x lower FLOPs vs. dense equivalent"]),

    # Slide 14
    ("Research Theme 2: AI Safety and Robustness",
     ["Adversarial robustness: textual adversarial attacks (TextFooler, BERT-Attack)",
      "Hallucination mitigation: retrieval-augmented generation (RAG) reduces factual errors 41%",
      "Constitutional AI (Anthropic, 2022): RLHF using AI feedback instead of human feedback",
      "Our work: bias detection in instruction-tuned models (EMNLP 2023 best paper nomination)",
      "Grants: DARPA GARD program ($2.1M) and NSF FAIROS RCN ($0.4M)"]),

    # Slide 15 — VISION SLIDE (must be removed — not NLP)
    ("Computer Vision Benchmarks: ImageNet SOTA 2023",
     ["ImageNet (Russakovsky et al., IJCV 2015): 1.28M images, 1,000 classes; standard CV benchmark",
      "Top-1 accuracy milestones: AlexNet 2012 (56.5%) → ResNet 2015 (76.5%) → ViT 2021 (88.6%)",
      "Current SOTA: EVA-E (2023): 91.1% top-1 on ImageNet-1k (Chen et al., arXiv:2303.11331)",
      "ImageNet-21k pre-training: standard practice for transfer learning in CV",
      "NOTE: This slide is from the Computer Vision group deck — NOT part of NLP research overview"]),

    # Slide 16
    ("Retrieval-Augmented Generation (RAG)",
     ["RAG (Lewis et al., 2020, NeurIPS 2020): combines parametric LM with non-parametric retrieval",
      "Architecture: dense retriever (DPR) + seq2seq generator (BART) over Wikipedia index",
      "Reduces hallucination: RAG-Token F1 on Natural Questions 44.5 vs. closed-book 29.0",
      "LlamaIndex (2022) and LangChain (2022): RAG frameworks enabling production deployment",
      "Our work: domain-specific RAG for scientific literature (BioRAG, accepted ACL 2024)"]),

    # Slide 17
    ("Multimodal Foundation Models (NLP + Vision-Language)",
     ["CLIP (Radford et al., 2021, OpenAI): contrastive image-text pretraining; zero-shot classification",
      "Flamingo (Alayrac et al., 2022, NeurIPS 2022): few-shot VQA via cross-attention to frozen LM",
      "LLaVA (Liu et al., 2023, NeurIPS 2023): instruction-tuned multimodal LLaMA",
      "GPT-4V (OpenAI, 2023): first widely-available multimodal LLM with vision input",
      "Our work: extending RAG to multimodal retrieval (image+text) — ICLR 2024 workshop"]),

    # Slide 18 — VISION SLIDE (must be removed — not NLP)
    ("Diffusion Models for Image Synthesis: DALL-E 2 and Stable Diffusion",
     ["DALL-E 2 (Ramesh et al., 2022, arXiv:2204.06125): hierarchical text-conditional image generation",
      "CLIP embeddings condition the diffusion prior; generates 1024×1024 images",
      "Stable Diffusion (Rombach et al., CVPR 2022): latent diffusion in compressed space",
      "LDM (latent diffusion) reduces compute 10-30x vs. pixel-space diffusion",
      "NOTE: This slide is from the CV group presentation — NOT NLP research overview"]),

    # Slide 19
    ("Infrastructure: GPU Cluster and Computing Resources",
     ["HPC cluster: 64 nodes × 8 × A100-80GB = 512 A100 GPUs (40 petaFLOPS peak)",
      "Storage: 4 PB NFS scratch + 500 TB fast NVMe for training datasets",
      "Software stack: PyTorch 2.0, HuggingFace Transformers 4.38, Megatron-LM",
      "FY2023 GPU utilization: 87% average; 94% during NeurIPS submission crunch",
      "Cloud overflow: AWS p4d.24xlarge for burst capacity (~$32/hr); budget: $180K FY2023"]),

    # Slide 20
    ("FY2024 Research Roadmap",
     ["Q1-Q2 2024: LLaMA-2 fine-tuning on domain-specific scientific corpora",
      "Q2 2024: Submit Constitutional AI + RAG hybrid to ICML 2024",
      "Q3 2024: Release SciCodeBench open-source benchmark (pending IRB clearance)",
      "Q4 2024: Deliverables to DARPA GARD (Phase 2 report) and NSF (annual progress report)",
      "FY2025 targets: submit 3 NSF proposals; target $15M+ sponsored research revenue"]),

    # Slide 21
    ("Collaborations and External Partnerships",
     ["Academic: Stanford CHAI, MIT CSAIL, CMU LTI, UC Berkeley BAIR",
      "Industry: Google DeepMind (research gift $400K), Microsoft Research (joint publication)",
      "Government: DARPA, NSF, NIH National Library of Medicine",
      "International: ETH Zurich AI Center (faculty exchange), Oxford Future of Humanity Institute",
      "Student placement: Google 4, Anthropic 2, Meta AI 2, OpenAI 1, DeepMind 1 (FY2023)"]),

    # Slide 22
    ("Acknowledgments and Contact",
     ["Research sponsored by: NSF, DARPA, Google DeepMind, Microsoft Research",
      "Institute Director: contact at director@ai-institute.edu",
      "HPC support: University Research Computing Office (research-computing@university.edu)",
      "Data governance: all datasets managed per IRB protocol #2023-AI-0047",
      "Full publication list and preprints: ai-institute.edu/publications"]),
]

for title_text, body_lines in slides_data:
    add_slide(prs, title_text, body_lines)

prs.save(PPTX_PATH)
print(f"Created {PPTX_PATH} with {len(prs.slides)} slides")
PYEOF

# Create the research integrity memo (does NOT name slide numbers)
cat > /home/ga/Desktop/research_integrity_memo.txt << 'DOCEOF'
UNIVERSITY AI RESEARCH INSTITUTE
RESEARCH INTEGRITY OFFICE

MEMO: Pre-Submission Review — Annual Research Overview Presentation
To: Director of Research Computing
From: Research Integrity Officer
Date: March 8, 2024
Re: Corrections Required Before Distribution

The draft at /home/ga/Documents/AI_research_overview.pptx has been reviewed and
three issues must be corrected before the presentation is shared with the Provost's
office or external sponsors.

─────────────────────────────────────────────────────────────────
ISSUE 1: INCORRECT PUBLICATION YEARS FOR CITED PAPERS
─────────────────────────────────────────────────────────────────
The presentation cites three foundational papers with incorrect publication years.
Incorrect citation years misrepresent the chronology of scientific progress and
constitute inaccurate attribution — a violation of research integrity standards.

Reference list (correct publication years):
  • BERT (Devlin et al.) — arXiv:1810.04805 — Published: October 2018
  • GPT-3 (Brown et al.) — arXiv:2005.14165 — Published: May 2020
  • LLaMA (Touvron et al.) — arXiv:2302.13971 — Published: February 2023

For each slide that cites one of these papers, verify that the year shown in the
citation matches the correct year from the reference list above. If a slide says
"Devlin et al., 2019," "Brown et al., 2021," or "Touvron et al., 2022," the year
must be corrected to 2018, 2020, or 2023 respectively.

─────────────────────────────────────────────────────────────────
ISSUE 2: COMPUTER VISION SLIDES IN NLP RESEARCH OVERVIEW
─────────────────────────────────────────────────────────────────
This presentation is the Natural Language Processing and Foundation Models research
overview. Two slides from the Computer Vision research group have been accidentally
included. These slides describe ImageNet benchmarks, image synthesis benchmarks,
and diffusion model architectures — topics entirely unrelated to NLP research.

Presenting another group's research work as part of this institute's NLP research
overview is misleading to sponsors and the Provost. These slides must be removed.
Any slide whose content primarily describes image synthesis, computer vision
benchmarks, or image generation models (rather than NLP, language understanding,
text generation, or language model training) should be deleted.

─────────────────────────────────────────────────────────────────
ISSUE 3: PDF COPY REQUIRED FOR PROVOST'S OFFICE
─────────────────────────────────────────────────────────────────
The Provost's office requires all research presentations to be submitted as PDF
for archival purposes. After correcting issues 1 and 2 above, export the corrected
presentation as a PDF file to:

    /home/ga/Documents/AI_research_corrected.pdf

─────────────────────────────────────────────────────────────────
REQUIRED ACTION SUMMARY
─────────────────────────────────────────────────────────────────
1. Correct the three paper citation years (BERT 2018, GPT-3 2020, LLaMA 2023)
2. Remove computer vision slides from the NLP research overview
3. Save the corrected PPTX as: /home/ga/Documents/AI_research_corrected.pptx
4. Export a PDF copy to: /home/ga/Documents/AI_research_corrected.pdf
5. Do NOT modify the original at: /home/ga/Documents/AI_research_overview.pptx
DOCEOF

chown ga:ga /home/ga/Documents/AI_research_overview.pptx
chown ga:ga /home/ga/Desktop/research_integrity_memo.txt
chown -R ga:ga /home/ga/Documents

launch_wps_with_file "/home/ga/Documents/AI_research_overview.pptx"

elapsed=0
while [ $elapsed -lt 60 ]; do
    dismiss_eula_if_present
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "AI_research_overview"; then
        echo "WPS loaded AI_research_overview.pptx after ${elapsed}s"
        sleep 3
        break
    fi
    if DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -l 2>/dev/null | grep -q "WPS Office"; then
        DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool mousemove 1280 630 click 1 2>/dev/null || true
        sleep 1
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

maximize_wps
sleep 2
take_screenshot /tmp/research_deck_prep_start_screenshot.png

echo "=== research_deck_prep setup complete ==="
echo "AI_research_overview.pptx created (22 slides)"
echo "Presentation requires correction per integrity memo"
echo "PDF export also required — see integrity memo"
echo "Integrity memo placed on Desktop"
