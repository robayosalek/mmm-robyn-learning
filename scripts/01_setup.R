# ============================================================
# MMM Project — Setup
# Configuración base del entorno
# ============================================================

# Fijar mirror de CRAN para evitar el menú interactivo
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Activar el entorno Python con Nevergrad
library(reticulate)
use_virtualenv("r-mmm", required = TRUE)

# Cargar librerías principales
library(Robyn)
library(tidyverse)

# Verificar que todo está conectado
py_config()
message("✅ Setup completo — entorno listo para modelar")