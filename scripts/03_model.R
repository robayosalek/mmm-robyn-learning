# ============================================================
# MMM Project — Modelo Robyn
# Especificación, entrenamiento y outputs del modelo
# ============================================================

source("scripts/01_setup.R")

data("dt_simulated_weekly")
data("dt_prophet_holidays")

# ── Constantes del proyecto ──────────────────────────────────
# Ajustar antes de correr en un proyecto real.
PROPHET_COUNTRY <- "US"   # país para festivos de Prophet
ITERATIONS      <- 500    # mínimo recomendado para producción: 2000
TRIALS          <- 3      # mínimo recomendado para producción: 5
SEED            <- 123

# ── 1. Directorios de salida ─────────────────────────────────
dir.create("outputs/robyn", recursive = TRUE, showWarnings = FALSE)

# ── 2. InputCollect ──────────────────────────────────────────

# paid_media_spends: columnas de gasto monetario (para budget allocator).
# paid_media_vars:   columnas de exposición reales usadas en la regresión
#                    (pueden ser distintas, ej. impressions o clicks).
paid_media_spends <- c("tv_S", "ooh_S", "print_S", "facebook_S", "search_S")
paid_media_vars   <- c("tv_S", "ooh_S", "print_S", "facebook_I",
                       "search_clicks_P")

# Variables orgánicas: transformadas con adstock pero sin spend asociado.
organic_vars <- c("newsletter")

# Variables de contexto: no reciben transformación adstock.
# competitor_sales_B: signo "default" — la dirección del efecto no es
# obvia a priori y debe quedar libre para que el modelo la estime.
context_vars  <- c("competitor_sales_B", "events")
context_signs <- c("default", "default")

InputCollect <- robyn_inputs(
  dt_input     = dt_simulated_weekly,
  dt_holidays  = dt_prophet_holidays,

  # KPI
  dep_var      = "revenue",
  dep_var_type = "revenue",   # "revenue" o "conversion"

  # Tiempo
  # window_start: se excluyen las primeras 6 semanas de 2015 por ser datos
  #   parciales (dataset empieza en nov-2015, año incompleto).
  # window_end:   se deja 2019 fuera de la ventana de entrenamiento para
  #   poder usar ese año como validación out-of-sample externa.
  date_var     = "DATE",
  window_start = "2016-01-04",
  window_end   = "2018-12-31",

  # Medios pagados
  paid_media_spends = paid_media_spends,
  paid_media_vars   = paid_media_vars,
  paid_media_signs  = c("positive", "positive", "positive",
                        "positive", "positive"),

  # Orgánicos
  organic_vars  = organic_vars,
  organic_signs = c("positive"),

  # Contexto
  context_vars  = context_vars,
  context_signs = context_signs,

  # Variables categóricas (factor)
  factor_vars = c("events"),

  # Prophet: tendencia, estacionalidad semanal/anual y festivos.
  # Si el negocio no opera en EE. UU., cambiar PROPHET_COUNTRY arriba.
  prophet_vars    = c("trend", "season", "holiday"),
  prophet_signs   = c("default", "default", "default"),
  prophet_country = PROPHET_COUNTRY,

  # Adstock geométrico: un parámetro por canal (theta).
  # Alternativas con más flexibilidad: "weibull_cdf" o "weibull_pdf"
  # (dos parámetros: shape + scale), útiles cuando el carryover no
  # decae de forma exponencial simple.
  adstock = "geometric"
)

print(InputCollect)

# ── 3. Hiperparámetros ───────────────────────────────────────
# theta = tasa de decaimiento del adstock.
#         0 = sin efecto de carryover; valores cercanos a 1 = decaimiento lento.
# alpha = pendiente de la curva de saturación Hill (Hill slope).
#         Valores bajos (~0.5) = saturación suave; altos (~3) = más abrupta.
# gamma = punto de inflexión de Hill, expresado como fracción del rango
#         de la variable de exposición. 0.3 = satura pronto; 1 = nunca satura
#         dentro del rango observado.
#
# Los rangos deben reflejar conocimiento previo del canal.
# Si hay estudios de efectividad o campañas anteriores, estrechar los rangos
# acelera la convergencia y produce modelos más interpretables.

hyperparameters <- list(
  # TV: carryover lento (campañas sostenidas), saturación posible a alto spend.
  tv_S_alphas = c(0.5, 3),
  tv_S_gammas = c(0.3, 1),
  tv_S_thetas = c(0.3, 0.8),

  # OOH: carryover moderado (visibilidad física, exposición repetida).
  ooh_S_alphas = c(0.5, 3),
  ooh_S_gammas = c(0.3, 1),
  ooh_S_thetas = c(0.1, 0.4),

  # Print: carryover rápido (impacto inmediato, sin efecto prolongado).
  print_S_alphas = c(0.5, 3),
  print_S_gammas = c(0.3, 1),
  print_S_thetas = c(0.1, 0.4),

  # Facebook: se modela con impressions; carryover corto (digital de respuesta
  # directa). Si la campaña fuera de branding, subir theta hasta [0.1, 0.5].
  facebook_I_alphas = c(0.5, 3),
  facebook_I_gammas = c(0.3, 1),
  facebook_I_thetas = c(0.0, 0.3),

  # Search: intención declarada → carryover prácticamente nulo.
  search_clicks_P_alphas = c(0.5, 3),
  search_clicks_P_gammas = c(0.3, 1),
  search_clicks_P_thetas = c(0.0, 0.3),

  # Newsletter: orgánico, carryover bajo-moderado.
  newsletter_alphas = c(0.5, 3),
  newsletter_gammas = c(0.3, 1),
  newsletter_thetas = c(0.1, 0.4)
)

InputCollect <- robyn_inputs(
  InputCollect    = InputCollect,
  hyperparameters = hyperparameters
)

print(InputCollect)

# ── 4. Entrenamiento ─────────────────────────────────────────
# NOTA: ITERATIONS y TRIALS están definidos arriba como constantes.
# Para una corrida de producción usar al menos 2000 iteraciones y 5 trials.
# La semilla fija garantiza reproducibilidad; cambiarla si se quiere explorar
# variabilidad entre corridas.
#
# ts_validation = TRUE: Robyn reserva entre 20–50 % de las semanas finales
# como conjunto de validación temporal. El rango de train_size se controla
# con el hiperparámetro train_size (por defecto [0.5, 0.8]).
#
# cores: se usa el máximo disponible menos uno para dejar el sistema operativo
# funcional. En un servidor compartido, establecer un valor fijo explícito.
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
# pareto_fronts = "auto": Robyn selecciona automáticamente cuántos frentes
# incluir para tener al menos 100 modelos candidatos. En producción, revisar
# el gráfico de Pareto (NRMSE vs DECOMP.RSSD) y fijar este número
# manualmente (ej. pareto_fronts = 3) para acotar la selección a los modelos
# con mejor balance entre ajuste y decomposición.
#
# calibration_constraint: solo es relevante si se define calibration_input
# en robyn_inputs() (ej. datos de lift tests o experimentos controlados).
# Sin calibración, este parámetro no tiene efecto y debe omitirse.
#
# csv_out = "pareto": exporta métricas y coeficientes de los modelos Pareto.
# Útil para análisis adicional fuera de R.
OutputCollect <- robyn_outputs(
  InputCollect  = InputCollect,
  OutputModels  = OutputModels,
  pareto_fronts = "auto",
  plot_folder   = "outputs/robyn",
  plot_pareto   = FALSE,
  csv_out       = "pareto",
  clusters      = TRUE,
  export        = TRUE,
  quiet         = FALSE
)

print(OutputCollect)

# ── 5b. Persistir objetos de sesión ──────────────────────────
# Guarda InputCollect y OutputCollect en RDS inmediatamente después del
# entrenamiento. Esto permite ejecutar robyn_write() en cualquier momento
# posterior sin necesidad de re-entrenar, cargando el RDS con readRDS().
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
# Se generan one-pagers únicamente para los modelos representativos de
# cada cluster (uno por cluster), que son los candidatos para selección
# manual. Generarlos para todos los modelos Pareto sería redundante y lento.
robyn_onepagers(
  InputCollect  = InputCollect,
  OutputCollect = OutputCollect,
  select_model  = OutputCollect$clusters$models$solID,
  plot_folder   = "outputs/robyn"
)

cat("\n── MODELOS CANDIDATOS (representantes de cluster) ───────\n")
print(OutputCollect$clusters$models[, c("solID", "cluster",
                                        "nrmse", "decomp.rssd")])

# ── 7. Selección manual del modelo y exportación ─────────────
#
# PASO MANUAL REQUERIDO — no correr esta sección sin revisión.
#
# 1. Abrir los one-pagers en outputs/robyn/<carpeta_de_corrida>/ y revisar
#    cada modelo candidato (uno por cluster). Criterios sugeridos:
#      - NRMSE test bajo: buen ajuste predictivo fuera de muestra.
#      - DECOMP.RSSD bajo: atribución por canal coherente con el spend real.
#      - Coeficientes con signos y magnitudes plausibles para el negocio.
#      - Curvas de saturación creíbles (ningún canal en zona plana extrema).
#
# 2. Asignar el solID elegido a select_model (ej. select_model <- "X_XX_X").
#
# 3. Si esta sección se corre en una sesión R distinta a la del entrenamiento,
#    cargar primero los objetos desde el RDS guardado en el paso 5b:
#
#    sess <- readRDS("outputs/robyn/<carpeta>/robyn_session.RDS")
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
#   dir           = "outputs/robyn",
#   export        = TRUE
# )

message("Entrenamiento completo — revisar one-pagers en outputs/robyn/ ",
        "antes de seleccionar el modelo final.")
