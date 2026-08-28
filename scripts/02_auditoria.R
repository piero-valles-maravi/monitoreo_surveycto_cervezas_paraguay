# =====================================================================
# 02_auditoria.R
# Orden de las alertas: 1) missings  2) outliers  3) duplicados  4) otras
# =====================================================================

library(pacman)
p_load(tidyverse, stringr, stringi, lubridate, haven, writexl)

# ---------------------------------------------------------------------
# 1. Cargar la cruda más reciente de data/01_crudas
# ---------------------------------------------------------------------
archivo <- tail(sort(list.files("data/01_crudas",
                    pattern = "^cruda_campo_.*\\.RData$", full.names = TRUE)), 1)
if (length(archivo) == 0) stop("No hay crudas en data/01_crudas.")
load(archivo)                                  # -> dataset
cat("Auditando:", basename(archivo), "|", nrow(dataset), "registros\n")

# --- Parámetros ajustables (por ahora no se van a auditar con tiempos, los tiempos se ajustarán en el piloto)
# (PILOTO) Sin chequeo por duración/tiempo por ahora 
# DUR_MIN_SPEEDING <- 5    # entrevistas < X min -> posible speeding
# DUR_MAX_MIN      <- 45   # entrevistas > X min -> revisar
CODIGOS_VALIDOS  <- sprintf("CATI%02d", 1:22)

# --- Ayudas (funciones propias, para no repetir la misma fórmula en cada chequeo) ---

# vacio(x): TRUE si la respuesta está VACÍA. Cuenta como vacío: NA, "", "NA" o 999 (missing).
#   ej: vacio("999") = TRUE  |  vacio("Marca A") = FALSE
vacio <- function(x) is.na(x) | trimws(as.character(x)) %in% c("", "NA", "999")

# n_sel(x): CUENTA cuántas opciones marcó en una pregunta de opción MÚLTIPLE
#   (las múltiples llegan como texto separado por espacios).  ej: n_sel("1 3 5") = 3
n_sel <- function(x) ifelse(vacio(x), 0L, str_count(str_trim(x), "\\S+"))

# flag(x): convierte una CONDICIÓN (TRUE/FALSE) en 1/0, y los NA/vacíos en 0.
#   ej: flag(edad > 40) = 1 si es mayor de 40, 0 si no (o si está vacío)
flag  <- function(x) as.integer(replace_na(x, FALSE))

# Preguntas de opción única (deben ser numéricas)
codificadas <- c(
  "confirma_encuestador",
  "consentimiento",
  "s1_edad",
  "s2_residencia",
  "p1_celular_confirma",
  "p4_consumo_habitual",
  "p4_1_frecuencia",
  "p5_edad",
  "p6_genero",
  "p7_zona",
  "p8_educacion",
  "p9_situacion_laboral",
  "p10_estado_civil_hijos",
  "p11_tipo_actividad",
  "p12_importancia_salud",
  "p17_motivo_1",
  "p17_motivo_2",
  "p17_motivo_3",
  "p19c_autoconcepto",
  "p19d_red_social",
  "p21_cambio_marca",
  "p21a_motivo_cambio",
  "p22_probabilidad_recompra",
  "p22b_sensibilidad_precio",
  "p22c_umbral_precio",
  "p23_refrescancia",
  "p23_no_pesadez",
  "p23_sabor_cervecero",
  "p23_precio_calidad",
  "p23_imagen_premium",
  "p24_refrescancia",
  "p24_no_pesadez",
  "p24_sabor_cervecero",
  "p24_precio_calidad",
  "p24_imagen_premium",
  "p25_recuerda_campana",
  "p26_tipo_contenido",
  "p27_interes_grupo_focal"
)

# ---------------------------------------------------------------------
# 2. Validar tipo de dato: campos que DEBERÍAN ser número y traen texto
#    (se chequea ANTES de convertir a numérico; excluye las abiertas)
# ---------------------------------------------------------------------
# OJO: sapply() devuelve un VECTOR (no una matriz) cuando la base trae UNA sola
# fila, y ahí rowSums() corta con "'x' debe ser un array de al menos dos
# dimensiones". Reduce(`|`) va combinando columna por columna, así que no depende
# de cuántas filas haya (pasa igual con 1 que con 500).
chk_num <- intersect(codificadas, names(dataset))
dataset$ale_tipo_dato <- if (length(chk_num))
  flag(Reduce(`|`, lapply(chk_num, function(v)
    !vacio(dataset[[v]]) & is.na(suppressWarnings(as.numeric(dataset[[v]])))))) else 0L

# ---------------------------------------------------------------------
# 3. Convertir opción única a numérico
# ---------------------------------------------------------------------
dataset <- dataset %>%
  mutate(across(any_of(codificadas), as.numeric))

# ---------------------------------------------------------------------
# 4. Asegurar que existan las columnas condicionales
# ---------------------------------------------------------------------
posibles_faltantes <- c(
  "p1_celular_confirma",
  "correo",
  "duration_min",
  "codigo_encuestador",
  "arquetipo_consumo_habitual",
  "p4_otra_especificar",
  "p7_otra_especificar",
  "p8_otra_especificar",
  "p9_otra_especificar",
  "p11_otra_especificar",
  "p14_otra_especificar",
  "p19_marca_persona",
  "p19_generico_persona",
  "p19c_otra_especificar",
  "p20_otra_especificar",
  "p21a_otra_especificar",
  "p26_otra_especificar",
  "p25a_cual_campana", 
  "p3_otra_especificar",
  "p10_otra_especificar",
  "p13_otra_especificar",
  "p15_otra_especificar",
  "p16_otra_especificar",
  "p17_otra_especificar",
  "p19d_otra_especificar"
)
for (v in setdiff(posibles_faltantes, colnames(dataset))) dataset[[v]] <- NA

# ---------------------------------------------------------------------
# 4b. Opción MÚLTIPLE: en el export WIDE vienen partidas (prefijo_opcion, 0/1).
#     n_<preg>   = cuántas opciones marcó (suma de las columnas)
#     otro_<preg> = 1 si marcó la opción 888 (Otro)   -> robusto si la columna no existe
# ---------------------------------------------------------------------
multiples <- c("p3_asociacion","p13_lugar_compra","p14_con_quien",
               "p15_ocasion_ligera","p16_ocasion_regular","p20_motivo_eleccion")
for (m in multiples) {
  cols <- grep(paste0("^", m, "_[0-9]+$"), names(dataset), value = TRUE)   # p3_asociacion_1, _888, ...
  # Reduce(`+`) por el mismo motivo que arriba: rowSums(sapply(...)) se rompe si
  # hay una sola fila, o si la pregunta trae una sola columna de opción.
  # (%in% ya devuelve FALSE en los NA, así que no hace falta na.rm.)
  dataset[[paste0("n_", m)]] <- if (length(cols))
    Reduce(`+`, lapply(dataset[cols], function(x) as.integer(x %in% c(1, "1")))) else 0L
  c888 <- paste0(m, "_888")
  dataset[[paste0("otro_", m)]] <- if (c888 %in% names(dataset))
    as.integer(dataset[[c888]] %in% c(1, "1")) else 0L
}

# ---------------------------------------------------------------------
# 5. Perfil / screening  (cumple_perfil = 1 si califica)
# ---------------------------------------------------------------------
alertas <- dataset %>%
  mutate(cumple_perfil = flag(consentimiento == 1 & s1_edad == 1 & s2_residencia == 1))

# Alertas
# ---------------------------------------------------------------------
# 1) MISSINGS (m_*): 1 si le faltó una respuesta que SÍ correspondía
# ---------------------------------------------------------------------
# 1a) Obligatorias (se piden a todos los que califican)
oblig_siempre <- c(
  "p1_celular",
  "p1_celular_confirma",
  "nombre_apellido",
  "p2_top_of_mind",
  "p4_consumo_habitual",
  "p4_1_frecuencia",
  "p5_edad",
  "p6_genero",
  "p7_zona",
  "p8_educacion",
  "p9_situacion_laboral",
  "p10_estado_civil_hijos",
  "p11_tipo_actividad",
  "p12_importancia_salud",
  "p17_motivo_1",
  "p18_por_que",
  "p19c_autoconcepto",
  "p19d_red_social",
  "p21_cambio_marca",
  "p22_probabilidad_recompra",
  "p22b_sensibilidad_precio",
  "p23_refrescancia",
  "p23_no_pesadez",
  "p23_sabor_cervecero",
  "p23_precio_calidad",
  "p23_imagen_premium",
  "p24_refrescancia",
  "p24_no_pesadez",
  "p24_sabor_cervecero",
  "p24_precio_calidad",
  "p24_imagen_premium",
  "p25_recuerda_campana",
  "p26_tipo_contenido",
  "p27_interes_grupo_focal"
)
alertas <- alertas %>%
  mutate(across(any_of(oblig_siempre),
                ~ flag(cumple_perfil == 1 & vacio(.x)), .names = "m_{.col}"))

# 1b) Condicionales: solo correspondían si se dio la condición
alertas <- alertas %>%
  mutate(
    m_p4_otra_especificar   = flag(p4_consumo_habitual == 888 & vacio(p4_otra_especificar)),
    m_p7_otra_especificar   = flag(p7_zona            == 888 & vacio(p7_otra_especificar)),
    m_p8_otra_especificar   = flag(p8_educacion       == 888 & vacio(p8_otra_especificar)),
    m_p9_otra_especificar   = flag(p9_situacion_laboral == 888 & vacio(p9_otra_especificar)),
    m_p11_otra_especificar  = flag(p11_tipo_actividad == 888 & vacio(p11_otra_especificar)),
    m_p14_otra_especificar  = flag(otro_p14_con_quien == 1 & vacio(p14_otra_especificar)),
    m_p19_marca_persona     = flag(cumple_perfil == 1 & arquetipo_consumo_habitual != "mainstream" & vacio(p19_marca_persona)),
    m_p19_generico_persona  = flag(cumple_perfil == 1 & arquetipo_consumo_habitual == "mainstream" & vacio(p19_generico_persona)),
    m_p19c_otra_especificar = flag(p19c_autoconcepto  == 888 & vacio(p19c_otra_especificar)),
    m_p20_otra_especificar  = flag(otro_p20_motivo_eleccion == 1 & vacio(p20_otra_especificar)),
    m_p21a_motivo_cambio    = flag(p21_cambio_marca   == 1   & vacio(p21a_motivo_cambio)),
    m_p21a_otra_especificar = flag(p21a_motivo_cambio == 888 & vacio(p21a_otra_especificar)),
    m_p22c_umbral_precio    = flag(p22b_sensibilidad_precio %in% c(4, 5) & vacio(p22c_umbral_precio)),
    m_p25a_cual_campana     = flag(p25_recuerda_campana == 1 & vacio(p25a_cual_campana)),
    m_p26_otra_especificar  = flag(p26_tipo_contenido  == 888 & vacio(p26_otra_especificar)),
    m_p3_otra_especificar   = flag(otro_p3_asociacion == 1     & vacio(p3_otra_especificar)),
    m_p10_otra_especificar  = flag(p10_estado_civil_hijos == 888                       & vacio(p10_otra_especificar)),
    m_p13_otra_especificar  = flag(otro_p13_lugar_compra == 1   & vacio(p13_otra_especificar)),
    m_p15_otra_especificar  = flag(otro_p15_ocasion_ligera == 1 & vacio(p15_otra_especificar)),
    m_p16_otra_especificar  = flag(otro_p16_ocasion_regular == 1& vacio(p16_otra_especificar)),
    m_p17_otra_especificar  = flag((p17_motivo_1 == 888 | p17_motivo_2 == 888 | p17_motivo_3 == 888) & vacio(p17_otra_especificar)),
    m_p19d_otra_especificar = flag(p19d_red_social == 888 & vacio(p19d_otra_especificar)),
    m_p3_asociacion       = flag(cumple_perfil == 1 & n_p3_asociacion == 0),
    m_p13_lugar_compra    = flag(cumple_perfil == 1 & n_p13_lugar_compra == 0),
    m_p14_con_quien       = flag(cumple_perfil == 1 & n_p14_con_quien == 0),
    m_p15_ocasion_ligera  = flag(cumple_perfil == 1 & n_p15_ocasion_ligera == 0),
    m_p16_ocasion_regular = flag(cumple_perfil == 1 & n_p16_ocasion_regular == 0),
    m_p20_motivo_eleccion = flag(cumple_perfil == 1 & n_p20_motivo_eleccion == 0)
  ) %>%
  mutate(ale_missing_total = rowSums(across(starts_with("m_")), na.rm = TRUE))

# ---------------------------------------------------------------------
# 2) OUTLIERS de duración (out_*)
# ---------------------------------------------------------------------
# (PILOTO) OUTLIERS de duración no activos hasta que pase el piloto
# alertas <- alertas %>%
#   mutate(
#     out_duracion_speeding = flag(as.numeric(duration_min) < DUR_MIN_SPEEDING),
#     out_duracion_larga    = flag(as.numeric(duration_min) > DUR_MAX_MIN),
#     ale_duracion_total    = rowSums(across(starts_with("out_")), na.rm = TRUE)
#   )

# ---------------------------------------------------------------------
# 3) DUPLICADOS (norm_* + dup_*): sobre todo TELÉFONO, y correo / nombre
# ---------------------------------------------------------------------
alertas <- alertas %>%
  mutate(
    norm_telefono = str_remove_all(as.character(p1_celular), "\\D"),          # solo dígitos
    norm_correo   = tolower(trimws(correo)),
    norm_nombre   = str_squish(stri_trans_general(str_to_upper(nombre_apellido), "Latin-ASCII")),
    dup_telefono  = flag(!vacio(norm_telefono) & (duplicated(norm_telefono) | duplicated(norm_telefono, fromLast = TRUE))),
    dup_correo    = flag(!vacio(norm_correo)   & (duplicated(norm_correo)   | duplicated(norm_correo, fromLast = TRUE))),
    dup_nombre    = flag(!vacio(norm_nombre)   & (duplicated(norm_nombre)   | duplicated(norm_nombre, fromLast = TRUE))),
    ale_duplicado_total = rowSums(across(starts_with("dup_")), na.rm = TRUE)
  )

# ---------------------------------------------------------------------
# 4) OTRAS alertas de calidad (como el celular, edad, código, exceso, tipo dato)
# ---------------------------------------------------------------------
alertas <- alertas %>%
  mutate(
    ale_celular = flag(!vacio(p1_celular) &
                    !str_detect(as.character(p1_celular), "^09[0-9]{8}$")),   # móvil PY: 09 + 8 dígitos
    ale_telefono_noconfirma = flag(p1_celular_confirma == 0),   # el encuestador marcó que el número NO es correcto
    ale_correo = flag(cumple_perfil == 1 &
                    (vacio(correo) |
                     !str_detect(tolower(trimws(as.character(correo))),
                                 "^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$"))),  # correo faltante o con formato inválido
    ale_edad = flag(!is.na(as.numeric(p5_edad)) &
                    (as.numeric(p5_edad) < 25 | as.numeric(p5_edad) > 40)),
    ale_codigo = flag(!vacio(codigo_encuestador) &
                    !(toupper(trimws(codigo_encuestador)) %in% CODIGOS_VALIDOS)),
    ale_exceso_seleccion = flag(
      n_p3_asociacion > 2 | n_p13_lugar_compra > 3 | n_p15_ocasion_ligera > 3 |
      n_p16_ocasion_regular > 3 | n_p20_motivo_eleccion > 3),
    # P17 top-3: motivo repetido (no debería marcar la misma opción en 1º/2º/3º)
    ale_p17_repetido = flag(
      (p17_motivo_1 == p17_motivo_2 & !vacio(p17_motivo_2)) |
      (p17_motivo_1 == p17_motivo_3 & !vacio(p17_motivo_3)) |
      (p17_motivo_2 == p17_motivo_3 & !vacio(p17_motivo_2) & !vacio(p17_motivo_3)))
    # ale_tipo_dato ya viene calculada del paso 2
  )

# ---------------------------------------------------------------------
# TOTAL de alertas + resumen de
# ---------------------------------------------------------------------
alertas <- alertas %>%
  mutate(
    ale_totales = ifelse(
      ale_missing_total    != 0 |
      ale_duplicado_total  != 0 |
      ale_celular          != 0 |
      ale_telefono_noconfirma != 0 |
      ale_correo           != 0 |
      ale_edad             != 0 |
      ale_codigo           != 0 |
      ale_exceso_seleccion != 0 |
      ale_p17_repetido     != 0 |
      ale_tipo_dato        != 0 |
      cumple_perfil        == 0, 1, 0
    ),
    aprobada = ifelse(ale_totales == 0, 1, 0)   # 1 = supera TODOS los filtros
  )

# ---------------------------------------------------------------------
# Ordenar columnas: ID y veredicto al frente, metadatos, preguntas en el
# orden del instrumento, y todas las columnas de auditoría al final.
# ---------------------------------------------------------------------
source("scripts/00_labels.R")            # define ordenar_columnas()
alertas <- ordenar_columnas(alertas)

# ---------------------------------------------------------------------
# Guardar base auditada (local) + resumen por tipo de alerta
# ---------------------------------------------------------------------
dir.create("data/02_auditadas", showWarnings = FALSE, recursive = TRUE)
fecha <- Sys.Date()
base  <- paste0("data/02_auditadas/auditadas_campo_", fecha)

save(alertas, file = paste0(base, ".RData"))              # RData
write_csv(as_tibble(alertas), paste0(base, ".csv"))       # CSV
writexl::write_xlsx(alertas, paste0(base, ".xlsx"), col_names = TRUE)   # Excel
try(haven::write_sav(alertas, paste0(base, ".sav")))      # SPSS
try(haven::write_dta(alertas, paste0(base, ".dta")))      # Stata

resumen <- alertas %>%
  summarise(
    califican     = sum(cumple_perfil, na.rm = TRUE),
    con_missing   = sum(ale_missing_total  != 0, na.rm = TRUE),
    con_duplicado = sum(ale_duplicado_total != 0, na.rm = TRUE),
    con_celular   = sum(ale_celular, na.rm = TRUE),
    con_tel_noconf = sum(ale_telefono_noconfirma, na.rm = TRUE),
    con_correo    = sum(ale_correo, na.rm = TRUE),
    con_edad      = sum(ale_edad, na.rm = TRUE),
    con_codigo    = sum(ale_codigo, na.rm = TRUE),
    con_exceso    = sum(ale_exceso_seleccion, na.rm = TRUE),
    con_p17_rep   = sum(ale_p17_repetido, na.rm = TRUE),
    con_tipo_dato = sum(ale_tipo_dato, na.rm = TRUE),
    aprobadas     = sum(aprobada, na.rm = TRUE),
    a_revisar     = sum(ale_totales, na.rm = TRUE)
  )

# para validar que todo corrió oki 
cat("\n---------------- RESUMEN DE AUDITORIA ----------------\n")
print(as.data.frame(resumen))
cat(sprintf("\n[OK] Base auditada guardada en data/02_auditadas/ (%s)\n", fecha))

# ---------------------------------------------------------------------
# Reporte de auditoría (.txt): legible para el equipo (no técnico)
# ---------------------------------------------------------------------
rep_path <- paste0("data/02_auditadas/reporte_auditoria_campo_", fecha, ".txt")

# Incidencias por pregunta/tipo: missings (m_*) + alertas (ale_*), solo con casos
inc <- c(
  unlist(alertas %>% summarise(across(starts_with("m_"),   ~ sum(.x, na.rm = TRUE)))),
  unlist(alertas %>% summarise(across(starts_with("ale_"), ~ sum(.x, na.rm = TRUE))))
)
inc <- sort(inc[inc > 0], decreasing = TRUE)

# Reforzamiento por encuestador: código con más casos a revisar
por_enc <- alertas %>%
  filter(!vacio(codigo_encuestador)) %>%
  group_by(codigo = toupper(trimws(codigo_encuestador))) %>%
  summarise(casos = n(), a_revisar = sum(ale_totales, na.rm = TRUE), .groups = "drop") %>%
  mutate(pct = round(100 * a_revisar / pmax(casos, 1), 1)) %>%
  arrange(desc(a_revisar))

tot <- max(nrow(alertas), 1)
con <- file(rep_path, open = "w", encoding = "UTF-8")
writeLines(c(
  "=====================================================================",
  "  REPORTE DE AUDITORIA DE CAMPO - 1er levantamiento",
  paste0("  Fecha: ", fecha, "   |   Base: ", basename(archivo)),
  "=====================================================================",
  "",
  "1) ESTADISTICAS GENERALES",
  sprintf("   Registros totales .......... %d", nrow(alertas)),
  sprintf("   Califican (perfil) ......... %d", sum(alertas$cumple_perfil, na.rm = TRUE)),
  sprintf("   Aprobadas .................. %d (%.1f%%)",
          sum(alertas$aprobada, na.rm = TRUE), 100 * sum(alertas$aprobada, na.rm = TRUE) / tot),
  sprintf("   A revisar .................. %d (%.1f%%)",
          sum(alertas$ale_totales, na.rm = TRUE), 100 * sum(alertas$ale_totales, na.rm = TRUE) / tot),
  "",
  "2) INCIDENCIAS POR PREGUNTA / TIPO (solo con casos, de mayor a menor)",
  if (length(inc)) paste0("   ", format(names(inc), width = 28), "  ", inc) else "   (sin incidencias)",
  "",
  "3) CASOS ATIPICOS DE DURACION",
  "   (PILOTO) Sin control de duracion todavia: se calibra al cerrar el piloto.",
  "   Por ahora estos casos NO se descuentan del tiempo promedio.",
  "",
  "4) CORREOS FALTANTES / INVALIDOS",
  sprintf("   Casos con correo faltante o con formato invalido: %d",
          sum(alertas$ale_correo, na.rm = TRUE)),
  "",
  "5) SUGERENCIAS DE REFORZAMIENTO (por encuestador)"
), con)
if (nrow(por_enc)) {
  writeLines(sprintf("   %-8s casos=%-4d a_revisar=%-4d (%.1f%%)",
                     por_enc$codigo, por_enc$casos, por_enc$a_revisar, por_enc$pct), con)
  top <- por_enc %>% filter(a_revisar > 0) %>% head(3)
  if (nrow(top)) writeLines(c("", "   -> Reforzar prioritariamente:",
                              paste0("      ", top$codigo, " (", top$a_revisar, " casos a revisar)")), con)
} else {
  writeLines("   (sin codigo de encuestador registrado)", con)
}
close(con)
cat(sprintf("[OK] Reporte de auditoria guardado en %s\n", rep_path))
