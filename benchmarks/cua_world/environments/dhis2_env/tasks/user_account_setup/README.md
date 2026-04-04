# Task: user_account_setup

## Overview

This task evaluates an AI agent's ability to perform DHIS2 system administration — specifically creating and configuring a new user account with appropriate roles and organisation unit access — reflecting the real workflow of a national DHIS2 system administrator onboarding district health staff.

**Difficulty**: Hard
**Timeout**: 600 seconds
**Max Steps**: 70

## Domain Context

In Sierra Leone's DHIS2 deployment, the national HMIS team manages user accounts for hundreds of district health officers, facility data entry clerks, and programme officers. Onboarding a new health information officer involves: creating their account, selecting appropriate pre-existing roles (which control what data they can enter and view), assigning their data capture scope (which facilities/districts they report for), and their data view scope (which data they can see in analytics).

This task reflects a real monthly onboarding process — new district health staff must be set up in DHIS2 before they can submit reports. Misconfigured access (wrong org unit, wrong role) has real consequences for data quality.

## Goal

Create a new DHIS2 user account:
- **Username**: fatmata.koroma
- **First name**: Fatmata
- **Surname**: Koroma
- **Email**: fatmata.koroma@mohsl.gov.sl
- **Password**: District2024!
- **Role**: Appropriate data entry role (agent must discover available roles)
- **Data capture org units**: Kenema district and/or its sub-units
- **Data view org units**: Sierra Leone (national root)
- **Account status**: Enabled/active

## What Makes This Hard

- User Management is in a separate admin section of DHIS2 — agent must navigate there independently
- Available user roles must be discovered (not told which role name to assign)
- Organisation unit assignment has TWO separate components: data capture AND data view
- The data capture org unit must be set to district level (not the national root)
- The data view org unit must be the national root (not just Kenema)
- Agent must confirm the account was created — verifying through the user list
- Password complexity may be enforced by the system

## Success Criteria

| Criterion | Points | Description |
|-----------|--------|-------------|
| User fatmata.koroma created in DHIS2 (MANDATORY) | 30 | User appears in DHIS2 user list via API |
| User has correct first name and surname | 15 | firstName=Fatmata, surname=Koroma |
| User has correct email | 10 | Email matches fatmata.koroma@mohsl.gov.sl |
| User has at least one role assigned | 20 | At least one userRole configured |
| User has data capture org unit configured | 15 | At least one org unit in data capture scope |
| User account is enabled (not disabled) | 10 | Account is active |

**Pass threshold**: 60 points
**Mandatory**: User must exist in DHIS2

## Verification Strategy

1. Query DHIS2 API: `/api/users?filter=username:eq:fatmata.koroma&fields=id,username,firstName,surname,email,userRoles,organisationUnits,disabled`
2. Verify all required fields match
3. Check role assignment and org unit configuration

## Data Reference

- **DHIS2 module**: Administration → Users (or Settings → Users)
- **Target org unit**: Kenema district (in Sierra Leone district list)
- **Available roles**: Discovery required — look for data entry, data capture, or facility roles
- **API verification**: `/api/users?filter=username:eq:fatmata.koroma`

## Edge Cases

- DHIS2 may enforce password complexity — agent should handle errors
- The "data view" org unit may be called "search org units" in some DHIS2 versions
- Email domain (@mohsl.gov.sl) may not pass format validation — agent may need to use alternative
- Role names vary by DHIS2 configuration — agent must read available roles and choose appropriately
