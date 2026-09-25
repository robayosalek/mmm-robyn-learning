# ============================================================
# MMM Project — Model Refresh Template (genérico)
# Reutilizable para cualquier proyecto Robyn.
#
# INSTRUCCIONES DE USO:
#   1. Completar las constantes de la sección de configuración.
#   2. Adaptar la carga del dataset (sección "Cargar datos").
#   3. Ejecutar interactivamente; con version_prompt = TRUE Robyn
#      pedirá confirmar el modelo seleccionado del refresh.
#   4. Los RDS guardados al final son compatibles con el budget
#      optimizer (misma estructura que robyn_session.RDS).
# ============================================================

source("scripts/01_setup.R")

data("dt_prophet_holidays")

# ── CONFIGURACIÓN ────────────────────────────────────────────
# Ajustar estos valores antes de cada refresh. Son los únicos
# parámetros que deben cambiar entre proyectos o corridas.

# JSON del modelo seleccionado en el paso de entrenamiento o del
# último refresh. Se obtiene de robyn_write() o robyn_refresh().
MODEL_JSON <- "outputs/<proyecto>/RobynModel-<solID>.json"

# Ruta al dataset completo, incluyendo los períodos nuevos que se
# quieren incorporar. Debe cubrir window_end del modelo + refresh_steps.
DATA_PATH <- "data/<archivo>.csv"

# Número de períodos nuevos a incorporar en la ventana de entrenamiento.
# Regla general: usar el mismo intervalo con el que se actualiza el
# negocio (ej. 13 = trimestre, 26 = semestre, 52 = año completo).
# No debe superar los períodos disponibles más allá de window_end.
REFRESH_STEPS <- 13

# Iteraciones del optimizador para el refresh.
# 500 es suficiente para exploración; usar 2000+ en producción.
# El refresh parte de los hiperparámetros del modelo base, por lo
# que converge más rápido que un entrenamiento desde cero.
REFRESH_ITERS <- 500

# Trials del refresh. 3 para exploración, 5+ para producción.
REFRESH_TRIALS <- 3

# Carpeta donde se guardan los outputs del refresh.
# Se recomienda usar la misma carpeta del proyecto para mantener
# la cadena de modelos centralizada.
OUTPUT_FOLDER <- "outputs/<proyecto>"

# ── Cargar datos ─────────────────────────────────────────────
# Adaptar según el formato de fecha y columnas del proyecto.
# El dataset debe incluir TODOS los períodos (histórico + nuevos),
# no solo las semanas nuevas.
#
# Ejemplo para formato DD-MM-YYYY:
#   df <- read_csv(DATA_PATH, col_types = cols(Date = col_character(),
#                                               .default = col_double())) %>%
#         mutate(Date = as.Date(Date, format = "%d-%m-%Y")) %>%
#         arrange(Date)
#
# Ejemplo para formato MM/DD/YY:
#   df <- read_csv(DATA_PATH, col_types = cols(Week = col_character(),
#                                               .default = col_double())) %>%
#         mutate(Week = as.Date(Week, format = "%m/%d/%y")) %>%
#         arrange(Week)
df <- NULL   # <-- reemplazar con la carga real del dataset

# ── 1. Directorios de salida ─────────────────────────────────
dir.create(OUTPUT_FOLDER, recursive = TRUE, showWarnings = FALSE)

# ── 2. Refresh del modelo ────────────────────────────────────
# refresh_mode = "manual": la selección siempre debe ser manual para
#   poder hacer el business sanity check. Revisar los one-pagers antes
#   de confirmar: coeficientes, curvas de saturación y atribución por
#   canal deben ser coherentes con el conocimiento del negocio.
#   Usar "auto" solo en pipelines automatizados sin impacto directo
#   en decisiones de inversión.
#
# version_prompt = TRUE: Robyn pregunta interactivamente qué modelo
#   del refresh confirmar. Requiere sesión R interactiva; cambiar a
#   FALSE solo si se corre en batch y se acepta la selección automática.
#
# bounds_freedom = NULL: Robyn calcula automáticamente cuánto pueden
#   desplazarse los hiperparámetros respecto al modelo base (basado en
#   el número de refreshes previos en la cadena). Pasar un valor numérico
#   (ej. 0.2) para forzar un rango fijo de libertad cuando el negocio
#   cambió estructuralmente en el período nuevo.
#
# plot_pareto = FALSE: no genera PNGs individuales de todos los modelos
#   del refresh. Los one-pagers del modelo seleccionado sí se generan.
#
# export = TRUE: exporta el JSON del modelo seleccionado y los CSVs
#   de resultados. Necesario para el budget optimizer y futuros refreshes.
cat("\n>>> Ejecutando robyn_refresh (refresh_steps =", REFRESH_STEPS, ")...\n")

RobynRefresh <- robyn_refresh(
  json_file      = MODEL_JSON,
  dt_input       = df,
  dt_holidays    = dt_prophet_holidays,
  refresh_steps  = REFRESH_STEPS,
  refresh_mode   = "manual",
  refresh_iters  = REFRESH_ITERS,
  refresh_trials = REFRESH_TRIALS,
  bounds_freedom = NULL,
  plot_folder    = OUTPUT_FOLDER,
  plot_pareto    = FALSE,
  version_prompt = TRUE,
  export         = TRUE
)

# ── 3. Persistir sesión de refresh ───────────────────────────
# Se guardan dos RDS con propósitos distintos:
#
# robyn_refresh_full.RDS: objeto RobynRefresh completo, necesario para
#   encadenar futuros refreshes (Robyn requiere el historial completo
#   de la cadena para calcular los nuevos bounds_freedom).
#
# robyn_refresh_session.RDS: InputCollect + OutputCollect del último
#   refresh, en el mismo formato que robyn_session.RDS del entrenamiento
#   inicial. Permite usar el modelo refrescado directamente en el budget
#   optimizer sin necesidad de cargar el objeto completo.
ultimo <- RobynRefresh[[length(RobynRefresh)]]

saveRDS(
  RobynRefresh,
  file = file.path(OUTPUT_FOLDER, "robyn_refresh_full.RDS")
)
saveRDS(
  list(InputCollect  = ultimo$InputCollect,
       OutputCollect = ultimo$OutputCollect),
  file = file.path(OUTPUT_FOLDER, "robyn_refresh_session.RDS")
)
cat("Sesion completa guardada en:", file.path(OUTPUT_FOLDER,
    "robyn_refresh_full.RDS"), "\n")
cat("Sesion compacta guardada en:", file.path(OUTPUT_FOLDER,
    "robyn_refresh_session.RDS"), "\n")

# ── 4. Resumen del modelo refrescado ─────────────────────────
cat("\n── RESUMEN DEL REFRESH ─────────────────────────────────\n")
cat("Modelo base       :", MODEL_JSON, "\n")
cat("Modelo refrescado :", ultimo$OutputCollect$selectID, "\n")
cat("Nueva ventana     :",
    as.character(ultimo$InputCollect$window_start), "->",
    as.character(ultimo$InputCollect$window_end), "\n")

# ── 5. Siguiente paso: budget optimizer ──────────────────────
# Para correr el budget optimizer con el modelo refrescado, actualizar
# model_json en el script del optimizer con la ruta al nuevo JSON:
#
#   sess <- readRDS(file.path(OUTPUT_FOLDER, "robyn_refresh_session.RDS"))
#   InputCollect  <- sess$InputCollect
#   OutputCollect <- sess$OutputCollect
#
# El JSON del modelo refrescado queda en:
#   <OUTPUT_FOLDER>/Robyn_<timestamp>_rf<N>/RobynModel-<solID>.json

message("Refresh completo — revisar outputs en ", OUTPUT_FOLDER)
