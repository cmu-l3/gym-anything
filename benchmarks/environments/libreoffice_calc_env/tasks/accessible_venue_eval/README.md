# LibreOffice Calc Accessible Venue Evaluator Task (`accessible_venue_eval@1`)

**Difficulty**: 🟡 Medium  
**Skills**: Data standardization, conditional formulas, multi-criteria decision-making  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~20

## Objective

Help someone with mobility and sensory accessibility needs evaluate and rank potential venues for attending multiple events. The task requires cleaning inconsistent venue data, standardizing accessibility information, calculating total costs, identifying venues meeting minimum requirements, and creating a decision support ranking.

## Real-World Context

Maya uses a power wheelchair and has hearing loss. She's been invited to 6 events and has collected wildly inconsistent information from venues. Some mentioned accessible parking costs, others didn't. Some described exact features, others just said "ADA compliant" (meaningless). She needs a systematic way to:
- Standardize messy venue data into comparable format
- Calculate total accessibility costs (parking, companion tickets, equipment rental)
- Identify which venues meet her minimum requirements
- Rank venues by cost and importance to make informed decisions

## Starting State

- CSV file (`venues_raw_data.csv`) with 6 venues and messy, inconsistent accessibility descriptions
- LibreOffice Calc ready to open the file

## Required Actions

### 1. Data Standardization (Core Requirement)
Create new columns to convert free-text descriptions into Yes/No flags:
- **Level/Ramped Entry?** (parse "Entry Description")
- **Accessible Restroom?** (parse "Restroom")
- **Hearing Support?** (parse "Hearing Support")
- **Accessible Parking?** (parse "Parking Notes")

Use IF/OR/SEARCH formulas to detect keywords:
- Positive: "level", "ramp", "accessible", "ada compliant", "no steps"
- Negative: "steps", "stairs", "not accessible", "second floor"

Example formula: