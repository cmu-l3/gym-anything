package com.example.studyplanner.data.local

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import androidx.room.Update
import com.example.studyplanner.model.FlashCard
import kotlinx.coroutines.flow.Flow

@Dao
interface FlashCardDao {
    @Query("SELECT * FROM flash_cards WHERE subjectId = :subjectId ORDER BY difficulty ASC")
    fun getBySubject(subjectId: String): Flow<List<FlashCard>>

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun insertAll(cards: List<FlashCard>)

    @Update
    suspend fun update(card: FlashCard)
}
