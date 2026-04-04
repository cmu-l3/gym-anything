#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Jump to Line Number Task ==="

WORKSPACE_DIR="/home/ga/workspace/line_nav_task"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Generate a realistic 500+ line Python file
cat > "$WORKSPACE_DIR/main.py" << 'EOF'
"""
Data processing module for analyzing user behavior
This is a realistic Python file with 500+ lines for navigation practice
"""

import json
import sqlite3
import logging
from datetime import datetime, timedelta
from typing import List, Dict, Optional, Tuple
from collections import defaultdict
import hashlib
import re


logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class UserDatabase:
    """Manages user data storage and retrieval"""
    
    def __init__(self, db_path: str):
        self.db_path = db_path
        self.connection = None
        
    def connect(self):
        """Establish database connection"""
        try:
            self.connection = sqlite3.connect(self.db_path)
            self.connection.row_factory = sqlite3.Row
            logger.info(f"Connected to database: {self.db_path}")
        except Exception as e:
            logger.error(f"Failed to connect to database: {e}")
            raise
            
    def disconnect(self):
        """Close database connection"""
        if self.connection:
            self.connection.close()
            logger.info("Database connection closed")
    
    def create_tables(self):
        """Initialize database schema"""
        cursor = self.connection.cursor()
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS users (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                username TEXT UNIQUE NOT NULL,
                email TEXT UNIQUE NOT NULL,
                password_hash TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                last_login TIMESTAMP,
                is_active BOOLEAN DEFAULT 1
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS sessions (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                session_token TEXT UNIQUE NOT NULL,
                ip_address TEXT,
                user_agent TEXT,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                expires_at TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)
        
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS activity_log (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                user_id INTEGER NOT NULL,
                action TEXT NOT NULL,
                details TEXT,
                timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (user_id) REFERENCES users(id)
            )
        """)
        
        self.connection.commit()
        logger.info("Database tables created successfully")


class UserAnalytics:
    """Analyzes user behavior patterns"""
    
    def __init__(self, database: UserDatabase):
        self.db = database
        self.cache = {}
        
    def get_active_users(self, days: int = 30) -> List[Dict]:
        """Get users active within specified days"""
        cursor = self.db.connection.cursor()
        cutoff_date = datetime.now() - timedelta(days=days)
        
        cursor.execute("""
            SELECT u.id, u.username, u.email, u.last_login
            FROM users u
            WHERE u.last_login >= ?
            AND u.is_active = 1
            ORDER BY u.last_login DESC
        """, (cutoff_date,))
        
        users = []
        for row in cursor.fetchall():
            users.append({
                'id': row['id'],
                'username': row['username'],
                'email': row['email'],
                'last_login': row['last_login']
            })
        
        return users
    
    def calculate_retention_rate(self, cohort_date: datetime) -> float:
        """Calculate user retention rate for a cohort"""
        cursor = self.db.connection.cursor()
        
        # Get users who signed up on cohort_date
        cursor.execute("""
            SELECT COUNT(*) as total
            FROM users
            WHERE DATE(created_at) = DATE(?)
        """, (cohort_date,))
        
        total_users = cursor.fetchone()['total']
        
        if total_users == 0:
            return 0.0
        
        # Get users from cohort who were active in last 7 days
        week_ago = datetime.now() - timedelta(days=7)
        cursor.execute("""
            SELECT COUNT(*) as retained
            FROM users
            WHERE DATE(created_at) = DATE(?)
            AND last_login >= ?
        """, (cohort_date, week_ago))
        
        retained_users = cursor.fetchone()['retained']
        
        return (retained_users / total_users) * 100
    
    def get_user_activity_summary(self, user_id: int) -> Dict:
        """Generate activity summary for a user"""
        cursor = self.db.connection.cursor()
        
        # Get total actions
        cursor.execute("""
            SELECT COUNT(*) as total_actions
            FROM activity_log
            WHERE user_id = ?
        """, (user_id,))
        
        total_actions = cursor.fetchone()['total_actions']
        
        # Get actions by type
        cursor.execute("""
            SELECT action, COUNT(*) as count
            FROM activity_log
            WHERE user_id = ?
            GROUP BY action
            ORDER BY count DESC
        """, (user_id,))
        
        actions_breakdown = {}
        for row in cursor.fetchall():
            actions_breakdown[row['action']] = row['count']
        
        # Get recent activity
        cursor.execute("""
            SELECT action, timestamp, details
            FROM activity_log
            WHERE user_id = ?
            ORDER BY timestamp DESC
            LIMIT 10
        """, (user_id,))
        
        recent_activity = []
        for row in cursor.fetchall():
            recent_activity.append({
                'action': row['action'],
                'timestamp': row['timestamp'],
                'details': row['details']
            })
        
        return {
            'user_id': user_id,
            'total_actions': total_actions,
            'actions_breakdown': actions_breakdown,
            'recent_activity': recent_activity
        }
    
    def detect_suspicious_activity(self, user_id: int) -> List[Dict]:
        """Detect potentially suspicious user behavior"""
        suspicious_patterns = []
        cursor = self.db.connection.cursor()
        
        # Check for rapid successive logins from different IPs
        cursor.execute("""
            SELECT ip_address, COUNT(*) as login_count,
                   MIN(created_at) as first_login,
                   MAX(created_at) as last_login
            FROM sessions
            WHERE user_id = ?
            AND created_at >= datetime('now', '-1 hour')
            GROUP BY ip_address
            HAVING login_count > 5
        """, (user_id,))
        
        for row in cursor.fetchall():
            suspicious_patterns.append({
                'type': 'rapid_logins',
                'ip_address': row['ip_address'],
                'count': row['login_count'],
                'timespan': f"{row['first_login']} to {row['last_login']}"
            })
        
        # Check for unusual activity volume
        cursor.execute("""
            SELECT COUNT(*) as action_count
            FROM activity_log
            WHERE user_id = ?
            AND timestamp >= datetime('now', '-1 hour')
        """, (user_id,))
        
        action_count = cursor.fetchone()['action_count']
        if action_count > 1000:  # More than 1000 actions in an hour
            suspicious_patterns.append({
                'type': 'high_activity_volume',
                'count': action_count,
                'period': 'last_hour'
            })
        
        return suspicious_patterns


class DataExporter:
    """Exports user data in various formats"""
    
    def __init__(self, database: UserDatabase):
        self.db = database
    
    def export_to_json(self, user_id: int, filepath: str):
        """Export user data to JSON file"""
        cursor = self.db.connection.cursor()
        
        # Get user info
        cursor.execute("SELECT * FROM users WHERE id = ?", (user_id,))
        user_row = cursor.fetchone()
        
        if not user_row:
            raise ValueError(f"User {user_id} not found")
        
        user_data = dict(user_row)
        
        # Get sessions
        cursor.execute("SELECT * FROM sessions WHERE user_id = ?", (user_id,))
        sessions = [dict(row) for row in cursor.fetchall()]
        
        # Get activity log
        cursor.execute("SELECT * FROM activity_log WHERE user_id = ?", (user_id,))
        activity = [dict(row) for row in cursor.fetchall()]
        
        export_data = {
            'user': user_data,
            'sessions': sessions,
            'activity_log': activity,
            'exported_at': datetime.now().isoformat()
        }
        
        with open(filepath, 'w') as f:
            json.dump(export_data, f, indent=2)
        
        logger.info(f"User data exported to {filepath}")
    
    def export_activity_report(self, start_date: datetime, end_date: datetime, filepath: str):
        """Generate activity report for date range"""
        cursor = self.db.connection.cursor()
        
        cursor.execute("""
            SELECT u.username, a.action, COUNT(*) as count
            FROM activity_log a
            JOIN users u ON a.user_id = u.id
            WHERE a.timestamp BETWEEN ? AND ?
            GROUP BY u.username, a.action
            ORDER BY u.username, count DESC
        """, (start_date, end_date))
        
        report_lines = []
        report_lines.append(f"Activity Report: {start_date} to {end_date}")
        report_lines.append("=" * 60)
        
        current_user = None
        for row in cursor.fetchall():
            if current_user != row['username']:
                current_user = row['username']
                report_lines.append(f"\nUser: {current_user}")
            report_lines.append(f"  {row['action']}: {row['count']} times")
        
        with open(filepath, 'w') as f:
            f.write('\n'.join(report_lines))
        
        logger.info(f"Activity report exported to {filepath}")


class SecurityManager:
    """Handles security-related operations"""
    
    @staticmethod
    def hash_password(password: str) -> str:
        """Hash password using SHA-256"""
        return hashlib.sha256(password.encode()).hexdigest()
    
    @staticmethod
    def validate_password_strength(password: str) -> Tuple[bool, List[str]]:
        """Validate password meets security requirements"""
        issues = []
        
        if len(password) < 8:
            issues.append("Password must be at least 8 characters long")
        
        if not re.search(r'[A-Z]', password):
            issues.append("Password must contain at least one uppercase letter")
        
        if not re.search(r'[a-z]', password):
            issues.append("Password must contain at least one lowercase letter")
        
        if not re.search(r'\d', password):
            issues.append("Password must contain at least one digit")
        
        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
            issues.append("Password must contain at least one special character")
        
        return len(issues) == 0, issues
    
    @staticmethod
    def validate_email(email: str) -> bool:
        """Validate email format"""
        pattern = r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'
        return re.match(pattern, email) is not None
    
    def generate_session_token(self) -> str:
        """Generate secure session token"""
        random_data = f"{datetime.now().isoformat()}{os.urandom(32).hex()}"
        return hashlib.sha256(random_data.encode()).hexdigest()


def process_user_cache():
    user_cache = {}
    for i in range(100):
        user_cache[f"user_{i}"] = {"cached_at": datetime.now(), "data": {}}
    return user_cache


def main():
    """Main entry point for the application"""
    logger.info("Starting user data processing application")
    
    db = UserDatabase("/tmp/users.db")
    db.connect()
    db.create_tables()
    
    analytics = UserAnalytics(db)
    active_users = analytics.get_active_users(days=30)
    logger.info(f"Found {len(active_users)} active users")
    
    for user in active_users[:5]:
        summary = analytics.get_user_activity_summary(user['id'])
        logger.info(f"User {user['username']}: {summary['total_actions']} total actions")
    
    db.disconnect()
    logger.info("Application finished successfully")


if __name__ == "__main__":
    main()
EOF

sudo chown -R ga:ga "$WORKSPACE_DIR"

# Open VSCode with the file
echo "Opening VSCode with main.py..."
su - ga -c "DISPLAY=:1 code '$WORKSPACE_DIR' '$WORKSPACE_DIR/main.py'" &
wait_for_vscode 20
wait_for_window "Visual Studio Code" 30

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 2

# Focus VSCode window
focus_vscode_window

# Move cursor to line 1 (top of file)
sleep 1
su - ga -c "DISPLAY=:1 xdotool key ctrl+Home" || true
sleep 1

echo "=== Jump to Line Number Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Press Ctrl+G to open 'Go to Line' dialog"
echo "  2. Type: 342"
echo "  3. Press Enter to jump to line 342"
echo "  4. Add comment '# CHECKPOINT' at the end of that line"
echo "  5. Save the file with Ctrl+S"
echo ""
echo "File: $WORKSPACE_DIR/main.py (342 lines)"
echo "Target: Line 342"