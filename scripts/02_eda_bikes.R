# ============================================================
# MMM Project — EDA · Bike Sales
# Dataset: data/bike_sales_data.csv
# KPI: sales  |  Fecha: columna Week (M/D/YY)
# ============================================================

source("scripts/01_setup.R")

df <- read_csv("data/bike_sales_data.csv",
               col_types = cols(Week = col_character(), .default = col_double())) %>%
  mutate(Week = as.Date(Week, format = "%m/%d/%y")) %>%
  arrange(Week)

kpi_col    <- "sales"
media_cols <- c("branded_search_spend", "nonbranded_search_spend",
                "facebook_spend", "print_spend",
                "ooh_spend", "tv_spend", "radio_spend")

dir.create("outputs", showWarnings = FALSE)

# ── 1. Estructura del dataset ────────────────────────────────
cat("\n── ESTRUCTURA ──────────────────────────────────────────\n")
glimpse(df)
cat("\nDimensiones:", nrow(df), "filas x", ncol(df), "columnas\n")
cat("Rango de fechas:", format(min(df$Week), "%Y-%m-%d"),
    "→", format(max(df$Week), "%Y-%m-%d"), "\n")

# ── 2. Estadísticas descriptivas ────────────────────────────
cat("\n── ESTADÍSTICAS DESCRIPTIVAS ───────────────────────────\n")
summary(df)

desc_stats <- df %>%
  select(all_of(c(kpi_col, media_cols))) %>%
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

p_kpi <- ggplot(df, aes(x = Week, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.8) +
  geom_smooth(method = "loess", se = TRUE, color = "#E05C2A",
              fill = "#E05C2A", alpha = 0.15, linewidth = 0.6) +
  scale_x_date(date_breaks = "6 months", date_labels = "%b\n%Y") +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI (Sales) en el tiempo",
       subtitle = paste("Semanas:", format(min(df$Week), "%b %Y"),
                        "-", format(max(df$Week), "%b %Y")),
       x = NULL, y = "Ventas") +
  theme_minimal(base_size = 9) +
  theme(axis.text.x = element_text(hjust = 0.5, size = 7))

print(p_kpi)
ggsave("outputs/bikes_01_kpi_tiempo.png", p_kpi,
       width = 18, height = 4, dpi = 150)

# ── 4. Distribución del KPI ──────────────────────────────────
p_dist <- ggplot(df, aes(x = .data[[kpi_col]])) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "#2C6FBF", alpha = 0.7) +
  geom_density(color = "#E05C2A", linewidth = 1) +
  scale_x_continuous(labels = scales::comma) +
  labs(title = "Distribución del KPI (Sales)", x = "Ventas", y = "Densidad") +
  theme_minimal(base_size = 12)

print(p_dist)
ggsave("outputs/bikes_02_kpi_distribucion.png", p_dist,
       width = 6, height = 4, dpi = 150)

# ── 5. Series temporales de canales de media ─────────────────
df_long <- df %>%
  select(Week, all_of(media_cols)) %>%
  pivot_longer(-Week, names_to = "canal", values_to = "spend")

p_media <- ggplot(df_long, aes(x = Week, y = spend)) +
  geom_line(color = "#2C6FBF", linewidth = 0.5) +
  facet_wrap(~ canal, scales = "free_y", ncol = 3) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Spend por canal en el tiempo", x = NULL, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(strip.text = element_text(face = "bold"))

print(p_media)
ggsave("outputs/bikes_03_canales_tiempo.png", p_media,
       width = 12, height = 8, dpi = 150)

# ── 6. Correlaciones con el KPI ──────────────────────────────
correlaciones <- df %>%
  select(all_of(c(kpi_col, media_cols))) %>%
  cor(use = "complete.obs", method = "pearson")

cor_kpi <- correlaciones[kpi_col, media_cols] %>%
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
  labs(title = "Correlación de canales con el KPI (Sales)",
       x = NULL, y = "Correlación de Pearson") +
  theme_minimal(base_size = 12)

print(p_cor)
ggsave("outputs/bikes_04_correlaciones.png", p_cor,
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
  labs(title = "Matriz de correlación completa") +
  theme_minimal(base_size = 9) +
  theme(axis.text.x = element_text(angle = 45, hjust = 1),
        axis.title  = element_blank())

print(p_heatmap)
ggsave("outputs/bikes_05_heatmap_correlacion.png", p_heatmap,
       width = 10, height = 8, dpi = 150)

# ── 8. Detección de outliers (IQR × 1.5) ─────────────────────
detectar_outliers <- function(x) {
  q1  <- quantile(x, 0.25, na.rm = TRUE)
  q3  <- quantile(x, 0.75, na.rm = TRUE)
  iqr <- q3 - q1
  x < (q1 - 1.5 * iqr) | x > (q3 + 1.5 * iqr)
}

vars_analizar <- c(kpi_col, media_cols)

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

cat("\n── OUTLIERS POR VARIABLE (método IQR × 1.5) ────────────\n")
print(outlier_summary, n = Inf)

df_scaled <- df %>%
  select(Week, all_of(vars_analizar)) %>%
  mutate(across(-Week, ~ as.numeric(scale(.x)))) %>%
  pivot_longer(-Week, names_to = "variable", values_to = "valor_z")

p_box <- ggplot(df_scaled, aes(x = reorder(variable, valor_z, FUN = median),
                                y = valor_z)) +
  geom_boxplot(fill = "#2C6FBF", alpha = 0.6,
               outlier.color = "#C0392B", outlier.size = 1.5) +
  coord_flip() +
  labs(title = "Boxplots normalizados (z-score) — detección de outliers",
       x = NULL, y = "Valor estandarizado (z)") +
  theme_minimal(base_size = 12)

print(p_box)
ggsave("outputs/bikes_06_boxplots_outliers.png", p_box,
       width = 8, height = 6, dpi = 150)

df_kpi_out <- df %>%
  mutate(es_outlier = detectar_outliers(.data[[kpi_col]]))

p_kpi_out <- ggplot(df_kpi_out, aes(x = Week, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.7) +
  geom_point(data = filter(df_kpi_out, es_outlier),
             color = "#C0392B", size = 3, shape = 17) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI (Sales) — outliers marcados (IQR × 1.5)",
       subtitle = "Triángulos rojos = outliers",
       x = NULL, y = "Ventas") +
  theme_minimal(base_size = 12)

print(p_kpi_out)
ggsave("outputs/bikes_07_kpi_outliers.png", p_kpi_out,
       width = 10, height = 4, dpi = 150)

# ── 9. Semanas activas por canal ─────────────────────────────
# Canales con actividad intermitente son distintos a los siempre-on;
# conocer la densidad de activación es clave para calibrar adstock.
active_summary <- df %>%
  select(all_of(media_cols)) %>%
  summarise(across(
    everything(),
    list(
      semanas_activas  = ~ sum(.x > 0),
      pct_activo       = ~ round(100 * mean(.x > 0), 1),
      semanas_cero     = ~ sum(.x == 0)
    )
  )) %>%
  pivot_longer(everything(),
               names_to  = c("canal", "stat"),
               names_sep = "_(?=semanas_activas|pct_activo|semanas_cero)") %>%
  pivot_wider(names_from = stat, values_from = value) %>%
  arrange(desc(semanas_activas))

cat("\n── SEMANAS ACTIVAS POR CANAL ────────────────────────────\n")
print(active_summary, n = Inf)

p_activo <- ggplot(active_summary,
                   aes(x = reorder(canal, pct_activo), y = pct_activo,
                       fill = pct_activo)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(pct_activo, "%\n(", semanas_activas, " sem)")),
            hjust = -0.05, size = 3) +
  coord_flip() +
  scale_fill_gradient(low = "#F0C27F", high = "#2C6FBF") +
  scale_y_continuous(limits = c(0, 115), labels = function(x) paste0(x, "%")) +
  labs(title = "Porcentaje de semanas activas por canal",
       x = NULL, y = "% semanas con spend > 0") +
  theme_minimal(base_size = 12)

print(p_activo)
ggsave("outputs/bikes_08_semanas_activas.png", p_activo,
       width = 8, height = 5, dpi = 150)

# ── 10. Variación de gasto por canal (solo semanas activas) ───
# Coeficiente de variación (CV) y rango intercuartílico relativo
# calculados únicamente sobre semanas con spend > 0.
variacion_summary <- df %>%
  select(all_of(media_cols)) %>%
  pivot_longer(everything(), names_to = "canal", values_to = "spend") %>%
  filter(spend > 0) %>%
  group_by(canal) %>%
  summarise(
    n_activo  = n(),
    media     = mean(spend),
    sd        = sd(spend),
    cv_pct    = round(100 * sd(spend) / mean(spend), 1),
    p25       = quantile(spend, 0.25),
    mediana   = median(spend),
    p75       = quantile(spend, 0.75),
    iqr_rel   = round(100 * (quantile(spend, 0.75) - quantile(spend, 0.25)) /
                        median(spend), 1),
    max_spend = max(spend),
    .groups = "drop"
  ) %>%
  arrange(desc(cv_pct))

cat("\n── VARIACIÓN DE GASTO POR CANAL (semanas activas) ──────\n")
print(variacion_summary, n = Inf)

# Boxplots de spend en semanas activas para visualizar dispersión
df_activo_long <- df %>%
  select(all_of(media_cols)) %>%
  pivot_longer(everything(), names_to = "canal", values_to = "spend") %>%
  filter(spend > 0)

p_var_box <- ggplot(df_activo_long,
                    aes(x = reorder(canal, spend, FUN = median), y = spend)) +
  geom_boxplot(fill = "#2C6FBF", alpha = 0.6,
               outlier.color = "#C0392B", outlier.size = 1.5) +
  coord_flip() +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Distribución de spend por canal (semanas activas)",
       subtitle = "Solo semanas con spend > 0",
       x = NULL, y = "Spend ($)") +
  theme_minimal(base_size = 12)

print(p_var_box)
ggsave("outputs/bikes_09_variacion_spend_boxplot.png", p_var_box,
       width = 8, height = 5, dpi = 150)

# CV por canal — cuánto varía el nivel de inversión semana a semana
p_cv <- ggplot(variacion_summary,
               aes(x = reorder(canal, cv_pct), y = cv_pct, fill = cv_pct)) +
  geom_col(show.legend = FALSE) +
  geom_text(aes(label = paste0(cv_pct, "%")), hjust = -0.1, size = 3) +
  coord_flip() +
  scale_fill_gradient(low = "#A8D5A2", high = "#C0392B") +
  scale_y_continuous(limits = c(0, max(variacion_summary$cv_pct) * 1.15),
                     labels = function(x) paste0(x, "%")) +
  labs(title = "Coeficiente de variación del spend por canal",
       subtitle = "CV alto = inversión muy irregular semana a semana",
       x = NULL, y = "CV (%)") +
  theme_minimal(base_size = 12)

print(p_cv)
ggsave("outputs/bikes_10_cv_spend.png", p_cv,
       width = 8, height = 5, dpi = 150)

# ── 11. Resumen final ────────────────────────────────────────
cat("\n── RESUMEN EDA ─────────────────────────────────────────\n")
cat("Dataset             : data/bike_sales_data.csv\n")
cat("Semanas analizadas  :", nrow(df), "\n")
cat("Rango de fechas     :", format(min(df$Week), "%Y-%m-%d"),
    "→", format(max(df$Week), "%Y-%m-%d"), "\n")
cat("Canales de media    :", length(media_cols), "\n")
cat("KPI (columna)       :", kpi_col, "\n")
cat("Correlación más alta:", cor_kpi$variable[1], "→",
    round(cor_kpi$correlacion[1], 4), "\n")
cat("Correlación más baja:", cor_kpi$variable[nrow(cor_kpi)], "→",
    round(cor_kpi$correlacion[nrow(cor_kpi)], 4), "\n")
cat("Canal siempre activo:", paste(filter(active_summary, pct_activo == 100)$canal,
                                    collapse = ", "), "\n")
cat("Canal más irregular :", variacion_summary$canal[1], "→ CV",
    variacion_summary$cv_pct[1], "%\n")
cat("Más outliers en     :", outlier_summary$variable[1], "→",
    outlier_summary$n_outliers[1], "observaciones\n")
cat("Gráficos guardados en outputs/ (prefijo bikes_)\n")
message("EDA bikes completo")
