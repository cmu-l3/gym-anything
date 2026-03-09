# Task: analyst_ehr_uml_design

## Domain Context

Systems Analysts in healthcare IT routinely use UML diagrams to communicate EHR system designs. A complete UML design document for a healthcare system includes a Class Diagram (domain model), a Use Case Diagram (actor-system interactions), and a Sequence Diagram (one key workflow in detail). This task requires using EdrawMax's UML shape library across 3 separate pages.

## Occupation

**Computer Systems Analysts** (top EdrawMax user group by economic impact)

## Task Overview

Create a 3-page UML design document for an EHR system in EdrawMax, saved as `/home/ga/ehr_uml_design.eddx`.

## Goal / End State

The completed file must contain exactly 3 pages:

- **Page 1 — UML Class Diagram**: ≥ 6 classes (Patient, Doctor, Appointment, Prescription, MedicalRecord, Department) with named attributes and association lines between related classes.
- **Page 2 — UML Use Case Diagram**: ≥ 4 actors (Patient, Doctor, Nurse, Administrator) and ≥ 8 use cases with actor-use case associations.
- **Page 3 — UML Sequence Diagram**: "Schedule Appointment" use case shown with ≥ 4 lifelines and message arrows between them.
- Consistent professional theme across all pages.

## Difficulty

**hard** — Task names specific classes, actors, and use cases (agent knows what entities to create) but provides no UI navigation steps. Agent must know EdrawMax's UML diagram type and shape library, and how to create 3 distinct pages with different UML types.

## Success Criteria

| Criterion | Points | What is checked |
|-----------|--------|-----------------|
| A: Valid EDDX archive | 15 | File at correct path, valid ZIP |
| B: Modified after task start | 10 | File mtime > start timestamp |
| C: Three pages (≥ 3) | 25 | ≥ 3 page XML files in archive |
| D: EHR class entities | 20 | ≥ 5 of: patient, doctor, appointment, prescription, medicalrecord, department in XML |
| E: Use case content | 15 | ≥ 5 use case/actor keywords on page 2 |
| F: Shape density (total) | 15 | ≥ 15 Shape elements across all 3 pages |

**Pass threshold: 60/100**

## Verification Strategy

`verifier.py::verify_analyst_ehr_uml_design` — copies EDDX, parses ZIP XML per-page, searches for EHR domain entity names and UML diagram keywords in shape text labels and NameU attributes.

## Anti-Gaming

- `setup_task.sh` deletes the output file and records start timestamp.
- Getting to score ≥ 60 requires content across 3 pages — a 2-page file can score at most 70 (A+B+C partial+D+E+F) but likely less.

## Edge Cases

- Agent creates only 2 pages — criterion C awards 10/25 pts (partial), C and F together limit the total.
- Agent creates Class Diagram but not Use Case or Sequence — criteria E fails.
- Agent uses generic boxes not labeled with class names — criterion D fails (20 pts lost).
- Agent misspells class names — verifier uses case-insensitive substring matching, so "MedicalRecord" matches "medicalrecord" and similar.
