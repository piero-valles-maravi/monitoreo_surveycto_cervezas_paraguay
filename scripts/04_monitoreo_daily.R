# =====================================================================
# 04_monitoreo_daily.R  —  sube CRUDAS y AUDITADAS a Google Drive
# =====================================================================

library(pacman)
p_load(tidyverse, googledrive, writexl, haven, lubridate)

# ---------------------------------------------------------------------
# 1. Autenticación con la CUENTA DE SERVICIO (Drive)
#    Local:   GDRIVE_SA en .Renviron apunta al .json (ej: .secrets/gdrive_sa.json)
#    Actions: GitHub inyecta el .json y define GDRIVE_SA con su ruta
# ---------------------------------------------------------------------
sa <- Sys.getenv("GDRIVE_SA")
if (!nzchar(sa) || !file.exists(sa))
  stop("No encuentro el JSON de la cuenta de servicio. Defini GDRIVE_SA en tu .Renviron apuntando al archivo .json (o se inyecta solo en GitHub Actions).")
drive_auth(path = sa)

# ---------------------------------------------------------------------
# 2. Carpetas de Drive (desde .Renviron, no en el script)
# ---------------------------------------------------------------------
url_crudas    <- Sys.getenv("DRIVE_CRUDA_URL")
url_auditoria <- Sys.getenv("DRIVE_AUDITORIA_URL")
if (url_crudas == "" || url_auditoria == "")
  stop("Faltan DRIVE_CRUDA_URL / DRIVE_AUDITORIA_URL en el .Renviron.")

folder_crudas    <- drive_get(url_crudas)
folder_auditoria <- drive_get(url_auditoria)

# Sube `ruta` a `folder` solo si el archivo existe.
# drive_put = actualiza el archivo EN SU LUGAR si ya existe, o lo crea si no.
# (no manda nada a la papelera -> funciona con rol "Colaborador" en Unidad compartida)
subir <- function(ruta, folder, ...) {
  if (file.exists(ruta)) {
    drive_put(media = ruta, path = as_id(folder), name = basename(ruta), ...)
  } else {
    message("Salteado (no existe): ", basename(ruta))
  }
}

fecha <- Sys.Date()

# ---------------------------------------------------------------------
# 3. CRUDAS  ->  Drive/cruda
# ---------------------------------------------------------------------
cru <- paste0("data/01_crudas/cruda_campo_", fecha)
subir(paste0(cru, ".RData"), folder_crudas)
subir(paste0(cru, ".xlsx"),  folder_crudas)
subir(paste0(cru, ".sav"),   folder_crudas)
subir(paste0(cru, ".dta"),   folder_crudas)
subir(paste0(cru, ".csv"),   folder_crudas)
# versión Google Sheet de la cruda
if (file.exists(paste0(cru, ".csv"))) {
  drive_put(media = paste0(cru, ".csv"), name = paste0("cruda_campo_", fecha),
            type = "spreadsheet", path = as_id(folder_crudas))
}

# ---------------------------------------------------------------------
# 4. AUDITADAS  ->  Drive/auditoria
# ---------------------------------------------------------------------
aud <- paste0("data/02_auditadas/auditadas_campo_", fecha)
subir(paste0(aud, ".RData"), folder_auditoria)
subir(paste0(aud, ".xlsx"),  folder_auditoria)
subir(paste0(aud, ".sav"),   folder_auditoria)
subir(paste0(aud, ".dta"),   folder_auditoria)
subir(paste0(aud, ".csv"),   folder_auditoria)
# versión Google Sheet de la auditada
if (file.exists(paste0(aud, ".csv"))) {
  drive_put(media = paste0(aud, ".csv"), name = paste0("auditadas_campo_", fecha),
            type = "spreadsheet", path = as_id(folder_auditoria))
}

# ---------------------------------------------------------------------
# 5. Limpieza del entorno
# ---------------------------------------------------------------------
rm(list = ls())
