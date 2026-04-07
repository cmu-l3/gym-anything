package com.example.studyplanner.data.local

import androidx.room.migration.Migration
import androidx.sqlite.db.SupportSQLiteDatabase

object Migrations {
    val MIGRATION_1_2 = object : Migration(1, 2) {
        override fun migrate(db: SupportSQLiteDatabase) {
            db.execSQL("ALTER TABLE study_sessions ADD COLUMN last_synced_at INTEGER NOT NULL DEFAULT 0")
            // TODO: Also need to add sync_status column
        }
    }
}
