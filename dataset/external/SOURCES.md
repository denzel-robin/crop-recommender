# External datasets

| File | What it is | Source | Licence |
|---|---|---|---|
| `harvestify/crop_recommendation_original.csv` | The original 2,200-row Kaggle Crop Recommendation dataset, unmodified | [Harvestify repo](https://github.com/Gladiator07/Harvestify) by Atharva Ingle, the Kaggle dataset's author (`Data-processed/`) | GPL-3.0 (repository licence) |
| `harvestify/cpdata.csv` | 3,100 rows of temperature, humidity, pH and rainfall for 31 crops; the source of the Kaggle climate columns | Harvestify, `Data-raw/` | GPL-3.0 |
| `harvestify/FertilizerData.csv` | One recommended N, P, K and pH value per crop (22 crops); the source of the Kaggle N, P, K columns | Harvestify, `Data-raw/` | GPL-3.0 |
| `soil_health_card/` | Real Soil Health Card records from 8 villages in 5 sub-districts of Pune, Maharashtra (2014–2019): pH, organic carbon and N as numbers, other nutrients as categories, and the advised crop. `soil_health_card.csv` is a tidy export written by `modelling/soil_health_card.R` | [Soil Nutrient Dataset for Crop Advice](https://data.mendeley.com/datasets/6n3jjhncbp), Mendeley Data, DOI 10.17632/6n3jjhncbp.1 | CC BY 4.0 |
| `india_crop_production.csv.gz` | 246,091 real district-level records of area and production: 33 states, 646 districts, 124 crops, crop years 1997–2015 | Harvestify, `Data-raw/raw_districtwise_yield_data.csv` (Government of India district crop statistics, published on data.gov.in) | Government Open Data Licence – India |
