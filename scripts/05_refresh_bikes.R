# ============================================================
# MMM Project — Model Refresh · Bike Sales
# Extiende el modelo 1_34_5 (ventana 2017-09-03 → 2021-07-11)
# incorporando las 52 semanas siguientes hasta 2022-07-10,
# que corresponden al período de validación out-of-sample.
# ============================================================

source("scripts/01_setup.R")

data("dt_prophet_holidays")

# Dataset completo (260 semanas). robyn_refresh usa los datos
# más allá de window_end del modelo original como nuevas observaciones.
df <- read_csv("data/bike_sales_data.csv",
               col_types = cols(Week = col_character(),
                                .default = col_double())) %>%
  mutate(Week = as.Date(Week, format = "%m/%d/%y")) %>%
  arrange(Week)

# ── Constantes ───────────────────────────────────────────────
model_json     <- "outputs/robyn_bikes/RobynModel-1_34_5.json"
REFRESH_STEPS  <- 52    # semanas nuevas a incorporar
REFRESH_ITERS  <- 500   # producción: 2000
REFRESH_TRIALS <- 3     # producción: 5
SEED           <- 123

# ── 1. Directorios de salida ─────────────────────────────────
dir.create("outputs/robyn_bikes", recursive = TRUE, showWarnings = FALSE)

# ── 2. Refresh del modelo ────────────────────────────────────
# refresh_steps: número de nuevas semanas que se incorporan a la ventana
#   de entrenamiento. Con 52 pasos se añade un año completo (2021-07-18
#   → 2022-07-10), consumiendo la totalidad del período out-of-sample.
#
# refresh_mode = "manual": la selección del modelo refrescado siempre debe
#   ser manual. Antes de confirmar, revisar los one-pagers y verificar que
#   los coeficientes, curvas de saturación y atribución por canal sean
#   coherentes con el conocimiento del negocio (business sanity check).
#   Usar "auto" solo en pipelines automatizados donde el output no va
#   directamente a decisiones de inversión.
#
# bounds_freedom = NULL: usa los límites por defecto de Robyn, que permiten
#   a los hiperparámetros desplazarse moderadamente respecto al modelo base.
#   Aumentar el valor (ej. 0.2) para dar más libertad si el negocio cambió
#   significativamente en el período nuevo.
#
# plot_pareto = FALSE: no genera PNGs individuales para todos los modelos
#   del refresh. Los one-pagers se generan internamente por robyn_refresh
#   para el modelo seleccionado.
cat("\n>>> Ejecutando robyn_refresh (refresh_steps =",
    REFRESH_STEPS, ")...\n")

RobynRefresh <- robyn_refresh(
  json_file      = model_json,
  dt_input       = df,
  dt_holidays    = dt_prophet_holidays,
  refresh_steps  = REFRESH_STEPS,
  refresh_mode   = "manual",
  refresh_iters  = REFRESH_ITERS,
  refresh_trials = REFRESH_TRIALS,
  bounds_freedom = NULL,
  plot_folder    = "outputs/robyn_bikes",
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
#   refresh, en el mismo formato que robyn_session.RDS de 03_model_bikes.R.
#   Permite usar el modelo refrescado directamente en el budget optimizer
#   sin cargar el objeto completo.
ultimo <- RobynRefresh[[length(RobynRefresh)]]

saveRDS(
  RobynRefresh,
  file = file.path("outputs/robyn_bikes", "robyn_refresh_full.RDS")
)
saveRDS(
  list(InputCollect  = ultimo$InputCollect,
       OutputCollect = ultimo$OutputCollect),
  file = file.path("outputs/robyn_bikes", "robyn_refresh_session.RDS")
)
cat("Sesion completa guardada en: outputs/robyn_bikes/robyn_refresh_full.RDS\n")
cat("Sesion compacta guardada en: outputs/robyn_bikes/robyn_refresh_session.RDS\n")

# ── 4. Resumen del modelo refrescado ────────────────────────
cat("\n── RESUMEN DEL REFRESH ─────────────────────────────────\n")
cat("Modelo base       :", "1_34_5", "\n")
cat("Modelo refrescado :",
    ultimo$OutputCollect$selectID, "\n")
cat("Nueva ventana     :",
    as.character(ultimo$InputCollect$window_start), "->",
    as.character(ultimo$InputCollect$window_end), "\n")

# ── 5. Selección manual y exportación (paso opcional) ────────
#
# PASO MANUAL REQUERIDO si refresh_mode = "manual".
# Con refresh_mode = "auto" el modelo ya fue seleccionado y
# exportado automáticamente en el paso 2.
#
# Para cargar el refresh en una sesion posterior:
#
#   RobynRefresh <- readRDS("outputs/robyn_bikes/robyn_refresh_session.RDS")
#   ultimo       <- RobynRefresh[[length(RobynRefresh)]]
#   InputCollect  <- ultimo$InputCollect
#   OutputCollect <- ultimo$OutputCollect
#
# Para ejecutar el budget optimizer sobre el modelo refrescado,
# actualizar model_json en 04_budget_optimizer_bikes.R con el
# nuevo JSON generado en outputs/robyn_bikes/.

message("Refresh completo — revisar outputs en outputs/robyn_bikes/")
