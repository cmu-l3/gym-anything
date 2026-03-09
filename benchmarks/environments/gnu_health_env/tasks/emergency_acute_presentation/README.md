# Task: Emergency Acute Abdominal Presentation

## Overview

**Environment**: GNU Health Hospital Information System (HIS) 5.0
**Domain**: Emergency Medicine / Acute Care
**Difficulty**: Very Hard
**Patient**: Luna

## Occupational Context

This task reflects the real workflow of an emergency physician documenting an acute presentation in a hospital EHR system. Emergency documentation in GNU Health requires simultaneous use of multiple modules: appointment scheduling (walk-in/urgent), clinical evaluation (vital signs + chief complaint), diagnostic ordering, and ICD-10 coding. Emergency physicians must synthesize clinical data and make appropriate documentation decisions — they are not given a step-by-step protocol. The task is very_hard because the agent must interpret the clinical picture and determine appropriate actions independently.

## Scenario

Patient **Luna** arrives at the emergency department with the following presentation:
- **Chief complaint**: Severe right lower quadrant abdominal pain (severity 8/10), started 18 hours ago
- **Associated symptoms**: Fever, nausea, loss of appetite
- **On examination**: Tenderness at McBurney's point, rebound tenderness present

Dr. Cameron Cordara is the attending emergency physician on duty. The agent must document this presentation appropriately in GNU Health, making independent clinical decisions about diagnosis and laboratory workup.

## Goal (End State)

**This is a very_hard task**: The description gives you the clinical picture but does NOT tell you exactly which menu to click, which ICD-10 code to select, or which labs to order. You must determine the appropriate clinical response based on the presentation.

The end state must reflect an appropriate emergency workup for **acute right lower quadrant abdominal pain with fever**:

1. **Emergency appointment for today**: An appointment for Luna must be scheduled or recorded for **today's date** (or within 1 day of task start), with an urgency level indicating emergency/urgent (not routine)
2. **Clinical evaluation with fever and tachycardia**: A patient evaluation (encounter/encounter note) for Luna must include vital signs consistent with the clinical picture: temperature **≥ 38.0°C** (fever), heart rate **≥ 100 bpm** (tachycardia)
3. **At least two laboratory orders**: A minimum of **two** new lab test orders for Luna — appropriate workup includes complete blood count (CBC), C-reactive protein (CRP), or any other blood tests appropriate for acute abdomen
4. **Appropriate abdominal diagnosis**: An ICD-10 diagnosis code for **abdominal pathology** must be documented — appropriate codes include anything in the **K35–K38** range (appendix disorders), K59, K57, or other abdominal ICD-10 codes beginning with 'K'
5. **Surgical consultation or urgent follow-up**: A referral note, consultation request, or very short-term appointment (within **7 days**) must be documented — reflecting the need for surgical evaluation

## Login Credentials

- **URL**: `http://localhost:8000/`
- **Database**: `health50`
- **Username**: `admin`
- **Password**: `gnusolidario`

## Clinical Decision Context (What a Real ER Doctor Would Know)

Based on the clinical picture (RLQ pain + McBurney's point tenderness + rebound + fever), the most likely diagnosis is **Acute Appendicitis** (ICD-10: K35.80 or K37). Standard of care requires:
- CBC (to check for leukocytosis — high WBCs indicate infection)
- CRP or ESR (inflammation marker)
- Clinical examination documentation
- Urgent surgical consultation

The agent must independently determine that:
- Appendicitis codes start with K35/K37
- CBC and CRP are the appropriate labs
- The follow-up should be urgent (surgery consultation, not a 6-month checkup)

## Verification Strategy

`export_result.sh` queries:
- gnuhealth_appointment for today's emergency appointment for Luna
- gnuhealth_patient_evaluation for fever (temp ≥ 38.0) AND tachycardia (HR ≥ 100)
- gnuhealth_patient_lab_test for count of new lab orders (need ≥ 2)
- gnuhealth_patient_disease for abdominal ICD-10 code (K prefix)
- gnuhealth_appointment for surgical/urgent short-term follow-up (≤ 7 days)

## Scoring

- 20 pts: Emergency appointment today (or within 1 day)
- 20 pts: Clinical evaluation with fever ≥ 38.0°C AND tachycardia ≥ 100 bpm
- 20 pts: At least 2 new lab test orders for Luna
- 20 pts: Abdominal ICD-10 diagnosis (K prefix codes)
- 20 pts: Short-term surgical/urgent follow-up (≤ 7 days) or separate referral appointment

Pass threshold: ≥ 70 pts (requires correctly identifying 3-4 of the 5 clinical response elements)
