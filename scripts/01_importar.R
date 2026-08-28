# =====================================================================
# 01_importar.R  —  SurveyCTO (API)  ->  data/01_crudas (local)
# NOTA: este script solo TRAE los datos y los guarda en local (data/01_crudas/).
#       La subida a Google Drive/cruda la hace 04_monitoreo_daily.R.
# =====================================================================


# 1. Instalar librerias ---------------------------------------------------------

#install.packages("pacman")

library(pacman)

p_load(tidyverse, 
       httr,
       jsonlite,
       googledrive,
       writexl,
       haven,
       stringr,
       labelled, 
       lubridate,
       gtsummary,
       googlesheets4)

# 2. Download de API ------------------------------------------------------------

## Conect to SurveyCTO ---------------------------------------------------------
servidor <- Sys.getenv('SURVEYCTO_SERVER')  
username <- Sys.getenv('SURVEYCTO_USER')    
password <- Sys.getenv('SURVEYCTO_PASS')
formid   <- Sys.getenv('SURVEYCTO_FORMID')   

if (any(c(servidor, username, password, formid) == '')) {
  stop('Faltan credenciales de SurveyCTO. Completá tu `.Renviron` y reiniciá R (Session > Restart R).')
}

API <- paste0('https://',servidor,'.surveycto.com/api/v2/forms/data/wide/json/',formid,'?date=0')

# 3. Import data ----------------------------------------------------------------
# Método POST (como la versión de Piero). add_headers(Expect = "") evita el error 417
# (SurveyCTO rechaza el encabezado 'Expect: 100-continue').
dataset_json <- POST(
  url = API,
  authenticate(username, password),
  add_headers("Content-Type" = "application/json", "Expect" = ""),
  encode = "json"
)
if (status_code(dataset_json) != 200)
  stop('Error de la API de SurveyCTO (', status_code(dataset_json), '). Revisá credenciales / formid.')

# 4. Convertir JSON a data frame ------------------------------------------------
dataset <- jsonlite::fromJSON(rawToChar(dataset_json$content), flatten = TRUE)
dataset <- as.data.frame(dataset)
cat(sprintf('Submissions recibidas: %d\n', nrow(dataset)))

# Si todavía no hay submissions, avisar y no intentar guardar.
if (nrow(dataset) == 0) {
  message('Todavía no hay datos en el formulario. Nada para guardar.')
} else {

# 5. Modificación del Dataset  --------------------------------------------------
dataset <- dataset %>%
  dplyr::mutate(ID = sprintf('ENCUESTA_%05d', row_number()))

# 5b. Versión ETIQUETADA (value + variable labels) para SPSS y Stata ------------
# aplicar_labels() coerce las codificadas a numérica y les pone labels; es robusta
# a columnas ausentes (data vieja / múltiples partidas), así que no rompe.
source('scripts/00_labels.R')            # define aplicar_labels()

dataset <- ordenar_columnas(dataset)     # columnas en el orden del instrumento

dataset_lab <- aplicar_labels(dataset)
# Stata limita las etiquetas de VARIABLE a 80 caracteres -> truncar solo para el .dta
dataset_dta <- dataset_lab
var_label(dataset_dta) <- lapply(var_label(dataset_lab),
                                 function(x) if (!is.null(x)) substr(x, 1, 80) else x)


# 6. Guardar en diferentes formatos ---------------------------------------------

dir.create('data/01_crudas', showWarnings = FALSE, recursive = TRUE)


## Rdata
save(
  dataset,
  file = paste0('data/01_crudas/cruda_campo_', Sys.Date(), '.RData')
)

## SPSS  (con labels; try: nombres/tipos del API a veces rompen el .sav; no debe cortar el resto)
try(haven::write_sav(
  dataset_lab,
  path = paste0('data/01_crudas/cruda_campo_', Sys.Date(), '.sav')
))

## Stata (con labels; version = 14 -> compatible Stata 14+ y UTF-8; try: idem .sav)
try(haven::write_dta(
  dataset_dta,
  path = paste0('data/01_crudas/cruda_campo_', Sys.Date(), '.dta'),
  version = 14
))

## Excel
writexl::write_xlsx(
  dataset,
  path = paste0('data/01_crudas/cruda_campo_', Sys.Date(), '.xlsx'),
  col_names = T
)

## CSV
write.csv(
  dataset,
  file = paste0('data/01_crudas/cruda_campo_', Sys.Date(), '.csv'),
  row.names = FALSE
)

}   # fin del else

# 7. Limpieza del Entorno -------------------------------------------------------

rm(list = ls())

