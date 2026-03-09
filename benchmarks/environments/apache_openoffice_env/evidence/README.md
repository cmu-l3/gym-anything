# Apache OpenOffice Environment - Evidence Documentation

This folder contains evidence of successful environment creation and task completion for the Apache OpenOffice Writer environment.

## Environment Overview

- **Environment ID**: apache_openoffice_env@0.1
- **Task ID**: create_business_letter@1
- **Difficulty**: Medium
- **Initial State**: Ubuntu desktop with OpenOffice Writer NOT running (agent must launch it)

## Real Data Requirements

The environment uses **REAL company data** as required by prompt.md guidelines (Phase 2.4, 4.1, 5.5):

### Companies and Executives
| Role | Name | Company | Title | Address |
|------|------|---------|-------|---------|
| Sender | Matt Hicks | Red Hat, Inc. | President and CEO | 100 East Davie Street, Raleigh, NC 27601 |
| Recipient | Arvind Krishna | IBM Corporation | Chairman and CEO | 1 New Orchard Road, Armonk, NY 10504 |

### Data Sources
- Company websites (redhat.com, ibm.com)
- SEC filings
- Public press releases

### Verification Notes
- Red Hat was acquired by IBM in 2019
- Matt Hicks has been Red Hat CEO since 2022
- Arvind Krishna has been IBM CEO since 2020

## Verifier Criteria (13 total)

The verifier checks for:

1. **File Exists** - Document saved at expected path
2. **File Size** - At least 5KB (prevents minimal content)
3. **Sender Company** - "Red Hat" present
4. **Sender Address** - Raleigh/Davie Street/NC 27601
5. **Recipient Name** - "Arvind Krishna" or "Mr. Krishna"
6. **Recipient Company** - "IBM" present
7. **Recipient Address** - Armonk/New Orchard/NY 10504
8. **Date** - "February X, 2026" format
9. **Salutation** - "Dear Mr. Krishna"
10. **Closing** - "Respectfully"
11. **Signer** - "Matt Hicks"
12. **Structure** - Elements in correct order (letterhead → date → recipient → salutation → closing → signer)
13. **Body Content** - At least 3 sentences, topic-relevant keywords

### Pass Requirements
- At least 11 of 13 criteria (85%)
- MUST pass: file_exists, sender_company, recipient_name, salutation, closing, signer, structure

## Test Screenshots

The screenshots document a successful task completion:

| Screenshot | Description |
|------------|-------------|
| real_data_test_01_initial.png | Initial desktop state (Writer not running) |
| real_data_test_12_current.png | First-run wizard appeared |
| real_data_test_13_after_yes.png | After accepting first-run |
| real_data_test_14_wizard_step2.png | User info step |
| real_data_test_16_wizard_done.png | OpenOffice Start Center |
| real_data_test_17_writer_opened.png | Writer opened with blank document |
| real_data_test_22_letter_typed.png | Business letter with real data typed |
| real_data_test_26_after_save.png | Document saved successfully |

## Saved Document

### partnership_letter_real_data.odt
The saved document (10,133 bytes) contains:
- Red Hat, Inc. letterhead with real address
- Letter addressed to Arvind Krishna, CEO of IBM
- Open source collaboration proposal (4 sentences)
- Signed by Matt Hicks, President and CEO

### Document Content Preview
```
Red Hat, Inc.
100 East Davie Street
Raleigh, NC 27601

February 3, 2026

Mr. Arvind Krishna
Chairman and CEO
IBM Corporation
1 New Orchard Road
Armonk, NY 10504

Dear Mr. Krishna,

I am writing to propose an open source collaboration initiative between Red Hat
and IBM. Our companies share a deep commitment to enterprise Linux and hybrid
cloud technologies. Together, we can accelerate innovation in container
orchestration, Kubernetes, and cloud-native development platforms. This
partnership would strengthen our competitive position in the rapidly evolving
enterprise software market.

Respectfully,

Matt Hicks
President and CEO
Red Hat, Inc.
```

## Interactive Testing Process

Testing was performed using `ask_cua.py` for VLM-guided GUI interaction:

1. Started environment on SSH port 2271, VNC port 5926
2. Used ask_cua.py to get coordinates for GUI elements
3. Scaled coordinates from 1280x720 (CUA output) to 1920x1080 (actual resolution)
4. Navigated through first-run wizard
5. Opened Writer from Start Center
6. Typed business letter with real company data using xdotool
7. Saved document to /home/ga/Documents/partnership_letter.odt
8. Ran export script and verification

## Key Technical Details

- **Coordinate Scaling**: CUA returns 1280x720 normalized coords → scale by 1.5× for 1920x1080
- **First-run Wizard**: Must complete (--nofirststartwizard unreliable)
- **ODT Format**: ZIP archives; extract content.xml for text verification
- **Initial State**: Writer NOT pre-launched (agent must open it)
