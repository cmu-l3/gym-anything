package com.google.samples.apps.sunflower.data

/**
 * Repository module for handling data operations related to [Plant].
 *
 * In a production app this would typically fetch data from a database or network.
 * For this sample, we use a hardcoded list of plants.
 */
class PlantRepository private constructor() {

    private val plants = mutableListOf<Plant>()

    init {
        // Seed with sample plant data
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
    }

    /**
     * Removes a plant from the repository by its ID.
     * Returns true if the plant was found and removed.
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
                    description = "An apple is an edible fruit produced by an apple tree (Malus domestica). Apple trees are cultivated worldwide and are the most widely grown species in the genus Malus.",
                    growZoneNumber = 3,
                    wateringInterval = 30,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/1/15/Red_Apple.jpg"
                ),
                Plant(
                    plantId = "beta-vulgaris",
                    name = "Beet",
                    description = "The beetroot is the taproot portion of a beet plant, usually known in North America as beets while the vegetable is referred to as beetroot in British English.",
                    growZoneNumber = 2,
                    wateringInterval = 7,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/2/29/Beetroot_jm26881.jpg"
                ),
                Plant(
                    plantId = "coriandrum-sativum",
                    name = "Cilantro",
                    description = "Coriander, also known as cilantro or Chinese parsley, is an annual herb in the family Apiaceae. All parts of the plant are edible, but the fresh leaves and the dried seeds are the parts most traditionally used in cooking.",
                    growZoneNumber = 2,
                    wateringInterval = 2,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/5/51/A_scene_of_Coriander_leaves.JPG"
                ),
                Plant(
                    plantId = "solanum-lycopersicum",
                    name = "Tomato",
                    description = "The tomato is the edible berry of the plant Solanum lycopersicum, commonly known as the tomato plant. The species originated in western South America and Central America.",
                    growZoneNumber = 9,
                    wateringInterval = 4,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/8/89/Tomato_je.jpg"
                ),
                Plant(
                    plantId = "helianthus-annuus",
                    name = "Sunflower",
                    description = "Helianthus annuus, the common sunflower, is a large annual forb of the daisy family Asteraceae. The sunflower is native to North America and was domesticated around 1000 BC.",
                    growZoneNumber = 8,
                    wateringInterval = 3,
                    imageUrl = "https://upload.wikimedia.org/wikipedia/commons/4/40/Sunflower_from_Silesia2.jpg"
                )
            )
        }
    }
}
