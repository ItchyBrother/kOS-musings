// lambert.ks — Simple universal variable Lambert solver for intercept
// Inputs: r1 (current position vector, VEC), r2 (target position at TOF, VEC), tof (time of flight, seconds), mu (BODY:MU)
// Returns: v1 (required velocity at r1, VEC)
// Assumes short-way transfer, single rev. Handles elliptic/hyperbolic.
// Adapted from universal variable method (Vallado algorithm 5-6)

FUNCTION LAMBERT_V1 {
  PARAMETER r1_vec, r2_vec, tof, mu.

  LOCAL r1 IS r1_vec:MAG.
  LOCAL r2 IS r2_vec:MAG.
  LOCAL c_vec IS r2_vec - r1_vec.
  LOCAL c IS c_vec:MAG.
  LOCAL cos_theta IS VDOT(r1_vec, r2_vec) / (r1 * r2).
  LOCAL theta IS ARCCOS(cos_theta).
  // Assume short way; if VDOT(VCROSS(r1_vec, r2_vec), facing) <0, theta = 360 - theta for long way (add if needed)

  LOCAL A IS SQRT(r1 * r2 * (1 - COS(theta))).
  IF A = 0 { RETURN V(0,0,0). } // Collinear, handle separately if needed

  LOCAL psi IS 0.
  LOCAL psi_low IS -4*CONSTANT:PI.
  LOCAL psi_up IS 4*CONSTANT:PI.
  LOCAL iter IS 0.
  
  // Pre-declare loop vars outside to ensure scope
  LOCAL c2 IS 0.5.
  LOCAL c3 IS 1/6.
  LOCAL y IS 0.
  LOCAL chi IS 0.
  LOCAL tof_calc IS 0.

  UNTIL iter > 100 {
    LOCAL sqrt_psi IS SQRT(ABS(psi)).
    IF psi > 1e-6 {
      LOCAL cos_sqrt IS COS(sqrt_psi).
      LOCAL sin_sqrt IS SIN(sqrt_psi).
      SET c2 TO (1 - cos_sqrt) / psi.
      SET c3 TO (sqrt_psi - sin_sqrt) / (sqrt_psi^3).
    } ELSE IF psi < -1e-6 {
      LOCAL cosh_sqrt IS COSH(SQRT(-psi)).
      LOCAL sinh_sqrt IS SINH(SQRT(-psi)).
      SET c2 TO (cosh_sqrt - 1) / (-psi).
      SET c3 TO (sinh_sqrt - SQRT(-psi)) / SQRT((-psi)^3).
    }

    SET y TO r1 + r2 + A * (psi * c3 - 1) / SQRT(c2).
    IF A > 0 AND y < 0 { SET y TO 0. } // Clamp if needed

    SET chi TO SQRT(y / c2).
    SET tof_calc TO (chi^3 * c3 + A * SQRT(y)) / SQRT(mu).

    IF tof_calc < tof {
      SET psi_low TO psi.
    } ELSE {
      SET psi_up TO psi.
    }
    SET psi TO (psi_low + psi_up) / 2.
    SET iter TO iter + 1.
    IF ABS(tof_calc - tof) < 1e-5 { BREAK. }
  }

  IF ABS(tof_calc - tof) > 1e-5 { 
    PRINT "Lambert did not converge.".
    LOG "Time: " + ROUND(TIME:SECONDS, 2) + ", Lambert did not converge." TO "0:/dock_log.txt".
    RETURN V(0,0,0). 
  }

  LOCAL f IS 1 - y / r1.
  LOCAL g IS A * SQRT(y / mu).
  LOCAL v1 IS (r2_vec - f * r1_vec) / g.

  RETURN v1.
}

// Helper to execute DV with RCS pulses (general direction)
FUNCTION EXECUTE_DV_RCS {
  PARAMETER dv_vec, pulse_dur IS 0.6, max_pulses IS 10, settle_t IS 1.0.

  LOCAL dir IS dv_vec:NORMALIZED.
  LOCAL dv_remain IS dv_vec:MAG.
  LOCAL pulses IS 0.
  LOCAL ref_v IS SHIP:VELOCITY:ORBIT.  // Reference velocity before any burns

  RCS ON.
  SAS OFF.
  LOCK STEERING TO dir.

  WAIT 2. // Settle steering

  UNTIL pulses >= max_pulses OR dv_remain < 0.5 {
    APP_PUSH_ALONG(dir, 0.7, pulse_dur). // Use your existing APP_PUSH_ALONG for world vec pulse
    
    WAIT settle_t.
    
    // Re-calculate remaining DV more accurately: target_v - current_v
    LOCAL current_v IS SHIP:VELOCITY:ORBIT.
    LOCAL achieved IS current_v - ref_v.
    LOCAL dv_remain IS (dv_vec - achieved):MAG.  // Vector subtraction for remaining
    
    SET pulses TO pulses + 1.
    
    // Optional: Log progress
    IF MOD(pulses, 2) = 0 {  // Every other pulse to avoid spam
      PRINT "Pulse " + pulses + ": DV remaining ≈ " + ROUND(dv_remain, 1) + " m/s.".
    }
  }

  UTL_KILL_TRANSLATION().
  PRINT "DV executed with " + pulses + " pulses (final remaining ≈ " + ROUND(dv_remain, 1) + " m/s).".
}