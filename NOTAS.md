# NOTAS — Proyecto MMM
*Última actualización: Mayo 2026*

---

## Cómo usar este archivo

Este archivo se actualiza al final de cada sesión. Contiene conceptos aprendidos, decisiones tomadas en cada dataset, errores cometidos, y lecciones. Es el complemento humano al código — explica el *por qué* detrás de cada decisión técnica.

---

## Conceptos clave

### Variables en un MMM

| Tipo | Qué es | Ejemplo |
|---|---|---|
| `date_var` | Columna de fechas | Date, Week, ds |
| `dep_var` | KPI a explicar (solo uno por modelo) | revenue, sales, conversions |
| `paid_media_spends` | Gasto en canales que controlas | TV, Facebook, Google |
| `paid_media_vars` | Exposición real del canal (impresiones, clicks) | facebook_I, search_clicks_P |
| `organic_vars` | Variables sin gasto pero con efecto en KPI | Newsletter clicks, tráfico SEO |
| `context_vars` | Factores externos que no controlas | Ventas competidor, precio, temperatura, CPI, desempleo |
| `factor_vars` | Variables categóricas de texto | events ("event1", "promo_verano") |

**Regla práctica:**
- ¿Puedes asignarle un presupuesto? → `paid_media`
- ¿Tiene efecto pero no lo controlas? → `context`
- ¿Tiene adstock pero sin gasto? → `organic`
- ¿Es texto categórico? → `factor_vars`
- ¿Es numérico continuo externo? → `context_vars`

**`dep_var` solo puede ser uno a la vez.** Si quieres modelar ventas online y offline por separado, necesitas dos modelos distintos.

---

### Adstock

El efecto de la publicidad se arrastra en el tiempo.

- **Theta alto** (0.7-0.9) → efecto dura muchas semanas → TV, OOH
- **Theta bajo** (0.0-0.2) → efecto desaparece rápido → Search, digital de respuesta directa
- **Geométrico:** un parámetro (theta). Punto de partida en exploración.
- **Weibull CDF:** dos parámetros. Más flexible. Para producción.

---

### Saturación

Cada canal tiene rendimientos decrecientes.

- **Effect share > spend share** → canal eficiente, tiene margen para crecer
- **Spend share > effect share** → canal sobreinvertido o saturado
- La curva de respuesta se aplana cuando el canal está saturado

---

### Variación en los datos

**Sin variación no hay aprendizaje.**

- **CV=0%** → excluir del modelo o diseñar experimento controlado
- **CV alto (>30%)** con suficientes semanas activas → estimable
- **Pocas semanas activas (<20% del total)** → ROAS incierto, advertir al cliente
- Más semanas del mismo gasto NO resuelven falta de variación

---

### Métricas de calidad del modelo

| Métrica | Qué mide | Umbral |
|---|---|---|
| **NRMSE** | Error de predicción normalizado | < 0.15 ideal, < 0.20 aceptable |
| **DECOMP.RSSD** | Coherencia entre atribución y gasto real | Más bajo = mejor |
| **R²** | Varianza explicada | > 0.8 aceptable, > 0.9 ideal |

**Prioridad según Meta:** DECOMP.RSSD primero, NRMSE como desempate.

---

### ROAS

- **ROAS = Revenue generado / Gasto invertido**
- **ROAS mínimo rentable = 1 / margen bruto**
- **CRÍTICO:** Nunca interpretar ROAS sin conocer los márgenes del negocio
- Intervalos de confianza amplios = estimado no confiable para decisiones

---

### Intercept (Baseline)

Lo que venderías si apagaras toda la publicidad.

- Intercept alto (>60%) → negocio fuerte sin publicidad
- Intercept bajo (<20%) → negocio dependiente de publicidad
- Intercept=0% con trend=0% = señal de alerta

**Argumento para clientes:** *"Una de las preguntas que este modelo responde es cuánto de tus ventas existen independientemente de lo que inviertes en publicidad."*

---

### Variables de contexto

Las variables de contexto con correlación baja con el KPI no son un problema. Su función es aislar su efecto para que el modelo pueda estimar mejor el efecto de los canales de media.

**Signo de la correlación:**
- Negativo = se mueven en direcciones opuestas (no significa que hace daño)
- Temperature negativa en retail = invierno = más ventas. Tiene sentido de negocio.

**Variables de contexto relevantes (ejemplo: marca DTC):**
- Índice de confianza del consumidor alemán
- Desempleo, CPI
- Share of voice de competidores (Google Trends, SimilarWeb, SEMrush, Brandwatch)
- Clima estacional

---

### Budget Optimizer — dos escenarios

| Escenario | Pregunta | Cuándo usarlo |
|---|---|---|
| `max_response` | ¿Cómo maximizo revenue con este presupuesto? | Fase de crecimiento |
| `target_efficiency` | ¿Cómo distribuyo para ROAS >= X? | Fase de consolidación |

**Las restricciones las define el cliente** — contratos, capacidad operativa, políticas de marca.

---

### Refresh del modelo

Actualiza el modelo con datos nuevos sin re-entrenar desde cero.

- **Cadencia recomendada:** trimestral (13 semanas)
- **`version_prompt = TRUE`** siempre — para hacer business sanity check
- **`refresh_mode = "manual"`** siempre — la selección es manual
- Guardar `robyn_refresh_full.RDS` para encadenar futuros refreshes
- El refresh re-estima coeficientes — el mejor modelo puede cambiar

---

### Validación temporal (ts_validation.png)

- **Train plano** → normal, el modelo siempre predice bien lo que memorizó
- **Val y test bajando** → el modelo está aprendiendo patrones reales
- **Train baja pero val/test suben** → overfitting

---

## Guía de selección de modelos (jerárquica)

1. **Actual vs. Predicted** — ¿Las líneas coinciden? Si no → descarta
2. **Fitted vs. Residual** — ¿La línea azul es plana en cero? Si tiene curva → descarta
3. **NRMSE y DECOMP.RSSD** — DECOMP primero, NRMSE como desempate
4. **Waterfall — business sanity check** — ¿Trend coherente? ¿Intercept razonable?
5. **Bootstrapped ROAS** — ¿Intervalos estrechos? Amplios = no accionable
6. **Curvas de respuesta** — ¿Forma cóncava? ¿Posición razonable?
7. **Adstock y carryover** — ¿Coherente con la naturaleza del canal?

---

### Cómo presentar resultados a no-técnicos

**Regla de oro:** el cliente no compró un modelo, compró una decisión.

Traducciones clave:
- "NRMSE = 0.15" → "el modelo predice las ventas con un margen de error del 15%"
- "Intercept = 43%" → "el 43% de tus ventas existirían aunque apagaras toda la publicidad"
- "Facebook ROAS = 8x" → "por cada euro en Facebook, el modelo estima 8 euros de revenue"
- "DECOMP.RSSD" → no lo menciones al cliente

**Estructura de presentación:**
1. Contexto — qué pregunta responde y con qué datos
2. Hallazgo principal — una sola frase que resume todo
3. Evidencia — waterfall y curvas de respuesta en lenguaje de negocio
4. Recomendación — concreta y accionable
5. Limitaciones — siempre mencionar qué no puede decir el modelo

---

## Dataset 1 — dt_simulated_weekly (Robyn)

### Decisiones tomadas
- Período de entrenamiento: 2016-2018. Se dejó 2019 para validación.
- `competitor_sales_B` → `context_vars` (estacionalidad compartida, no causalidad)
- `events` → `factor_vars`
- `newsletter` → `organic_vars`
- Modelo seleccionado final: **`3_55_6`**

### Errores cometidos
- Claude Code eligió `1_56_7` automáticamente → detectado y corregido
- No se revisaron los intervalos de bootstrapped ROAS durante la selección
- Se eligió `3_44_8` por pereza en una corrida anterior

---

## Dataset 2 — bike_sales_data.csv

### Características
- 260 semanas (2017-2023), 7 canales, sin variables de control
- Siempre activos: branded_search, nonbranded_search, facebook
- Intermitentes con CV=0%: TV (11%), OOH (19%), radio (22%) → excluidos

### Decisiones tomadas
- Excluidos TV, OOH, radio por CV=0%
- Período entrenamiento: 2017-09-03 → 2021-07-11
- Modelo seleccionado: **`1_34_5`**
- Refresh completado: ventana 2018-09-02 → 2022-07-10

### Errores cometidos
- Se intentó excluir OOH por correlación negativa — razón incorrecta. La correcta es CV=0%
- No se usó la jerarquía de selección — se fue directo a las métricas

### Hallazgos relevantes
- Pico 2020 = COVID → variable binaria de evento necesaria
- NRMSE de 0.28 alto por datos ruidosos y variables faltantes

---

## Dataset 3 — Walmart_Sales.csv (Store 1)

### Clasificación de variables
- `date_var`: Date
- `dep_var`: Weekly_Sales
- `context_vars`: Holiday_Flag, Temperature, Fuel_Price, CPI, Unemployment
- `factor_vars`: vacío
- `Store`: excluido (filtrado por Store=1)

### Hallazgos relevantes
- Temperature negativa = invierno = más ventas en retail. Tiene sentido.
- Holiday_Flag → lift de 7.7% en semanas festivas
- Sin canales de media — usado solo para practicar clasificación de variables

---

## Scripts del proyecto

| Script | Propósito | Dataset |
|---|---|---|
| `01_setup.R` | Configuración del entorno | — |
| `02_eda.R` | EDA dataset simulado Robyn | dt_simulated_weekly |
| `02_eda_bikes.R` | EDA dataset bikes | bike_sales_data.csv |
| `02_eda_walmart.R` | EDA dataset Walmart Store 1 | Walmart_Sales.csv |
| `03_model.R` | Modelo dataset simulado Robyn | dt_simulated_weekly |
| `03_model_bikes.R` | Modelo dataset bikes | bike_sales_data.csv |
| `04_budget_optimizer.R` | Optimizer dataset simulado | RobynModel-3_55_6.json |
| `04_budget_optimizer_bikes.R` | Optimizer dataset bikes | RobynModel-1_34_5.json |
| `05_refresh_bikes.R` | Refresh modelo bikes | bike_sales_data.csv |
| `05_refresh_template.R` | Template genérico de refresh | cualquier proyecto |

