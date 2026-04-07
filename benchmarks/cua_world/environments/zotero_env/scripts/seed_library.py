#!/usr/bin/env python3
"""
Seed Zotero library with academic papers for task pre-setup.

Zotero 7 schema key facts:
  - journalArticle = itemTypeID 22
  - note = itemTypeID 28, attachment = 3, annotation = 1
  - creators table: (creatorID, firstName, lastName, fieldMode)
  - author creatorTypeID = 8
  - Field IDs: title=1, abstractNote=2, date=6, volume=19, pages=32,
               publicationTitle=38, issue=76, DOI=59
  - libraryID = 1 (user library)
  - tags table: (tagID, name)  -- ONLY these two columns in Zotero 7; type lives in itemTags
  - itemTags table: (itemID, tagID, type)
  - itemTags table: (itemID, tagID, type)
  - savedSearches table: (savedSearchID, savedSearchName, ..., libraryID, key, ...)
  - savedSearchConditions table: (savedSearchID, searchConditionID, condition, operator, value, ...)

Usage:
  python3 seed_library.py --mode all
  python3 seed_library.py --mode classic
  python3 seed_library.py --mode ml
  python3 seed_library.py --mode ml_with_collection
  python3 seed_library.py --mode classic_with_errors
  python3 seed_library.py --mode all_with_errors
  python3 seed_library.py --mode triage_pipeline
  python3 seed_library.py --mode metadata_audit
  python3 seed_library.py --mode duplicate_merge
  python3 seed_library.py --mode hierarchical_reorg
  python3 seed_library.py --mode citation_qa
  python3 seed_library.py --mode systematic_review

Outputs JSON to stdout with item IDs for use by task scripts.
"""

import sqlite3
import random
import string
import time
import os
import sys
import json
import argparse

DB_PATH = "/home/ga/Zotero/zotero.sqlite"
LIBRARY_ID = 1

# ── Paper data ──────────────────────────────────────────────────────────────

CLASSIC_PAPERS = [
    {
        "title": "On the Electrodynamics of Moving Bodies",
        "year": "1905",
        "publication": "Annalen der Physik",
        "authors": [("Albert", "Einstein")],
        "volume": "17",
        "pages": "891-921",
    },
    {
        "title": "On Computable Numbers, with an Application to the Entscheidungsproblem",
        "year": "1936",
        "publication": "Proceedings of the London Mathematical Society",
        "authors": [("Alan", "Turing")],
        "volume": "42",
        "pages": "230-265",
    },
    {
        "title": "A Mathematical Theory of Communication",
        "year": "1948",
        "publication": "Bell System Technical Journal",
        "authors": [("Claude E.", "Shannon")],
        "volume": "27",
        "pages": "379-423",
    },
    {
        "title": "A Note on Two Problems in Connexion with Graphs",
        "year": "1959",
        "publication": "Numerische Mathematik",
        "authors": [("Edsger W.", "Dijkstra")],
        "volume": "1",
        "pages": "269-271",
    },
    {
        "title": "Molecular Structure of Nucleic Acids: A Structure for Deoxyribose Nucleic Acid",
        "year": "1953",
        "publication": "Nature",
        "authors": [("James D.", "Watson"), ("Francis H.C.", "Crick")],
        "volume": "171",
        "pages": "737-738",
    },
    {
        "title": "An Unsolvable Problem of Elementary Number Theory",
        "year": "1936",
        "publication": "American Journal of Mathematics",
        "authors": [("Alonzo", "Church")],
        "volume": "58",
        "pages": "345-363",
    },
    {
        "title": "Computing Machinery and Intelligence",
        "year": "1950",
        "publication": "Mind",
        "authors": [("Alan", "Turing")],
        "volume": "59",
        "pages": "433-460",
    },
    {
        "title": "A Method for the Construction of Minimum-Redundancy Codes",
        "year": "1952",
        "publication": "Proceedings of the IRE",
        "authors": [("David A.", "Huffman")],
        "volume": "40",
        "pages": "1098-1101",
    },
    {
        "title": "Recursive Functions of Symbolic Expressions and Their Computation by Machine, Part I",
        "year": "1960",
        "publication": "Communications of the ACM",
        "authors": [("John", "McCarthy")],
        "volume": "3",
        "pages": "184-195",
    },
    {
        "title": "The Mathematical Theory of Communication",
        "year": "1949",
        "publication": "University of Illinois Press",
        "authors": [("Claude E.", "Shannon"), ("Warren", "Weaver")],
    },
]

ML_PAPERS = [
    {
        "title": "Attention Is All You Need",
        "year": "2017",
        "publication": "Advances in Neural Information Processing Systems",
        "authors": [
            ("Ashish", "Vaswani"), ("Noam", "Shazeer"), ("Niki", "Parmar"), ("Jakob", "Uszkoreit"),
        ],
        "volume": "30",
    },
    {
        "title": "BERT: Pre-training of Deep Bidirectional Transformers for Language Understanding",
        "year": "2019",
        "publication": "Proceedings of NAACL-HLT 2019",
        "authors": [
            ("Jacob", "Devlin"), ("Ming-Wei", "Chang"), ("Kenton", "Lee"), ("Kristina", "Toutanova"),
        ],
    },
    {
        "title": "Language Models are Few-Shot Learners",
        "year": "2020",
        "publication": "Advances in Neural Information Processing Systems",
        "authors": [("Tom B.", "Brown"), ("Benjamin", "Mann"), ("Nick", "Ryder")],
        "volume": "33",
    },
    {
        "title": "ImageNet Classification with Deep Convolutional Neural Networks",
        "year": "2012",
        "publication": "Advances in Neural Information Processing Systems",
        "authors": [("Alex", "Krizhevsky"), ("Ilya", "Sutskever"), ("Geoffrey E.", "Hinton")],
        "volume": "25",
        "pages": "1097-1105",
    },
    {
        "title": "Deep Residual Learning for Image Recognition",
        "year": "2016",
        "publication": "Proceedings of the IEEE Conference on Computer Vision and Pattern Recognition",
        "authors": [("Kaiming", "He"), ("Xiangyu", "Zhang"), ("Shaoqing", "Ren"), ("Jian", "Sun")],
        "pages": "770-778",
    },
    {
        "title": "Generative Adversarial Nets",
        "year": "2014",
        "publication": "Advances in Neural Information Processing Systems",
        "authors": [("Ian J.", "Goodfellow"), ("Jean", "Pouget-Abadie"), ("Mehdi", "Mirza")],
        "volume": "27",
    },
    {
        "title": "Deep Learning",
        "year": "2015",
        "publication": "Nature",
        "authors": [("Yann", "LeCun"), ("Yoshua", "Bengio"), ("Geoffrey", "Hinton")],
        "volume": "521",
        "pages": "436-444",
        "doi": "10.1038/nature14539",
    },
    {
        "title": "Mastering the Game of Go with Deep Neural Networks and Tree Search",
        "year": "2016",
        "publication": "Nature",
        "authors": [("David", "Silver"), ("Aja", "Huang"), ("Chris J.", "Maddison")],
        "volume": "529",
        "pages": "484-489",
    },
]

# ── Hard task datasets (distinct from CLASSIC_PAPERS and ML_PAPERS) ──────────

# 20 systems/distributed-systems papers for triage_pipeline task.
# Papers at indices 0,2,4,8,12,18 are pre-tagged "priority".
# Pre-2010 priority: indices 0(1974), 2(1984), 4(2003), 8(2001) → should become "review-now"
# Post-2010 priority: indices 12(2014), 18(2019) → should become "review-later"
SYSTEMS_PAPERS = [
    {"title": "The UNIX Time-Sharing System", "year": "1974",
     "publication": "Communications of the ACM",
     "authors": [("Dennis M.", "Ritchie"), ("Ken", "Thompson")], "volume": "17", "pages": "365-375"},
    {"title": "Ethernet: Distributed Packet Switching for Local Computer Networks", "year": "1976",
     "publication": "Communications of the ACM",
     "authors": [("Robert M.", "Metcalfe"), ("David R.", "Boggs")], "volume": "19", "pages": "395-404"},
    {"title": "End-to-End Arguments in System Design", "year": "1984",
     "publication": "ACM Transactions on Computer Systems",
     "authors": [("Jerome H.", "Saltzer"), ("David P.", "Reed"), ("David D.", "Clark")],
     "volume": "2", "pages": "277-288"},
    {"title": "The Design and Implementation of a Log-Structured File System", "year": "1992",
     "publication": "ACM Transactions on Computer Systems",
     "authors": [("Mendel", "Rosenblum"), ("John K.", "Ousterhout")], "volume": "10", "pages": "26-52"},
    {"title": "The Google File System", "year": "2003",
     "publication": "Proceedings of the 19th ACM Symposium on Operating Systems Principles",
     "authors": [("Sanjay", "Ghemawat"), ("Howard", "Gobioff"), ("Shun-Tak", "Leung")],
     "pages": "29-43"},
    {"title": "MapReduce: Simplified Data Processing on Large Clusters", "year": "2004",
     "publication": "Proceedings of the 6th USENIX Symposium on Operating Systems Design and Implementation",
     "authors": [("Jeffrey", "Dean"), ("Sanjay", "Ghemawat")], "pages": "137-150"},
    {"title": "Bigtable: A Distributed Storage System for Structured Data", "year": "2006",
     "publication": "Proceedings of the 7th USENIX Symposium on Operating Systems Design and Implementation",
     "authors": [("Fay", "Chang"), ("Jeffrey", "Dean"), ("Sanjay", "Ghemawat")], "pages": "205-218"},
    {"title": "Dynamo: Amazon's Highly Available Key-value Store", "year": "2007",
     "publication": "Proceedings of the 21st ACM Symposium on Operating Systems Principles",
     "authors": [("Giuseppe", "DeCandia"), ("Deniz", "Hastorun"), ("Madan", "Jampani")],
     "pages": "205-220"},
    {"title": "Chord: A Scalable Peer-to-peer Lookup Service for Internet Applications", "year": "2001",
     "publication": "Proceedings of ACM SIGCOMM",
     "authors": [("Ion", "Stoica"), ("Robert", "Morris"), ("David", "Karger"), ("M. Frans", "Kaashoek")],
     "pages": "149-160"},
    {"title": "Paxos Made Simple", "year": "2001",
     "publication": "ACM SIGACT News",
     "authors": [("Leslie", "Lamport")], "volume": "32", "pages": "18-25"},
    {"title": "ZooKeeper: Wait-free Coordination for Internet-scale Systems", "year": "2010",
     "publication": "Proceedings of the USENIX Annual Technical Conference",
     "authors": [("Patrick", "Hunt"), ("Mahadev", "Konar"), ("Flavio P.", "Junqueira"), ("Benjamin", "Reed")],
     "pages": "145-158"},
    {"title": "Cassandra: A Decentralized Structured Storage System", "year": "2010",
     "publication": "ACM SIGOPS Operating Systems Review",
     "authors": [("Avinash", "Lakshman"), ("Prashant", "Malik")], "volume": "44", "pages": "35-40"},
    {"title": "Raft: In Search of an Understandable Consensus Algorithm", "year": "2014",
     "publication": "Proceedings of the USENIX Annual Technical Conference",
     "authors": [("Diego", "Ongaro"), ("John", "Ousterhout")], "pages": "305-319"},
    {"title": "Resilient Distributed Datasets: A Fault-Tolerant Abstraction for In-Memory Cluster Computing",
     "year": "2012",
     "publication": "Proceedings of the 9th USENIX Symposium on Networked Systems Design and Implementation",
     "authors": [("Matei", "Zaharia"), ("Mosharaf", "Chowdhury"), ("Tathagata", "Das")], "pages": "15-28"},
    {"title": "Spanner: Google's Globally Distributed Database", "year": "2012",
     "publication": "ACM Transactions on Computer Systems",
     "authors": [("James C.", "Corbett"), ("Jeffrey", "Dean"), ("Michael", "Epstein")],
     "volume": "31", "pages": "8:1-8:22"},
    {"title": "Apache Kafka: A Distributed Messaging System for Log Processing", "year": "2011",
     "publication": "Proceedings of the NetDB Workshop",
     "authors": [("Jay", "Kreps"), ("Neha", "Narkhede"), ("Jun", "Rao")]},
    {"title": "Scaling Distributed Machine Learning with the Parameter Server", "year": "2014",
     "publication": "Proceedings of the 11th USENIX Symposium on Operating Systems Design and Implementation",
     "authors": [("Mu", "Li"), ("David G.", "Anderson"), ("Jun Woo", "Park")], "pages": "583-598"},
    {"title": "Serverless Computation with OpenLambda", "year": "2016",
     "publication": "Proceedings of the 8th USENIX Workshop on Hot Topics in Cloud Computing",
     "authors": [("Scott", "Hendrickson"), ("Stephen", "Sturdevant"), ("Tyler", "Harter")]},
    {"title": "CockroachDB: The Resilient Geo-Distributed SQL Database", "year": "2020",
     "publication": "Proceedings of ACM SIGMOD International Conference on Management of Data",
     "authors": [("Rebecca", "Taft"), ("Irfan", "Sharif"), ("Andrei", "Matei")], "pages": "1493-1509"},
    {"title": "TiKV: A Distributed Transactional Key-Value Database", "year": "2019",
     "publication": "Proceedings of ACM SIGMOD International Conference on Management of Data",
     "authors": [("Dongxu", "Huang"), ("Qi", "Liu"), ("Qiu", "Cui")], "pages": "2289-2300"},
]
# Indices of priority-tagged papers in SYSTEMS_PAPERS:
# 0=UNIX(1974), 2=End-to-End(1984), 4=GFS(2003), 8=Chord(2001) → review-now
# 12=Raft(2014), 19=TiKV(2019) → review-later
SYSTEMS_PRIORITY_INDICES = [0, 2, 4, 8, 12, 19]

# 25 biology/medicine papers for metadata_audit task.
# The first 15 have planted errors; the last 10 are clean.
# Year errors (indices 0-4): stored wrong year (off by 10).
# Name swap errors (indices 5-9): firstName=actual_last_name, lastName=actual_first_name.
# Abstract placeholder (indices 10-14): abstract = "Abstract not available".
SCIENCE_PAPERS = [
    # ── Year errors (stored wrong year, should be noted by ._correct_year) ────
    {"title": "Caspase Activation Mechanisms in Apoptotic Cell Death",
     "year": "1988",   # Wrong! caspases were characterized ~1998
     "_correct_year": "1998",
     "publication": "Cell", "authors": [("Xiaodong", "Wang")], "volume": "91", "pages": "479-489",
     "abstract": "We describe the biochemical cascade leading to caspase activation during programmed cell death."},
    {"title": "RNA Interference: Gene Silencing by Double-Stranded RNA",
     "year": "1988",   # Wrong! RNAi discovered 1998
     "_correct_year": "1998",
     "publication": "Nature", "authors": [("Andrew Z.", "Fire"), ("SiQun", "Xu")],
     "volume": "391", "pages": "806-811",
     "abstract": "We describe potent and specific genetic interference by double-stranded RNA."},
    {"title": "CRISPR-Cas9-Mediated Genome Editing in Human Cells",
     "year": "2003",   # Wrong! CRISPR editing was demonstrated ~2013
     "_correct_year": "2013",
     "publication": "Science", "authors": [("Le", "Cong"), ("F. Ann", "Ran"), ("David", "Cox")],
     "volume": "339", "pages": "819-823",
     "abstract": "Clustered regularly interspaced short palindromic repeats (CRISPR) enable targeted genome editing."},
    {"title": "Stem Cell-Derived Cerebral Organoids Model Human Brain Development",
     "year": "2003",   # Wrong! cerebral organoids paper was 2013
     "_correct_year": "2013",
     "publication": "Nature", "authors": [("Madeline A.", "Lancaster"), ("Magdalena", "Gotz")],
     "volume": "501", "pages": "373-379",
     "abstract": "We describe the generation of cerebral organoids, three-dimensional structures that model human brain development."},
    {"title": "Single-Cell RNA Sequencing Reveals Transcriptional Heterogeneity",
     "year": "2005",   # Wrong! scRNA-seq technology emerged ~2015
     "_correct_year": "2015",
     "publication": "Cell", "authors": [("Rahul", "Satija"), ("Jeffrey A.", "Farrell"), ("David", "Gennert")],
     "volume": "162", "pages": "666-677",
     "abstract": "Single-cell transcriptomics reveals extensive heterogeneity within seemingly homogeneous cell populations."},
    # ── Swapped author names (firstName=actual_last, lastName=actual_first) ───
    {"title": "Molecular Mechanisms of Synaptic Vesicle Endocytosis",
     "year": "2000",
     "publication": "Neuron",
     "authors": [("Bhaskara", "Elena"),   # Wrong! Should be ("Elena", "Bhaskara") → i.e. firstName=Elena, lastName=Bhaskara
                 ("Michael", "Bhaskara")],
     "_swapped_author_idx": 0,
     "_correct_first": "Elena", "_correct_last": "Bhaskara",
     "volume": "28", "pages": "317-320",
     "abstract": "Synaptic vesicle recycling is essential for sustained neurotransmitter release."},
    {"title": "Chromatin Remodeling Complexes and Gene Regulation",
     "year": "2005",
     "publication": "Annual Review of Biochemistry",
     "authors": [("Peterson", "Craig L."),   # Wrong! Should be ("Craig L.", "Peterson")
                 ("Jerry L.", "Workman")],
     "_swapped_author_idx": 0,
     "_correct_first": "Craig L.", "_correct_last": "Peterson",
     "volume": "74", "pages": "755-792",
     "abstract": "ATP-dependent chromatin remodeling complexes regulate gene expression by repositioning nucleosomes."},
    {"title": "Insulin Signaling and the Regulation of Glucose Metabolism",
     "year": "2001",
     "publication": "Nature",
     "authors": [("Saltiel", "Alan R."),   # Wrong! Should be ("Alan R.", "Saltiel")
                 ("C. Ronald", "Kahn")],
     "_swapped_author_idx": 0,
     "_correct_first": "Alan R.", "_correct_last": "Saltiel",
     "volume": "414", "pages": "799-806",
     "abstract": "Insulin activates a complex network of signaling cascades to regulate glucose uptake and metabolism."},
    {"title": "The Role of MicroRNAs in Cancer Biology",
     "year": "2006",
     "publication": "Nature Reviews Cancer",
     "authors": [("Calin", "George A."),   # Wrong! Should be ("George A.", "Calin")
                 ("Carlo M.", "Croce")],
     "_swapped_author_idx": 0,
     "_correct_first": "George A.", "_correct_last": "Calin",
     "volume": "6", "pages": "857-866",
     "abstract": "MicroRNAs act as oncogenes or tumor suppressors depending on cellular context."},
    {"title": "Autophagy: Cellular and Molecular Mechanisms",
     "year": "2010",
     "publication": "Journal of Pathology",
     "authors": [("Mizushima", "Noboru"),   # Wrong! Should be ("Noboru", "Mizushima")
                 ("Beth", "Levine")],
     "_swapped_author_idx": 0,
     "_correct_first": "Noboru", "_correct_last": "Mizushima",
     "volume": "221", "pages": "3-12",
     "abstract": "Autophagy is a conserved degradation pathway essential for cellular homeostasis."},
    # ── Placeholder abstracts ─────────────────────────────────────────────────
    {"title": "Telomere Dynamics and Cellular Senescence",
     "year": "2003",
     "publication": "Cell",
     "authors": [("Titia", "de Lange")], "volume": "120", "pages": "656-667",
     "abstract": "Abstract not available"},
    {"title": "Mechanisms of Antibiotic Resistance in Gram-Negative Bacteria",
     "year": "2010",
     "publication": "Nature Reviews Microbiology",
     "authors": [("Julian", "Davies"), ("Dorothy", "Davies")], "volume": "8", "pages": "636-648",
     "abstract": "Abstract not available"},
    {"title": "The Gut Microbiome and Human Health",
     "year": "2012",
     "publication": "Science",
     "authors": [("Justin L.", "Sonnenburg"), ("Fredrik", "Backhed")], "volume": "336", "pages": "1262-1267",
     "abstract": "Abstract not available"},
    {"title": "Immune Checkpoint Blockade in Cancer Therapy",
     "year": "2014",
     "publication": "Science",
     "authors": [("Suzanne L.", "Topalian"), ("Charles G.", "Drake"), ("Drew M.", "Pardoll")],
     "volume": "344", "pages": "1. 1. 1248-1250",
     "abstract": "Abstract not available"},
    {"title": "Protein Structure Prediction Using Deep Learning",
     "year": "2021",
     "publication": "Nature",
     "authors": [("John M.", "Jumper"), ("Richard", "Evans"), ("Alexander", "Pritzel")],
     "volume": "596", "pages": "583-589",
     "abstract": "Abstract not available"},
    # ── Clean papers (no errors) ───────────────────────────────────────────────
    {"title": "The Hallmarks of Cancer", "year": "2000",
     "publication": "Cell", "authors": [("Douglas", "Hanahan"), ("Robert A.", "Weinberg")],
     "volume": "100", "pages": "57-70",
     "abstract": "This review describes the essential alterations in cell physiology that collectively dictate malignant growth."},
    {"title": "Structure of the HIV-1 Protease", "year": "1989",
     "publication": "Nature", "authors": [("Melanie", "Miller"), ("Madeleine", "Jaskólski")],
     "volume": "337", "pages": "576-579",
     "abstract": "The three-dimensional structure of HIV protease has been determined by X-ray crystallography."},
    {"title": "Signal Transduction by the B Cell Antigen Receptor", "year": "1994",
     "publication": "Annual Review of Immunology",
     "authors": [("Tomohiro", "Kurosaki")], "volume": "17", "pages": "555-592",
     "abstract": "B cell activation requires coordinated signals from multiple receptor systems."},
    {"title": "Mechanisms of Tumor Angiogenesis", "year": "1989",
     "publication": "Journal of Clinical Investigation",
     "authors": [("Judah", "Folkman")], "volume": "84", "pages": "1018-1027",
     "abstract": "Tumor growth beyond 2-3mm requires the induction of new blood vessel growth."},
    {"title": "Clonal Selection and the Immune Response", "year": "1974",
     "publication": "Annual Review of Microbiology",
     "authors": [("Niels K.", "Jerne")], "volume": "28", "pages": "57-62",
     "abstract": "The immune network theory proposes self-regulatory feedback through idiotypic interactions."},
    {"title": "G Protein-Coupled Receptor Signaling", "year": "1998",
     "publication": "Annual Review of Biochemistry",
     "authors": [("Robert J.", "Lefkowitz")], "volume": "67", "pages": "819-822",
     "abstract": "G protein-coupled receptors (GPCRs) mediate most cellular responses to hormones and neurotransmitters."},
    {"title": "Epigenetic Regulation of Gene Expression", "year": "2007",
     "publication": "Nature Reviews Genetics",
     "authors": [("Andrew", "Goldberg"), ("Christopher David", "Allis"), ("Emily", "Bernstein")],
     "volume": "8", "pages": "721-729",
     "abstract": "Epigenetic mechanisms including DNA methylation and histone modification regulate gene expression."},
    {"title": "The Architecture of Genetic Regulatory Networks", "year": "2002",
     "publication": "Science",
     "authors": [("Uri", "Alon")], "volume": "298", "pages": "799-804",
     "abstract": "Network motifs are patterns of interconnections that recur throughout transcriptional networks."},
    {"title": "Cell Division and the Mitotic Spindle", "year": "1966",
     "publication": "Journal of Cell Biology",
     "authors": [("Shinya", "Inoue")], "volume": "32", "pages": "1-27",
     "abstract": "Birefringence studies of the mitotic spindle reveal dynamic instability of spindle fibers."},
    {"title": "DNA Polymerase and the Fidelity of Replication", "year": "1979",
     "publication": "Journal of Biological Chemistry",
     "authors": [("Lawrence A.", "Loeb"), ("Thomas A.", "Kunkel")], "volume": "254", "pages": "5718-5727",
     "abstract": "The frequency of base substitution errors during DNA replication is measured using phi X174 DNA."},
]

# 10 neuroscience/cognitive science papers for duplicate_merge task.
# Each will be inserted TWICE in the seeding function.
# Copy A of each pair gets a child note; copy B is bare.
NEURO_PAPERS = [
    {"title": "Synaptic Plasticity and Memory: An Evaluation of the Hypothesis",
     "year": "2000", "publication": "Annual Review of Neuroscience",
     "authors": [("Roberto", "Malenka"), ("Mark F.", "Bear")], "volume": "27", "pages": "649-711",
     "abstract": "Long-term potentiation and long-term depression are candidate synaptic mechanisms for learning and memory."},
    {"title": "The Role of Dopamine in Reward and Motivation",
     "year": "1997", "publication": "Neuron",
     "authors": [("Wolfram", "Schultz")], "volume": "20", "pages": "1-12",
     "abstract": "Dopamine neurons signal the discrepancy between predicted and actual rewards."},
    {"title": "Grid Cells and the Entorhinal Map of Space",
     "year": "2004", "publication": "Nature",
     "authors": [("Torkel", "Hafting"), ("Marianne", "Fyhn"), ("Sturla", "Molden"),
                 ("May-Britt", "Moser"), ("Edvard I.", "Moser")],
     "volume": "436", "pages": "801-806",
     "abstract": "Grid cells in the entorhinal cortex encode spatial location with a hexagonal firing pattern."},
    {"title": "Hebbian Synapses: Biophysical Mechanisms and Algorithms",
     "year": "1992", "publication": "Annual Review of Neuroscience",
     "authors": [("William B.", "Levy"), ("Robert A.", "Steward")], "volume": "15", "pages": "353-375",
     "abstract": "Activity-dependent synaptic modification follows a Hebbian learning rule."},
    {"title": "Default Mode Network Activity and Consciousness",
     "year": "2001", "publication": "Proceedings of the National Academy of Sciences",
     "authors": [("Marcus E.", "Raichle"), ("Ann Mary", "MacLeod"), ("Abraham Z.", "Snyder")],
     "volume": "98", "pages": "676-682",
     "abstract": "A default mode of brain function emerges during task-independent resting-state conditions."},
    {"title": "Mirror Neurons and the Simulation Theory of Mind-Reading",
     "year": "1998", "publication": "Trends in Cognitive Sciences",
     "authors": [("Vittorio", "Gallese"), ("Alvin", "Goldman")], "volume": "2", "pages": "493-501",
     "abstract": "Mirror neurons provide a mechanism for understanding others' actions through motor simulation."},
    {"title": "Prefrontal Cortex and Executive Function: A Review",
     "year": "2000", "publication": "Annual Review of Neuroscience",
     "authors": [("E.K.", "Miller"), ("Jonathan D.", "Cohen")], "volume": "24", "pages": "167-202",
     "abstract": "The prefrontal cortex orchestrates thought and action in accordance with internal goals."},
    {"title": "Cortical Oscillations and the Binding Problem",
     "year": "1994", "publication": "Current Opinion in Neurobiology",
     "authors": [("Wolf", "Singer"), ("Charles M.", "Gray")], "volume": "5", "pages": "557-564",
     "abstract": "Synchronized gamma oscillations may provide a mechanism for feature binding in cortical processing."},
    {"title": "Neural Basis of Visual Attention",
     "year": "2000", "publication": "Nature Reviews Neuroscience",
     "authors": [("Robert", "Desimone"), ("John", "Duncan")], "volume": "1", "pages": "194-202",
     "abstract": "Attention modulates neural activity in visual cortex through biased competition between stimuli."},
    {"title": "Basal Ganglia and the Control of Action Selection",
     "year": "2007", "publication": "Trends in Cognitive Sciences",
     "authors": [("Peter", "Redgrave"), ("Tony J.", "Prescott"), ("Kevin", "Gurney")],
     "volume": "12", "pages": "31-38",
     "abstract": "The basal ganglia select actions by modulating thalamo-cortical activity."},
]
# Notes to attach to copy A of each NEURO_PAPERS pair
NEURO_NOTES = [
    "Key paper establishing bidirectional synaptic plasticity as memory substrate. LTP/LTD evidence solid.",
    "Foundational evidence that dopamine encodes prediction errors, not just reward magnitude.",
    "Discovery paper for grid cells. Established hexagonal spatial encoding in entorhinal cortex.",
    "Classic formulation of Hebbian learning: 'neurons that fire together wire together'.",
    "Identified default mode network deactivation during task engagement. High citation count.",
    "Controversial but influential: mirror neurons as basis for social cognition.",
    "Comprehensive review of PFC in working memory and cognitive control.",
    "Evidence for gamma-band synchrony in binding visual features across cortical areas.",
    "Biased competition model of selective attention with strong neural evidence.",
    "Influential model of basal ganglia as action selection device via thalamic disinhibition.",
]

# 30 papers spanning multiple decades for hierarchical_reorganization task.
# Distribution: 8 pre-1960, 10 from 1960-1999, 7 from 2000-2010, 5 post-2010.
DECADES_PAPERS = [
    # Pre-1960 (8 papers: years 1932-1958)
    {"title": "The Theory of Economic Development", "year": "1934",
     "publication": "Quarterly Journal of Economics",
     "authors": [("Joseph A.", "Schumpeter")], "volume": "48", "pages": "333-351",
     "abstract": "Innovation-driven creative destruction as the engine of capitalist development."},
    {"title": "The Logic of Scientific Discovery", "year": "1934",
     "publication": "Springer",
     "authors": [("Karl R.", "Popper")],
     "abstract": "Scientific theories must be falsifiable to be considered scientific."},
    {"title": "Theory of Games and Economic Behavior", "year": "1944",
     "publication": "Princeton University Press",
     "authors": [("John von", "Neumann"), ("Oskar", "Morgenstern")],
     "abstract": "Mathematical game theory applied to economic competition."},
    {"title": "The Great Transformation", "year": "1944",
     "publication": "Rinehart and Company",
     "authors": [("Karl", "Polanyi")],
     "abstract": "Analysis of the social disruptions caused by the emergence of market economy."},
    {"title": "Cybernetics: Control and Communication in Animal and Machine", "year": "1948",
     "publication": "MIT Press",
     "authors": [("Norbert", "Wiener")],
     "abstract": "Interdisciplinary study of regulatory systems and feedback mechanisms."},
    {"title": "The Concept of Mind", "year": "1949",
     "publication": "Hutchinson",
     "authors": [("Gilbert", "Ryle")],
     "abstract": "Philosophical critique of Cartesian dualism and the mind-body problem."},
    {"title": "Social Choice and Individual Values", "year": "1951",
     "publication": "Yale University Press",
     "authors": [("Kenneth J.", "Arrow")],
     "abstract": "Arrow's impossibility theorem: no perfect voting system exists."},
    {"title": "The Structure of Scientific Revolutions", "year": "1957",
     "publication": "University of Chicago Press",
     "authors": [("Thomas S.", "Kuhn")],
     "abstract": "Science advances through paradigm shifts rather than continuous accumulation."},
    # 1960-1999 (10 papers)
    {"title": "Stages of Economic Growth: A Non-Communist Manifesto", "year": "1960",
     "publication": "Cambridge University Press",
     "authors": [("W.W.", "Rostow")],
     "abstract": "Linear stages theory of economic development from traditional to high-consumption society."},
    {"title": "The Silent Spring", "year": "1962",
     "publication": "Houghton Mifflin",
     "authors": [("Rachel", "Carson")],
     "abstract": "Environmental consequences of pesticide use in agriculture."},
    {"title": "A Theory of Justice", "year": "1971",
     "publication": "Harvard University Press",
     "authors": [("John", "Rawls")],
     "abstract": "Justice as fairness, veil of ignorance, and the difference principle."},
    {"title": "The Limits to Growth", "year": "1972",
     "publication": "Universe Books",
     "authors": [("Donella H.", "Meadows"), ("Dennis L.", "Meadows"), ("Jorgen", "Randers")],
     "abstract": "System dynamics modeling of exponential growth within finite planetary boundaries."},
    {"title": "Sociobiology: The New Synthesis", "year": "1975",
     "publication": "Harvard University Press",
     "authors": [("Edward O.", "Wilson")],
     "abstract": "Evolutionary basis of social behavior across species."},
    {"title": "Prospect Theory: An Analysis of Decision Under Risk", "year": "1979",
     "publication": "Econometrica",
     "authors": [("Daniel", "Kahneman"), ("Amos", "Tversky")], "volume": "47", "pages": "263-292",
     "abstract": "Descriptive theory of decision-making under uncertainty challenging expected utility theory."},
    {"title": "The Social Construction of Reality", "year": "1966",
     "publication": "Anchor Books",
     "authors": [("Peter L.", "Berger"), ("Thomas", "Luckmann")],
     "abstract": "Sociological theory of knowledge and the sociology of knowledge."},
    {"title": "Competitive Strategy", "year": "1980",
     "publication": "Free Press",
     "authors": [("Michael E.", "Porter")],
     "abstract": "Framework for industry analysis and competitive dynamics using five forces."},
    {"title": "The Second Sex", "year": "1989",
     "publication": "Vintage Books",
     "authors": [("Simone de", "Beauvoir")],
     "abstract": "Feminist analysis of women's oppression and the concept of the 'other'."},
    {"title": "End of History and the Last Man", "year": "1992",
     "publication": "Free Press",
     "authors": [("Francis", "Fukuyama")],
     "abstract": "Liberal democracy as the final form of human government following the Cold War."},
    # 2000-2010 (7 papers)
    {"title": "Empire", "year": "2000",
     "publication": "Harvard University Press",
     "authors": [("Michael", "Hardt"), ("Antonio", "Negri")],
     "abstract": "Post-Marxist theory of globalization and new forms of sovereignty."},
    {"title": "Bowling Alone: The Collapse and Revival of American Community", "year": "2000",
     "publication": "Simon and Schuster",
     "authors": [("Robert D.", "Putnam")],
     "abstract": "Decline of civic engagement and social capital in the United States."},
    {"title": "Guns, Germs, and Steel: The Fates of Human Societies", "year": "2005",
     "publication": "W.W. Norton",
     "authors": [("Jared", "Diamond")],
     "abstract": "Geographic and environmental factors as determinants of societal development."},
    {"title": "The World Is Flat: A Brief History of the Twenty-first Century", "year": "2005",
     "publication": "Farrar, Straus and Giroux",
     "authors": [("Thomas L.", "Friedman")],
     "abstract": "Globalization and the leveling of the global competitive playing field."},
    {"title": "The Black Swan: The Impact of the Highly Improbable", "year": "2007",
     "publication": "Random House",
     "authors": [("Nassim Nicholas", "Taleb")],
     "abstract": "High-impact unexpected events and their effects on history and society."},
    {"title": "Nudge: Improving Decisions About Health, Wealth, and Happiness", "year": "2008",
     "publication": "Yale University Press",
     "authors": [("Richard H.", "Thaler"), ("Cass R.", "Sunstein")],
     "abstract": "Libertarian paternalism and the design of choice architectures."},
    {"title": "The Age of Surveillance Capitalism", "year": "2009",
     "publication": "PublicAffairs",
     "authors": [("Shoshana", "Zuboff")],
     "abstract": "New economic logic extracting human behavioral data as raw material."},
    # Post-2010 (5 papers)
    {"title": "Capital in the Twenty-First Century", "year": "2014",
     "publication": "Harvard University Press",
     "authors": [("Thomas", "Piketty")],
     "abstract": "Analysis of wealth and income inequality over centuries showing r > g dynamics."},
    {"title": "The Second Machine Age", "year": "2014",
     "publication": "W.W. Norton",
     "authors": [("Erik", "Brynjolfsson"), ("Andrew", "McAfee")],
     "abstract": "Economic and societal impact of digitization, automation, and artificial intelligence."},
    {"title": "Sapiens: A Brief History of Humankind", "year": "2015",
     "publication": "Harper",
     "authors": [("Yuval Noah", "Harari")],
     "abstract": "Cognitive, agricultural, and scientific revolutions as drivers of human dominance."},
    {"title": "The Great Leveler: Violence and the History of Inequality", "year": "2017",
     "publication": "Princeton University Press",
     "authors": [("Walter", "Scheidel")],
     "abstract": "Historical analysis showing only mass mobilization, pandemics, and collapse reduce inequality."},
    {"title": "The Code Breaker: Jennifer Doudna, Gene Editing, and the Future of the Human Race",
     "year": "2021",
     "publication": "Simon and Schuster",
     "authors": [("Walter", "Isaacson")],
     "abstract": "Biography of Jennifer Doudna and the CRISPR revolution in genome editing."},
]

# 20 CS theory papers for citation_qa_export task.
# All tagged "cite-in-paper".
# Indices 0-10: clean papers (11 papers).
# Indices 11-13: empty publicationTitle (3 papers).
# Indices 14-16: first copy of 3 duplicate pairs (will be inserted twice each).
CS_THEORY_PAPERS = [
    # ── Clean papers ──────────────────────────────────────────────────────────
    {"title": "Probabilistic Algorithms for Approximate String Matching",
     "year": "1986", "publication": "Theoretical Computer Science",
     "authors": [("Ricardo A.", "Baeza-Yates"), ("Gaston H.", "Gonnet")], "volume": "68", "pages": "329-338",
     "abstract": "Approximate pattern matching using probabilistic data structures."},
    {"title": "The Complexity of Theorem Proving Procedures",
     "year": "1971", "publication": "Proceedings of the 3rd Annual ACM Symposium on Theory of Computing",
     "authors": [("Stephen A.", "Cook")], "pages": "151-158",
     "abstract": "NP-completeness of the satisfiability problem."},
    {"title": "Randomized Algorithms", "year": "1995",
     "publication": "Cambridge University Press",
     "authors": [("Rajeev", "Motwani"), ("Prabhakar", "Raghavan")],
     "abstract": "Comprehensive treatment of randomized algorithms and their analysis."},
    {"title": "A Fast Algorithm for the Maximum Flow Problem",
     "year": "1988", "publication": "Journal of the ACM",
     "authors": [("Andrew V.", "Goldberg"), ("Robert E.", "Tarjan")], "volume": "35", "pages": "921-940",
     "abstract": "Push-relabel algorithm for maximum flow with O(V^2 sqrt(E)) complexity."},
    {"title": "Lower Bounds for Data Structures", "year": "1989",
     "publication": "SIAM Journal on Computing",
     "authors": [("Michael L.", "Fredman"), ("Michael E.", "Saks")], "volume": "18", "pages": "1167-1184",
     "abstract": "Cell probe complexity model for proving data structure lower bounds."},
    {"title": "Quantum Computation and Quantum Information",
     "year": "2000", "publication": "Cambridge University Press",
     "authors": [("Michael A.", "Nielsen"), ("Isaac L.", "Chuang")],
     "abstract": "Comprehensive introduction to quantum computing and quantum information theory."},
    {"title": "Probabilistically Checkable Proofs", "year": "1998",
     "publication": "Journal of the ACM",
     "authors": [("Sanjeev", "Arora"), ("Carsten", "Lund"), ("Rajeev", "Motwani"),
                 ("Madhu", "Sudan"), ("Mario", "Szegedy")], "volume": "45", "pages": "501-555",
     "abstract": "Every NP statement has a probabilistically checkable proof checking O(log n) bits."},
    {"title": "Streaming Algorithms for Approximating MAX-CUT",
     "year": "2010", "publication": "ACM Transactions on Algorithms",
     "authors": [("Amit", "Chakrabarti"), ("Subhash", "Khot")], "volume": "7",
     "abstract": "Single-pass streaming algorithms for approximating MAX-CUT with sublinear space."},
    {"title": "Hardness of Approximation Between P and NP",
     "year": "2021", "publication": "ACM Communications",
     "authors": [("Boaz", "Barak")], "volume": "64", "pages": "90-97",
     "abstract": "Survey of hardness of approximation results and the unique games conjecture."},
    {"title": "Distributed Computing: Fundamentals, Simulations, and Advanced Topics",
     "year": "2004", "publication": "Wiley",
     "authors": [("Hagit", "Attiya"), ("Jennifer", "Welch")],
     "abstract": "Rigorous treatment of distributed algorithm design and impossibility results."},
    {"title": "An Introduction to Kolmogorov Complexity and Its Applications",
     "year": "1993", "publication": "Springer",
     "authors": [("Ming", "Li"), ("Paul", "Vitanyi")],
     "abstract": "Algorithmic information theory and its applications to learning and randomness."},
    # ── Empty publicationTitle (3 papers) ─────────────────────────────────────
    {"title": "Algebraic Complexity Theory and Circuit Lower Bounds",
     "year": "2006",
     "publication": "",   # Intentionally empty
     "authors": [("Avi", "Wigderson")], "volume": "24",
     "abstract": "Geometric complexity theory as an approach to proving circuit lower bounds."},
    {"title": "Interactive Proofs and Zero-Knowledge Arguments",
     "year": "1989",
     "publication": "",   # Intentionally empty
     "authors": [("Shafi", "Goldwasser"), ("Silvio", "Micali"), ("Charles", "Rackoff")],
     "pages": "291-304",
     "abstract": "Zero-knowledge proofs enable proving a statement without revealing why it is true."},
    {"title": "Parameterized Complexity and Kernelization",
     "year": "2015",
     "publication": "",   # Intentionally empty
     "authors": [("Marek", "Cygan"), ("Fedor V.", "Fomin"), ("Lukasz", "Kowalik")],
     "abstract": "Fixed-parameter tractable algorithms and kernelization for hard combinatorial problems."},
    # ── Duplicate pairs (indices 14-16 will each be inserted twice) ───────────
    {"title": "Linear Programming and Extensions",
     "year": "1963", "publication": "Princeton University Press",
     "authors": [("George B.", "Dantzig")],
     "abstract": "The simplex method and mathematical programming foundations."},
    {"title": "Computability and Unsolvability",
     "year": "1958", "publication": "McGraw-Hill",
     "authors": [("Martin Davis",  "")],
     "abstract": "Turing machines, recursive functions, and undecidability results."},
    {"title": "Foundations of Cryptography: Basic Tools",
     "year": "2001", "publication": "Cambridge University Press",
     "authors": [("Oded", "Goldreich")],
     "abstract": "Rigorous foundations for modern cryptography based on computational hardness."},
]
# Indices in CS_THEORY_PAPERS that will be inserted twice (duplicate pairs):
CS_THEORY_DUPLICATE_INDICES = [14, 15, 16]

# ── NEUROAI: Computational Neuroscience papers for systematic_review task ────

# Group A: pre-2000 papers (to be trashed)
# Group B: papers with placeholder abstracts (to be flagged)
# Group C: duplicate pairs with metadata variations (to be merged)
# Group D: abbreviated venues (to be fixed)
# Group E: clean papers
NEUROAI_PAPERS_PRE2000 = [
    {"title": "A Quantitative Description of Membrane Current and its Application to Conduction and Excitation in Nerve",
     "year": "1952", "publication": "Journal of Physiology",
     "authors": [("A.L.", "Hodgkin"), ("A.F.", "Huxley")],
     "volume": "117", "pages": "500-544",
     "abstract": "We propose equations which describe the changes in sodium and potassium conductance associated with excitation and recovery in the giant axon of Loligo."},
    {"title": "Neural Networks and Physical Systems with Emergent Collective Computational Abilities",
     "year": "1982", "publication": "Proceedings of the National Academy of Sciences",
     "authors": [("J.J.", "Hopfield")],
     "volume": "79", "pages": "2554-2558",
     "abstract": "Computational properties of use to biological organisms or to the construction of computers can emerge as collective properties of systems having a large number of simple equivalent components."},
    {"title": "Learning Representations by Back-propagating Errors",
     "year": "1986", "publication": "Nature",
     "authors": [("David E.", "Rumelhart"), ("Geoffrey E.", "Hinton"), ("Ronald J.", "Williams")],
     "volume": "323", "pages": "533-536",
     "abstract": "We describe a new learning procedure, back-propagation, for networks of neurone-like units."},
    {"title": "Receptive Fields, Binocular Interaction and Functional Architecture in the Cat's Visual Cortex",
     "year": "1962", "publication": "Journal of Physiology",
     "authors": [("D.H.", "Hubel"), ("T.N.", "Wiesel")],
     "volume": "160", "pages": "106-154",
     "abstract": "The striate cortex was studied in lightly anaesthetized cats by recording extracellularly from single units and stimulating the retinas with spots or patterns of light."},
]

NEUROAI_PAPERS_INCOMPLETE = [
    {"title": "Performance-optimized hierarchical models predict neural responses in higher visual cortex",
     "year": "2014", "publication": "Proceedings of the National Academy of Sciences",
     "authors": [("Daniel L.K.", "Yamins"), ("Ha", "Hong"), ("Charles F.", "Cadieu"), ("Ethan A.", "Solomon"), ("Darren", "Seibert"), ("James J.", "DiCarlo")],
     "volume": "111", "pages": "8619-8624",
     "abstract": "Abstract not available"},
    {"title": "Vector-based navigation using grid-like representations in artificial agents",
     "year": "2018", "publication": "Nature",
     "authors": [("Andrea", "Banino"), ("Caswell", "Barry"), ("Benigno", "Uria"), ("Charles", "Blundell"), ("Timothy", "Lillicrap")],
     "volume": "557", "pages": "429-433",
     "abstract": "Abstract not available"},
    {"title": "A Task-Optimized Neural Network Replicates Human Auditory Behavior, Predicts Brain Responses, and Reveals a Cortical Processing Hierarchy",
     "year": "2018", "publication": "Neuron",
     "authors": [("Alexander J.E.", "Kell"), ("Daniel L.K.", "Yamins"), ("Erica N.", "Shook"), ("Sam V.", "Norman-Haignere"), ("Josh H.", "McDermott")],
     "volume": "98", "pages": "630-644",
     "abstract": "Abstract not available"},
    {"title": "If deep learning is the answer, what is the question?",
     "year": "2021", "publication": "Nature Reviews Neuroscience",
     "authors": [("Andrew M.", "Saxe"), ("Stephanie", "Nelli"), ("Christopher", "Summerfield")],
     "volume": "22", "pages": "55-67",
     "abstract": "Abstract not available"},
]

# Duplicate pair A: copy_a has DOI but no pages; copy_b has pages but no DOI
NEUROAI_DUP_A = {
    "title": "Neuroscience-Inspired Artificial Intelligence",
    "year": "2017", "publication": "Neuron",
    "authors": [("Christopher", "Summerfield"), ("Demis", "Hassabis"), ("Dharshan", "Kumaran"), ("Matthew", "Botvinick")],
    "volume": "95",
    "copy_a": {"doi": "10.1016/j.neuron.2017.06.011", "pages": None,
               "abstract": "The fields of neuroscience and artificial intelligence (AI) have a long and intertwined history."},
    "copy_b": {"doi": None, "pages": "245-258",
               "abstract": "The fields of neuroscience and artificial intelligence (AI) have a long and intertwined history."},
}

# Duplicate pair B: copy_a has full venue + DOI; copy_b has abbreviated venue + no DOI
NEUROAI_DUP_B = {
    "title": "A deep learning framework for neuroscience",
    "year": "2019", "publication_a": "Nature Neuroscience", "publication_b": "Nat. Neurosci.",
    "authors": [("Blake A.", "Richards"), ("Timothy P.", "Lillicrap"), ("Denis", "Beaulieu"), ("Yoshua", "Bengio"), ("Rafal", "Bogacz")],
    "volume": "22",
    "copy_a": {"doi": "10.1038/s41593-019-0520-2", "pages": "1761-1770",
               "abstract": "Systems neuroscience seeks explanations for how the brain implements a wide variety of perceptual, cognitive and motor tasks."},
    "copy_b": {"doi": None, "pages": None,
               "abstract": "Systems neuroscience seeks explanations for how the brain implements a wide variety of perceptual, cognitive and motor tasks."},
}

# Duplicate pair C: copy_a has full venue + DOI; copy_b has abbreviated venue + no DOI
NEUROAI_DUP_C = {
    "title": "Toward an Integration of Deep Learning and Neuroscience",
    "year": "2016", "publication_a": "Frontiers in Computational Neuroscience", "publication_b": "Front. Comput. Neurosci.",
    "authors": [("Adam H.", "Marblestone"), ("Greg", "Wayne"), ("Konrad P.", "Kording")],
    "volume": "10",
    "copy_a": {"doi": "10.3389/fncom.2016.00094", "pages": "94",
               "abstract": "Neuroscience has focused on the detailed implementation of computation, studying neural codes, dynamics of networks, and the like."},
    "copy_b": {"doi": None, "pages": None,
               "abstract": "Neuroscience has focused on the detailed implementation of computation, studying neural codes, dynamics of networks, and the like."},
}
# Papers with abbreviated venues (standalone, not duplicates)
NEUROAI_PAPERS_WRONG_VENUE = [
    {"title": "Recurrent neural networks as versatile tools of neuroscience research",
     "year": "2017", "publication": "Curr. Opin. Neurobiol.",
     "authors": [("Omri", "Barak")],
     "volume": "46", "pages": "1-6",
     "abstract": "Task-based modeling with recurrent neural networks (RNNs) has emerged as a popular approach in systems neuroscience."},
    {"title": "Deep Neural Networks: A New Framework for Modeling Biological Vision and Brain Information Processing",
     "year": "2015", "publication": "Annu. Rev. Vis. Sci.",
     "authors": [("Nikolaus", "Kriegeskorte")],
     "volume": "1", "pages": "417-446",
     "abstract": "Recent advances in neural network modeling have enabled major strides in computer vision and other areas of artificial intelligence."},
]

# Clean papers (no issues)
NEUROAI_PAPERS_CLEAN = [
    {"title": "Backpropagation and the brain",
     "year": "2020", "publication": "Nature Reviews Neuroscience",
     "authors": [("Timothy P.", "Lillicrap"), ("Adam", "Santoro"), ("Luke", "Marris"), ("Colin J.", "Akerman"), ("Geoffrey", "Hinton")],
     "volume": "21", "pages": "335-346",
     "abstract": "During learning, the weights of deep artificial neural networks are adjusted by backpropagation."},
    {"title": "Engineering a Less Artificial Intelligence",
     "year": "2019", "publication": "Neuron",
     "authors": [("Fabian H.", "Sinz"), ("Xaq", "Pitkow"), ("Jacob", "Reimer"), ("Matthias", "Bethge"), ("Andreas S.", "Tolias")],
     "volume": "103", "pages": "967-979",
     "abstract": "We argue for a more integrated approach to AI inspired by the brain."},
    {"title": "A critique of pure learning and what artificial neural networks can learn from animal brains",
     "year": "2019", "publication": "Nature Communications",
     "authors": [("Anthony M.", "Zador")],
     "volume": "10", "pages": "3770",
     "abstract": "Artificial neural networks (ANNs) have undergone a revolution."},
    {"title": "Deep Neural Networks as Scientific Models",
     "year": "2019", "publication": "Trends in Cognitive Sciences",
     "authors": [("Radoslaw M.", "Cichy"), ("Daniel", "Kaiser")],
     "volume": "23", "pages": "305-317",
     "abstract": "Deep neural networks (DNNs) have become increasingly popular as models in cognitive science and neuroscience."},
    {"title": "An Approximation of the Error Backpropagation Algorithm in a Predictive Coding Network with Local Hebbian Synaptic Plasticity",
     "year": "2017", "publication": "Neural Computation",
     "authors": [("Rafal", "Bogacz"), ("James C.R.", "Whittington")],
     "volume": "29", "pages": "1229-1262",
     "abstract": "This article shows that a network related to the predictive coding model can approximate the error backpropagation algorithm."},
    {"title": "Analyzing biological and artificial neural networks: challenges with opportunities for synergy?",
     "year": "2019", "publication": "Current Opinion in Neurobiology",
     "authors": [("David G.T.", "Barrett"), ("Ari S.", "Morcos"), ("Jakob H.", "Macke")],
     "volume": "55", "pages": "55-64",
     "abstract": "We review recent developments in analyzing both biological and artificial neural networks."},
    {"title": "Deep Neural Networks in Computational Neuroscience",
     "year": "2019", "publication": "Oxford Research Encyclopedia of Neuroscience",
     "authors": [("Nikolaus", "Kriegeskorte"), ("Tim C.", "Kietzmann"), ("Patrick", "McClure")],
     "volume": None, "pages": None,
     "abstract": "Deep neural networks are increasingly being used as models of brain information processing."},
    {"title": "Convolutional Neural Networks as a Model of the Visual System: Past, Present, and Future",
     "year": "2021", "publication": "Annual Review of Vision Science",
     "authors": [("Grace W.", "Lindsay")],
     "volume": "7", "pages": "397-421",
     "abstract": "Convolutional neural networks (CNNs) were inspired by the visual brain."},
    {"title": "Brain-Score: Which Artificial Neural Network for Object Recognition is most Brain-Like?",
     "year": "2020", "publication": "bioRxiv",
     "authors": [("Ha", "Hong"), ("James J.", "DiCarlo"), ("Martin", "Schrimpf"), ("Jonas", "Kubilius"), ("Najib J.", "Majaj"), ("Rishi", "Rajalingham"), ("Elias B.", "Issa"), ("Kohitij", "Kar"), ("Pouya", "Bashivan"), ("Jonathan", "Prescott-Roy")],
     "volume": None, "pages": None,
     "abstract": "The internal representations of brain and deep neural networks (DNNs) can be compared using neural predictivity metrics."},
]




# ── Database helpers ─────────────────────────────────────────────────────────

def generate_key(length=8):
    chars = string.ascii_uppercase + string.digits
    return "".join(random.choices(chars, k=length))


def get_or_create_value(cur, value):
    cur.execute("SELECT valueID FROM itemDataValues WHERE value = ?", (str(value),))
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute("INSERT INTO itemDataValues (value) VALUES (?)", (str(value),))
    return cur.lastrowid


def get_or_create_creator(cur, first_name, last_name, field_mode=0):
    cur.execute(
        "SELECT creatorID FROM creators WHERE lastName=? AND firstName=? AND fieldMode=?",
        (last_name, first_name, field_mode),
    )
    row = cur.fetchone()
    if row:
        return row[0]
    cur.execute(
        "INSERT INTO creators (firstName, lastName, fieldMode) VALUES (?,?,?)",
        (first_name, last_name, field_mode),
    )
    return cur.lastrowid


def item_exists_by_title(cur, title):
    cur.execute(
        """SELECT i.itemID FROM items i
           JOIN itemData d ON i.itemID=d.itemID
           JOIN itemDataValues v ON d.valueID=v.valueID
           WHERE d.fieldID=1 AND v.value=?""",
        (title,),
    )
    row = cur.fetchone()
    return row[0] if row else None


def insert_journal_article(cur, title, year, publication, authors,
                            volume=None, issue=None, pages=None, doi=None, abstract=None):
    """Insert a journal article; return itemID (creates or returns existing)."""
    existing = item_exists_by_title(cur, title)
    if existing:
        return existing

    now = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    key = generate_key()
    cur.execute(
        """INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified,
                              libraryID, key, version, synced)
           VALUES (22, ?, ?, ?, ?, ?, 0, 0)""",
        (now, now, now, LIBRARY_ID, key),
    )
    item_id = cur.lastrowid

    # Field values
    field_map = {1: title, 6: str(year), 38: publication}
    if volume:
        field_map[19] = str(volume)
    if issue:
        field_map[76] = str(issue)
    if pages:
        field_map[32] = str(pages)
    if doi:
        field_map[59] = str(doi)
    if abstract:
        field_map[2] = str(abstract)

    for field_id, value in field_map.items():
        if value:  # Skip empty strings
            value_id = get_or_create_value(cur, value)
            cur.execute(
                "INSERT OR REPLACE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)",
                (item_id, field_id, value_id),
            )

    # Creators
    for order_idx, (first_name, last_name) in enumerate(authors):
        creator_id = get_or_create_creator(cur, first_name, last_name)
        cur.execute(
            """INSERT OR IGNORE INTO itemCreators
               (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?,?,8,?)""",
            (item_id, creator_id, order_idx),
        )

    return item_id


def insert_journal_article_force(cur, title, year, publication, authors,
                                  volume=None, issue=None, pages=None, doi=None, abstract=None):
    """Insert a journal article WITHOUT dedup check (for creating intentional duplicates)."""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    key = generate_key()
    cur.execute(
        """INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified,
                              libraryID, key, version, synced)
           VALUES (22, ?, ?, ?, ?, ?, 0, 0)""",
        (now, now, now, LIBRARY_ID, key),
    )
    item_id = cur.lastrowid

    field_map = {1: title, 6: str(year), 38: publication}
    if volume:
        field_map[19] = str(volume)
    if issue:
        field_map[76] = str(issue)
    if pages:
        field_map[32] = str(pages)
    if doi:
        field_map[59] = str(doi)
    if abstract:
        field_map[2] = str(abstract)

    for field_id, value in field_map.items():
        if value:
            value_id = get_or_create_value(cur, value)
            cur.execute(
                "INSERT OR REPLACE INTO itemData (itemID, fieldID, valueID) VALUES (?,?,?)",
                (item_id, field_id, value_id),
            )

    for order_idx, (first_name, last_name) in enumerate(authors):
        creator_id = get_or_create_creator(cur, first_name, last_name)
        cur.execute(
            """INSERT OR IGNORE INTO itemCreators
               (itemID, creatorID, creatorTypeID, orderIndex) VALUES (?,?,8,?)""",
            (item_id, creator_id, order_idx),
        )

    return item_id


def create_collection(cur, name, parent_id=None):
    """Create a collection; return collectionID."""
    cur.execute(
        "SELECT collectionID FROM collections WHERE collectionName=? AND libraryID=? AND parentCollectionID IS ?",
        (name, LIBRARY_ID, parent_id),
    )
    row = cur.fetchone()
    if row:
        return row[0]
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    key = generate_key()
    cur.execute(
        """INSERT INTO collections
           (collectionName, parentCollectionID, clientDateModified, libraryID, key, version, synced)
           VALUES (?,?,?,?,?,0,0)""",
        (name, parent_id, now, LIBRARY_ID, key),
    )
    return cur.lastrowid


def add_item_to_collection(cur, collection_id, item_id, order_index=0):
    cur.execute(
        "INSERT OR IGNORE INTO collectionItems (collectionID, itemID, orderIndex) VALUES (?,?,?)",
        (collection_id, item_id, order_index),
    )


def add_tag_to_item(cur, item_id, tag_name, tag_type=0):
    """Add a user-defined tag to an item. Creates the tag if it doesn't exist.

    Actual Zotero 7 schema:
      tags(tagID INTEGER PK, name TEXT UNIQUE)  -- no type, no libraryID
      itemTags(itemID, tagID, type INT)          -- type lives here
    """
    cur.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
    row = cur.fetchone()
    if row:
        tag_id = row[0]
    else:
        cur.execute("INSERT OR IGNORE INTO tags (name) VALUES (?)", (tag_name,))
        cur.execute("SELECT tagID FROM tags WHERE name=?", (tag_name,))
        tag_id = cur.fetchone()[0]
    cur.execute(
        "INSERT OR IGNORE INTO itemTags (itemID, tagID, type) VALUES (?,?,?)",
        (item_id, tag_id, tag_type),
    )
    return tag_id


def insert_child_note(cur, parent_item_id, note_text):
    """Insert a child note attached to parent_item_id; return noteItemID."""
    now = time.strftime("%Y-%m-%dT%H:%M:%SZ")
    key = generate_key()
    cur.execute(
        """INSERT INTO items (itemTypeID, dateAdded, dateModified, clientDateModified,
                              libraryID, key, version, synced)
           VALUES (28, ?, ?, ?, ?, ?, 0, 0)""",
        (now, now, now, LIBRARY_ID, key),
    )
    note_id = cur.lastrowid
    title_preview = note_text[:100] if len(note_text) > 100 else note_text
    cur.execute(
        "INSERT INTO itemNotes (itemID, parentItemID, note, title) VALUES (?,?,?,?)",
        (note_id, parent_item_id, f"<p>{note_text}</p>", title_preview),
    )
    return note_id


def corrupt_item_year(cur, title, wrong_year):
    """Set a paper's date field to wrong_year."""
    cur.execute(
        """SELECT i.itemID FROM items i
           JOIN itemData d ON i.itemID=d.itemID
           JOIN itemDataValues v ON d.valueID=v.valueID
           WHERE d.fieldID=1 AND v.value=?""",
        (title,),
    )
    row = cur.fetchone()
    if not row:
        print(f"WARNING: Could not find paper '{title}' to corrupt year", file=sys.stderr)
        return

    item_id = row[0]
    value_id = get_or_create_value(cur, str(wrong_year))
    cur.execute(
        "INSERT OR REPLACE INTO itemData (itemID, fieldID, valueID) VALUES (?,6,?)",
        (item_id, value_id),
    )
    print(f"  Corrupted year for '{title[:50]}...' to {wrong_year}", file=sys.stderr)


def set_item_abstract(cur, item_id, abstract_text):
    """Set abstractNote field for an item."""
    if abstract_text:
        value_id = get_or_create_value(cur, abstract_text)
        cur.execute(
            "INSERT OR REPLACE INTO itemData (itemID, fieldID, valueID) VALUES (?,2,?)",
            (item_id, value_id),
        )
    else:
        cur.execute("DELETE FROM itemData WHERE itemID=? AND fieldID=2", (item_id,))


# ── Seeding modes ────────────────────────────────────────────────────────────

def seed_all(cur):
    ids = {}
    for p in CLASSIC_PAPERS:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
        )
        ids[p["title"]] = iid
    for p in ML_PAPERS:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
        )
        ids[p["title"]] = iid
    return ids


def seed_classic(cur):
    ids = {}
    for p in CLASSIC_PAPERS:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"),
        )
        ids[p["title"]] = iid
    return ids


def seed_ml(cur):
    ids = {}
    for p in ML_PAPERS:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
        )
        ids[p["title"]] = iid
    return ids


def seed_ml_with_collection(cur):
    ids = seed_ml(cur)
    # Create "ML References" collection with all 8 ML papers
    coll_id = create_collection(cur, "ML References")
    for order_idx, (title, item_id) in enumerate(ids.items()):
        add_item_to_collection(cur, coll_id, item_id, order_idx)
    ids["__collection_id__"] = coll_id
    ids["__collection_name__"] = "ML References"
    return ids


def seed_classic_with_errors(cur):
    ids = seed_classic(cur)
    # Corrupt Einstein 1905 -> 1906
    corrupt_item_year(cur, "On the Electrodynamics of Moving Bodies", "1906")
    # Corrupt Shannon 1948 -> 1950
    corrupt_item_year(cur, "A Mathematical Theory of Communication", "1950")
    return ids


def seed_all_with_errors(cur):
    ids = seed_all(cur)
    corrupt_item_year(cur, "On the Electrodynamics of Moving Bodies", "1906")
    corrupt_item_year(cur, "A Mathematical Theory of Communication", "1950")
    return ids


def seed_triage_pipeline(cur):
    """
    Seed 20 systems papers in a 'Reading Queue' collection.
    6 papers pre-tagged 'priority':
      - Pre-2010 priority (4): UNIX 1974, End-to-End 1984, GFS 2003, Chord 2001
        → agent should tag these 'review-now'
      - Post-2010 priority (2): Raft 2014, TiKV 2019
        → agent should tag these 'review-later'
    """
    ids = {}
    coll_id = create_collection(cur, "Reading Queue")

    for order_idx, p in enumerate(SYSTEMS_PAPERS):
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
        )
        ids[p["title"]] = iid
        add_item_to_collection(cur, coll_id, iid, order_idx)

    # Pre-tag priority papers
    for idx in SYSTEMS_PRIORITY_INDICES:
        title = SYSTEMS_PAPERS[idx]["title"]
        add_tag_to_item(cur, ids[title], "priority")
        print(f"  Tagged 'priority': {title[:60]}", file=sys.stderr)

    ids["__collection_id__"] = coll_id
    ids["__collection_name__"] = "Reading Queue"

    # Export expected state for verifier
    pre2010_titles = [SYSTEMS_PAPERS[i]["title"] for i in SYSTEMS_PRIORITY_INDICES
                      if int(SYSTEMS_PAPERS[i]["year"]) < 2010]
    post2010_titles = [SYSTEMS_PAPERS[i]["title"] for i in SYSTEMS_PRIORITY_INDICES
                       if int(SYSTEMS_PAPERS[i]["year"]) >= 2010]
    ids["__priority_pre2010__"] = pre2010_titles
    ids["__priority_post2010__"] = post2010_titles

    return ids


def seed_metadata_audit(cur):
    """
    Seed 25 science/biology papers with planted metadata errors.
    Indices 0-4:  year errors (stored wrong year, 10 years off)
    Indices 5-9:  swapped author first/last names
    Indices 10-14: abstract = "Abstract not available"
    Indices 15-24: clean papers
    """
    ids = {}

    for p in SCIENCE_PAPERS:
        # Store using paper's stated year (which may be the corrupted one)
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"],
            p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
            p.get("abstract"),
        )
        ids[p["title"]] = iid

    return ids


def seed_duplicate_merge(cur):
    """
    Seed 10 neuroscience papers, each inserted TWICE = 20 total items.
    Copy A (first insert): gets a child note attached.
    Copy B (second insert): bare, no children.
    Returns mapping of title -> [copy_a_id, copy_b_id].
    """
    ids = {}

    for paper_idx, p in enumerate(NEURO_PAPERS):
        note_text = NEURO_NOTES[paper_idx]

        # Copy A: insert and attach note
        id_a = insert_journal_article_force(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
            p.get("abstract"),
        )
        note_id = insert_child_note(cur, id_a, note_text)
        print(f"  Inserted copy A (id={id_a}, note={note_id}): {p['title'][:50]}", file=sys.stderr)

        # Copy B: bare duplicate
        id_b = insert_journal_article_force(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
            p.get("abstract"),
        )
        print(f"  Inserted copy B (id={id_b}): {p['title'][:50]}", file=sys.stderr)

        ids[p["title"]] = [id_a, id_b]

    ids["__note_texts__"] = NEURO_NOTES
    return ids


def seed_hierarchical_reorg(cur):
    """
    Seed 30 papers spanning 1934-2021 in a flat 'Unsorted Import' collection.
    Agent must create 'Research Archive' > {Pre-1960, 1960-1999, 2000-2010, Post-2010}
    and move each paper to the correct subcollection, then delete 'Unsorted Import'.
    """
    ids = {}
    coll_id = create_collection(cur, "Unsorted Import")

    for order_idx, p in enumerate(DECADES_PAPERS):
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
            p.get("abstract"),
        )
        ids[p["title"]] = iid
        add_item_to_collection(cur, coll_id, iid, order_idx)

    ids["__collection_id__"] = coll_id
    ids["__collection_name__"] = "Unsorted Import"

    # Export expected distribution for verifier
    pre1960 = [p["title"] for p in DECADES_PAPERS if int(p["year"]) < 1960]
    era_1960_1999 = [p["title"] for p in DECADES_PAPERS if 1960 <= int(p["year"]) <= 1999]
    era_2000_2010 = [p["title"] for p in DECADES_PAPERS if 2000 <= int(p["year"]) <= 2010]
    post2010 = [p["title"] for p in DECADES_PAPERS if int(p["year"]) > 2010]

    ids["__pre1960__"] = pre1960
    ids["__1960_1999__"] = era_1960_1999
    ids["__2000_2010__"] = era_2000_2010
    ids["__post2010__"] = post2010

    return ids


def seed_citation_qa(cur):
    """
    Seed 20 CS theory papers, all tagged 'cite-in-paper'.
    Indices 0-10: clean papers (11 papers).
    Indices 11-13: papers with empty publicationTitle (fieldID=38 not set).
    Indices 14-16: duplicate pairs — each inserted twice.
    Total items: 11 + 3 + 3*2 = 20.
    """
    ids = {}
    all_item_ids = []

    for p_idx, p in enumerate(CS_THEORY_PAPERS):
        if p_idx in CS_THEORY_DUPLICATE_INDICES:
            # Insert twice for duplicate pairs
            id_a = insert_journal_article_force(
                cur, p["title"], p["year"], p["publication"], p["authors"],
                p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
                p.get("abstract"),
            )
            id_b = insert_journal_article_force(
                cur, p["title"], p["year"], p["publication"], p["authors"],
                p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
                p.get("abstract"),
            )
            ids[p["title"]] = [id_a, id_b]
            all_item_ids.extend([id_a, id_b])
            print(f"  Inserted dupe pair (ids={id_a},{id_b}): {p['title'][:50]}", file=sys.stderr)
        else:
            iid = insert_journal_article(
                cur, p["title"], p["year"], p.get("publication", ""), p["authors"],
                p.get("volume"), p.get("issue"), p.get("pages"), p.get("doi"),
                p.get("abstract"),
            )
            ids[p["title"]] = iid
            all_item_ids.append(iid)

    # Tag all items as "cite-in-paper"
    for iid in all_item_ids:
        if isinstance(iid, int):
            add_tag_to_item(cur, iid, "cite-in-paper")

    ids["__total_items__"] = len(all_item_ids)
    ids["__duplicate_titles__"] = [CS_THEORY_PAPERS[i]["title"] for i in CS_THEORY_DUPLICATE_INDICES]
    ids["__empty_journal_titles__"] = [CS_THEORY_PAPERS[i]["title"] for i in [11, 12, 13]]

    return ids

def seed_systematic_review(cur):
    """Seed 25 computational neuroscience papers for systematic review task.

    Paper groups:
      A. 4 pre-2000 papers (to be trashed by agent)
      B. 4 papers with placeholder abstracts (to be flagged)
      C. 3 duplicate pairs with metadata variations (to be merged; 6 rows total)
      D. 2 papers with abbreviated venue names (to be fixed)
      E. 9 clean papers

    Total: 4 + 4 + 6 + 2 + 9 = 25 items
    """
    ids = {}

    # Group A: pre-2000 papers
    for p in NEUROAI_PAPERS_PRE2000:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            abstract=p.get("abstract"), volume=p.get("volume"), pages=p.get("pages"))
        if iid:
            ids[f"pre2000_{p['title'][:30]}"] = iid

    # Group B: papers with placeholder abstracts
    for p in NEUROAI_PAPERS_INCOMPLETE:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            abstract=p.get("abstract"), volume=p.get("volume"), pages=p.get("pages"))
        if iid:
            ids[f"incomplete_{p['title'][:30]}"] = iid

    # Group C: duplicate pairs with metadata variations
    # Pair A: Hassabis et al. - copy_a has DOI, copy_b has pages
    dup = NEUROAI_DUP_A
    id_a = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication"], dup["authors"],
        abstract=dup["copy_a"]["abstract"], volume=dup["volume"],
        pages=dup["copy_a"]["pages"], doi=dup["copy_a"]["doi"])
    id_b = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication"], dup["authors"],
        abstract=dup["copy_b"]["abstract"], volume=dup["volume"],
        pages=dup["copy_b"]["pages"], doi=dup["copy_b"]["doi"])
    ids["dup_a_copy_a"] = id_a
    ids["dup_a_copy_b"] = id_b

    # Pair B: Richards et al. - copy_a has full venue+DOI, copy_b abbreviated venue
    dup = NEUROAI_DUP_B
    id_a = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication_a"], dup["authors"],
        abstract=dup["copy_a"]["abstract"], volume=dup["volume"],
        pages=dup["copy_a"]["pages"], doi=dup["copy_a"]["doi"])
    id_b = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication_b"], dup["authors"],
        abstract=dup["copy_b"]["abstract"], volume=dup["volume"],
        pages=dup["copy_b"]["pages"], doi=dup["copy_b"]["doi"])
    ids["dup_b_copy_a"] = id_a
    ids["dup_b_copy_b"] = id_b

    # Pair C: Marblestone et al. - copy_a has full venue+DOI, copy_b abbreviated venue
    dup = NEUROAI_DUP_C
    id_a = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication_a"], dup["authors"],
        abstract=dup["copy_a"]["abstract"], volume=dup["volume"],
        pages=dup["copy_a"]["pages"], doi=dup["copy_a"]["doi"])
    id_b = insert_journal_article_force(
        cur, dup["title"], dup["year"], dup["publication_b"], dup["authors"],
        abstract=dup["copy_b"]["abstract"], volume=dup["volume"],
        pages=dup["copy_b"]["pages"], doi=dup["copy_b"]["doi"])
    ids["dup_c_copy_a"] = id_a
    ids["dup_c_copy_b"] = id_b

    # Group D: papers with abbreviated venues
    for p in NEUROAI_PAPERS_WRONG_VENUE:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            abstract=p.get("abstract"), volume=p.get("volume"), pages=p.get("pages"))
        if iid:
            ids[f"wrong_venue_{p['title'][:30]}"] = iid

    # Group E: clean papers
    for p in NEUROAI_PAPERS_CLEAN:
        iid = insert_journal_article(
            cur, p["title"], p["year"], p["publication"], p["authors"],
            abstract=p.get("abstract"), volume=p.get("volume"), pages=p.get("pages"))
        if iid:
            ids[f"clean_{p['title'][:30]}"] = iid

    ids["__total_items__"] = 25
    ids["__pre2000_titles__"] = [p["title"] for p in NEUROAI_PAPERS_PRE2000]
    ids["__incomplete_titles__"] = [p["title"] for p in NEUROAI_PAPERS_INCOMPLETE]
    ids["__duplicate_titles__"] = [NEUROAI_DUP_A["title"], NEUROAI_DUP_B["title"], NEUROAI_DUP_C["title"]]
    ids["__wrong_venue_titles__"] = [p["title"] for p in NEUROAI_PAPERS_WRONG_VENUE]

    return ids
# ── Main ─────────────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        choices=["all", "classic", "ml", "ml_with_collection",
                 "classic_with_errors", "all_with_errors",
                 "triage_pipeline", "metadata_audit",
                 "duplicate_merge", "hierarchical_reorg", "citation_qa", "systematic_review"],
        default="all",
    )
    args = parser.parse_args()

    if not os.path.exists(DB_PATH):
        print(f"ERROR: DB not found at {DB_PATH}", file=sys.stderr)
        sys.exit(1)

    conn = sqlite3.connect(DB_PATH, timeout=30)
    cur = conn.cursor()
    # Disable FK enforcement for direct inserts
    cur.execute("PRAGMA foreign_keys = OFF")

    try:
        mode_fn = {
            "all": seed_all,
            "classic": seed_classic,
            "ml": seed_ml,
            "ml_with_collection": seed_ml_with_collection,
            "classic_with_errors": seed_classic_with_errors,
            "all_with_errors": seed_all_with_errors,
            "triage_pipeline": seed_triage_pipeline,
            "metadata_audit": seed_metadata_audit,
            "duplicate_merge": seed_duplicate_merge,
            "hierarchical_reorg": seed_hierarchical_reorg,
            "citation_qa": seed_citation_qa,
            "systematic_review": seed_systematic_review,
        }[args.mode]

        print(f"Seeding mode: {args.mode}", file=sys.stderr)
        ids = mode_fn(cur)
        conn.commit()
        paper_count = sum(1 for k in ids if not k.startswith('__'))
        print(f"Inserted/verified {paper_count} papers", file=sys.stderr)
        # Output IDs as JSON to stdout
        print(json.dumps(ids))

    except Exception as e:
        conn.rollback()
        print(f"ERROR: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc(file=sys.stderr)
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()
