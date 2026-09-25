# ============================================================
# MMM Project — Optimizador de presupuesto · Bike Sales
# Modelo: outputs/robyn_bikes/RobynModel-1_34_5.json
# Escenarios: max_response y target_efficiency (ROAS = 6)
# ============================================================

source("scripts/01_setup.R")
dir.create("outputs/allocator_bikes", recursive = TRUE, showWarnings = FALSE)

# ── Constantes ───────────────────────────────────────────────
model_json    <- "outputs/robyn_bikes/RobynModel-1_34_5.json"
roas_objetivo <- 6

# Presupuesto histórico total calculado sobre la ventana de entrenamiento
# (2017-09-03 → 2021-07-11) y los 4 canales incluidos en el modelo.
# Se mantiene fijo en ambos escenarios para que los resultados sean
# comparables con el mismo nivel de inversión.
df_raw <- read_csv("data/bike_sales_data.csv",
                   col_types = cols(Week = col_character(),
                                    .default = col_double())) %>%
  mutate(Week = as.Date(Week, format = "%m/%d/%y"))

total_budget_historico <- df_raw %>%
  filter(Week >= as.Date("2017-09-03"), Week <= as.Date("2021-07-11")) %>%
  summarise(total = sum(branded_search_spend + nonbranded_search_spend +
                          facebook_spend + print_spend)) %>%
  pull(total)

cat("Presupuesto histórico total (ventana entrenamiento):",
    format(round(total_budget_historico), big.mark = ","), "\n")

# ── Restricciones por canal ──────────────────────────────────
# Mínimo 0.1× y máximo 2.0× el spend medio histórico por canal.
# Aplican igual en ambos escenarios para que la comparación sea justa.
# tv_spend, ooh_spend y radio_spend están excluidos del modelo (CV = 0%).
constr_low <- c(
  branded_search_spend    = 0.1,
  nonbranded_search_spend = 0.1,
  facebook_spend          = 0.1,
  print_spend             = 0.1
)
constr_up <- c(
  branded_search_spend    = 2.0,
  nonbranded_search_spend = 2.0,
  facebook_spend          = 2.0,
  print_spend             = 2.0
)

# ── Helper: extrae resumen de un AllocatorCollect ────────────
extraer_resumen <- function(alloc) {
  out          <- alloc$dt_optimOut
  periods      <- as.numeric(gsub("[^0-9]", "", out$periods[1]))
  resp_opt_sem <- out$optmResponseUnitTotal[1]
  uplift_total <- out$optmResponseUnitTotalLift[1]
  resp_hist_sem <- resp_opt_sem / (1 + uplift_total)
  list(
    por_canal = data.frame(
      canal           = out$channels,
      spend_hist      = round(out$histSpendAllUnit),
      spend_opt       = round(out$optmSpendUnit),
      delta_pct       = round(out$optmSpendUnitDelta * 100, 1),
      roi_opt         = round(out$optmRoiUnit, 2),
      uplift_resp_pct = round(out$optmResponseUnitLift * 100, 1)
    ),
    totales = list(
      periods     = periods,
      resp_hist   = round(resp_hist_sem  * periods),
      resp_opt    = round(resp_opt_sem   * periods),
      uplift_pct  = round(uplift_total   * 100, 2),
      spend_usado = round(sum(out$optmSpendUnit) * periods)
    )
  )
}

# ── 1. Escenario: max_response ───────────────────────────────
# Maximiza el volumen de ventas con el presupuesto fijo. No impone
# restricción de eficiencia: acepta ROAS bajos si el canal sigue
# aportando ventas incrementales. Útil en fases de crecimiento.
cat("\n>>> Escenario 1: max_response\n")
alloc_max <- robyn_allocator(
  json_file                 = model_json,
  scenario                  = "max_response",
  total_budget              = total_budget_historico,
  date_range                = "all",
  channel_constr_low        = constr_low,
  channel_constr_up         = constr_up,
  channel_constr_multiplier = 1,
  constr_mode               = "eq",
  optim_algo                = "SLSQP_AUGLAG",
  maxeval                   = 100000,
  plots                     = TRUE,
  plot_folder               = "outputs/allocator_bikes",
  export                    = TRUE,
  quiet                     = TRUE
)
res_max <- extraer_resumen(alloc_max)

# ── 2. Escenario: target_efficiency (ROAS = 6) ───────────────
# Redistribuye el presupuesto para que cada canal alcance el ROAS
# objetivo. Si con el presupuesto disponible no es posible alcanzar
# el target en todos los canales, se usa menos del total (el excedente
# no es rentable al nivel exigido). Útil cuando hay un floor de
# rentabilidad impuesto por el negocio.
cat("\n>>> Escenario 2: target_efficiency (ROAS =", roas_objetivo, ")\n")
alloc_eff <- robyn_allocator(
  json_file                 = model_json,
  scenario                  = "target_efficiency",
  target_value              = roas_objetivo,
  total_budget              = total_budget_historico,
  date_range                = "all",
  channel_constr_low        = constr_low,
  channel_constr_up         = constr_up,
  channel_constr_multiplier = 1,
  constr_mode               = "eq",
  optim_algo                = "SLSQP_AUGLAG",
  maxeval                   = 100000,
  plots                     = TRUE,
  plot_folder               = "outputs/allocator_bikes",
  export                    = TRUE,
  quiet                     = TRUE
)
res_eff <- extraer_resumen(alloc_eff)

# ── 3. Tabla comparativa ─────────────────────────────────────
cat("\n")
cat("══════════════════════════════════════════════════════\n")
cat("  COMPARACIÓN DE ESCENARIOS — mismo presupuesto\n")
cat("══════════════════════════════════════════════════════\n")

comp <- merge(
  res_max$por_canal[, c("canal", "spend_hist", "spend_opt",
                         "delta_pct", "roi_opt")],
  res_eff$por_canal[, c("canal", "spend_opt", "delta_pct", "roi_opt")],
  by = "canal", suffixes = c("_max", "_eff")
)
comp <- comp[order(comp$canal), ]

cat("\n── Spend semanal óptimo por escenario ──────────────\n")
cat(sprintf("%-26s %10s %12s %12s %10s\n",
            "Canal", "Histórico", "max_resp", "target_eff", "Δ entre esc"))
cat(strrep("-", 72), "\n")
for (i in seq_len(nrow(comp))) {
  delta_entre <- comp$spend_opt_eff[i] - comp$spend_opt_max[i]
  cat(sprintf("%-26s %10s %12s %12s %+10s\n",
              comp$canal[i],
              format(comp$spend_hist[i],    big.mark = ","),
              format(comp$spend_opt_max[i], big.mark = ","),
              format(comp$spend_opt_eff[i], big.mark = ","),
              format(delta_entre,           big.mark = ",")))
}

cat("\n── ROI óptimo por escenario ────────────────────────\n")
cat(sprintf("%-26s %10s %10s\n", "Canal", "max_resp", "target_eff"))
cat(strrep("-", 48), "\n")
for (i in seq_len(nrow(comp))) {
  cat(sprintf("%-26s %10.2f %10.2f\n",
              comp$canal[i], comp$roi_opt_max[i], comp$roi_opt_eff[i]))
}

cat("\n── Totales (ventana completa:", res_max$totales$periods,
    "semanas) ──\n")
cat(sprintf("%-30s %14s %14s\n", "", "max_response", "target_eff"))
cat(strrep("-", 60), "\n")
cat(sprintf("%-30s %14s %14s\n", "Ventas históricas",
    format(res_max$totales$resp_hist, big.mark = ","), "—"))
cat(sprintf("%-30s %14s %14s\n", "Ventas óptimas",
    format(res_max$totales$resp_opt,  big.mark = ","),
    format(res_eff$totales$resp_opt,  big.mark = ",")))
cat(sprintf("%-30s %13s%% %13s%%\n", "Uplift vs histórico",
    res_max$totales$uplift_pct, res_eff$totales$uplift_pct))
cat(sprintf("%-30s %14s %14s\n", "Presupuesto utilizado",
    format(res_max$totales$spend_usado, big.mark = ","),
    format(res_eff$totales$spend_usado, big.mark = ",")))
cat(strrep("=", 60), "\n")

message("Optimización completa — gráficos en outputs/allocator_bikes/")
