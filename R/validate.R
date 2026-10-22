# Check a scenario's parameters before simulating, so an edit to R/params.R fails with a
# clear message instead of silently renormalized shares or NaN service times.

validate_params <- function(p) {
  sev <- c("high", "medium", "low")
  fail <- function(msg) stop(sprintf("Scenario '%s': %s", p$name, msg), call. = FALSE)
  whole <- function(x) length(x) == 1 && is.finite(x) && x >= 1 && x == round(x)

  if (!setequal(names(p$severity_mix), sev) || abs(sum(p$severity_mix) - 1) > 1e-8 ||
      any(p$severity_mix < 0)) {
    fail("severity_mix needs high, medium and low shares that sum to 1")
  }
  for (s in sev) {
    tt <- p$triage_time[[s]]
    if (length(tt) != 3 || any(!is.finite(tt)) || tt[1] < 0 || tt[1] > tt[2] || tt[2] > tt[3] ||
        tt[1] == tt[3]) {
      fail(sprintf("triage_time$%s must be (min, mode, max) with min <= mode <= max and min < max", s))
    }
  }
  tp <- p$true_positive_rate[sev]
  if (anyNA(tp) || any(tp < 0 | tp > 1)) {
    fail("true_positive_rate must be between 0 and 1 for high, medium and low")
  }
  if (!(p$alerts_per_hour > 0)) fail("alerts_per_hour must be positive")
  if (!isTRUE(p$priorities) && !isFALSE(p$priorities)) fail("priorities must be TRUE or FALSE")
  if (length(p$hourly_profile) != 24 || any(!is.finite(p$hourly_profile)) ||
      any(p$hourly_profile < 0) || !(sum(p$hourly_profile) > 0)) {
    fail("hourly_profile needs 24 non-negative values, not all zero")
  }
  if (!(p$fp_suppression >= 0) || p$fp_suppression > min(1 - tp)) {
    fail("fp_suppression must be between 0 and the false-positive share of every severity")
  }
  if (!(p$investigation_mean > 0) || !(p$investigation_shape > 0)) {
    fail("investigation_mean and investigation_shape must be positive")
  }
  shifts <- p$shift_start
  if (length(shifts) < 1 || shifts[1] != 0 || any(diff(shifts) <= 0) || any(shifts >= 24)) {
    fail("shift_start must be increasing hours of the day starting at 0")
  }
  for (k in c("tier1_analysts", "tier2_analysts")) {
    x <- p[[k]]
    if (!(length(x) %in% c(1, length(shifts))) || !all(vapply(x, whole, logical(1)))) {
      fail(sprintf("%s must be one whole number of at least 1, or one per shift", k))
    }
  }
  if (!is.null(p$flood)) {
    f <- p$flood
    if (!(f$rate >= 0) || !(f$minutes > 0) || !(f$plant_at >= 0 && f$plant_at < f$minutes) ||
        !(f$start >= 0)) {
      fail("flood needs a rate of at least 0, a positive length, a start time, and plant_at within the flood")
    }
  }
  if (!whole(p$balk_queue_length)) fail("balk_queue_length must be a whole number of at least 1")
  if (length(p$low_expiry) != 2 || p$low_expiry[1] < 0 || p$low_expiry[1] > p$low_expiry[2]) {
    fail("low_expiry must be (min, max) minutes with 0 <= min <= max")
  }
  invisible(TRUE)
}
