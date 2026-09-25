# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a **Marketing Mix Modeling (MMM)** project built in R using [Robyn](https://github.com/facebookexperimental/Robyn) (Meta's open-source MMM library). It models the impact of media spend and other variables on a business KPI.

## Environment Setup

Before running any script, the Python virtualenv `r-mmm` must exist with Nevergrad installed (used by Robyn for hyperparameter optimization):

```bash
# Create the virtualenv and install Nevergrad (one-time)
python3 -m venv ~/.virtualenvs/r-mmm
source ~/.virtualenvs/r-mmm/bin/activate
pip install nevergrad
```

Required R packages: `Robyn`, `reticulate`, `tidyverse`.

## Running Scripts

Scripts are numbered and meant to be run in order:

```r
source("scripts/01_setup.R")   # Load libraries, activate Python env
source("scripts/02_eda.R")     # Exploratory data analysis
source("scripts/03_model.R")   # Robyn model fitting and output
```

Run a single script from the terminal:

```bash
Rscript scripts/01_setup.R
```

## Architecture

| Path | Purpose |
|------|---------|
| `scripts/01_setup.R` | Sets CRAN mirror, activates `r-mmm` virtualenv via reticulate, loads Robyn + tidyverse |
| `scripts/02_eda.R` | EDA — not yet implemented |
| `scripts/03_model.R` | Robyn model specification, training, and output — not yet implemented |
| `data/` | Input data (raw data in `data/raw/` is gitignored) |
| `outputs/` | Model outputs — gitignored due to size |

## Key Constraints

- `outputs/` and `data/raw/` are gitignored — do not commit model artifacts or raw source data.
- The Python virtualenv is named `r-mmm` and is required by reticulate at runtime; scripts will fail if it doesn't exist.
- Robyn relies on Nevergrad (Python) for Bayesian optimization — any changes to the Python environment can break model runs.
