# Gym-Anything Website Layout

## Design Philosophy
- Research-credible, not startup-marketing
- Dark theme (near-black background, white text, accent colors)
- ALL numbers pulled from actual paper data — nothing fabricated
- Top hero section is the highest priority
- Clean, spacious, typographically strong

## Color Palette
- Background: #0a0a0a (near black)
- Cards/sections: #141414 / #1a1a1a
- Primary accent: #22d3ee (cyan) — for highlights, buttons
- Secondary: #a78bfa (soft purple) — for secondary elements
- Text: #f5f5f5 (primary), #a1a1aa (muted)
- Success/green: #4ade80
- Warm accent: #f59e0b (amber)

## Tech Stack
- Single index.html with embedded CSS/JS
- No build tools, no framework — pure HTML/CSS/JS
- Google Fonts for typography
- CSS animations for carousels/reels
- Chart.js or inline SVG for result charts (using real data)

---

## Section 1: Hero
**Goal:** Instantly communicate what Gym-Anything does.

- **Title:** "Gym-Anything" in large bold type
- **Subtitle:** "Turn Any Software into an Agent Environment"
- **Authors:** Pranjal Aggarwal, Graham Neubig, Sean Welleck · CMU (smaller, muted)
- **TLDR blurb:** 2-3 sentences. Something like:
  "Got a software? Gym-Anything automatically converts it into a computer-use
  agent environment — complete with realistic data, tasks, and verification.
  No manual setup needed."
- **Action buttons:** [Paper] [Code] [Leaderboard ↓] [Explore CUA-World ↓]

## Section 2: Software Carousel
**Goal:** Visual proof of breadth and diversity.

- Two rows of software screenshots scrolling in opposite directions (infinite loop)
- Each card: screenshot image + software name label below
- Slow, smooth, continuous auto-scroll
- Uses mosaic_screenshots/ and figures/task_examples/ images
- On hover: card slightly scales up, scroll pauses

## Section 3: Key Numbers Bar
**Goal:** Quick stats that anchor credibility.

- Horizontal row of 4 stat cards:
  - "200+" / Software Environments
  - "10,000+" / Tasks & Environments
  - "22/22" / SOC Occupation Groups
  - "3" / Operating Systems (Linux, Windows, Android)

## Section 4: How It Works
**Goal:** Brief, clear explanation of the pipeline. Not the audit details — just the core insight.

- Section heading: "How It Works"
- 3 horizontal cards/steps:
  1. **Select** — GDP-grounded software selection. "We identify economically important software using U.S. GDP data."
  2. **Create** — Agent-built environments. "A coding agent automatically installs, configures, and populates each software with real-world data."
  3. **Scale** — Task generation. "5 seed tasks per software, amplified to 75 via LLM, yielding 10K+ verified tasks."
- Below: single teaser image (final_teaser_v2.png) showing the full pipeline

## Section 5: Occupation / Industry / Software Reels
**Goal:** Showcase the breadth of coverage in an engaging way.

- 3 vertical "slot machine" reels side by side:
  - Reel 1: Occupations (all 22 SOC groups, scrolling)
  - Reel 2: Industries / Domains
  - Reel 3: Software names
- Auto-spinning, occasionally stopping at random positions
- When stopped: right side shows a representative screenshot + sample task description for that software
- Smooth CSS animation for the reel spin effect

## Section 6: Leaderboard (CUA-World-Long)
**Goal:** Forward-looking benchmark table.

- Section heading: "Leaderboard: CUA-World-Long"
- Subtitle: "200 long-horizon tasks, one per software. Best model: 14.0% pass rate."
- Table with columns: Rank | Model | Avg Score | Pass Rate (%)
- Data from paper:
  - Gemini 3 Flash + TTA: 39.9, 14.0%
  - Gemini 3 Flash: 36.2, 7.5%
  - Kimi-K 2.5: 33.9, 5.5%
  - Sonnet 4.6: 20.5, 6.0%
  - GPT-5.4: 22.7, 3.0%
- Note at bottom: "Submit your results: [link placeholder]"

## Section 7: Results
**Goal:** 3 key results, interactive/visual.

Three sub-panels:

### 7a: Training Data Scaling
- Line chart (from fig_scaling.py data):
  - X: 0%, 25%, 50%, 100% of training data
  - Two lines: # Software (blue), # Tasks (red)
  - Values: baseline 12.7; software: 16.3, 17.6, 22.5; tasks: 14.6, 18.3, 22.5

### 7b: Generalization (IID vs OOD)
- Grouped bar chart (from fig_generalization.py data):
  - 25% Software: IID 24.2, OOD 14.1
  - 50% Software: IID 21.0, OOD 14.6

### 7c: Test-Time Compute Scaling
- Line chart (from fig_ttc_scaling.py data):
  - X: average steps (48.9, 96.8, 186.3, 406.7, 1281.6)
  - Y: pass rate (2.0, 2.5, 6.5, 7.5, 11.5)
  - Star marker for TTA: 14.0% at 1384.7 steps

## Section 8: Explore CUA-World (Placeholder)
**Goal:** Teaser for the full collection browser.

- "Explore CUA-World" heading
- Brief text: "Browse 200+ software environments, tasks, and agent trajectories."
- Placeholder card grid showing 6-8 software with screenshot + name + task count
- "Coming Soon" or expandable placeholder

## Section 9: Citation
**Goal:** Easy copy of BibTeX.

- Dark code block with BibTeX entry
- Copy button
- Links: [arXiv] [GitHub] [Dataset]

---

## Asset Requirements
- mosaic_screenshots/*.png (12 images available)
- figures/task_examples/*.png (48 images: 12 software × 4 trajectory steps each)
- figures/softwares_mosaic_v7b_final.png (full mosaic)
- figures/final_teaser_v2.png (pipeline overview)
- All result numbers hardcoded from analysis scripts (verified data)
