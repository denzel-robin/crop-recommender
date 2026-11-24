<!-- markdownlint-disable MD013 -->
<!-- markdownlint-disable MD060 -->
# Intelligent Crop Recommendation System (ICRS)

Recommends crops from soil nutrients (N, P, K, pH) and climate (temperature, humidity, rainfall), using R.

Most projects built on the popular Kaggle crop dataset report about 99% accuracy. This project asks
whether that number means anything. It audits the benchmark, evaluates models honestly, and tests them
on real Indian Soil Health Card data.

## Status

| Stage | Status |
|---|---|
| Data audit, cleaning and outlier analysis | Done |
| Model benchmark with stratified cross-validation | Done |
| Robustness tests and explainability (SHAP) | Planned |
| Validation on real Soil Health Card data | Planned |
| Soil clustering (k-means and PCA) | Planned |
| Shiny web app | Planned |

## Data

- **Main:** the [Kaggle Crop Recommendation dataset](https://www.kaggle.com/datasets/atharvaingle/crop-recommendation-dataset). It has 2,200 rows, 22 crops (100 each), 7 numeric features and a `label` column.
- **Test copy with injected defects:** `dataset/Crop_recommendation.csv` has 2,714 rows. It adds 507 exact duplicate rows and 7 copies of real rows with `P` blanked out, so the cleaning stage has real problems to catch.
- **Planned external validation:** [Soil Nutrient Dataset for Crop Advice](https://data.mendeley.com/datasets/6n3jjhncbp). It has 1,653 Soil Health Card records from Pune, Maharashtra (2016–2018), 11 soil features and 15 crops (CC BY 4.0).

## Running

Run the scripts from the repository root:

```sh
Rscript dataset_cleaning/datasetClean.R      # -> dataset/Crop_recommendation_cleaned.csv
Rscript dataset_outlier/outlier_detect.R     # IQR outlier report
Rscript dataset_outlier/outlier_managing.R   # -> dataset/Outlier_removed.csv (analysis only, see below)
Rscript dataset_stats/DataExploration.R      # summary statistics
Rscript modelling/benchmark.R                # -> modelling/results/ (about 20 min on one core)
```

## Phase 1 results

### Cleaning

The cleaning script (`dataset_cleaning/datasetClean.R`) runs in this order:

1. Remove the 507 exact duplicates (18.68%).
2. Remove the 7 rows with a missing `P`. Each one matches a complete row on every other column, so it is a damaged copy, not a new sample.
3. Fill any value that is still missing with that crop's median. None remained in this data.

The order matters. Filling in values first would turn the damaged copies into new-looking rows that survive
de-duplication. An earlier version did this and left rice with 107 rows instead of 100.

Result: **2,200 rows, 100 per crop, no missing values.** Full log: [`dataset_cleaning/datasetCleaned.txt`](dataset_cleaning/datasetCleaned.txt).

### Outliers: detected, kept

The IQR rule (1.5 × IQR) flags many values in 6 of the 7 features:

| Feature | Flagged values | Normal range (IQR rule) |
|---|---|---|
| K | 200 | -23.5 to 92.5 |
| P | 138 | -32 to 128 |
| Rainfall | 100 | -25.0 to 213.8 mm |
| Temperature | 86 | 14.1 to 37.3 °C |
| pH | 57 | 4.54 to 8.35 |
| Humidity | 30 | 15.7 to 134.5 % |
| N | 0 | -73.9 to 179.1 |

Removing every flagged row would cut the data from 2,200 to 1,768 rows (-19.6%). Two whole crops, **apple and grapes, would disappear**, and rice would drop to 32 rows. These values are not errors: apple and grapes really need K of about 200, rice needs heavy rainfall, and chickpea grows at very low humidity.
So the outliers stay in the modelling data. `Outlier_removed.csv` is kept only to show this effect.
Logs: [`outliers.txt`](dataset_outlier/outliers.txt), [`outlier_output.txt`](dataset_outlier/outlier_output.txt).

### Benchmark audit

Each crop's features fall in narrow bands with sharp edges. For example, K for apple and grapes is always 195–205.
A 1-nearest-neighbour classifier with no tuning already scores **97.6%** (leave-one-out, standardised features).
High accuracy on this dataset is therefore expected, not impressive. That is why the next stages focus on robustness and real-data validation.
Other work supports this: [Sam & D'Abreo (2025)](https://arxiv.org/abs/2505.21201) report 99.96% with 10-fold CV, which drops to 78.55% with a time-based split.

### Model benchmark

Each model is tuned with stratified 10-fold cross-validation on 80% of the cleaned data, then scored once on the held-out 20% (440 rows).
Script: [`modelling/benchmark.R`](modelling/benchmark.R). Results: [`modelling/results/`](modelling/results/).

| Model | CV accuracy | Test accuracy | Test macro-F1 |
|---|---|---|---|
| Random Forest | 99.49% | **99.77%** | 0.998 |
| XGBoost | 99.38% | 99.77% | 0.998 |
| SVM (RBF kernel) | 98.52% | 99.09% | 0.990 |
| k-NN (k = 3) | 97.61% | 98.18% | 0.982 |
| Decision tree | 97.73% | 97.95% | 0.981 |
| 1-NN baseline (no tuning) | 97.39% | 97.05% | 0.970 |
| Multinomial logistic | 97.05% | 96.36% | 0.964 |

The best model gets 1 of 440 test rows wrong (it predicts jute as rice). It is only 2.7 points better than an untuned 1-nearest-neighbour model.
By permutation importance the most useful features are humidity, K, rainfall and P; pH matters least.

![Confusion matrix](modelling/results/confusion_matrix.png)

### Exploratory analysis (raw data, before cleaning)

![Summary](dataset_stats/Summary.png)
![Overview](dataset_stats/SizeDupliMissing.png)

| Variable    | Mean   | SD     | Min   | Max    |
|-------------|--------|--------|-------|--------|
| N           | 54.07  | 34.25  | 0     | 140    |
| P           | 51.69  | 30.23  | 5     | 145    |
| K           | 46.98  | 45.67  | 5     | 205    |
| temperature | 25.41  | 4.66   | 8.83  | 43.68  |
| humidity    | 73.33  | 20.41  | 14.26 | 99.98  |
| ph          | 6.63   | 0.80   | 3.50  | 9.94   |
| rainfall    | 131.08 | 75.93  | 20.21 | 298.56 |

![Correlation Matrix](dataset_stats/CorrMatrix.png)

| Humidity | Rainfall |
|---|---|
| ![Humidity](dataset_stats/HumiBox.png) | ![Rainfall](dataset_stats/RainfallBox.png) |
| **pH** | **Temperature** |
| ![pH](dataset_stats/phBox.png) | ![Temperature](dataset_stats/TempBox.png) |

![Skewness](dataset_stats/Skewness.png)

## Project structure

```text
dataset/            raw, cleaned and outlier-removed CSVs
dataset_cleaning/   de-duplication and missing-value handling
dataset_outlier/    IQR outlier detection and impact analysis
dataset_stats/      exploratory statistics and plots
modelling/          classifier benchmark and saved results
```
