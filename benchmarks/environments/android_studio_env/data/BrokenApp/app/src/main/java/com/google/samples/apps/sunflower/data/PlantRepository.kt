package com.google.samples.apps.sunflower.data

import retrofit2.Retrofit
import retrofit2.converter.gson.GsonConverterFactory

/**
 * Repository module for handling data operations related to [Plant].
 */
class PlantRepository private constructor() {

    private val plants = mutableListOf<Plant>()
    private val retrofit: Retrofit = Retrofit.Builder()
        .baseUrl("https://api.example.com/")
        .addConverterFactory(GsonConverterFactory.create())
        .build()

    init {
        plants.addAll(getSamplePlants())
    }

    /**
     * Returns all plants in the repository.
     */
    fun getPlants(): List<Plant> = plants.toList()

    /**
     * Returns a specific plant by its ID, or null if not found.
     */
    fun getPlant(plantId: String): Plant? {
        return plants.find { it.plantId == plantId }
    }

    /**
     * Returns plants filtered by grow zone number.
     */
    fun getPlantsByGrowZone(growZoneNumber: Int): List<Plant> {
        return plants.filter { it.growZoneNumber == growZoneNumber }
    }

    /**
     * Adds a new plant to the repository.
     */
    fun addPlant(plant: Plant) {
        if (plants.none { it.plantId == plant.plantId }) {
            plants.add(plant)
        }

    /**
     * Removes a plant from the repository by its ID.
     */
    fun removePlant(plantId: String): Boolean {
        return plants.removeAll { it.plantId == plantId }
    }

    companion object {
        @Volatile
        private var instance: PlantRepository? = null

        fun getInstance(): PlantRepository {
            return instance ?: synchronized(this) {
                instance ?: PlantRepository().also { instance = it }
            }
        }

        private fun getSamplePlants(): List<Plant> {
            return listOf(
                Plant(
                    plantId = "malus-pumila",
                    name = "Apple",
                    description = "An apple is an edible fruit produced by an apple tree.",
                    growZoneNumber = 3,
                    wateringInterval = 30,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/1/15/Red_Apple.jpg"
                ),
                Plant(
                    plantId = "helianthus-annuus",
                    name = "Sunflower",
                    description = "The common sunflower is a large annual forb of the daisy family.",
                    growZoneNumber = 8,
                    wateringInterval = 3,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/4/40/Sunflower_from_Silesia2.jpg"
                )
            )
        }
    }
}
