# License Audit Task (`audit_dependency_licenses@1`)

**Difficulty**: 🟡 Medium  
**Skills**: License compliance, dependency analysis, risk assessment, documentation  
**Duration**: 300 seconds (5 minutes)  
**Steps**: ~30

## Overview

Audit a Node.js project's npm dependencies for license compliance before a commercial software release. This task simulates a critical pre-release legal compliance check where you must identify problematic licenses (especially GPL/AGPL) that are incompatible with commercial distribution.

## Scenario

Your company is releasing a commercial analytics dashboard in 48 hours. The legal team needs a comprehensive license audit of all dependencies to ensure compliance. The project is proprietary software that requires all dependencies to use permissive licenses (MIT, Apache-2.0, BSD, ISC).

**Your mission:** Create a detailed license audit report identifying any GPL, AGPL, or other copyleft licenses that pose legal risks, plus any dependencies with missing license information.

## Objective

Create a file named `LICENSE_AUDIT_REPORT.md` in the project root directory (`/home/ga/workspace/license_audit_project/`) that includes:

1. **Executive Summary**: Total dependencies and high-level findings
2. **Detailed Findings**: List of dependencies with licenses and risk levels
3. **High-Risk Items**: GPL/AGPL licenses incompatible with commercial use
4. **Missing Licenses**: Dependencies without clear license information
5. **Recommendations**: Alternative packages or actions to resolve issues

## Expected Workflow

### 1. Explore Project Structure
- Open the project in VSCode
- Read `README.md` to understand the commercial licensing requirements
- Review `package.json` to see direct dependencies
- Examine `package-lock.json` for the full dependency tree

### 2. Investigate Dependencies
- Navigate to `node_modules` directory
- For each dependency, check:
  - `package.json` "license" field
  - `LICENSE` or `LICENSE.txt` file
  - `README.md` license section
- Take notes on what you find

### 3. Identify Problematic Licenses
Look for:
- **GPL-3.0** ❌ (strong copyleft - incompatible with commercial)
- **AGPL** ❌ (strong copyleft - incompatible)
- **LGPL** ⚠️ (weak copyleft - requires legal review)
- **Missing licenses** ⚠️ (unclear legal status)

Safe licenses:
- **MIT** ✅ (permissive)
- **Apache-2.0** ✅ (permissive)
- **BSD** ✅ (permissive)
- **ISC** ✅ (permissive)

### 4. Create Audit Report
- Create new file: `LICENSE_AUDIT_REPORT.md` in project root
- Use markdown formatting (headers, tables, lists)
- Structure the report clearly for non-technical stakeholders
- Include risk levels: HIGH / MEDIUM / LOW
- Provide actionable recommendations

### 5. Document Findings
Your report should answer:
- How many total dependencies are there?
- Which ones have problematic licenses?
- What specific risks do they pose?
- What alternatives exist?
- What actions should be taken before release?

## Verification Criteria

The verifier checks:

1. ✅ **Report Exists** (15 pts): `LICENSE_AUDIT_REPORT.md` created with substantial content
2. ✅ **Markdown Structure** (10 pts): Proper headers, tables, or lists
3. ✅ **GPL Identified** (30 pts): The GPL-3.0 dependency is found and flagged as high-risk
4. ✅ **Comprehensive Coverage** (20 pts): At least 10 dependencies documented
5. ✅ **Risk Categorization** (10 pts): High/Medium/Low risk levels assigned
6. ✅ **Recommendations** (10 pts): Alternatives or action items provided
7. ✅ **Executive Summary** (5 pts): High-level overview section present

**Pass Threshold**: 70/100 points

## Key Files to Examine

- `/home/ga/workspace/license_audit_project/package.json` - Direct dependencies
- `/home/ga/workspace/license_audit_project/package-lock.json` - Full dependency tree
- `/home/ga/workspace/license_audit_project/node_modules/*/package.json` - Individual package licenses
- `/home/ga/workspace/license_audit_project/node_modules/*/LICENSE` - License full text

## Tips

- **Focus on the GPL package first**: There's a dependency with GPL-3.0 license that's critical to find
- **Use VSCode search**: Use `Ctrl+Shift+F` to search for "license" across node_modules
- **Check multiple sources**: Some packages have license in package.json, others in LICENSE files
- **Be thorough but practical**: You don't need to document every single package, but cover the most important ones
- **Think like legal/business**: Your report should be readable by non-technical stakeholders

## Sample Report Structure
