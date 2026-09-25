# ============================================================
# MMM Project — Optimizador de presupuesto (dos escenarios)
# Corre robyn_allocator con max_response y target_efficiency
# y presenta una tabla comparativa de ambos resultados.
# ============================================================

source("scripts/01_setup.R")
dir.create("outputs/allocator", recursive = TRUE, showWarnings = FALSE)

# ── Constantes ───────────────────────────────────────────────
# Ruta al JSON del modelo elegido en 03_model.R (sección 7).
model_json <- "outputs/robyn/RobynModel-3_55_6.json"

# Presupuesto total histórico en la ventana 2016-01-04 / 2018-12-31.
# Se mantiene fijo en ambos escenarios para que los resultados sean
# comparables con el mismo nivel de inversión.
#   tv_S:       2,591,412  |  ooh_S:  8,239,694
#   print_S:      601,635  |  facebook_S: 334,078
#   search_S:     809,960  |  TOTAL: 12,576,779
total_budget_historico <- 12576779

# ROAS objetivo para el escenario target_efficiency.
# Debe calibrarse con el margen bruto del negocio: si el margen es 30%,
# un ROAS de 6x implica un retorno sobre el margen de ~1.8x.
roas_objetivo <- 6

# ── Restricciones por canal (conservadoras) ──────────────────
# Se aplican igual en ambos escenarios para que la comparación sea justa.
# Límite inferior (low): mínimo que puede recibir cada canal como fracción
#   de su spend medio histórico. Refleja compromisos mínimos de compra,
#   visibilidad mínima de marca o contratos ya firmados.
# Límite superior (up): máximo de 2x el histórico en todos los canales.
#   Conservador: evita que el modelo sugiera reasignaciones extremas que
#   serían difíciles de ejecutar operativamente en un ciclo de planificación.
#   Para explorar oportunidades más agresivas, subir a 3x o 5x en canales
#   digitales (facebook_S, search_S) donde el inventario no es el cuello
#   de botella.
constr_low <- c(
  tv_S       = 0.5,   # TV: mínimo por visibilidad de marca
  ooh_S      = 0.7,   # OOH: mínimo por contratos de espacio físico
  print_S    = 0.1,   # Print: sin compromisos relevantes
  facebook_S = 0.1,   # Facebook: sin compromisos mínimos
  search_S   = 0.1    # Search: sin compromisos mínimos
)
constr_up <- c(
  tv_S       = 2.0,   # TV: limitado por inventario de medios
  ooh_S      = 2.0,   # OOH: limitado por disponibilidad de espacios
  print_S    = 2.0,   # Print: conservador, canal en declive
  facebook_S = 2.0,   # Facebook: conservador para primera iteración
  search_S   = 2.0    # Search: conservador para primera iteración
)

# ── Helper: extrae resumen de un AllocatorCollect ────────────
extraer_resumen <- function(alloc) {
  out           <- alloc$dt_optimOut
  periods       <- as.numeric(gsub("[^0-9]", "", out$periods[1]))
  resp_opt_sem  <- out$optmResponseUnitTotal[1]
  uplift_total  <- out$optmResponseUnitTotalLift[1]
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
      periods        = periods,
      resp_hist      = round(resp_hist_sem * periods),
      resp_opt       = round(resp_opt_sem  * periods),
      uplift_pct     = round(uplift_total  * 100, 2),
      spend_usado    = round(sum(out$optmSpendUnit) * periods)
    )
  )
}

# ── 1. Escenario: max_response ───────────────────────────────
# Cuándo usarlo: cuando el objetivo es maximizar el volumen de revenue
# (o conversiones) con un presupuesto fijo. No impone ninguna restricción
# de eficiencia: acepta invertir en canales con ROAS bajo si siguen
# aportando revenue incremental positivo en el margen. Apropiado en fases
# de crecimiento donde el volumen importa más que la rentabilidad unitaria.
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
  plot_folder               = "outputs/allocator",
  export                    = TRUE,
  quiet                     = TRUE    # silenciar logs intermedios
)
res_max <- extraer_resumen(alloc_max)

# ── 2. Escenario: target_efficiency (ROAS = 6) ───────────────
# Cuándo usarlo: cuando el negocio tiene una meta de rentabilidad mínima
# que no puede sacrificarse. El optimizador redistribuye el presupuesto
# para que cada canal alcance el ROAS objetivo; si con el presupuesto
# disponible no es posible alcanzar el target en todos los canales,
# la solución usará menos del presupuesto total (el resto "no es rentable
# al nivel exigido"). Apropiado en fases de consolidación o cuando el CFO
# impone un floor de rentabilidad sobre inversión en medios.
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
  plot_folder               = "outputs/allocator",
  export                    = TRUE,
  quiet                     = TRUE
)
res_eff <- extraer_resumen(alloc_eff)

# ── 3. Tabla comparativa ─────────────────────────────────────
cat("\n")
cat("══════════════════════════════════════════════════════\n")
cat("  COMPARACIÓN DE ESCENARIOS — mismo presupuesto\n")
cat("══════════════════════════════════════════════════════\n")

# Por canal
comp <- merge(
  res_max$por_canal[, c("canal", "spend_hist", "spend_opt",
                         "delta_pct", "roi_opt")],
  res_eff$por_canal[, c("canal", "spend_opt", "delta_pct", "roi_opt")],
  by = "canal", suffixes = c("_max", "_eff")
)
comp <- comp[order(comp$canal), ]

cat("\n── Spend semanal óptimo por escenario ──────────────\n")
cat(sprintf("%-18s %10s %12s %12s %10s\n",
            "Canal", "Histórico", "max_resp", "target_eff", "Δ entre esc"))
cat(strrep("-", 64), "\n")
for (i in seq_len(nrow(comp))) {
  delta_entre <- comp$spend_opt_eff[i] - comp$spend_opt_max[i]
  cat(sprintf("%-18s %10s %12s %12s %+10s\n",
              comp$canal[i],
              format(comp$spend_hist[i],   big.mark = ","),
              format(comp$spend_opt_max[i], big.mark = ","),
              format(comp$spend_opt_eff[i], big.mark = ","),
              format(delta_entre,           big.mark = ",")))
}

cat("\n── ROI óptimo por escenario ────────────────────────\n")
cat(sprintf("%-18s %10s %10s\n", "Canal", "max_resp", "target_eff"))
cat(strrep("-", 40), "\n")
for (i in seq_len(nrow(comp))) {
  cat(sprintf("%-18s %10.2f %10.2f\n",
              comp$canal[i], comp$roi_opt_max[i], comp$roi_opt_eff[i]))
}

cat("\n── Totales (ventana completa:", res_max$totales$periods,
    "semanas) ──\n")
cat(sprintf("%-30s %14s %14s\n", "", "max_response", "target_eff"))
cat(strrep("-", 60), "\n")
cat(sprintf("%-30s %14s %14s\n", "Revenue histórico",
    format(res_max$totales$resp_hist, big.mark = ","), "—"))
cat(sprintf("%-30s %14s %14s\n", "Revenue óptimo",
    format(res_max$totales$resp_opt, big.mark = ","),
    format(res_eff$totales$resp_opt, big.mark = ",")))
cat(sprintf("%-30s %13s%% %13s%%\n", "Uplift vs histórico",
    res_max$totales$uplift_pct, res_eff$totales$uplift_pct))
cat(sprintf("%-30s %14s %14s\n", "Presupuesto utilizado",
    format(res_max$totales$spend_usado, big.mark = ","),
    format(res_eff$totales$spend_usado, big.mark = ",")))
cat(strrep("═", 60), "\n")

message("Optimización completa — gráficos en outputs/allocator/")
