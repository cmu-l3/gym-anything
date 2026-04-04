# Task: offer_letter_batch

**Difficulty**: Very Hard
**Domain**: Human Resources / Document Production
**Primary Occupation**: Human Resources Specialists, Administrative Services Managers
**Application**: Apache OpenOffice Writer

---

## Overview

Crestline Medical Devices, Inc. (Louisville, KY) has 5 new employees starting in February and March 2025. Each new hire requires a personalized employment offer letter before their start date. This is a standard HR workflow where the HR manager creates individual offer letters customized with each candidate's specific role details from a hiring database.

The agent, acting as HR Manager Diana Osei-Bonsu, must:
1. Read the hire data file at `/home/ga/Documents/new_hires.json` to obtain all candidate details, including names, job titles, departments, salaries, start dates, work locations, and employment types
2. Create **5 individual offer letter documents** in Apache OpenOffice Writer — one per new hire
3. Each letter must be addressed to the specific candidate and contain their personalized details (title, department, salary, start date, work location)
4. Each letter must reference the company benefits summary and include a signature block for CEO Robert Flanagan
5. Save each letter using the filename specified in the `offer_letter_filename` field of each hire's record (e.g., `offer_letter_Okonkwo_Amara.odt`) in `/home/ga/Documents/`

This task is genuinely hard because: the agent must create 5 separate documents (not one); must correctly personalize each with distinct hire-specific data (salary, title, start date vary per person); and must produce professional-quality formal letters — not placeholder or template text.

---

## Real Data

The hire data uses realistic positions typical of a medical device company:
- **Company**: Crestline Medical Devices, Inc. (fictitious but realistically modeled)
- **Address**: 9300 Shelbyville Road, Suite 400, Louisville, KY 40222
- **5 hires** across departments: Regulatory Affairs, Quality Assurance, R&D, Technical Services, Clinical Affairs
- Salaries range from $68,000 (Field Service Tech) to $118,000 (Senior R&D Engineer)
- Mix of on-site, hybrid, and remote roles

---

## Starting State

- `/home/ga/Documents/new_hires.json` — full hire data with 5 candidates and all offer letter details
- No offer letter `.odt` files yet in `/home/ga/Documents/`

---

## Expected End State

Five `.odt` files exist in `/home/ga/Documents/`:
- `offer_letter_Okonkwo_Amara.odt` — for Amara Okonkwo, Regulatory Affairs Specialist II, $87,500
- `offer_letter_Tremblay_Kevin.odt` — for Kevin Tremblay, Quality Systems Engineer, $92,000
- `offer_letter_Nair_Preethi.odt` — for Preethi Nair, Senior R&D Engineer – Biomaterials, $118,000
- `offer_letter_Vasquez_Jordan.odt` — for Jordan Vasquez, Field Service Technician, $68,000
- `offer_letter_Petrov_Marcus.odt` — for Marcus Petrov, Clinical Affairs Manager, $105,000

Each file must be ≥ 2 KB and contain the hire's last name, title keyword, and salary.

---

## Verification Criteria

Each letter is scored out of 20 points (5 letters × 20 = 100 pts total):
- **File exists**: 10 pts
- **Correct hire-specific content** (name + title + salary present): 6 pts
- **Substantial size** (≥ 2 KB): 4 pts

| Letter | Max pts | Verified By |
|--------|---------|-------------|
| offer_letter_Okonkwo_Amara.odt | 20 | Name "okonkwo", "regulatory affairs", "87,500" in text |
| offer_letter_Tremblay_Kevin.odt | 20 | Name "tremblay", "quality systems", "92,000" in text |
| offer_letter_Nair_Preethi.odt | 20 | Name "nair", "r&d", "118,000" in text |
| offer_letter_Vasquez_Jordan.odt | 20 | Name "vasquez", "field service", "68,000" in text |
| offer_letter_Petrov_Marcus.odt | 20 | Name "petrov", "clinical", "105,000" in text |
| **Total** | **100** | |
| **Pass threshold** | **70** | |

**GATE**: If zero offer letter files are found → score=0 immediately.

**Partial completion scenarios**:
- 4 complete letters = 80 pts (passes)
- 3 complete letters + 1 exists-only = 34+10 = 64 pts (fails)
- All 5 exist but no correct content = 50 pts (fails)
- The agent must get the names and salaries right — generic boilerplate without personalization scores only the file-exists points

---

## Schema Reference

JSON data file: `/home/ga/Documents/new_hires.json`
- `.company` — name, address, HR contact, CEO name
- `.offer_letter_terms` — benefits summary, at-will notice, confidentiality clause
- `.new_hires[]` — array of 5 hire objects, each with:
  - `full_name`, `title`, `department`, `manager`
  - `salary_annual_usd`, `salary_formatted` (e.g., "$87,500")
  - `start_date` (e.g., "February 3, 2025")
  - `work_location`, `employee_type`
  - `offer_letter_filename` — exact filename to use when saving
