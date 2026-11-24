# External datasets

| File | What it is | Source | Licence |
|---|---|---|---|
| `harvestify/crop_recommendation_original.csv` | The original 2,200-row Kaggle Crop Recommendation dataset, unmodified | [Harvestify repo](https://github.com/Gladiator07/Harvestify) by Atharva Ingle, the Kaggle dataset's author (`Data-processed/`) | GPL-3.0 (repository licence) |
| `harvestify/cpdata.csv` | 3,100 rows of temperature, humidity, pH and rainfall for 31 crops; the source of the Kaggle climate columns | Harvestify, `Data-raw/` | GPL-3.0 |
| `harvestify/FertilizerData.csv` | One recommended N, P, K and pH value per crop (22 crops); the source of the Kaggle N, P, K columns | Harvestify, `Data-raw/` | GPL-3.0 |
| `india_crop_production.csv.gz` | 246,091 real district-level records of area and production: 33 states, 646 districts, 124 crops, crop years 1997–2015 | Harvestify, `Data-raw/raw_districtwise_yield_data.csv` (Government of India district crop statistics, published on data.gov.in) | Government Open Data Licence – India |

## Not yet included

- **[Soil Nutrient Dataset for Crop Advice](https://data.mendeley.com/datasets/6n3jjhncbp)** (Mendeley Data, CC BY 4.0): 1,653 real Soil Health Card
  records from 5 sub-districts of Pune, Maharashtra (2016–2018), 11 soil features and 15 crops. Nutrient values are categories
  (e.g. low/medium/high), not numbers. Download `Crop Adv data.zip` and `data_dictionary.csv` from the page and unzip them into
  `dataset/external/soil_health_card/`.
