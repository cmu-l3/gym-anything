# Chrome Autofill Profile Setup Task (`autofill_profile_setup@1`)

## Overview

This task tests an agent's ability to navigate Chrome's settings interface and configure an autofill profile with personal information. The agent must access Chrome's address settings, create a new address profile, fill in required fields (name, email, phone, address), and ensure the data is properly saved. This represents essential browser configuration that saves users significant time when filling out forms.

## Rationale

**Why this task is valuable:**
- **Settings Navigation Mastery:** Tests understanding of Chrome's multi-level settings interface structure
- **Data Entry Accuracy:** Requires precise input of structured personal information across multiple fields
- **Real-world Time-Saver:** Represents one of Chrome's most practical productivity features for daily use
- **Privacy-Adjacent Skills:** Introduces concepts related to how browsers store and manage personal data
- **Form Interaction:** Builds skills for interacting with complex web forms and validation
- **Practical Configuration:** Common task performed by billions of Chrome users worldwide

**Real-world Context:** A user is tired of repeatedly typing their name, address, email, and phone number into countless online forms for shopping, job applications, account registrations, and service signups. They've heard that Chrome can auto-fill this information but have never set it up. They want to configure their autofill profile once so Chrome can automatically populate form fields in the future, saving minutes on every form they encounter.

## Task Description

**Goal:** Configure Chrome autofill profile with personal information to enable automatic form filling

**Starting State:** Chrome open at `chrome://settings/addresses`

**Expected Actions:**
1. Navigate to `chrome://settings/addresses` (done by setup)
2. Click "Add" button to create new address profile
3. Fill in test data in the modal form:
   - **Name:** Jane Smith
   - **Street Address:** 742 Evergreen Terrace
   - **City:** Springfield
   - **State:** IL (Illinois)
   - **ZIP Code:** 62701
   - **Phone:** 555-0123
   - **Email:** jane.smith@example.com
4. Click "Save" button to persist the profile

**Final State:** Chrome with saved autofill profile containing complete personal information

## Verification Strategy

### SQLite Database Analysis

The verifier uses **direct database inspection** to validate autofill configuration:

#### A. Database Access and Parsing
- **File Location:** Chrome stores autofill data in `~/.config/google-chrome/Default/Web Data`
- **SQLite Structure:** The `Web Data` file is a SQLite database with multiple related tables
- **Data Extraction:** Queries the database for newly created profile entries
- **Field Validation:** Verifies that required fields contain valid data

#### B. Multi-Table JOIN Verification
Chrome stores autofill data across multiple normalized tables:
- `autofill_profiles`: Main profile table (address, city, state, zip, timestamps)
- `autofill_profile_names`: Name components (first, middle, last)
- `autofill_profile_emails`: Email addresses linked by GUID
- `autofill_profile_phones`: Phone numbers linked by GUID

#### C. Verification Criteria (5 total, need 4+ to pass)

✅ **Profile Exists:** At least one autofill profile found in database  
✅ **Name Populated:** First name or last name is non-empty  
✅ **Email Valid:** Email field contains "@" and "." characters  
✅ **Phone Populated:** Phone field contains at least one digit  
✅ **Address Complete:** Street, city, state, and ZIP code all non-empty  

### Scoring System

- **100%:** All 5 criteria met (perfect profile)
- **80%:** 4/5 criteria met (minor missing field)
- **60%:** 3/5 criteria met (significant gaps)
- **40%:** 2/5 criteria met (incomplete)
- **0-20%:** 0-1 criteria met (failed)

**Pass Threshold:** 80% (requires at least 4 out of 5 criteria)

### Database Query Example
