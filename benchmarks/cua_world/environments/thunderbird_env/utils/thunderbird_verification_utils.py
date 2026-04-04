"""
Thunderbird Verification Utilities

Provides helper functions for verifying Thunderbird email operations,
calendar events, contacts, and other email-related tasks in gym-anything environments.
"""

import os
import re
import json
import shutil
import sqlite3
import mailbox
import email
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from email.utils import parsedate_to_datetime

# Temporary directory for copied files during verification
TEMP_VERIFY_DIR = Path("/tmp/thunderbird_verify")


def get_thunderbird_profile_dir(username: str = "ga") -> Optional[Path]:
    """
    Get the Thunderbird profile directory for a user.

    Args:
        username: Username (default: ga)

    Returns:
        Path to profile directory or None if not found
    """
    home = Path(f"/home/{username}")
    tb_dir = home / ".thunderbird"

    if not tb_dir.exists():
        return None

    # Find the default profile directory
    for item in tb_dir.iterdir():
        if item.is_dir() and not item.name.startswith('.'):
            return item

    return None


def copy_thunderbird_files(copy_from_env: callable, files: List[str], username: str = "ga") -> Tuple[bool, Dict[str, Path], str]:
    """
    Copy Thunderbird files from the container to host for verification.

    Args:
        copy_from_env: Function to copy files from container
        files: List of files to copy (relative to profile dir)
        username: Username (default: ga)

    Returns:
        Tuple of (success, {filename: local_path}, error_message)
    """
    profile_dir = get_thunderbird_profile_dir(username)
    if not profile_dir:
        return False, {}, f"Thunderbird profile not found for user {username}"

    # Create temp directory
    TEMP_VERIFY_DIR.mkdir(parents=True, exist_ok=True)

    copied_files = {}
    for file_rel in files:
        src_path = profile_dir / file_rel
        dst_path = TEMP_VERIFY_DIR / Path(file_rel).name

        try:
            copy_from_env(str(src_path), str(dst_path))
            if dst_path.exists():
                copied_files[Path(file_rel).name] = dst_path
            else:
                return False, {}, f"Failed to copy {file_rel}"
        except Exception as e:
            return False, {}, f"Error copying {file_rel}: {str(e)}"

    return True, copied_files, ""


def setup_thunderbird_verification(copy_from_env: callable, files: List[str], username: str = "ga") -> Tuple[bool, Dict[str, Path], str]:
    """
    Set up verification by copying necessary Thunderbird files.

    Args:
        copy_from_env: Function to copy files from container
        files: List of files to copy
        username: Username

    Returns:
        Tuple of (success, file_paths_dict, error_message)
    """
    cleanup_verification_temp()
    return copy_thunderbird_files(copy_from_env, files, username)


def cleanup_verification_temp():
    """Clean up temporary verification directory."""
    if TEMP_VERIFY_DIR.exists():
        shutil.rmtree(TEMP_VERIFY_DIR)


def parse_mbox_file(mbox_path: Path) -> List[email.message.Message]:
    """
    Parse an mbox file and return list of email messages.

    Args:
        mbox_path: Path to mbox file

    Returns:
        List of email.message.Message objects
    """
    if not mbox_path.exists():
        return []

    messages = []
    try:
        mbox = mailbox.mbox(str(mbox_path))
        for message in mbox:
            messages.append(message)
        mbox.close()
    except Exception as e:
        print(f"Error parsing mbox file: {e}")
        return []

    return messages


def count_emails_in_mbox(mbox_path: Path) -> int:
    """
    Count number of emails in an mbox file.

    Args:
        mbox_path: Path to mbox file

    Returns:
        Number of emails
    """
    return len(parse_mbox_file(mbox_path))


def get_email_subjects(mbox_path: Path) -> List[str]:
    """
    Get list of email subjects from an mbox file.

    Args:
        mbox_path: Path to mbox file

    Returns:
        List of subject strings
    """
    messages = parse_mbox_file(mbox_path)
    return [msg.get('Subject', '') for msg in messages]


def get_email_by_subject(mbox_path: Path, subject_pattern: str) -> Optional[email.message.Message]:
    """
    Find an email by subject pattern (regex).

    Args:
        mbox_path: Path to mbox file
        subject_pattern: Regex pattern to match subject

    Returns:
        First matching email message or None
    """
    messages = parse_mbox_file(mbox_path)
    pattern = re.compile(subject_pattern, re.IGNORECASE)

    for msg in messages:
        subject = msg.get('Subject', '')
        if pattern.search(subject):
            return msg

    return None


def verify_email_sent(sent_mbox_path: Path, to_address: str, subject_pattern: Optional[str] = None) -> bool:
    """
    Verify that an email was sent to a specific address.

    Args:
        sent_mbox_path: Path to Sent mbox file
        to_address: Recipient email address
        subject_pattern: Optional subject pattern to match

    Returns:
        True if email found, False otherwise
    """
    messages = parse_mbox_file(sent_mbox_path)

    for msg in messages:
        to = msg.get('To', '')
        if to_address.lower() in to.lower():
            if subject_pattern:
                subject = msg.get('Subject', '')
                if re.search(subject_pattern, subject, re.IGNORECASE):
                    return True
            else:
                return True

    return False


def verify_email_received(inbox_mbox_path: Path, from_address: str, subject_pattern: Optional[str] = None) -> bool:
    """
    Verify that an email was received from a specific address.

    Args:
        inbox_mbox_path: Path to Inbox mbox file
        from_address: Sender email address
        subject_pattern: Optional subject pattern to match

    Returns:
        True if email found, False otherwise
    """
    messages = parse_mbox_file(inbox_mbox_path)

    for msg in messages:
        from_addr = msg.get('From', '')
        if from_address.lower() in from_addr.lower():
            if subject_pattern:
                subject = msg.get('Subject', '')
                if re.search(subject_pattern, subject, re.IGNORECASE):
                    return True
            else:
                return True

    return False


def read_address_book(abook_path: Path) -> List[Dict[str, Any]]:
    """
    Read contacts from Thunderbird's address book database.

    Args:
        abook_path: Path to abook.sqlite file

    Returns:
        List of contact dictionaries
    """
    if not abook_path.exists():
        return []

    contacts = []
    try:
        conn = sqlite3.connect(str(abook_path))
        cursor = conn.cursor()

        # Query the properties table for contact info
        cursor.execute("""
            SELECT card, name, value
            FROM properties
            WHERE name IN ('PrimaryEmail', 'DisplayName', 'FirstName', 'LastName')
            ORDER BY card
        """)

        # Group by card ID
        card_data = {}
        for card_id, name, value in cursor.fetchall():
            if card_id not in card_data:
                card_data[card_id] = {}
            card_data[card_id][name] = value

        conn.close()

        # Convert to list
        for card_id, data in card_data.items():
            contacts.append({
                'id': card_id,
                'email': data.get('PrimaryEmail', ''),
                'display_name': data.get('DisplayName', ''),
                'first_name': data.get('FirstName', ''),
                'last_name': data.get('LastName', ''),
            })

    except Exception as e:
        print(f"Error reading address book: {e}")

    return contacts


def get_contacts_count(abook_path: Path) -> int:
    """
    Count number of contacts in address book.

    Args:
        abook_path: Path to abook.sqlite file

    Returns:
        Number of contacts
    """
    return len(read_address_book(abook_path))


def verify_contact_exists(abook_path: Path, email: Optional[str] = None, name: Optional[str] = None) -> bool:
    """
    Verify that a contact exists in the address book.

    Args:
        abook_path: Path to abook.sqlite file
        email: Email address to search for
        name: Name to search for

    Returns:
        True if contact found, False otherwise
    """
    contacts = read_address_book(abook_path)

    for contact in contacts:
        if email and email.lower() in contact.get('email', '').lower():
            return True
        if name:
            display_name = contact.get('display_name', '').lower()
            first_name = contact.get('first_name', '').lower()
            last_name = contact.get('last_name', '').lower()
            name_lower = name.lower()

            if name_lower in display_name or name_lower in first_name or name_lower in last_name:
                return True

    return False


def parse_calendar_file(calendar_dir: Path) -> List[Dict[str, Any]]:
    """
    Parse calendar events from Thunderbird's calendar data.

    Args:
        calendar_dir: Path to calendar-data directory

    Returns:
        List of event dictionaries
    """
    events = []

    if not calendar_dir.exists():
        return events

    # Look for .ics files
    for ics_file in calendar_dir.glob("*.ics"):
        try:
            from icalendar import Calendar

            with open(ics_file, 'rb') as f:
                cal = Calendar.from_ical(f.read())

                for component in cal.walk():
                    if component.name == "VEVENT":
                        events.append({
                            'summary': str(component.get('summary', '')),
                            'description': str(component.get('description', '')),
                            'start': component.get('dtstart').dt if component.get('dtstart') else None,
                            'end': component.get('dtend').dt if component.get('dtend') else None,
                            'location': str(component.get('location', '')),
                        })
        except Exception as e:
            print(f"Error parsing calendar file {ics_file}: {e}")

    return events


def get_calendar_events(calendar_dir: Path) -> List[Dict[str, Any]]:
    """
    Get all calendar events.

    Args:
        calendar_dir: Path to calendar-data directory

    Returns:
        List of event dictionaries
    """
    return parse_calendar_file(calendar_dir)


def verify_event_exists(calendar_dir: Path, summary_pattern: str) -> bool:
    """
    Verify that a calendar event exists.

    Args:
        calendar_dir: Path to calendar-data directory
        summary_pattern: Regex pattern to match event summary

    Returns:
        True if event found, False otherwise
    """
    events = get_calendar_events(calendar_dir)
    pattern = re.compile(summary_pattern, re.IGNORECASE)

    for event in events:
        if pattern.search(event.get('summary', '')):
            return True

    return False


def check_email_filter(profile_dir: Path, filter_name: str) -> bool:
    """
    Check if an email filter exists.

    Args:
        profile_dir: Path to Thunderbird profile directory
        filter_name: Name of the filter to check

    Returns:
        True if filter found, False otherwise
    """
    # Thunderbird stores filters in msgFilterRules.dat files
    filter_files = list(profile_dir.glob("**/msgFilterRules.dat"))

    for filter_file in filter_files:
        try:
            with open(filter_file, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
                if f'name="{filter_name}"' in content or f"name={filter_name}" in content:
                    return True
        except Exception as e:
            print(f"Error reading filter file: {e}")

    return False


def get_folder_list(profile_dir: Path) -> List[str]:
    """
    Get list of mail folders.

    Args:
        profile_dir: Path to Thunderbird profile directory

    Returns:
        List of folder names
    """
    folders = []
    mail_dir = profile_dir / "Mail" / "Local Folders"

    if mail_dir.exists():
        for item in mail_dir.iterdir():
            if item.is_file() and not item.name.endswith('.msf'):
                folders.append(item.name)

    return folders


def verify_folder_exists(profile_dir: Path, folder_name: str) -> bool:
    """
    Verify that a mail folder exists.

    Args:
        profile_dir: Path to Thunderbird profile directory
        folder_name: Name of the folder

    Returns:
        True if folder exists, False otherwise
    """
    folders = get_folder_list(profile_dir)
    return folder_name in folders
