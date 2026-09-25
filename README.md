# Marketing Mix Modeling with Robyn (learning project)

A personal project to learn Marketing Mix Modeling (MMM) end to end in R, using [Robyn](https://github.com/facebookexperimental/Robyn), Meta's open-source MMM library.

This is not client work. The models run on simulated and public demo datasets.

## What it covers

- Exploratory data analysis and variable classification (paid media, organic, context)
- Adstock and saturation modeling
- Hyperparameter optimization with Nevergrad and model selection from the Pareto front
- Time-series validation
- Budget optimization under two scenarios (`max_response`, `target_efficiency`)
- Model refresh with new data

## Datasets (not included in the repo)

| Dataset | Source | Used for |
|---|---|---|
| `dt_simulated_weekly` | Simulated data shipped with the Robyn package | Full pipeline: EDA, model, optimizer |
| `bike_sales_data.csv` | Public MMM demo dataset (Kaggle) | EDA, model, optimizer, refresh |
| `Walmart_Sales.csv` | Public Walmart weekly sales data (Kaggle) | EDA only (Store 1); no media spend, so no MMM |

To run the bike and Walmart scripts, download the data and place it in `data/`.

## Structure

```
scripts/
  01_setup.R                  libraries and Python environment
  02_eda*.R                   exploratory analysis per dataset
  03_model*.R                 Robyn model fitting
  04_budget_optimizer*.R      budget allocation
  05_refresh_*.R              model refresh
NOTAS.md                      learning notes: concepts, decisions, mistakes (Spanish)
CLAUDE.md                     setup guide; the code was written with Claude Code as a coding assistant
```

## Setup

Requires R with `Robyn`, `reticulate` and `tidyverse`, and a Python virtualenv with `nevergrad` (see CLAUDE.md).
