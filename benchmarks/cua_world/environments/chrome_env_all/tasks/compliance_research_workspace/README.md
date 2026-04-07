# Compliance Research Workspace (`compliance_research_workspace@1`)

## Overview

**Domain**: Regulatory Affairs Manager -- Browser Workspace Configuration

A regulatory affairs manager must configure their Chrome browser according to the department's Browser Configuration Standard. The standard document on the Desktop specifies a comprehensive set of requirements covering bookmark organization into a deep hierarchy for regulatory bodies (FDA, EPA, OSHA, SEC), custom search engine shortcuts for regulatory databases, homepage and startup page configuration, privacy and security settings, and download directory management.

## Initial State

- **Bookmarks**: 24 regulatory bookmarks placed flat on the bookmark bar with no folder structure. Bookmarks span FDA, EPA, OSHA, SEC, NIST, EU, WHO, ISO, Federal Register, and other regulatory/legislative sites.
- **Preferences**: Non-compliant defaults -- homepage set to `google.com`, no custom search engines, third-party cookies allowed, Do Not Track disabled, Safe Browsing in standard mode, download directory at `/home/ga/Downloads`, password saving and autofill enabled.
- **Spec file**: `~/Desktop/browser_config_standard.txt` -- the full Browser Configuration Standard v2.1.
- **Download directory**: `/home/ga/Documents/Regulatory_Downloads` pre-created.

## Goal

All specifications from `~/Desktop/browser_config_standard.txt` are fully implemented:

- Bookmarks organized into 5 top-level folders (`Federal Agencies`, `Standards Bodies`, `International`, `Legislative Resources`, `Consumer Protection`) with agency-specific sub-folders under `Federal Agencies` (`FDA`, `EPA`, `OSHA`, `SEC`).
- 3 custom search engine shortcuts configured: `cfr` (Code of Federal Regulations), `fr` (Federal Register), `edgar` (SEC EDGAR).
- Homepage set to `https://www.federalregister.gov`.
- Startup pages: `federalregister.gov`, `regulations.gov`, `ecfr.gov`.
- Third-party cookies blocked, Do Not Track enabled, Safe Browsing in Enhanced Protection mode.
- Download directory set to `/home/ga/Documents/Regulatory_Downloads` with "always ask" enabled.
- Password saving, address autofill, and payment methods all disabled.

## Success Criteria

The task is verified against 7 criteria totaling 100 points. Pass threshold: **70/100**.

## Scoring Breakdown

| # | Criterion | Points | Details |
|---|-----------|--------|---------|
| 1 | Bookmark hierarchy created | 20 | >= 4 of 5 required top-level folders on bookmark bar (case-insensitive match) |
| 2 | Federal Agencies sub-folders | 10 | >= 3 of 4 sub-folders (FDA, EPA, OSHA, SEC) inside "Federal Agencies" with matching bookmarks |
| 3 | Custom search engines | 15 | 5 pts per search engine keyword found (`cfr`, `fr`, `edgar`) |
| 4 | Homepage and startup pages | 15 | Homepage contains `federalregister.gov` (5 pts); startup URLs: proportional credit for 3 expected domains (10 pts) |
| 5 | Privacy settings | 15 | Third-party cookies blocked (5 pts); Do Not Track enabled (5 pts); Safe Browsing enhanced (5 pts) |
| 6 | Download directory | 10 | Path contains `Regulatory_Downloads` (5 pts); prompt_for_download = true (5 pts) |
| 7 | Autofill/password disabled | 15 | Password saving disabled (5 pts); address autofill disabled (5 pts); payment methods disabled (5 pts) |

## Verification Strategy

1. **Bookmark hierarchy**: The verifier reads the Bookmarks JSON, inspects bookmark_bar children for folders matching each of the 5 required names (case-insensitive exact match).
2. **Federal Agencies sub-folders**: Within the "Federal Agencies" folder, the verifier looks for sub-folders named FDA, EPA, OSHA, SEC. Each sub-folder must contain at least one bookmark whose URL matches the corresponding agency domain (e.g., `fda.gov`).
3. **Search engines**: Preferences JSON is parsed for search engine entries in `search_provider_overrides`, `default_search_provider_data.template_url_data`, and `profile.custom_search_providers`. Each entry's keyword is checked against the expected set.
4. **Homepage/startup**: The `homepage` field is checked for `federalregister.gov`. The `session.startup_urls` list is checked for three expected domains. `restore_on_startup` should be 4 (open specific pages).
5. **Privacy**: `profile.block_third_party_cookies`, `enable_do_not_track`, and `safebrowsing.enhanced` are read from Preferences.
6. **Download**: `download.default_directory` checked for `regulatory_downloads` (case-insensitive); `download.prompt_for_download` checked for `true`.
7. **Autofill/password**: Multiple Preferences locations checked -- `credentials_enable_service`, `profile.password_manager_enabled`, `autofill.profile_enabled`, `autofill.credit_card_enabled`.

## Edge Cases and Potential Issues

- **Folder name sensitivity**: Folder matching is case-insensitive exact match. Slight name variations (e.g., "Federal Agency" instead of "Federal Agencies") will not match.
- **Search engine storage locations**: Chrome stores custom search engines in different Preferences keys across versions. The verifier checks 3 locations but the agent's method of adding them matters.
- **Startup vs. restore mode**: Setting startup URLs requires `restore_on_startup = 4`. If the agent sets URLs but leaves restore mode at 1 (restore last session) or 5 (new tab), the URLs may be configured but not active.
- **Privacy setting paths**: Some privacy settings have multiple valid Preferences paths (e.g., cookie blocking via `block_third_party_cookies` or `default_content_setting_values.cookies`). The verifier accepts either.
- **No contamination injection**: This task does not seed incorrect items -- all 24 bookmarks are legitimate and need to be organized. The challenge is implementing a complex spec correctly, not filtering.
