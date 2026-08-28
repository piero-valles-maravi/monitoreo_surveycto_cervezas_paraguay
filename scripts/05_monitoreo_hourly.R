# =====================================================================
# 05_monitoreo_hourly.R  —  auditada LOCAL  ->  labels  ->  Google Sheet (dashboard)
# =====================================================================

library(pacman)
p_load(tidyverse, googlesheets4, labelled, lubridate, stringr)

# ---------------------------------------------------------------------
# 1. Autenticación con la CUENTA DE SERVICIO (Google Sheets)
#    Local:   GDRIVE_SA en .Renviron apunta al .json (ej: .secrets/gdrive_sa.json)
#    Actions: GitHub inyecta el .json y define GDRIVE_SA con su ruta
# ---------------------------------------------------------------------
sa <- Sys.getenv("GDRIVE_SA")
if (!nzchar(sa) || !file.exists(sa))
  stop("No encuentro el JSON de la cuenta de servicio. Defini GDRIVE_SA en tu .Renviron apuntando al archivo .json (o se inyecta solo en GitHub Actions).")
gs4_auth(path = sa)

url_dashboard <- Sys.getenv("DASHBOARD_URL")
if (url_dashboard == "") stop("Falta DASHBOARD_URL en el .Renviron.")

# ---------------------------------------------------------------------
# 2. Cargar la auditada más reciente de data/02_auditadas  (objeto `alertas`)
# ---------------------------------------------------------------------
archivo <- tail(sort(list.files("data/02_auditadas",
                    pattern = "^auditadas_campo_.*\\.RData$", full.names = TRUE)), 1)
if (length(archivo) == 0) stop("No hay auditadas en data/02_auditadas. Corré 02_auditoria.R primero.")
load(archivo)                                  # -> alertas
cat("== 05 · MONITOREO HOURLY ==\nAuditada:", basename(archivo), "|", nrow(alertas), "filas\n")

# ---------------------------------------------------------------------
# 3. Aplicar labels legibles  (00_labels.R opera sobre `alertas`)
# ---------------------------------------------------------------------
source("scripts/00_labels.R")             # define aplicar_labels()
alertas <- aplicar_labels(alertas)
alertas_labels <- alertas %>% labelled::to_factor()

# Guardar también una copia legible en local (opcional, útil para revisar)
write_csv(as_tibble(alertas_labels),
          paste0("data/02_auditadas/auditadas_labels_", Sys.Date(), ".csv"))

# ---------------------------------------------------------------------
# 4. Escribir en el Google Sheet del tablero (tiempo real)
# ---------------------------------------------------------------------
sheet_write(as_tibble(alertas_labels), ss = url_dashboard, sheet = "Dashboard")
cat("[OK] Dashboard actualizado.\n")

# ---------------------------------------------------------------------
# 5. Limpieza del entorno
# ---------------------------------------------------------------------
rm(list = ls())
