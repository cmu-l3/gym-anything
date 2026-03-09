# Rotate Exposed Credentials Task

**Difficulty**: 🟡 Medium  
**Skills**: Multi-file search, find-and-replace, security best practices, context awareness  
**Duration**: 300 seconds  
**Steps**: ~100

## Objective

Rotate an accidentally exposed Stripe API secret key across the entire codebase while carefully preserving test mock keys and documentation placeholders.

## Scenario

A live Stripe API secret key (`sk_live_A7xK9mP2nQ4rL8vB3wE6yT1`) was accidentally committed to version control. The security team has rotated the key and issued a new one (`sk_live_Z9yN2mR5pK8qX3vL7wT4jE6`). You must replace all occurrences of the exposed key with the new key in production code, while preserving:
- Test mock keys (`sk_test_mock_12345`)
- Documentation placeholders (`sk_live_your_key_here`)

## Expected Workflow

1. Open workspace (`/home/ga/workspace/payment_service`)
2. Use **Find in Files** (Ctrl+Shift+F) to locate exposed key
3. Use **Replace in Files** (Ctrl+Shift+H) to replace with new key
4. Use **Files to Exclude** pattern to avoid test and doc files: `**/tests/**, **/*.md`
5. Carefully review each replacement before applying
6. Verify changes (optional: check Source Control)
7. Save all modified files (Ctrl+K S or File > Save All)

## Files to Update

### Production files (MUST replace):
- `src/payment_client.py`
- `src/utils/stripe_helper.js`
- `config/production.yaml`
- `.env.example`
- `.env.local`

### Files to PRESERVE (must NOT change):
- `tests/test_payment.py` (contains mock key)
- `tests/stripe.test.js` (contains mock key)
- `README.md` (contains placeholder)

## Verification

Checks for:
1. ✅ Exposed key replaced in all 5 production files
2. ✅ New key present in all 5 production files
3. ✅ Mock key preserved in test files
4. ✅ Documentation placeholder unchanged in README

**Pass Threshold**: 100% (all criteria must pass for security tasks)

## Tips

- Use `Ctrl+Shift+F` for multi-file search
- Use `Ctrl+Shift+H` for multi-file replace
- Use exclude pattern: `**/tests/**, **/*.md`
- Preview changes before applying
- Double-check test files remain unchanged