# Setup Code Spell Checker Task

**Difficulty**: 🟢 Easy  
**Skills**: Extension installation, workspace configuration, spell checking  
**Duration**: 600 seconds  
**Steps**: ~50

## Objective

Configure VSCode's spell checking for a Python project being prepared for open-source release. The project contains many domain-specific technical terms that should be added to a custom dictionary, while still catching real typos in documentation and code comments.

## Context

You're preparing to open-source an internal authentication library. The code works perfectly but has embarrassing typos in documentation and comments. You need to:
1. Install a spell checker extension
2. Configure it with a custom dictionary for legitimate technical terms
3. Fix the real typos it finds

## Expected Workflow

1. **Install Code Spell Checker extension**
   - Press `Ctrl+Shift+P` to open Command Palette
   - Type "Extensions: Install Extensions"
   - Search for "Code Spell Checker"
   - Install "Code Spell Checker" by Street Side Software

2. **Configure custom dictionary**
   - Create/edit `.vscode/settings.json` in the workspace
   - Add `cSpell.words` array with technical terms:
     - "AuthN", "AuthZ"
     - "CRMSync", "SalesforceAPI"
     - "MetricsAgg", "TimeSeries"
     - "RefreshToken", "JWTValidator"

3. **Fix typos in documentation**
   - Open README.md
   - Use spell checker suggestions to fix typos like:
     - "syncronizing" → "synchronizing"
     - "automaticaly" → "automatically"
     - "managment" → "management"
     - "suports" → "supports"
     - etc.

4. **Fix typos in code comments/docstrings**
   - Open `auth_provider.py`
   - Fix typos in docstrings:
     - "authentification" → "authentication"
     - "syncronize" → "synchronize"
     - etc.

## Verification

Checks for:
1. Code Spell Checker extension installed (2 points)
2. Custom dictionary configured with required terms (3 points)
3. At least 8 typos fixed in README.md (3 points)
4. At least 5 typos fixed in Python docstrings (2 points)

**Pass Threshold**: 70% (7/10 points)

## Tips

- The spell checker will underline misspelled words with a blue squiggle
- Right-click on underlined words for quick fix suggestions
- Technical terms like "AuthN", "CRMSync" should go in the custom dictionary
- Real typos like "recieve", "occured" should be fixed