# Task: FDA Regulatory Guidance Research and Documentation

## Domain Context
Regulatory affairs specialists at pharmaceutical companies routinely search the FDA's guidance document database to find relevant guidance for drug development programs. FDA.gov has hundreds of guidance documents organized by therapeutic area, document type, and regulatory pathway. Finding relevant documents requires domain knowledge, navigational skill, and systematic search strategies. Producing a well-organized regulatory research summary is a core professional deliverable.

## Starting State
- Edge is open on the FDA homepage (https://www.fda.gov)
- A research briefing describing the regulatory topic is placed at `/home/ga/Desktop/research_brief.txt`
- Research brief describes the need for pharmacokinetics/bioavailability guidance for a small molecule NDA
- ~/Downloads directory is empty (clean state)

## Goal
Find and download at least 2 FDA guidance PDFs relevant to pharmacokinetics/bioavailability/bioequivalence, bookmark the pages in a folder called "FDA Guidance", and write a regulatory research summary.

## Research Brief Content (set by setup script)
The research brief describes:
- A new molecular entity (NME) in Phase III clinical trials
- Regulatory team needs FDA guidance on:
  1. Pharmacokinetics study design for NDA submission
  2. Bioavailability and bioequivalence requirements
  3. Food effect studies
- Documents should be from FDA's Drugs guidance section

## What the Agent Must Figure Out
- How to navigate FDA.gov's guidance search interface (complex site with multiple search paths)
- How to search for guidance by topic (pharmacokinetics, bioavailability, NDA)
- How to distinguish guidance documents from other FDA content
- How to download PDFs from FDA guidance pages (usually a link within the guidance page)
- How to create a named bookmark folder in Edge
- How to write a professional regulatory research summary with document identifiers

## Success Criteria
1. Summary file exists at `/home/ga/Desktop/fda_research_summary.txt`, written after task start
2. At least one PDF file downloaded from fda.gov
3. History shows multiple visits to fda.gov guidance pages
4. "FDA Guidance" bookmark folder exists in Edge with fda.gov bookmarks
5. Summary contains FDA-specific regulatory vocabulary

## Verification Strategy
- **Downloads**: Check ~/Downloads for PDF files, check History downloads table for fda.gov source
- **History**: Query Edge History for fda.gov URLs containing "guidance"
- **Bookmarks**: Parse Edge Bookmarks JSON for "FDA Guidance" folder with fda.gov URLs
- **Summary**: Check for FDA vocabulary (NDA, BLA, pharmacokinetics, bioavailability, ICH, etc.)

## Scoring Breakdown (100 points)
- Summary file exists and was modified after task start: 10 points
- At least one PDF from fda.gov downloaded: 30 points
- History shows visits to FDA guidance pages: 20 points
- "FDA Guidance" bookmark folder exists with fda.gov bookmarks: 20 points
- Summary contains FDA regulatory vocabulary (NDA, bioavailability, pharmacokinetics, etc.): 20 points

**Pass threshold**: 60 points

## Why This Is Very Hard
1. FDA.gov is a large, complex government website with many navigation paths
2. Agent must know to look in the Drugs/Guidance section (not obvious)
3. Finding guidance on specific pharmacology topics requires understanding the regulatory domain
4. Some guidance pages require multiple clicks to reach the PDF download
5. Creating a named bookmark folder and populating it requires multi-step Edge UI operations
6. The summary must contain domain-specific vocabulary that only appears if agent actually read the documents
7. Must complete 4 independent subtasks (download, browse, bookmark, write)

## Real FDA Guidance Documents (examples agent might find)
- "Pharmacokinetics in Patients With Impaired Renal Function" (FDA Guidance)
- "Bioavailability and Bioequivalence Studies Submitted in NDAs or INDs" (FDA Guidance)
- "Food-Effect Bioavailability and Fed Bioequivalence Studies" (FDA Guidance)
- ICH E5 "Ethnic Factors in the Acceptability of Foreign Clinical Data"
- These are all real, publicly downloadable FDA guidance documents
