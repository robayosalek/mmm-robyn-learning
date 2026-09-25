# ============================================================
# MMM Project — Modelo Robyn · Bike Sales
# Dataset: data/bike_sales_data.csv
# KPI: sales  |  Fecha: columna Week (M/D/YY)
# ============================================================

source("scripts/01_setup.R")

data("dt_prophet_holidays")

df <- read_csv("data/bike_sales_data.csv",
               col_types = cols(Week = col_character(), .default = col_double())) %>%
  mutate(Week = as.Date(Week, format = "%m/%d/%y")) %>%
  arrange(Week)

# Canales excluidos: tv_spend, ooh_spend, radio_spend.
# Motivo: CV = 0 % en semanas activas — invierten siempre la misma cantidad
# fija (tv: $2,500; ooh: $1,000; radio: $2,000 o $3,000), lo que impide al
# modelo estimar su efecto marginal con la variabilidad necesaria.
paid_media_spends <- c("branded_search_spend", "nonbranded_search_spend",
                       "facebook_spend", "print_spend")
paid_media_vars   <- paid_media_spends   # todas las vars son spend directo

# ── Constantes del proyecto ──────────────────────────────────
PROPHET_COUNTRY <- "US"
ITERATIONS      <- 500    # mínimo recomendado para producción: 2000
TRIALS          <- 3      # mínimo recomendado para producción: 5
SEED            <- 123

# ── 1. Directorios de salida ─────────────────────────────────
dir.create("outputs/robyn_bikes", recursive = TRUE, showWarnings = FALSE)

# ── 2. InputCollect ──────────────────────────────────────────
InputCollect <- robyn_inputs(
  dt_input     = df,
  dt_holidays  = dt_prophet_holidays,

  # KPI
  dep_var      = "sales",
  dep_var_type = "revenue",

  # Tiempo
  # window_start: se saltan las primeras ~6 semanas (2017-07-23 → 2017-09-03)
  # para que el adstock se estabilice antes de la ventana de entrenamiento.
  # window_end: se corta en 2021-07-11 para dejar las ~52 semanas siguientes
  # (2021-07-18 → 2022-07-10) como período de validación out-of-sample.
  # Esto permite evaluar la capacidad predictiva del modelo en datos que nunca
  # vio durante el entrenamiento, sin depender únicamente del ts_validation
  # interno de Robyn.
  date_var     = "Week",
  window_start = "2017-09-03",
  window_end   = "2021-07-11",

  # Medios pagados
  paid_media_spends = paid_media_spends,
  paid_media_vars   = paid_media_vars,
  paid_media_signs  = c("positive", "positive", "positive", "positive"),

  # Prophet: tendencia, estacionalidad anual y festivos.
  # No se incluye "weekday" porque el dataset es semanal (no hay variación
  # intra-semana). No hay columna de eventos en este dataset.
  prophet_vars    = c("trend", "season", "holiday"),
  prophet_signs   = c("default", "default", "default"),
  prophet_country = PROPHET_COUNTRY,

  # Adstock geométrico: un parámetro (theta) por canal.
  # Alternativa con más flexibilidad: "weibull_cdf" para print, donde el
  # carryover podría no ser exponencial simple dado el patrón intermitente.
  adstock = "geometric"
)

print(InputCollect)

# ── 3. Hiperparámetros ───────────────────────────────────────
# theta = tasa de decaimiento del adstock (0 = sin carryover; ~1 = lento).
# alpha = pendiente de la curva Hill (bajo ~0.5 = saturación suave).
# gamma = punto de inflexión Hill como fracción del rango de exposición.

hyperparameters <- list(
  # Branded search: intención de compra declarada → carryover prácticamente
  # nulo; el efecto se consume en la misma semana o la siguiente.
  branded_search_spend_alphas = c(0.5, 3),
  branded_search_spend_gammas = c(0.3, 1),
  branded_search_spend_thetas = c(0.0, 0.3),

  # Non-branded search: descubrimiento/awareness; mismo patrón que branded
  # pero con mayor variabilidad de spend (CV=49.7 %) → rango idéntico.
  nonbranded_search_spend_alphas = c(0.5, 3),
  nonbranded_search_spend_gammas = c(0.3, 1),
  nonbranded_search_spend_thetas = c(0.0, 0.3),

  # Facebook: canal digital de respuesta directa; carryover corto.
  # Si la estrategia fuera principalmente de branding subir theta a [0.1, 0.5].
  facebook_spend_alphas = c(0.5, 3),
  facebook_spend_gammas = c(0.3, 1),
  facebook_spend_thetas = c(0.0, 0.3),

  # Print: medio offline intermitente (44 % semanas activas); el efecto
  # puede extenderse más allá de la semana de publicación → theta más alto.
  print_spend_alphas = c(0.5, 3),
  print_spend_gammas = c(0.3, 1),
  print_spend_thetas = c(0.1, 0.4)
)

InputCollect <- robyn_inputs(
  InputCollect    = InputCollect,
  hyperparameters = hyperparameters
)

print(InputCollect)

# ── 4. Entrenamiento ─────────────────────────────────────────
# ts_validation = TRUE: Robyn reserva ~20–50 % de las semanas finales como
# conjunto de validación temporal. Para producción usar 2000 iteraciones y
# 5 trials; la semilla fija garantiza reproducibilidad.
OutputModels <- robyn_run(
  InputCollect       = InputCollect,
  cores              = parallel::detectCores() - 1,
  iterations         = ITERATIONS,
  trials             = TRIALS,
  ts_validation      = TRUE,
  add_penalty_factor = FALSE,
  outputs            = FALSE,
  seed               = SEED
)

print(OutputModels)

# ── 5. Outputs y selección de Pareto ────────────────────────
# plot_pareto = FALSE: no se generan PNGs individuales para todos los modelos
# Pareto. Los one-pagers de los representativos por cluster se generan en la
# sección 6, que es suficiente para la selección manual del modelo final.
OutputCollect <- robyn_outputs(
  InputCollect  = InputCollect,
  OutputModels  = OutputModels,
  pareto_fronts = "auto",
  plot_folder   = "outputs/robyn_bikes",
  plot_pareto   = FALSE,
  csv_out       = "pareto",
  clusters      = TRUE,
  export        = TRUE,
  quiet         = FALSE
)

print(OutputCollect)

# ── 5b. Persistir objetos de sesión ──────────────────────────
# Permite ejecutar robyn_write() en cualquier sesión posterior sin re-entrenar.
session_rds <- file.path(
  OutputCollect$plot_folder,
  "robyn_session.RDS"
)
saveRDS(
  list(InputCollect = InputCollect, OutputCollect = OutputCollect),
  file = session_rds
)
cat("Sesión guardada en:", session_rds, "\n")

# ── 6. One-pagers de los modelos representativos ─────────────
# Se genera un one-pager por cluster (modelo representativo), que son los
# únicos candidatos necesarios para la selección manual.
robyn_onepagers(
  InputCollect  = InputCollect,
  OutputCollect = OutputCollect,
  select_model  = OutputCollect$clusters$models$solID,
  plot_folder   = "outputs/robyn_bikes"
)

cat("\n── MODELOS CANDIDATOS (representantes de cluster) ───────\n")
print(OutputCollect$clusters$models[, c("solID", "cluster",
                                        "nrmse", "decomp.rssd")])

# ── 7. Selección manual del modelo y exportación ─────────────
#
# PASO MANUAL REQUERIDO — no correr esta sección sin revisión.
#
# 1. Abrir los one-pagers en outputs/robyn_bikes/<carpeta_de_corrida>/ y
#    revisar cada candidato (uno por cluster). Criterios sugeridos:
#      - NRMSE test bajo: buen ajuste predictivo fuera de muestra.
#      - DECOMP.RSSD bajo: atribución coherente con el share de spend real.
#      - Coeficientes con signos y magnitudes plausibles para el negocio.
#      - Curvas de saturación creíbles (ningún canal en zona plana extrema).
#
# 2. Asignar el solID elegido a select_model (ej. select_model <- "X_XX_X").
#
# 3. Si esta sección se corre en una sesión R distinta a la del entrenamiento,
#    cargar primero los objetos desde el RDS:
#
#    sess <- readRDS("outputs/robyn_bikes/<carpeta>/robyn_session.RDS")
#    InputCollect  <- sess$InputCollect
#    OutputCollect <- sess$OutputCollect

# select_model <- "X_XX_X"   # <-- reemplazar con el solID elegido

# stopifnot(
#   select_model %in% OutputCollect$allSolutions   # aborta si el ID no existe
# )
#
# robyn_write(
#   InputCollect  = InputCollect,
#   OutputCollect = OutputCollect,
#   select_model  = select_model,
#   dir           = "outputs/robyn_bikes",
#   export        = TRUE
# )

message("Entrenamiento completo — revisar one-pagers en outputs/robyn_bikes/ ",
        "antes de seleccionar el modelo final.")
