package com.example.studyplanner.data.local

import android.content.Context
import androidx.room.Database
import androidx.room.Room
import androidx.room.RoomDatabase
import androidx.room.TypeConverters
import com.example.studyplanner.model.FlashCard
import com.example.studyplanner.model.StudySession
import com.example.studyplanner.model.Subject

@Database(
    entities = [Subject::class, StudySession::class, FlashCard::class],
    version = 2,
    exportSchema = false
)
@TypeConverters(Converters::class)
abstract class AppDatabase : RoomDatabase() {

    abstract fun subjectDao(): SubjectDao
    abstract fun studySessionDao(): StudySessionDao
    abstract fun flashCardDao(): FlashCardDao

    companion object {
        @Volatile
        private var INSTANCE: AppDatabase? = null

        fun getDatabase(context: Context): AppDatabase {
            return INSTANCE ?: synchronized(this) {
                val instance = Room.databaseBuilder(
                    context.applicationContext,
                    AppDatabase::class.java,
                    "study_planner_database"
                )
                    .addMigrations(Migrations.MIGRATION_1_2)
                    .build()
                INSTANCE = instance
                instance
            }
        }
    }
}
