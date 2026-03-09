# Task: implement_room_database

## Overview
Add Room database persistence to the SunflowerApp project. The app currently stores plant data in an in-memory list within PlantRepository. This task requires implementing a proper Room database layer so plant data persists across app restarts.

## Domain Context
Adding database persistence is one of the most common Android development tasks. The Room persistence library is Google's recommended approach for local data storage in Android apps.

## Goal
Transform the SunflowerApp from using an in-memory data store to using Room database persistence. The agent must:
- Add the Room library dependencies
- Annotate the Plant data class as a Room Entity
- Create a Data Access Object (DAO) interface with queries
- Create a RoomDatabase subclass
- Update the repository to use the DAO

## Success Criteria
- Room dependencies are present in build.gradle.kts
- Plant.kt has @Entity annotation and @PrimaryKey on plantId
- A PlantDao.kt interface exists with @Dao annotation and at least @Query, @Insert methods
- A PlantDatabase.kt abstract class exists extending RoomDatabase with @Database annotation
- PlantRepository.kt references the DAO (not just a MutableList)
- Project compiles successfully (Gradle build passes)

## Verification Strategy
1. Check build.gradle.kts for Room dependencies (room-runtime, room-ktx, room-compiler with kapt/ksp)
2. Check Plant.kt for @Entity annotation and @PrimaryKey
3. Check for PlantDao.kt existence with @Dao, @Query, @Insert annotations
4. Check for PlantDatabase.kt with @Database annotation and RoomDatabase parent
5. Check PlantRepository.kt references DAO
6. Run Gradle build to verify compilation

## Ground Truth
- Room version should be 2.6.x (latest stable for AGP 8.x)
- Plant entity needs @Entity and @PrimaryKey(column) on plantId
- DAO needs at minimum: getAll query, getById query, insert, delete
- Database needs @Database(entities = [Plant::class], version = 1)
