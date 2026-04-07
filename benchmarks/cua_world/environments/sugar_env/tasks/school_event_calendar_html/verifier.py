#!/usr/bin/env python3
import json
import os
import tempfile
import re
from html.parser import HTMLParser
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class CalendarParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.in_td = False
        self.in_style = False
        self.td_contents = []
        self.current_td = []
        self.styles = []
        self.text_content = []
        self.has_table = False
        
    def handle_starttag(self, tag, attrs):
        if tag == 'table':
            self.has_table = True
        elif tag == 'td':
            self.in_td = True
            self.current_td = []
        elif tag == 'style':
            self.in_style = True
            
        # Check inline styles as fallback for borders
        for attr, value in attrs:
            if attr == 'style' and value and 'border' in value.lower():
                self.styles.append(value)
            
    def handle_endtag(self, tag):
        if tag == 'td':
            self.in_td = False
            self.td_contents.append(" ".join(self.current_td))
        elif tag == 'style':
            self.in_style = False
            
    def handle_data(self, data):
        self.text_content.append(data)
        if self.in_td:
            self.current_td.append(data)
        if self.in_style:
            self.styles.append(data)

def verify_school_event_calendar_html(traj, env_info, task_info):
    copy_from_env = env_info.get('copy_from_env')
    if not copy_from_env:
        return {"passed": False, "score": 0, "feedback": "Copy function not available"}

    # 1. Read task result
    temp_result = tempfile.NamedTemporaryFile(delete=False, suffix='.json')
    result = {}
    try:
        copy_from_env("/tmp/calendar_task_result.json", temp_result.name)
        with open(temp_result.name, 'r') as f:
            result = json.load(f)
    except Exception as e:
        return {"passed": False, "score": 0, "feedback": f"Failed to read result JSON: {e}"}
    finally:
        if os.path.exists(temp_result.name):
            os.unlink(temp_result.name)

    score = 0
    feedback = []

    # 2. Check Python script for anti-gaming measures
    py_exists = result.get('py_exists', False)
    py_size = result.get('py_size', 0)
    
    temp_py = tempfile.NamedTemporaryFile(delete=False, suffix='.py')
    py_content = ""
    if py_exists:
        try:
            copy_from_env("/tmp/generate_calendar.py", temp_py.name)
            with open(temp_py.name, 'r', encoding='utf-8', errors='ignore') as f:
                py_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read python script: {e}")
        finally:
            if os.path.exists(temp_py.name):
                os.unlink(temp_py.name)

    events_in_py = 0
    if py_exists and py_size > 100:
        events_to_check = ["math olympiad", "science fair", "museum field trip", "thanksgiving break"]
        lower_py = py_content.lower()
        events_in_py = sum(1 for e in events_to_check if e in lower_py)
        if events_in_py >= 3:
            score += 15
            feedback.append("Python script exists, size > 100 bytes, contains event strings")
        else:
            score += 5
            feedback.append("Python script exists but missing event strings (anti-gaming check failed)")
    else:
        feedback.append("Python script not found or too small")

    # 3. Check HTML file existence and mod-time
    html_exists = result.get('html_exists', False)
    html_modified = result.get('html_modified', False)

    temp_html = tempfile.NamedTemporaryFile(delete=False, suffix='.html')
    html_content = ""
    if html_exists:
        try:
            copy_from_env("/tmp/school_calendar.html", temp_html.name)
            with open(temp_html.name, 'r', encoding='utf-8', errors='ignore') as f:
                html_content = f.read()
        except Exception as e:
            logger.error(f"Failed to read html file: {e}")
        finally:
            if os.path.exists(temp_html.name):
                os.unlink(temp_html.name)
                
    if html_exists and html_modified:
        score += 15
        feedback.append("HTML file generated during task")
    elif html_exists:
        score += 5
        feedback.append("HTML file exists but mtime check failed (was it modified?)")
    else:
        feedback.append("HTML file not found")
        # Early exit if there's no HTML to evaluate
        return {
            "passed": False,
            "score": score,
            "feedback": " | ".join(feedback),
            "subscores": {"py_script": bool(events_in_py >= 3), "html_exists": False}
        }

    # 4. Parse HTML and assess structure
    parser = CalendarParser()
    try:
        parser.feed(html_content)
    except Exception as e:
        logger.error(f"HTML parsing failed: {e}")
        
    full_text = " ".join(parser.text_content).lower()
    has_month_year = "november" in full_text and "2026" in full_text
    if has_month_year:
        score += 10
        feedback.append("Month/Year correctly set to November 2026")
    else:
        feedback.append("Missing 'November' or '2026' in HTML text")

    has_border = False
    for style in parser.styles:
        if 'border' in style.lower():
            has_border = True
            
    if parser.has_table and has_border:
        score += 10
        feedback.append("Basic HTML structure valid (contains <table> and CSS border property)")
    elif parser.has_table:
        score += 5
        feedback.append("Contains <table> but missing <style> with border")
    else:
        feedback.append("Missing <table> element completely")

    # 5. Check accurate date/event mapping per cell
    events = {
        "5": "math olympiad",
        "12": "science fair",
        "18": "museum field trip",
        "26": "thanksgiving break"
    }
    
    found_events = {k: False for k in events}
    
    for td_text in parser.td_contents:
        cell_text = td_text.lower()
        numbers = re.findall(r'\b\d{1,2}\b', cell_text)
        if numbers:
            day = numbers[0]
            if day in events:
                if events[day] in cell_text:
                    found_events[day] = True

    correct_events = sum(1 for v in found_events.values() if v)
    score += correct_events * 12.5
    
    for day, ev in events.items():
        if found_events[day]:
            feedback.append(f"Event '{ev}' correctly mapped to cell for day {day}")
        else:
            feedback.append(f"Missing event '{ev}' in cell for day {day}")

    passed = (score >= 70 and html_exists and correct_events >= 3)
    
    return {
        "passed": bool(passed),
        "score": min(100, int(score)),
        "feedback": " | ".join(feedback),
        "subscores": {
            "py_exists": py_exists,
            "html_exists": html_exists,
            "month_year_correct": has_month_year,
            "structure_correct": parser.has_table and has_border,
            "events_mapped": correct_events
        }
    }