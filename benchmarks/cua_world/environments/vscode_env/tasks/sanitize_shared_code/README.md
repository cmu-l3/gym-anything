# Sanitize Shared Code Task

**Difficulty**: 🟡 Medium  
**Skills**: Find/Replace, Security awareness, Documentation, Multi-file editing  
**Duration**: 300 seconds  
**Steps**: ~80

## Objective

Clean a Flask demo codebase by removing all hardcoded credentials (database passwords, API keys, AWS secrets) before sharing with colleagues or publishing to GitHub. Replace them with safe placeholder values and document what was removed.

## Expected Workflow

1. Open workspace `/home/ga/workspace/flask_demo` in VSCode
2. Review files: `app.py`, `config.py`, `test_app.py`
3. Use Find and Replace (Ctrl+Shift+H) to systematically find and replace secrets:
   - Database passwords
   - Stripe API keys (both test and live)
   - AWS access keys and secrets
   - SendGrid API key
   - Flask secret key
   - JWT secret
4. Replace secrets with placeholders like `YOUR_API_KEY_HERE`, `<REPLACE_ME>`, etc.
5. Create `SECRETS_REMOVED.md` documenting what types of secrets were sanitized
6. Verify code still has valid Python syntax

## Verification

Checks for:
1. All 8 hardcoded secrets removed from files
2. Placeholder values present in at least 2 files
3. `SECRETS_REMOVED.md` exists with meaningful content (>50 chars, mentions security keywords)
4. Python syntax remains valid in all files

**Pass Threshold**: 100% (all criteria must pass)

## Secret Types to Remove

- Database password: `MyS3cr3tP@ssw0rd2024!`
- Stripe live key: `sk_live_51K7xYz...`
- Stripe public key: `pk_live_51K7xYz...`
- AWS access key: `AKIAIOSFODNN7EXAMPLE`
- AWS secret key: `wJalrXUtnFEMI/K7MDENG/...`
- SendGrid key: `SG.xYz123AbC456...`
- Flask secret: `flask-secret-key-change-in-production-xyz789`
- JWT secret: `super-secret-jwt-token-12345`