# Cross-Project Dependency Audit

## Domain Context
QA Analyst performing a quarterly cross-project dependency audit, identifying and documenting blockers between projects, creating tracking work packages, and adjusting priorities to reflect blocking relationships.

**Occupation**: Software Quality Assurance Analysts and Testers (O*NET importance: 99.0, GDP: $156M)
**Rationale**: Reporting bugs, tracking defects, and managing workflows are fundamental to the QA role.

## Task Overview
The QA analyst discovers that the mobile-banking-app depends on the ecommerce-platform's checkout security fixes. They must:
1. Add a dependency comment to the biometric login WP
2. Change the biometric WP status to reflect it's blocked
3. Create a dependency tracking dashboard WP in devops-automation
4. Escalate the checkout bug priority to High
5. Create a wiki page documenting the cross-project dependency

## Starting State
- **Biometric login WP**: In progress, mobile-banking-app
- **Checkout bug WP**: Normal priority, ecommerce-platform
- No "Cross-project dependency tracking dashboard" WP in devops-automation
- No "Cross-Project Dependencies" wiki page

## Success Criteria

| Criterion | Points | Check |
|-----------|--------|-------|
| Comment on biometric WP about dependency | 20 | Keywords: blocked, ecommerce/checkout |
| Biometric WP status changed from In progress | 15 | On hold preferred; New + [BLOCKED] prefix accepted |
| Dashboard WP created in devops-automation | 25 | Subject, type=Task, assignee=carol, version=Sprint 3, description |
| Checkout bug priority → High | 15 | Priority name check |
| Wiki page with dependency documentation | 25 | Page exists + biometric/checkout/ecommerce/blocking keywords |

**Pass threshold**: 65/100

## Verification Strategy
- **Baseline recording**: Initial WP count in devops-automation
- **Anti-gaming**: Checks both biometric modifications and dashboard creation
- **Multi-criterion**: 5 independent checks spanning 3 projects
- **Cross-project**: Task requires working across 3 different projects

## Key Tables/Models
- `WorkPackage` (subject, status, priority, assigned_to, version, journals/notes)
- `Project` (identifier: mobile-banking-app, ecommerce-platform, devops-automation)
- `WikiPage` (wiki → project, title, content)
