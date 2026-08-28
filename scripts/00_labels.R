# =====================================================================
# 00_labels.R  —  diccionario del instrumento
#
# Define dos cosas que el resto del pipeline reutiliza:
#   aplicar_labels(df)     value labels + variable labels (.sav / .dta / tablero)
#   ordenar_columnas(df)   reordena las columnas siguiendo el cuestionario
#
# Ambas son robustas a columnas ausentes (usan intersect), así que sirven
# igual para una base cruda, una auditada o un subconjunto para el tablero.
# Se usan desde 01_importar.R, 02_auditoria.R y 05_monitoreo_hourly.R.
#
# ---------------------------------------------------------------------
# NOTA SOBRE ESTA VERSIÓN PÚBLICA
#
# El diccionario real —enunciados de las preguntas y texto de las opciones
# de respuesta— es propiedad del cliente y NO se versiona acá. Lo que queda
# es la ESTRUCTURA: qué variables existen, cuántas opciones tiene cada una,
# qué códigos especiales usa y en qué orden van.
#
# Las etiquetas son marcadores genéricos ("Opción 1", "Nivel 3"). El
# mecanismo es idéntico al de producción: reemplazando las etiquetas por
# las reales, el pipeline funciona sin tocar una línea más.
# ---------------------------------------------------------------------
# Códigos especiales del estudio:
#   888 = Otro (especificar)
#   777 = No conoce la marca  (respuesta válida, no es un missing)
#   999 = Sin respuesta
# =====================================================================
library(labelled)
library(tidyverse)

# 1. Etiquetas -------------------------------------------------------------

aplicar_labels <- function(df) {

  # --- Escalas genéricas ---
  si_no <- c("Sí" = 1, "No" = 0)

  # Escala de valoración de 1 a 5
  escala_5 <- setNames(1:5, paste("Nivel", 1:5))

  # Escala de valoración con la salida "no conoce la marca"
  escala_5_nc <- c(escala_5, "No conoce la marca" = 777)

  # opciones(k): pregunta nominal de k opciones, con o sin "Otro"
  opciones <- function(k, otro = TRUE) {
    v <- setNames(seq_len(k), paste("Opción", seq_len(k)))
    if (otro) c(v, "Otro (especificar)" = 888) else v
  }

  # --- Value labels (opción única) ---
  # La cardinalidad de cada pregunta es la real; el texto no.
  value_labels <- list(
    confirma_encuestador       = si_no,
    consentimiento             = si_no,
    s1_edad                    = si_no,
    s2_residencia              = si_no,
    p1_celular_confirma        = si_no,
    p21_cambio_marca           = si_no,
    p25_recuerda_campana       = si_no,

    p4_consumo_habitual        = opciones(2),
    p4_1_frecuencia            = opciones(4, otro = FALSE),
    p6_genero                  = opciones(3, otro = FALSE),
    p7_zona                    = opciones(18),
    p8_educacion               = opciones(4),
    p9_situacion_laboral       = opciones(4),
    p10_estado_civil_hijos     = opciones(4),
    p11_tipo_actividad         = opciones(6),
    p12_importancia_salud      = escala_5,

    p17_motivo_1               = opciones(8),
    p17_motivo_2               = opciones(8),
    p17_motivo_3               = opciones(8),

    p19c_autoconcepto          = opciones(4),
    p19d_red_social            = opciones(5),
    p21a_motivo_cambio         = opciones(6),

    p22_probabilidad_recompra  = escala_5,
    p22b_sensibilidad_precio   = escala_5,
    p22c_umbral_precio         = opciones(5, otro = FALSE),

    # Batería de atributos evaluada para dos marcas (p23 = Marca A,
    # p24 = Marca B). Comparten escala, incluido el código 777.
    p23_refrescancia           = escala_5_nc,
    p23_no_pesadez             = escala_5_nc,
    p23_sabor_cervecero        = escala_5_nc,
    p23_precio_calidad         = escala_5_nc,
    p23_imagen_premium         = escala_5_nc,
    p24_refrescancia           = escala_5_nc,
    p24_no_pesadez             = escala_5_nc,
    p24_sabor_cervecero        = escala_5_nc,
    p24_precio_calidad         = escala_5_nc,
    p24_imagen_premium         = escala_5_nc,

    p26_tipo_contenido         = opciones(4),
    p27_interes_grupo_focal    = opciones(3, otro = FALSE)
  )

  # --- Variable labels ---
  # Los enunciados reales no se versionan: se genera un marcador uniforme
  # a partir del nombre de cada variable, respetando la numeración del
  # cuestionario. ORDEN_INSTRUMENTO se define más abajo en este archivo.
  var_labels <- setNames(
    lapply(ORDEN_INSTRUMENTO, function(v) {
      num <- str_match(v, "^p([0-9]+[a-z]?)")[, 2]
      if (is.na(num)) "Variable de control de campo"
      else paste0("P", toupper(num), ". Enunciado de la pregunta")
    }),
    ORDEN_INSTRUMENTO
  )

  # 1) coerción a numérica de las codificadas que estén presentes
  cod <- intersect(names(value_labels), names(df))
  if (length(cod))
    df <- df %>% mutate(across(all_of(cod), ~ suppressWarnings(as.numeric(.))))

  # 2) aplicar value labels SOLO a las columnas presentes
  for (v in cod) df[[v]] <- labelled(df[[v]], labels = value_labels[[v]])

  # 3) aplicar variable labels SOLO a las columnas presentes
  for (v in intersect(names(var_labels), names(df)))
    var_label(df[[v]]) <- var_labels[[v]]

  df
}





# 2. Ordenamiento de columnas ---------------------------------------------

# Problema: Al importar los datos de SCTO como JSON, las columnas de data.frame 
# no sigue necesarimente el orden del cuestionario o XLS. Más aún luego de 
# la auditoría esto puede generar que se desordene aún más.

# Solución: Crear una función que ordene las columnas seguiendo un orden
# específico y determinado por el asistente/consultor/especialista.
# Es importante que solo se ordenen las columnas, pero no se eliminen registros.

# La función es ordenar_columnas(df)

# y el ornde que seguirán las columnas es el siguiente:

#   1) ID y veredicto de la auditoría
#   2) metadatos de SurveyCTO (KEY, SubmissionDate, ...)
#   3) preguntas en el orden del instrumento
#   4) columnas no reconocidas (algo nuevo en SurveyCTO): se conservan
#   5) columnas de auditoría (norm_, n_, otro_, m_, out_, dup_, ale_)

ORDEN_INSTRUMENTO <- c(
  "codigo_encuestador", "confirma_encuestador", "consentimiento",
  "s1_edad", "s2_residencia", "screening_ok",
  "p1_celular", "p1_celular_confirma", "nombre_apellido", "correo",
  "p2_top_of_mind",
  "p3_asociacion", "p3_otra_especificar",
  "p4_consumo_habitual", "p4_otra_especificar", "p4_1_frecuencia",
  "arquetipo_consumo_habitual",
  "p5_edad", "p6_genero",
  "p7_zona", "p7_otra_especificar",
  "p8_educacion", "p8_otra_especificar",
  "p9_situacion_laboral", "p9_otra_especificar",
  "p10_estado_civil_hijos", "p10_otra_especificar",
  "p11_tipo_actividad", "p11_otra_especificar",
  "p12_importancia_salud",
  "p13_lugar_compra", "p13_otra_especificar",
  "p14_con_quien", "p14_otra_especificar",
  "p15_ocasion_ligera", "p15_otra_especificar",
  "p16_ocasion_regular", "p16_otra_especificar",
  "p17_motivo_1", "p17_motivo_2", "p17_motivo_3", "p17_otra_especificar",
  "p18_por_que",
  "p19_marca_persona", "p19_generico_persona",
  "p19c_autoconcepto", "p19c_otra_especificar",
  "p19d_red_social", "p19d_otra_especificar",
  "p20_motivo_eleccion", "p20_otra_especificar",
  "p21_cambio_marca", "p21a_motivo_cambio", "p21a_otra_especificar",
  "p22_probabilidad_recompra", "p22b_sensibilidad_precio", "p22c_umbral_precio",
  "p23_refrescancia", "p23_no_pesadez", "p23_sabor_cervecero",
  "p23_precio_calidad", "p23_imagen_premium",
  "p24_refrescancia", "p24_no_pesadez", "p24_sabor_cervecero",
  "p24_precio_calidad", "p24_imagen_premium",
  "p25_recuerda_campana", "p25a_cual_campana",
  "p26_tipo_contenido", "p26_otra_especificar",
  "p27_interes_grupo_focal"
)


ordenar_columnas <- function(df) {

  cols <- names(df)

  frente <- intersect(c("ID", "aprobada", "cumple_perfil"), cols)

  meta <- intersect(c("KEY", "SubmissionDate", "CompletionDate", "starttime",
                      "endtime", "duration", "duration_min", "caseid",
                      "username", "deviceid", "subscriberid", "simid",
                      "devicephonenum", "formdef_version", "review_status",
                      "review_quality", "review_comments", "instanceID"), cols)

  # Para cada pregunta: la columna exacta y su familia de opción múltiple,
  # ordenada por el sufijo NUMÉRICO (así _2 va antes de _10; ordenado como
  # texto quedaría al revés).
  preguntas <- character(0)
  for (v in ORDEN_INSTRUMENTO) {
    fam <- cols[str_detect(cols, paste0("^", v, "_[0-9]+$"))]
    if (length(fam) > 1)
      fam <- fam[order(as.numeric(str_extract(fam, "[0-9]+$")))]
    preguntas <- c(preguntas, cols[cols == v], fam)
  }

  # Auditoría: agrupada por familia y, dentro de cada familia, también en el
  # orden del instrumento (m_p1_celular antes de m_p27..., no alfabético).
  auditoria <- character(0)
  for (p in c("norm_", "n_", "otro_", "m_", "out_", "dup_", "ale_")) {
    fam <- setdiff(cols[startsWith(cols, p)], auditoria)
    if (length(fam)) {
      base <- substring(fam, nchar(p) + 1)
      auditoria <- c(auditoria, fam[order(match(base, ORDEN_INSTRUMENTO), base)])
    }
  }

  orden <- unique(c(frente, meta, preguntas))
  audit <- setdiff(auditoria, orden)
  resto <- setdiff(cols, c(orden, audit))
  final <- c(orden, resto, audit)

  # Red de seguridad: si alguna columna se perdiera o duplicara, corta acá.
  stopifnot(setequal(final, cols), !anyDuplicated(final))

  dplyr::select(df, dplyr::all_of(final))
}
