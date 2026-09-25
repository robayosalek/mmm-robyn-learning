# ============================================================
# MMM Project — EDA
# Análisis exploratorio del dataset dt_simulated_weekly
# ============================================================

source("scripts/01_setup.R")

data("dt_simulated_weekly")
df <- dt_simulated_weekly

# ── 1. Estructura del dataset ────────────────────────────────
cat("\n── ESTRUCTURA ──────────────────────────────────────────\n")
glimpse(df)
cat("\nDimensiones:", nrow(df), "filas x", ncol(df), "columnas\n")
cat("Rango de fechas:", format(min(df$DATE), "%Y-%m-%d"),
    "→", format(max(df$DATE), "%Y-%m-%d"), "\n")

# ── 2. Estadísticas descriptivas ────────────────────────────
cat("\n── ESTADÍSTICAS DESCRIPTIVAS ───────────────────────────\n")
summary(df)

# Variables de media (numéricas, excepto DATE y KPI)
kpi_col    <- "revenue"
media_cols <- df %>%
  select(-DATE, -all_of(kpi_col)) %>%
  select(where(is.numeric)) %>%
  names()

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
dir.create("outputs", showWarnings = FALSE)

p_kpi <- ggplot(df, aes(x = DATE, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.8) +
  geom_smooth(method = "loess", se = TRUE, color = "#E05C2A",
              fill = "#E05C2A", alpha = 0.15, linewidth = 0.6) +
  scale_x_date(
    date_breaks  = "1 month",
    date_labels  = "%b\n%Y"
  ) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI (Revenue) en el tiempo",
       subtitle = paste("Semanas:", format(min(df$DATE), "%b %Y"),
                        "-", format(max(df$DATE), "%b %Y")),
       x = NULL, y = "Revenue") +
  theme_minimal(base_size = 9) +
  theme(axis.text.x = element_text(hjust = 0.5, size = 7))

print(p_kpi)
ggsave("outputs/eda_01_kpi_tiempo.png", p_kpi,
       width = 18, height = 4, dpi = 150)

# ── 4. Distribución del KPI ──────────────────────────────────
p_dist <- ggplot(df, aes(x = .data[[kpi_col]])) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "#2C6FBF", alpha = 0.7) +
  geom_density(color = "#E05C2A", linewidth = 1) +
  scale_x_continuous(labels = scales::comma) +
  labs(title = "Distribución del KPI", x = "Revenue", y = "Densidad") +
  theme_minimal(base_size = 12)

print(p_dist)
ggsave("outputs/eda_02_kpi_distribucion.png", p_dist,
       width = 6, height = 4, dpi = 150)

# ── 5. Series temporales de variables de media ───────────────
df_long <- df %>%
  select(DATE, all_of(media_cols)) %>%
  pivot_longer(-DATE, names_to = "variable", values_to = "valor")

p_media <- ggplot(df_long, aes(x = DATE, y = valor)) +
  geom_line(color = "#2C6FBF", linewidth = 0.5) +
  facet_wrap(~ variable, scales = "free_y", ncol = 3) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "Variables de media en el tiempo",
       x = NULL, y = NULL) +
  theme_minimal(base_size = 9) +
  theme(strip.text = element_text(face = "bold"))

print(p_media)
ggsave("outputs/eda_03_media_tiempo.png", p_media,
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
                       high = "#2C6FBF", midpoint = 0,
                       guide = "none") +
  scale_y_continuous(limits = c(
    min(cor_kpi$correlacion) - 0.1,
    max(cor_kpi$correlacion) + 0.1
  )) +
  labs(title = "Correlación de variables de media con el KPI",
       x = NULL, y = "Correlación de Pearson") +
  theme_minimal(base_size = 12)

print(p_cor)
ggsave("outputs/eda_04_correlaciones.png", p_cor,
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
ggsave("outputs/eda_05_heatmap_correlacion.png", p_heatmap,
       width = 10, height = 8, dpi = 150)

# ── 8. Detección de outliers (IQR) ───────────────────────────
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
    list(n  = ~ sum(detectar_outliers(.x)),
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

# Boxplots normalizados para comparar dispersión entre variables
df_scaled <- df %>%
  select(DATE, all_of(vars_analizar)) %>%
  mutate(across(-DATE, ~ as.numeric(scale(.x)))) %>%
  pivot_longer(-DATE, names_to = "variable", values_to = "valor_z")

p_box <- ggplot(df_scaled, aes(x = reorder(variable, valor_z,
                                             FUN = median),
                                y = valor_z)) +
  geom_boxplot(fill = "#2C6FBF", alpha = 0.6,
               outlier.color = "#C0392B", outlier.size = 1.5) +
  coord_flip() +
  labs(title = "Boxplots normalizados (z-score) — detección de outliers",
       x = NULL, y = "Valor estandarizado (z)") +
  theme_minimal(base_size = 12)

print(p_box)
ggsave("outputs/eda_06_boxplots_outliers.png", p_box,
       width = 8, height = 6, dpi = 150)

# Marcar outliers del KPI en la serie temporal
df_kpi_out <- df %>%
  mutate(es_outlier = detectar_outliers(.data[[kpi_col]]))

p_kpi_out <- ggplot(df_kpi_out, aes(x = DATE, y = .data[[kpi_col]])) +
  geom_line(color = "#2C6FBF", linewidth = 0.7) +
  geom_point(data = filter(df_kpi_out, es_outlier),
             color = "#C0392B", size = 3, shape = 17) +
  scale_y_continuous(labels = scales::comma) +
  labs(title = "KPI en el tiempo — outliers marcados (IQR × 1.5)",
       subtitle = "Triángulos rojos = outliers",
       x = NULL, y = "Revenue") +
  theme_minimal(base_size = 12)

print(p_kpi_out)
ggsave("outputs/eda_07_kpi_outliers.png", p_kpi_out,
       width = 10, height = 4, dpi = 150)

# ── 9. Resumen final ─────────────────────────────────────────
cat("\n── RESUMEN EDA ─────────────────────────────────────────\n")
cat("Semanas analizadas  :", nrow(df), "\n")
cat("Variables de media  :", length(media_cols), "\n")
cat("KPI (columna)       :", kpi_col, "\n")
cat("Correlación más alta:", cor_kpi$variable[1], "→",
    round(cor_kpi$correlacion[1], 4), "\n")
cat("Correlación más baja:", cor_kpi$variable[nrow(cor_kpi)], "→",
    round(cor_kpi$correlacion[nrow(cor_kpi)], 4), "\n")
cat("Más outliers en     :", outlier_summary$variable[1], "→",
    outlier_summary$n_outliers[1], "observaciones\n")
cat("Gráficos guardados en outputs/\n")
message("EDA completo")
