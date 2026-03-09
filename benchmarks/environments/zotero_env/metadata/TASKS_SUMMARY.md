# Zotero Environment - Tasks Summary

## Overview

This environment provides **Zotero 7.x**, an open-source reference management application, for bibliographic organization and citation management tasks. Agents interact with Zotero through the GNOME desktop GUI to import, organize, and manage research papers.

## Tasks

### Task 1: Import BibTeX Library
**ID**: `import_bibtex_library@1`

**Description**: Import a BibTeX bibliography file containing 10 classic computer science and physics papers (Einstein, Turing, Knuth, Shannon, etc.) into your Zotero library.

**Objective**:
- Navigate to File > Import
- Select `/home/ga/Documents/classic_papers.bib`
- Import the bibliography

**Success Criteria**:
- 9-11 items added to library
- Expected authors found (Einstein, Turing, Knuth, Shannon)
- BibTeX import confirmed

**Timeout**: 180 seconds | **Max Steps**: 30

---

### Task 2: Create Collection and Organize
**ID**: `create_collection_organize@1`

**Description**: Create a new collection named "Machine Learning Papers" and import an RIS file containing 8 foundational ML papers into this collection.

**Objective**:
- Create a new collection: "Machine Learning Papers"
- Import `/home/ga/Documents/machine_learning_papers.ris` into this collection
- Verify papers appear in the collection

**Success Criteria**:
- Collection "Machine Learning Papers" exists
- 7-9 items imported into the collection
- Items are properly organized

**Timeout**: 180 seconds | **Max Steps**: 40

---

### Task 3: Add Tags to Items
**ID**: `add_tags_to_items@1`

**Description**: Organize library items by adding at least 3 different relevant tags to research papers related to AI/ML topics.

**Objective**:
- Select items in your library
- Add relevant tags (e.g., 'deep-learning', 'neural-networks', 'computer-vision', 'NLP')
- Ensure at least 2 items are tagged

**Success Criteria**:
- At least 3 different tags added
- At least 2 items tagged
- Tags are relevant to research topics

**Timeout**: 180 seconds | **Max Steps**: 35

---

## Data Sources

All data files use **real academic papers** from published literature:

### classic_papers.bib (BibTeX format)
- Einstein (1905): On the electrodynamics of moving bodies
- Turing (1936): On computable numbers
- Knuth (1984): The TeXbook
- Shannon (1948): A mathematical theory of communication
- Dijkstra (1959): A note on two problems in connexion with graphs
- Church (1936): An unsolvable problem of elementary number theory
- Feynman (1965): Space-time view of quantum electrodynamics
- Darwin (1859): On the origin of species
- Watson & Crick (1953): Molecular structure of nucleic acids
- von Neumann (1945): First draft of a report on the EDVAC

### machine_learning_papers.ris (RIS format)
- LeCun, Bengio, Hinton (2015): Deep learning (Nature)
- Krizhevsky, Sutskever, Hinton (2012): ImageNet classification with deep CNNs
- Goodfellow et al. (2014): Generative adversarial nets
- Vaswani et al. (2017): Attention is all you need
- Silver et al. (2016): Mastering the game of Go
- Brown et al. (2020): Language models are few-shot learners (GPT-3)
- Devlin et al. (2019): BERT
- He et al. (2016): Deep residual learning for image recognition (ResNet)

## Technical Details

**Application**: Zotero 7.0.11
**Database**: SQLite (`/home/ga/Zotero/zotero.sqlite`)
**Profile**: `/home/ga/.zotero/zotero/*.default`
**Data Directory**: `/home/ga/Zotero`

## Verification Method

All tasks use programmatic verification:
1. **Export script** queries Zotero SQLite database
2. **Verifier** evaluates JSON results against criteria
3. Scores based on multiple criteria (item counts, metadata, relationships)

## Environment Resources

- **CPU**: 4 cores
- **Memory**: 4 GB
- **Display**: 1920x1080 (GNOME desktop)
- **Network**: Enabled (for potential future tasks involving online import)
