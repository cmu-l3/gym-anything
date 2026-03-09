package com.google.samples.apps.sunflower

import androidx.appcompat.app.AppCompatActivity
import com.google.samples.apps.sunflower.data.Plant
import com.google.samples.apps.sunflower.data.PlantRepository

class MainActivity : AppCompatActivity() {

    private lateinit var plantRepository: PlantRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_main)

        plantRepository = PlantRepository.getInstance()

        // Load initial plant data
        val plants = plantRepository.getPlants()
        displayPlants(plants)
    }

    private fun displayPlants(plants: List<Plant>) {
        val titleView = findViewById<android.widget.TextView>(R.id.text_title)
        titleView.text = getString(R.string.plant_list_title, plants.size)
    }
}
