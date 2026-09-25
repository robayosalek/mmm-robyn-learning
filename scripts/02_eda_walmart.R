# ============================================================
# MMM Project — EDA · Walmart Store 1
# Dataset: data/Walmart_Sales.csv  (filtrado Store = 1)
# KPI: Weekly_Sales  |  Fecha: columna Date (DD-MM-YYYY)
# Context vars: Holiday_Flag, Temperature, Fuel_Price, CPI, Unemployment
# ============================================================

source("scripts/01_setup.R")

df <- read_csv("data/Walmart_Sales.csv",
               col_types = cols(
                 Store        = col_double(),
                 Date         = col_character(),
                 Weekly_Sales = col_double(),
                 Holiday_Flag = col_double(),
                 Temperature  = col_double(),
                 Fuel_Price   = col_double(),
                 CPI          = col_double(),
                 Unemployment = col_double()
               )) %>%
  filter(Store == 1) %>%
  mutate(Date = as.Date(Date, format = "%d-%m-%Y")) %>%
  arrange(Date)

kpi_col      <- "Weekly_Sales"
context_cols <- c("Holiday_Flag", "Temperature", "Fuel_Price",
                  "CPI", "Unemployment")

dir.create("outputs", showWarnings = FALSE)

# ── 1. Estructura del dataset ────────────────────────────────
cat("\n── ESTRUCTURA ──────────────────────────────────────────\n")
glimpse(df)
cat("\nDimensiones:", nrow(df), "filas x", ncol(df), "columnas\n")
cat("Rango de fechas:", format(min(df$Date), "%Y-%m-%d"),
    "->", format(max(df$Date), "%Y-%m-%d"), "\n")

# ── 2. Estadísticas descriptivas ────────────────────────────
cat("\n── ESTADÍSTICAS DESCRIPTIVAS ───────────────────────────\n")
summary(df %>% select(all_of(c(kpi_col, context_cols))))

desc_stats <- df %>%
  select(all_of(c(kpi_col, context_cols))) %>%
  summarise(across(
    everything(),
    list(
      media   = ~ mean(.x, na.rm = TRUE),
      sd      = ~ sd(.x, na.rm = TRUE),
      min     = ~ min(.x, na.rm = TRUE),
      p25     = ~ quantile(.x, 0.25, na.rm = TRUE),
      mediana = ~ median(.x, na.rm = TRUE),
      p75     = ~ quantile(.x, 0.75, na.rm = TRUE),
      max     = ~ max(.x, na.rm = TRUE),
      na      = ~ sum(is.na(.x))
    ),
    .names = "{.col}__{.fn}"
  )) %>%
  pivot_longer(everything(), names_to = c("variable", "stat"),
               names_sep = "__") %>%
  pivot_wider(names_from = stat, values_from = value)

cat("\n── ESTADÍSTICAS POR VARIABLE ───────────────────────────\n")
print(desc_stats, n = Inf)

# ── 3. KPI en el tiempo ──────────────────────────────────────
cat("\n── VISUALIZACIONES ─────────────────────────────────────\n")

p_kpi <- ggplot(df, aes(x = Date, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.8) +
  geom_smooth(method = "loess", se = TRUE, color = "#E05C2A",
              fill = "#E05C2A", alpha = 0.15, linewidth = 0.6) +
  # Marcar semanas con Holiday_Flag = 1
  geom_point(data = filter(df, Holiday_Flag == 1),
             aes(x = Date, y = .data[[kpi_col]]),
             color = "#E05C2A", size = 2.5, shape = 18) +
  scale_x_date(date_breaks = "3 months", date_labels = "%b\n%Y") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI (Weekly Sales) en el tiempo — Store 1",
       subtitle = paste("Semanas:", format(min(df$Date), "%b %Y"),
                        "-", format(max(df$Date), "%b %Y"),
                        "| Diamantes naranjas = semanas festivas"),
       x = NULL, y = "Ventas semanales ($)") +
  theme_minimal(base_size = 9) +
  theme(axis.text.x = element_text(hjust = 0.5, size = 7))

print(p_kpi)
ggsave("outputs/walmart_01_kpi_tiempo.png", p_kpi,
       width = 18, height = 4, dpi = 150)

# ── 4. Distribución del KPI ──────────────────────────────────
p_dist <- ggplot(df, aes(x = .data[[kpi_col]])) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "#2C6FBF", alpha = 0.7) +
  geom_density(color = "#E05C2A", linewidth = 1) +
  scale_x_continuous(labels = scales::comma) +
  labs(title = "Distribucion del KPI (Weekly Sales) — Store 1",
       x = "Ventas semanales ($)", y = "Densidad") +
  theme_minimal(base_size = 12)

print(p_dist)
ggsave("outputs/walmart_02_kpi_distribucion.png", p_dist,
       width = 6, height = 4, dpi = 150)

# ── 5. Series temporales de variables de contexto ────────────
df_long <- df %>%
  select(Date, all_of(context_cols)) %>%
  pivot_longer(-Date, names_to = "variable", values_to = "valor")

p_context <- ggplot(df_long, aes(x = Date, y = valor)) +
  geom_line(color = "#2C6FBF", linewidth = 0.5) +
  facet_wrap(~ variable, scales = "free_y", ncol = 3) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Variables de contexto en el tiempo — Store 1",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(strip.text = element_text(face = "bold"))

print(p_context)
ggsave("outputs/walmart_03_context_tiempo.png", p_context,
       width = 12, height = 6, dpi = 150)

# ── 6. Correlaciones con el KPI ──────────────────────────────
correlaciones <- df %>%
  select(all_of(c(kpi_col, context_cols))) %>%
  cor(use = "complete.obs", method = "pearson")

cor_kpi <- correlaciones[kpi_col, context_cols] %>%
  enframe(name = "variable", value = "correlacion") %>%
  arrange(desc(abs(correlacion)))

cat("\n── CORRELACIONES CON EL KPI (Pearson) ─────────────────\n")
print(cor_kpi, n = Inf)

p_cor <- ggplot(cor_kpi,
                aes(x = reorder(variable, correlacion),
                    y = correlacion,
                    fill = correlacion)) +
  geom_col() +
  geom_text(aes(label = round(correlacion, 3),
                hjust = ifelse(correlacion >= 0, -0.1, 1.1)),
            size = 3) +
  coord_flip() +
  scale_fill_gradient2(low = "#C0392B", mid = "white",
                       high = "#2C6FBF", midpoint = 0, guide = "none") +
  scale_y_continuous(limits = c(
    min(cor_kpi$correlacion) - 0.1,
    max(cor_kpi$correlacion) + 0.1
  )) +
  labs(title = "Correlacion de variables de contexto con el KPI",
       x = NULL, y = "Correlacion de Pearson") +
  theme_minimal(base_size = 12)

print(p_cor)
ggsave("outputs/walmart_04_correlaciones.png", p_cor,
       width = 8, height = 5, dpi = 150)

# ── 7. Matriz de correlación completa (heatmap) ───────────────
cor_df <- as.data.frame(correlaciones) %>%
  rownames_to_column("var1") %>%
  pivot_longer(-var1, names_to = "var2", values_to = "r")

p_heatmap <- ggplot(cor_df, aes(x = var1, y = var2, fill = r)) +
  geom_tile(color = "white") +
  geom_text(aes(label = round(r, 2)), size = 2.5) +
  scale_fill_gradient2(low = "#C0392B", mid = "white",
                       high = "#2C6FBF", midpoint = 0,
                       limits = c(-1, 1), name = "r") +
  labs(title = "Matriz de correlacion completa — Store 1") +
  theme_minimal(base_size = 9) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        axis.title  = element_blank())

print(p_heatmap)
ggsave("outputs/walmart_05_heatmap_correlacion.png", p_heatmap,
       width = 8, height = 6, dpi = 150)

# ── 8. Detección de outliers (IQR × 1.5) ─────────────────────
detectar_outliers <- function(x) {
  q1  <- quantile(x, 0.25, na.rm = TRUE)
  q3  <- quantile(x, 0.75, na.rm = TRUE)
  iqr <- q3 - q1
  x < (q1 - 1.5 * iqr) | x > (q3 + 1.5 * iqr)
}

vars_analizar <- c(kpi_col, context_cols)

outlier_summary <- df %>%
  select(all_of(vars_analizar)) %>%
  summarise(across(
    everything(),
    list(n   = ~ sum(detectar_outliers(.x)),
         pct = ~ round(100 * mean(detectar_outliers(.x)), 2))
  )) %>%
  pivot_longer(everything(),
               names_to  = c("variable", "stat"),
               names_sep = "_(?=[^_]+$)") %>%
  pivot_wider(names_from = stat, values_from = value) %>%
  rename(n_outliers = n, pct_outliers = pct) %>%
  arrange(desc(n_outliers))

cat("\n── OUTLIERS POR VARIABLE (metodo IQR x 1.5) ───────────\n")
print(outlier_summary, n = Inf)

df_scaled <- df %>%
  select(Date, all_of(vars_analizar)) %>%
  mutate(across(-Date, ~ as.numeric(scale(.x)))) %>%
  pivot_longer(-Date, names_to = "variable", values_to = "valor_z")

p_box <- ggplot(df_scaled, aes(x = reorder(variable, valor_z, FUN = median),
                                y = valor_z)) +
  geom_boxplot(fill = "#2C6FBF", alpha = 0.6,
               outlier.color = "#C0392B", outlier.size = 1.5) +
  coord_flip() +
  labs(title = "Boxplots normalizados (z-score) — deteccion de outliers",
       x = NULL, y = "Valor estandarizado (z)") +
  theme_minimal(base_size = 12)

print(p_box)
ggsave("outputs/walmart_06_boxplots_outliers.png", p_box,
       width = 8, height = 5, dpi = 150)

df_kpi_out <- df %>%
  mutate(es_outlier = detectar_outliers(.data[[kpi_col]]))

p_kpi_out <- ggplot(df_kpi_out, aes(x = Date, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.7) +
  geom_point(data = filter(df_kpi_out, es_outlier),
             color = "#C0392B", size = 3, shape = 17) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI (Weekly Sales) — outliers marcados (IQR x 1.5)",
       subtitle = "Triangulos rojos = outliers",
       x = NULL, y = "Ventas semanales ($)") +
  theme_minimal(base_size = 12)

print(p_kpi_out)
ggsave("outputs/walmart_07_kpi_outliers.png", p_kpi_out,
       width = 10, height = 4, dpi = 150)

# ── 9. Ventas: semanas festivas vs no festivas ────────────────
# Holiday_Flag = 1 en semanas con festivos nacionales importantes
# (Super Bowl, Labor Day, Thanksgiving, Christmas). Comparar la
# distribucion de ventas permite cuantificar el lift de festividades.
df_holiday <- df %>%
  mutate(tipo_semana = ifelse(Holiday_Flag == 1,
                              "Festiva", "Normal"))

p_holiday <- ggplot(df_holiday,
                    aes(x = tipo_semana, y = .data[[kpi_col]],
                        fill = tipo_semana)) +
  geom_boxplot(alpha = 0.7, show.legend = FALSE,
               outlier.color = "#C0392B", outlier.size = 1.5) +
  scale_fill_manual(values = c("Festiva" = "#E05C2A",
                                "Normal"  = "#2C6FBF")) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Ventas: semanas festivas vs normales — Store 1",
       x = NULL, y = "Ventas semanales ($)") +
  theme_minimal(base_size = 12)

print(p_holiday)
ggsave("outputs/walmart_08_holiday_vs_normal.png", p_holiday,
       width = 6, height = 5, dpi = 150)

n_festivas <- sum(df$Holiday_Flag == 1)
media_fest  <- mean(df$Weekly_Sales[df$Holiday_Flag == 1])
media_norm  <- mean(df$Weekly_Sales[df$Holiday_Flag == 0])
cat("\n── SEMANAS FESTIVAS vs NORMALES ───────────────────────\n")
cat("Semanas festivas   :", n_festivas, "/", nrow(df), "\n")
cat("Media ventas festiv:", format(round(media_fest), big.mark = ","), "\n")
cat("Media ventas normal:", format(round(media_norm), big.mark = ","), "\n")
cat("Lift festivo       :", round(100 * (media_fest / media_norm - 1), 1),
    "%\n")

# ── 10. Resumen final ────────────────────────────────────────
cat("\n── RESUMEN EDA ─────────────────────────────────────────\n")
cat("Dataset             : data/Walmart_Sales.csv (Store = 1)\n")
cat("Semanas analizadas  :", nrow(df), "\n")
cat("Rango de fechas     :", format(min(df$Date), "%Y-%m-%d"),
    "->", format(max(df$Date), "%Y-%m-%d"), "\n")
cat("Variables de contexto:", length(context_cols), "\n")
cat("KPI (columna)       :", kpi_col, "\n")
cat("Correlacion mas alta:", cor_kpi$variable[1], "->",
    round(cor_kpi$correlacion[1], 4), "\n")
cat("Correlacion mas baja:", cor_kpi$variable[nrow(cor_kpi)], "->",
    round(cor_kpi$correlacion[nrow(cor_kpi)], 4), "\n")
cat("Mas outliers en     :", outlier_summary$variable[1], "->",
    outlier_summary$n_outliers[1], "observaciones\n")
cat("Graficos guardados en outputs/ (prefijo walmart_)\n")
message("EDA Walmart completo")
