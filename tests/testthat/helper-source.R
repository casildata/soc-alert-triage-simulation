# The helpers use repository-relative paths, so source them from the root
local({
  owd <- setwd(file.path("..", ".."))
  on.exit(setwd(owd))
  for (f in c("R/params.R", "R/validate.R", "R/metrics.R", "R/model.R")) source(f)
})
