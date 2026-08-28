# =====================================================================
# 03_limpieza.R  —  data/02_auditadas  ->  base limpia  ->  data/03_limpias
#
# Lee la base AUDITADA local (la que dejó el 02, objeto `alertas`), aplica las
# reglas de limpieza y guarda la base limpia `limpia`. La subida a Drive la
# hacen 04/05 (según cómo lo dejemos).
# =====================================================================

library(pacman)
p_load(tidyverse, lubridate, stringr)

# Ayuda chiquita: ¿celda vacía?
vacio <- function(x) is.na(x) | trimws(as.character(x)) %in% c("", "NA", "999")

# ---------------------------------------------------------------------
# 1. Cargar la auditada más reciente de data/02_auditadas  (objeto `alertas`)
# ---------------------------------------------------------------------
archivo <- tail(sort(list.files("data/02_auditadas",
                    pattern = "^auditadas_campo_.*\\.RData$", full.names = TRUE)), 1)
if (length(archivo) == 0) stop("No hay auditadas en data/02_auditadas. Corré 02_auditoria.R primero.")
load(archivo)                                  # -> alertas
n0 <- nrow(alertas)
cat("Limpiando:", basename(archivo), "|", n0, "registros auditados\n")

# ---------------------------------------------------------------------
# 2. Reglas de limpieza
# ---------------------------------------------------------------------
# 1) solo los que califican
limpia <- alertas %>% filter(cumple_perfil == 1)

# 2) recortar espacios en los campos de texto
limpia <- limpia %>% mutate(across(where(is.character), trimws))

# 3) eliminar celulares duplicados (deja el más reciente por SubmissionDate)
if ("SubmissionDate" %in% names(limpia)) limpia <- limpia[order(limpia$SubmissionDate), ]
limpia <- limpia[!duplicated(limpia$p1_celular, fromLast = TRUE) | vacio(limpia$p1_celular), ]

# 4) quitar las columnas auxiliares de la auditoría (dejar la base prolija)
limpia <- limpia %>%
  select(-starts_with("m_"), -starts_with("out_"), -starts_with("dup_"),
         -starts_with("ale_"),
         -any_of("cumple_perfil"), -starts_with("norm_"))

cat(sprintf("Casos: %d auditados -> %d limpios\n", n0, nrow(limpia)))

# ---------------------------------------------------------------------
# 3. Guardar base limpia (local)
# ---------------------------------------------------------------------
dir.create("data/03_limpias", showWarnings = FALSE, recursive = TRUE)
fecha <- Sys.Date()
save(limpia, file = paste0("data/03_limpias/limpias_campo_", fecha, ".RData"))
write_csv(limpia, paste0("data/03_limpias/limpias_campo_", fecha, ".csv"))
cat(sprintf("[OK] Base limpia guardada en data/03_limpias/ (%s)\n", fecha))
