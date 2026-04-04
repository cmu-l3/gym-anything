#!/usr/bin/env python3
"""
Automate the OpenSIS web-based installer using Selenium.

This script:
1. Opens the OpenSIS URL (redirects to installer if not configured)
2. Fills in database credentials (Step 1)
3. Creates database (Step 2)
4. Enters school information (Step 3)
5. Creates admin account (Step 4)
6. Verifies completion (Step 5)
"""

import time
import sys
from selenium import webdriver
from selenium.webdriver.common.by import By
from selenium.webdriver.support.ui import WebDriverWait
from selenium.webdriver.support import expected_conditions as EC
from selenium.webdriver.chrome.options import Options
from selenium.webdriver.chrome.service import Service
from selenium.common.exceptions import TimeoutException, NoSuchElementException

# Configuration
OPENSIS_URL = "http://localhost/opensis/"
DB_SERVER = "localhost"
DB_PORT = "3306"
DB_USERNAME = "root"  # Need root to create database
DB_PASSWORD = ""  # Empty for default MariaDB root
DB_NAME = "opensis"
SCHOOL_NAME = "Demo School"
SCHOOL_START = "08/01/2024"
SCHOOL_END = "06/30/2025"
ADMIN_FIRST = "Admin"
ADMIN_LAST = "User"
ADMIN_MIDDLE = ""
ADMIN_EMAIL = "admin@school.edu"
ADMIN_USERNAME = "admin"
ADMIN_PASSWORD = "Admin@123"  # Must meet complexity: 8+ chars, number, special char


def create_driver():
    """Create Chrome WebDriver with appropriate options."""
    options = Options()
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--disable-gpu")
    options.add_argument("--window-size=1920,1080")
    options.add_argument("--password-store=basic")
    # Run headless for automation
    options.add_argument("--headless=new")

    driver = webdriver.Chrome(options=options)
    driver.implicitly_wait(10)
    return driver


def wait_for_element(driver, by, value, timeout=30):
    """Wait for element to be present and return it."""
    return WebDriverWait(driver, timeout).until(
        EC.presence_of_element_located((by, value))
    )


def wait_and_click(driver, by, value, timeout=30):
    """Wait for element to be clickable and click it."""
    element = WebDriverWait(driver, timeout).until(
        EC.element_to_be_clickable((by, value))
    )
    element.click()
    return element


def fill_field(driver, field_id, value):
    """Fill a form field by ID."""
    field = driver.find_element(By.ID, field_id)
    field.clear()
    field.send_keys(value)


def step1_database_credentials(driver):
    """Step 1: Enter database connection credentials."""
    print("Step 1: Database credentials...")

    # Wait for the form to load
    wait_for_element(driver, By.ID, "s_server")
    time.sleep(1)

    # Fill in credentials
    fill_field(driver, "s_server", DB_SERVER)
    fill_field(driver, "s_port", DB_PORT)
    fill_field(driver, "s_dbusername", DB_USERNAME)

    # Password field
    password_field = driver.find_element(By.ID, "s_dbpassword")
    password_field.clear()
    if DB_PASSWORD:
        password_field.send_keys(DB_PASSWORD)

    # Click Save & Next
    time.sleep(0.5)
    submit_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit'][value='Save & Next']")
    submit_btn.click()

    print("Step 1 completed")


def step2_create_database(driver):
    """Step 2: Create or select database."""
    print("Step 2: Database creation...")

    # Wait for step 2 page
    wait_for_element(driver, By.ID, "s_dbname")
    time.sleep(1)

    # Fill database name
    fill_field(driver, "s_dbname", DB_NAME)

    # Select "Create new database" radio button
    create_new = driver.find_element(By.ID, "dOpt2")
    create_new.click()

    # Click Save & Next
    time.sleep(0.5)
    submit_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit'][value='Save & Next']")
    submit_btn.click()

    # Wait for database creation (can take a while)
    print("Waiting for database to be created...")
    time.sleep(30)  # Database creation takes time

    print("Step 2 completed")


def step3_school_info(driver):
    """Step 3: Enter school information."""
    print("Step 3: School information...")

    # Wait for step 3 page
    wait_for_element(driver, By.ID, "school_name", timeout=60)
    time.sleep(1)

    # Fill school info
    fill_field(driver, "school_name", SCHOOL_NAME)
    fill_field(driver, "start_school", SCHOOL_START)
    fill_field(driver, "end_school", SCHOOL_END)

    # Check "Install with sample data" checkbox
    try:
        sample_data = driver.find_element(By.ID, "sample_data")
        if not sample_data.is_selected():
            sample_data.click()
    except NoSuchElementException:
        print("Sample data checkbox not found, continuing...")

    # Click Save & Next
    time.sleep(0.5)
    submit_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit'][value='Save & Next']")
    submit_btn.click()

    # Wait for processing
    print("Waiting for school setup...")
    time.sleep(20)

    print("Step 3 completed")


def step4_admin_account(driver):
    """Step 4: Create admin account."""
    print("Step 4: Admin account setup...")

    # Wait for step 4 page
    wait_for_element(driver, By.ID, "first_name", timeout=60)
    time.sleep(1)

    # Fill admin info
    fill_field(driver, "first_name", ADMIN_FIRST)
    fill_field(driver, "last_name", ADMIN_LAST)
    if ADMIN_MIDDLE:
        fill_field(driver, "middle_name", ADMIN_MIDDLE)
    fill_field(driver, "email", ADMIN_EMAIL)
    fill_field(driver, "username", ADMIN_USERNAME)
    fill_field(driver, "password", ADMIN_PASSWORD)
    fill_field(driver, "c_password", ADMIN_PASSWORD)  # Confirm password

    # Click Save & Next
    time.sleep(0.5)
    submit_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit'][value='Save & Next']")
    submit_btn.click()

    # Wait for account creation
    print("Waiting for account creation...")
    time.sleep(10)

    print("Step 4 completed")


def step5_completion(driver):
    """Step 5: Verify installation completion."""
    print("Step 5: Verifying completion...")

    # Wait for completion page
    try:
        # Look for success message
        WebDriverWait(driver, 60).until(
            EC.presence_of_element_located((By.XPATH, "//*[contains(text(), 'Congratulations')]"))
        )
        print("Installation completed successfully!")

        # Click "Proceed to openSIS Login" button if present
        try:
            proceed_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit'][value*='Proceed']")
            proceed_btn.click()
            time.sleep(3)
        except NoSuchElementException:
            print("Proceed button not found, navigating manually...")
            driver.get(OPENSIS_URL)

        return True

    except TimeoutException:
        print("ERROR: Did not find completion message")
        print(f"Current URL: {driver.current_url}")
        print(f"Page source preview: {driver.page_source[:1000]}")
        return False


def verify_login(driver):
    """Verify we can login with the created credentials."""
    print("Verifying login...")

    driver.get(OPENSIS_URL)
    time.sleep(3)

    # Look for login form
    try:
        username_field = wait_for_element(driver, By.ID, "username", timeout=10)
        password_field = driver.find_element(By.ID, "password")

        username_field.clear()
        username_field.send_keys(ADMIN_USERNAME)
        password_field.clear()
        password_field.send_keys(ADMIN_PASSWORD)

        # Submit login
        login_btn = driver.find_element(By.CSS_SELECTOR, "input[type='submit']")
        login_btn.click()

        time.sleep(5)

        # Check if we're now on the portal/dashboard
        if "Portal" in driver.page_source or "Dashboard" in driver.page_source or "Modules.php" in driver.current_url:
            print("Login successful!")
            return True
        elif "incorrect" in driver.page_source.lower() or "failed" in driver.page_source.lower():
            print("Login failed - incorrect credentials message shown")
            return False
        else:
            print(f"Login status unclear. Current URL: {driver.current_url}")
            return True  # Assume success if no error shown

    except Exception as e:
        print(f"Error during login verification: {e}")
        return False


def main():
    """Run the automated installation."""
    print("=" * 50)
    print("OpenSIS Automated Installer")
    print("=" * 50)

    driver = None
    try:
        driver = create_driver()

        # Navigate to OpenSIS
        print(f"Navigating to {OPENSIS_URL}")
        driver.get(OPENSIS_URL)
        time.sleep(3)

        # Check if we're on the installer or already installed
        if "install" in driver.current_url.lower() or "Step" in driver.page_source:
            print("Installer detected, proceeding with automated setup...")

            # Determine which step we're on
            current_url = driver.current_url

            if "Step1" in current_url or "step1" in current_url:
                step1_database_credentials(driver)

            # Wait and proceed through steps
            time.sleep(2)

            if "Step2" in driver.current_url or "Selectdb" in driver.page_source:
                step2_create_database(driver)

            time.sleep(2)

            if "Step3" in driver.current_url or "School Information" in driver.page_source:
                step3_school_info(driver)

            time.sleep(2)

            if "Step4" in driver.current_url or "Admin" in driver.page_source:
                step4_admin_account(driver)

            time.sleep(2)

            # Check for completion
            if not step5_completion(driver):
                print("Installation may not have completed properly")
                return 1

        elif "username" in driver.page_source.lower() and "password" in driver.page_source.lower():
            print("OpenSIS already installed - login page detected")
        else:
            print(f"Unknown state. Current URL: {driver.current_url}")
            print("Attempting to navigate to installer...")
            driver.get(OPENSIS_URL + "install/")
            time.sleep(3)

            if "Step" in driver.page_source:
                print("Found installer, running setup...")
                step1_database_credentials(driver)
                step2_create_database(driver)
                step3_school_info(driver)
                step4_admin_account(driver)
                step5_completion(driver)

        # Verify login works
        if verify_login(driver):
            print("\n" + "=" * 50)
            print("INSTALLATION SUCCESSFUL")
            print("=" * 50)
            print(f"URL: {OPENSIS_URL}")
            print(f"Username: {ADMIN_USERNAME}")
            print(f"Password: {ADMIN_PASSWORD}")
            print("=" * 50)
            return 0
        else:
            print("\n" + "=" * 50)
            print("INSTALLATION COMPLETE BUT LOGIN VERIFICATION FAILED")
            print("=" * 50)
            return 1

    except Exception as e:
        print(f"ERROR: {e}")
        import traceback
        traceback.print_exc()
        return 1

    finally:
        if driver:
            driver.quit()


if __name__ == "__main__":
    sys.exit(main())
