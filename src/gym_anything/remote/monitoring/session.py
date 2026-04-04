"""
Session management for persisting metrics to disk.

Handles saving and loading monitoring sessions, allowing historical
analysis and server restart recovery.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any, Optional

from .metrics import MetricsCollector

logger = logging.getLogger(__name__)


class SessionManager:
    """
    Manages persistence of metrics sessions to disk.
    
    Features:
    - Auto-save at configurable intervals
    - Session file management
    - Load latest or specific session
    - List available sessions
    """
    
    def __init__(self,
                 sessions_dir: str = "monitoring_sessions",
                 auto_save_interval: int = 300):  # 5 minutes default
        """
        Initialize session manager.

        Args:
            sessions_dir: Directory to store session files. Relative paths are
                resolved under ``$GYM_ANYTHING_STATE_DIR`` when set, otherwise
                under ``~/.gym_anything``.
            auto_save_interval: Auto-save interval in seconds
        """
        sessions_path = Path(sessions_dir)
        if not sessions_path.is_absolute():
            state_root = os.environ.get("GYM_ANYTHING_STATE_DIR")
            if state_root:
                sessions_path = Path(state_root).expanduser() / sessions_dir
            else:
                sessions_path = Path.home() / ".gym_anything" / sessions_dir

        self.sessions_dir = sessions_path
        self.sessions_dir.mkdir(parents=True, exist_ok=True)

        self.auto_save_interval = auto_save_interval
        self.auto_save_thread: Optional[threading.Thread] = None
        self.stop_event = threading.Event()

        self.current_session_file: Optional[Path] = None
        self.last_save_time = time.time()

        logger.info(f"SessionManager initialized with sessions_dir={self.sessions_dir}")
    
    def start_auto_save(self, metrics_collector: MetricsCollector):
        """
        Start auto-save background thread.
        
        Args:
            metrics_collector: MetricsCollector instance to save
        """
        if self.auto_save_thread is not None:
            logger.warning("Auto-save thread already running")
            return
        
        self.stop_event.clear()
        self.auto_save_thread = threading.Thread(
            target=self._auto_save_loop,
            args=(metrics_collector,),
            daemon=True
        )
        self.auto_save_thread.start()
        logger.info(f"Started auto-save thread (interval={self.auto_save_interval}s)")
    
    def stop_auto_save(self):
        """Stop auto-save background thread."""
        if self.auto_save_thread is None:
            return
        
        self.stop_event.set()
        self.auto_save_thread.join(timeout=5)
        self.auto_save_thread = None
        logger.info("Stopped auto-save thread")
    
    def _auto_save_loop(self, metrics_collector: MetricsCollector):
        """Background loop for auto-saving metrics."""
        while not self.stop_event.is_set():
            try:
                # Sleep in small increments to check stop event
                for _ in range(self.auto_save_interval):
                    if self.stop_event.is_set():
                        break
                    time.sleep(1)
                
                if not self.stop_event.is_set():
                    self.save_session(metrics_collector)
                    
            except Exception as e:
                logger.error(f"Error in auto-save loop: {e}", exc_info=True)
    
    def save_session(self, metrics_collector: MetricsCollector,
                     session_file: Optional[Path] = None) -> Path:
        """
        Save metrics to session file.

        Args:
            metrics_collector: MetricsCollector instance to save
            session_file: Optional specific file path (generates one if None)

        Returns:
            Path to saved session file
        """
        try:
            # Ensure directory exists (may have been deleted)
            self.sessions_dir.mkdir(parents=True, exist_ok=True)

            # Generate filename if not provided
            if session_file is None:
                if self.current_session_file is None:
                    # Create new session file
                    session_id = metrics_collector.session_id
                    filename = f"session_{session_id}.json"
                    session_file = self.sessions_dir / filename
                    self.current_session_file = session_file
                else:
                    # Use existing session file
                    session_file = self.current_session_file

            # Get metrics data
            data = metrics_collector.to_dict()

            # Add save metadata
            data['_saved_at'] = time.time()
            data['_saved_at_formatted'] = datetime.now().isoformat()

            # Write to temp file first, then rename (atomic)
            temp_file = session_file.with_suffix('.tmp')
            with open(temp_file, 'w') as f:
                json.dump(data, f, indent=2)

            # Atomic rename - use shutil.move as fallback for cross-filesystem
            try:
                temp_file.replace(session_file)
            except OSError:
                # Fallback: copy + delete (less atomic but works cross-filesystem)
                import shutil
                shutil.move(str(temp_file), str(session_file))

            self.last_save_time = time.time()
            logger.info(f"Saved session to {session_file}")

            return session_file

        except Exception as e:
            logger.error(f"Failed to save session: {e}", exc_info=True)
            raise
    
    def load_session(self, session_file: Path, 
                     metrics_collector: MetricsCollector) -> bool:
        """
        Load metrics from session file.
        
        Args:
            session_file: Path to session file
            metrics_collector: MetricsCollector instance to load into
        
        Returns:
            True if successful, False otherwise
        """
        try:
            if not session_file.exists():
                logger.warning(f"Session file not found: {session_file}")
                return False
            
            with open(session_file, 'r') as f:
                data = json.load(f)
            
            # Remove metadata fields before loading
            data.pop('_saved_at', None)
            data.pop('_saved_at_formatted', None)
            
            metrics_collector.from_dict(data)
            
            self.current_session_file = session_file
            logger.info(f"Loaded session from {session_file}")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to load session: {e}", exc_info=True)
            return False
    
    def load_latest_session(self, metrics_collector: MetricsCollector) -> bool:
        """
        Load the most recent session file.
        
        Args:
            metrics_collector: MetricsCollector instance to load into
        
        Returns:
            True if successful, False otherwise
        """
        try:
            sessions = self.list_sessions()
            
            if not sessions:
                logger.info("No previous sessions found")
                return False
            
            # Load the most recent one
            latest = sessions[0]
            session_file = self.sessions_dir / latest['filename']
            
            return self.load_session(session_file, metrics_collector)
            
        except Exception as e:
            logger.error(f"Failed to load latest session: {e}", exc_info=True)
            return False
    
    def list_sessions(self) -> List[Dict[str, Any]]:
        """
        List all available session files.
        
        Returns:
            List of session info dicts, sorted by modified time (newest first)
        """
        try:
            sessions = []
            
            for session_file in self.sessions_dir.glob("session_*.json"):
                try:
                    stat = session_file.stat()
                    
                    # Try to extract session_id from filename
                    # Format: session_YYYYMMDD_HHMMSS.json
                    session_id = session_file.stem.replace('session_', '')
                    
                    # Quick peek at file to get metadata
                    with open(session_file, 'r') as f:
                        data = json.load(f)
                    
                    sessions.append({
                        'filename': session_file.name,
                        'session_id': session_id,
                        'path': str(session_file),
                        'size_bytes': stat.st_size,
                        'size_kb': round(stat.st_size / 1024, 2),
                        'modified_at': stat.st_mtime,
                        'modified_at_formatted': datetime.fromtimestamp(stat.st_mtime).isoformat(),
                        'saved_at': data.get('_saved_at'),
                        'saved_at_formatted': data.get('_saved_at_formatted'),
                        'start_time': data.get('start_time'),
                        'total_envs_created': data.get('total_envs_created', 0),
                        'active_envs_count': len(data.get('active_environments', {})),
                        'is_current': session_file == self.current_session_file
                    })
                    
                except Exception as e:
                    logger.warning(f"Error reading session file {session_file}: {e}")
                    continue
            
            # Sort by modified time, newest first
            sessions.sort(key=lambda x: x['modified_at'], reverse=True)
            
            return sessions
            
        except Exception as e:
            logger.error(f"Failed to list sessions: {e}", exc_info=True)
            return []
    
    def delete_session(self, session_file: Path) -> bool:
        """
        Delete a session file.
        
        Args:
            session_file: Path to session file
        
        Returns:
            True if successful, False otherwise
        """
        try:
            if not session_file.exists():
                logger.warning(f"Session file not found: {session_file}")
                return False
            
            # Don't delete current session
            if session_file == self.current_session_file:
                logger.warning(f"Cannot delete current session: {session_file}")
                return False
            
            session_file.unlink()
            logger.info(f"Deleted session file: {session_file}")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to delete session: {e}", exc_info=True)
            return False
    
    def cleanup_old_sessions(self, keep_count: int = 10):
        """
        Delete old session files, keeping only the most recent ones.
        
        Args:
            keep_count: Number of recent sessions to keep
        """
        try:
            sessions = self.list_sessions()
            
            if len(sessions) <= keep_count:
                return
            
            # Delete old sessions
            to_delete = sessions[keep_count:]
            
            for session_info in to_delete:
                session_file = self.sessions_dir / session_info['filename']
                self.delete_session(session_file)
            
            logger.info(f"Cleaned up {len(to_delete)} old session(s)")
            
        except Exception as e:
            logger.error(f"Failed to cleanup old sessions: {e}", exc_info=True)
    
    def get_session_info(self, session_file: Path) -> Optional[Dict[str, Any]]:
        """
        Get detailed information about a session file.
        
        Args:
            session_file: Path to session file
        
        Returns:
            Session info dict or None if error
        """
        try:
            if not session_file.exists():
                return None
            
            with open(session_file, 'r') as f:
                data = json.load(f)
            
            stat = session_file.stat()
            
            return {
                'filename': session_file.name,
                'session_id': data.get('session_id'),
                'start_time': data.get('start_time'),
                'saved_at': data.get('_saved_at'),
                'size_bytes': stat.st_size,
                'total_envs_created': data.get('total_envs_created', 0),
                'active_envs_count': len(data.get('active_environments', {})),
                'closed_envs_count': len(data.get('closed_environments', [])),
                'cleanup_count': data.get('cleanup_count', 0),
                'endpoints_count': len(data.get('endpoints', {})),
                'timeline_points': len(data.get('timeline', []))
            }
            
        except Exception as e:
            logger.error(f"Failed to get session info: {e}", exc_info=True)
            return None
