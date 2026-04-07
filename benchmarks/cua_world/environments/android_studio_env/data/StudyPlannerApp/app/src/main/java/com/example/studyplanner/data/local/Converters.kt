package com.example.studyplanner.data.local

import androidx.room.TypeConverter
import java.util.Date

class Converters {
    @TypeConverter
    fun dateToTimestamp(date: Date?): Long? {
        return date?.time
    }

    // TODO: Add reverse converter timestampToDate
    // The developer forgot to implement the reverse conversion
}
