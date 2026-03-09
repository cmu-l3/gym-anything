# Format API Response Task

**Difficulty**: 🟡 Easy-Medium  
**Skills**: JSON formatting, file creation, data extraction, documentation  
**Duration**: 240 seconds  
**Steps**: ~30

## Objective

Format a minified cryptocurrency API response to make it readable, extract key price data, and document the structure. This simulates a common real-world scenario when integrating with third-party APIs.

## Context

A backend team sent you a sample API response saved as `api_response.json`, but it's minified (all on one line) making it impossible to understand the nested structure. You need to make it readable, extract essential data, and document it for your team.

## Expected Workflow

1. Open `api_response.json` in VSCode (currently unreadable - 1000+ chars on one line)
2. Format the JSON using VSCode's Format Document feature:
   - Command Palette (Ctrl+Shift+P) → "Format Document"
   - OR Right-click → "Format Document"  
   - OR Keyboard shortcut (Shift+Alt+F)
3. Create `price_summary.json` with extracted BTC and ETH prices for USD and EUR
4. Create `API_STRUCTURE.md` documenting the response structure
5. Save all files

## Verification

Checks for:
1. `api_response.json` is formatted (multi-line, proper indentation)
2. `price_summary.json` exists with correct structure and price values
3. `API_STRUCTURE.md` exists with documentation (>100 chars, mentions key terms)

**Pass Threshold**: 100% (all 3 criteria must pass)