# Task: Edge Browser Security Policy Compliance

## Domain Context
IT administrators and regulatory affairs managers are frequently required to configure browsers to meet enterprise security policies. This is real professional work: reading a policy document, locating the appropriate settings in a complex UI, and verifying compliance. Edge's Settings UI has dozens of sub-pages and options — finding each policy-required setting requires systematic navigation.

## Starting State
Edge is configured with the following **non-compliant** settings (set by setup script):
- **SmartScreen/Safe Browsing**: DISABLED (policy requires ENABLED)
- **Password Manager**: ENABLED (policy requires DISABLED)
- **Address Autofill**: ENABLED (policy requires DISABLED)
- **Search Engine**: Bing (policy requires DuckDuckGo)
- **Tracking Prevention**: Basic (policy requires Strict)

The policy document at `/home/ga/Desktop/security_policy.txt` describes each requirement.

## Goal
Read the policy, navigate Edge Settings, change all 5 non-compliant settings to compliant values, and write a compliance confirmation report.

## What the Agent Must Figure Out
- Where each setting lives in Edge's Settings (multiple sub-pages):
  - SmartScreen: Settings → Privacy, search, and services → Microsoft Defender SmartScreen
  - Password Manager: Settings → Passwords (or Autofill and passwords)
  - Address Autofill: Settings → Personal info (or Autofill and passwords)
  - Search Engine: Settings → Privacy, search, and services → Address bar and search
  - Tracking Prevention: Settings → Privacy, search, and services → Tracking prevention
- How to navigate between Settings sub-pages
- What "Strict" mode looks like in Edge's tracking prevention UI
- How to add DuckDuckGo as search engine and set it as default

## Success Criteria
The task is considered complete when:
1. Compliance report exists at `/home/ga/Desktop/compliance_report.txt`, written after task start
2. Microsoft Defender SmartScreen is enabled in Edge Preferences
3. Password manager is disabled in Edge Preferences
4. Address autofill is disabled in Edge Preferences
5. Compliance report mentions "DuckDuckGo" (evidence of search engine change)
6. Compliance report mentions "Strict" (evidence of tracking prevention change)

## Verification Strategy
- **Preferences file**: Kill Edge to flush preferences, then read JSON and check specific keys
- **Report file**: Check existence, modification time, and content for required terms
- All Preferences keys verified are ones explicitly set by the base setup script (known keys)

## Scoring Breakdown (100 points)
- Compliance report file exists and was written after task start: 10 points
- SmartScreen enabled (`safebrowsing.enabled` = true): 20 points
- Password manager disabled (`credentials_enable_service` = false): 20 points
- Address autofill disabled (`autofill.enabled` = false): 20 points
- Report mentions DuckDuckGo (search engine change documented): 15 points
- Report mentions Strict tracking prevention (tracking change documented): 15 points

**Pass threshold**: 65 points

## Why This Is Hard
1. Edge Settings has a complex multi-level UI — finding each setting requires navigating different sub-sections
2. The agent must read and interpret a policy document, then map policy requirements to browser settings
3. Five independent settings must all be changed, requiring multiple Settings navigations
4. Adding DuckDuckGo as default search requires finding and using "Manage search engines" dialog
5. Setting tracking prevention to "Strict" requires knowing that "Strict" is a specific mode in Edge
6. The agent must write a structured compliance confirmation document

## Security Policy (set by setup script)
Content of `/home/ga/Desktop/security_policy.txt`:
```
BROWSER SECURITY POLICY - COMPLIANCE REQUIRED

All workstations using Microsoft Edge must meet:

1. TRACKING PREVENTION: Set to "Strict" mode (not Basic or Balanced)
2. PASSWORD MANAGER: Edge password saving must be DISABLED
3. SEARCH ENGINE: Default must be changed to DuckDuckGo (duckduckgo.com)
4. SAFE BROWSING: Microsoft Defender SmartScreen must be ENABLED
5. AUTOFILL: Address and payment autofill must be DISABLED
```
