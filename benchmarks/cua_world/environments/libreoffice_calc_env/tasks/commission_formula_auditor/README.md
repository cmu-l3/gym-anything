# Commission Formula Auditor Task

**Difficulty**: 🟡 Medium  
**Skills**: Formula comprehension, debugging, cell dependency tracing, policy compliance verification  
**Duration**: 180 seconds  
**Steps**: ~15

## Objective

Reverse-engineer and audit an existing commission spreadsheet to verify calculations against written policy. A salesperson disputed their payment, and you must inspect the formulas to identify any errors. This tests the critical real-world skill of understanding and debugging inherited spreadsheets.

## Scenario

A small business owner inherited a commission spreadsheet from a departed bookkeeper. A salesperson (Alice) claims her commission payment of $350 is incorrect for $15,000 in sales. You must audit the commission calculation formulas to verify if they correctly implement the written commission policy.

## Starting State

- LibreOffice Calc opens with `commission_data.ods`
- Column A: Salesperson names
- Column B: Monthly sales figures
- Column C: Calculated commission (contains formulas to audit)
- Column E: Written Commission Policy
- Cell F1: "Audit Status" - where you should document findings

## Commission Policy (Written in Column E)
