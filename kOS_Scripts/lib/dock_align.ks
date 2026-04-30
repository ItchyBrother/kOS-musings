// ===============================================================
// dock_align.ks — Step 4+5+6: stationkeep, align, final meters
// Requires: utils.ks, approach.ks (APP_* helpers).
// ===============================================================

SET DCK_V_AT_200M  TO 2.0.  // Target at 200m
SET DCK_V_AT_100M  TO 1.0.  // Target at 100m
SET DCK_V_AT_70M   TO 0.70. // Target at 70m
SET DCK_V_AT_55M   TO 0.50.  // Adjusted start of final taper for gentler braking
SET DCK_V_HOLD     TO 0.0.  // Final hold velocity at 50m (zero cvel)
SET DCK_V_MIN      TO 0.05. // Minimum non-zero for control
SET DCK_BIG_ERR    TO 0.5.
SET DCK_LONG_T     TO 0.5.  // Increased for stronger braking pulses
SET DCK_DEADBAND_V TO 0.2.
SET DCK_PULSE_COOLDOWN TO 1.2.

// Schedule helper - braking at 55m
FUNCTION DCK_VSCHEDULE {
  PARAMETER rng.
  IF rng >= 200 {
    LOCAL vset IS DCK_V_AT_200M * (rng / 200.0).
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE IF rng >= 100 {
    LOCAL frac IS (rng - 100) / (200 - 100).
    LOCAL vset IS DCK_V_AT_100M + frac * (DCK_V_AT_200M - DCK_V_AT_100M).
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE IF rng >= 70 {
    LOCAL frac IS (rng - 70) / (100 - 70).
    LOCAL vset IS DCK_V_AT_70M + frac * (DCK_V_AT_100M - DCK_V_AT_70M).
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE IF rng >= 55 {
    LOCAL frac IS (rng - 55) / (70 - 55).
    LOCAL vset IS DCK_V_AT_55M + frac * (DCK_V_AT_70M - DCK_V_AT_55M).
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE {
    IF rng > 50 {
      LOCAL frac IS (rng - 50) / (55 - 50).
      RETURN DCK_V_HOLD + frac * (DCK_V_AT_55M - DCK_V_HOLD).  // No clamp for braking
    } ELSE {
      RETURN DCK_V_HOLD.
    }
  }
}
// Safe port pose helpers (unchanged)
FUNCTION DCK_PORT_POS {
  PARAMETER x.
  IF x = "NONE" { RETURN SHIP:POSITION. }
  IF x:HASSUFFIX("PORTPOSITION") { RETURN x:PORTPOSITION. }
  IF x:HASSUFFIX("POSITION")     { RETURN x:POSITION. }
  IF x:HASSUFFIX("PART") AND x:PART:HASSUFFIX("POSITION") { RETURN x:PART:POSITION. }
  RETURN SHIP:POSITION.
}

FUNCTION DCK_PORT_UP {
  PARAMETER x.
  IF x:HASSUFFIX("PART") AND x:PART:HASSUFFIX("FACING") { RETURN x:PART:FACING:TOPVECTOR. }
  IF x:HASSUFFIX("FACING")                               { RETURN x:FACING:TOPVECTOR. }
  RETURN SHIP:FACING:TOPVECTOR.
}

// Pick my port by tag else first (unchanged)
FUNCTION DCK_GET_MY_PORT {
  PARAMETER tag IS "".
  IF SHIP:HASSUFFIX("DOCKINGPORTS") {
    LIST DOCKINGPORTS IN dps.
    IF tag <> "" {
      FOR dp IN dps {
        IF dp:HASSUFFIX("PART") AND dp:PART:HASSUFFIX("TAG") { IF dp:PART:TAG = tag { RETURN dp. } }
      }
    }
    IF dps:LENGTH > 0 { RETURN dps[0]. }
  }
  LIST PARTS IN ps.
  IF tag <> "" {
    FOR p IN ps {
      IF p:HASSUFFIX("TAG") AND p:TAG = tag AND p:HASSUFFIX("DOCKINGPORT") { RETURN p:DOCKINGPORT. }
    }
  }
  FOR p IN ps { IF p:HASSUFFIX("DOCKINGPORT") { RETURN p:DOCKINGPORT. } }
  RETURN "NONE".
}

// Pick target port by tag else first (unchanged)
FUNCTION DCK_GET_TGT_PORT {
  PARAMETER tag IS "".
  IF NOT HASTARGET { RETURN "NONE". }
  IF TARGET:HASSUFFIX("DOCKINGPORTS") {
    LOCAL tps IS TARGET:DOCKINGPORTS.
    IF tag <> "" {
      FOR tdp IN tps {
        IF tdp:HASSUFFIX("PART") AND tdp:PART:HASSUFFIX("TAG") { IF tdp:PART:TAG = tag { RETURN tdp. } }
      }
    }
    IF tps:LENGTH > 0 { RETURN tps[0]. }
  }
  IF TARGET:HASSUFFIX("PARTS") {
    LOCAL tps IS TARGET:PARTS.
    IF tag <> "" {
      FOR tp IN tps {
        IF tp:HASSUFFIX("TAG") AND tp:TAG = tag AND tp:HASSUFFIX("DOCKINGPORT") { RETURN tp:DOCKINGPORT. }
      }
    }
    FOR tp IN tps { IF tp:HASSUFFIX("DOCKINGPORT") { RETURN tp:DOCKINGPORT. } }
  }
  RETURN "NONE".
}

// Pulse wrapper
FUNCTION DCK_DRIVE {
  PARAMETER vErr, longOrPulse.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL gain IS 1.8.  // Increased to avoid F=0
  LOCAL dur IS 0.15.
  IF longOrPulse {
    SET gain TO 3.5.
    SET dur TO DCK_LONG_T.
  }
  IF vErr:MAG < 0.3 {
    SET gain TO gain * 0.5.
    SET dur TO MIN(0.08, dur).
  }
  LOCAL braking IS VDOT(vErr, SHIP:FACING:FOREVECTOR) < -0.1.
  IF braking {
    SET gain TO gain * 1.3.
    SET dur TO MIN(0.7, dur * 1.3).
  }
  LOCAL diag_vErr IS "DCK_DRIVE: Input vErr:MAG = " + ROUND(vErr:MAG, 2) + ", vErr = (" + ROUND(vErr:X, 2) + "," + ROUND(vErr:Y, 2) + "," + ROUND(vErr:Z, 2) + ").".
  DISP_LOG_UPDATE(diag_vErr).
  IF vErr:MAG < DCK_DEADBAND_V { 
    LOCAL diag_msg IS "DCK_DRIVE: Skipped, vErr:MAG = " + ROUND(vErr:MAG, 2) + " < " + DCK_DEADBAND_V.
    DISP_LOG_UPDATE(diag_msg).
    RETURN.
  }
  APP_DRIVE_RCS(vErr, gain, dur).
  LOCAL brake_label IS "".
  IF braking { SET brake_label TO " (BRAKING)". }
  LOCAL diag_msg IS "DCK_DRIVE: vErr:MAG = " + ROUND(vErr:MAG, 2) + ", dur=" + ROUND(dur, 3) + brake_label.
  DISP_LOG_UPDATE(diag_msg).
  UTL_KILL_TRANSLATION().
}

// ======= Public routines =======

// New: Backout to 200-400m if 'N' pressed
FUNCTION APP_BACKOUT_TO_WINDOW {
  PARAMETER near IS AP_WINDOW_NEAR, far IS AP_WINDOW_FAR.
  LOCAL msg0 IS "Operator aborted. Backing out to 200-400m window.".
  DISP_WARN(msg0).
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL nextPulseUT IS TIME:SECONDS.
  LOCAL backoutV IS -0.5.  // Gentle reverse velocity

  UNTIL TRUE {
    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].

    LOCK STEERING TO LOOKDIRUP(los, SHIP:UP:VECTOR).

    IF rng >= far { BREAK. }  // Reached window

    LOCAL vGoal IS los * backoutV.  // Negative for separation
    LOCAL vErr IS vGoal - vrel.

    IF TIME:SECONDS >= nextPulseUT AND vErr:MAG > DCK_DEADBAND_V {
      DCK_DRIVE(vErr, vErr:MAG > DCK_BIG_ERR).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    WAIT 0.12.
  }
  DCK_WINDOW_HOLD(near, far, AP_STATION_VHOLD, AP_HOLD_STABLE_S).
  RETURN TRUE.
}

// Initiate forward thrust to start approach from 200-400m
FUNCTION DCK_PUSH_FWD {
  PARAMETER maxTime IS 10, targetCvel IS 1.5.
  CLEARSCREEN.
  LOCAL msg0 IS "Initiating forward thrust to begin 50m approach.".
  DISP_LOG_UPDATE(msg0).
  
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL t0 IS TIME:SECONDS.
  LOCAL nextPulseUT IS TIME:SECONDS.
  SET DCK_DEADBAND_V TO 0.3.
  SET DCK_PULSE_COOLDOWN TO 2.0.
  
  LOCAL initialCvel IS APP_RELSTATE()["closing"].
  UNTIL TIME:SECONDS - t0 > maxTime {
    IF NOT HASTARGET {
      LOCAL msg1 IS "ERROR: Target lost in DCK_PUSH_FWD. Aborting.".
      DISP_ERROR(msg1).
      UTL_KILL_TRANSLATION().
      RETURN FALSE.
    }

    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    LOCK STEERING TO LOOKDIRUP(los, SHIP:UP:VECTOR).

    // Forward thrust based on distance
    LOCAL cmdF IS 0.
    IF rng > 200 {
      SET cmdF TO 1.0.  // ~2.0 m/s
    } ELSE IF rng > 100 {
      SET cmdF TO 0.5.  // ~1.0 m/s
    } ELSE {
      SET cmdF TO 0.2.  // Gentle ~0.4 m/s
    }
    SET SHIP:CONTROL:FORE TO cmdF.

    // Correct lateral drift
    IF vside:MAG > 0.2 AND TIME:SECONDS >= nextPulseUT {
      LOCAL uSide IS -vside:NORMALIZED * 0.5.
      SET SHIP:CONTROL:STARBOARD TO VDOT(uSide, SHIP:FACING:STARVECTOR).
      SET SHIP:CONTROL:TOP TO VDOT(uSide, SHIP:FACING:TOPVECTOR).
      DCK_DRIVE(V(0,0,0), FALSE).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      SET SHIP:CONTROL:STARBOARD TO 0.
      SET SHIP:CONTROL:TOP TO 0.
    }

    // Log progress
    IF TIME:SECONDS - lastPrint >= 2.0 {
      LOCAL msg2 IS "Pushing: rng=" + ROUND(rng, 1) + "m, cvel=" + ROUND(cvel, 2) + "m/s, cmdF=" + ROUND(cmdF, 2) + ", |vside|=" + ROUND(vside:MAG, 2) + "m/s.".
      DISP_LOG_UPDATE(msg2).
      SET lastPrint TO TIME:SECONDS.
    }

    // Success if moving toward target
    IF cvel > targetCvel AND rng < 400 {
      UTL_KILL_TRANSLATION().
      LOCAL msg3 IS "Forward thrust confirmed: cvel=" + ROUND(cvel, 2) + "m/s at rng=" + ROUND(rng, 1) + "m.".
      DISP_SUCCESS(msg3).
      RETURN TRUE.
    }

    WAIT 0.1.
  }

  // Timeout: no movement
  UTL_KILL_TRANSLATION().
  LOCAL msg4 IS "ERROR: No forward motion after " + maxTime + "s (cvel=" + ROUND(cvel, 2) + "m/s). Aborting.".
  DISP_ERROR(msg4).
  RETURN FALSE.
}

// Add this function to dock_align.ks
// Conservative forward breakout to transition from stationkeeping to approach
FUNCTION DCK_BREAKOUT_FORWARD {
  PARAMETER targetCvel IS 0.8, maxTime IS 12, targetDist IS 40.
  
  //CLEARSCREEN.
  LOCAL msg0 IS "Breaking out of stationkeeping: target cvel = " + ROUND(targetCvel, 2) + " m/s.".
  DISP_SUCCESS(msg0).
  
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL t0 IS TIME:SECONDS.
  LOCAL nextUpdate IS TIME:SECONDS.
  
  // More assertive settings to reach proper approach velocity
  LOCAL breakoutPhase IS TRUE.
  LOCAL thrustLevel IS 0.6.  // Higher thrust to reach 0.8 m/s
  
  UNTIL TIME:SECONDS - t0 > maxTime {
    IF NOT HASTARGET {
      LOCAL msg1 IS "ERROR: Target lost during forward breakout.".
      DISP_ERROR(msg1).
      UTL_KILL_TRANSLATION().
      RETURN FALSE.
    }

    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL vside IS vrel - (VDOT(vrel, los) * los).

    LOCK STEERING TO LOOKDIRUP(los, SHIP:UP:VECTOR).

    // Phase 1: More assertive acceleration to reach proper approach velocity
    IF breakoutPhase {
      IF cvel >= targetCvel * 0.85 OR rng <= targetDist {
        SET breakoutPhase TO FALSE.
        LOCAL msg2 IS "Breakout phase complete: cvel = " + ROUND(cvel, 2) + " m/s at " + ROUND(rng, 1) + " m.".
        DISP_SUCCESS(msg2).
        UTL_KILL_TRANSLATION().
        RETURN TRUE.
      } ELSE {
        // More assertive forward thrust to overcome stationkeeping inertia
        LOCAL thrustNeeded IS targetCvel - cvel.
        IF thrustNeeded > 0.15 {
          SET SHIP:CONTROL:FORE TO MIN(0.8, thrustLevel * (thrustNeeded / targetCvel)).
        } ELSE IF thrustNeeded > 0.05 {
          SET SHIP:CONTROL:FORE TO 0.3.  // Maintain gentle thrust
        } ELSE {
          SET SHIP:CONTROL:FORE TO 0.
        }
      }
    }

    // Fine lateral control - much tighter than before
    IF vside:MAG > 0.05 {  // Very tight threshold
      LOCAL uSide IS -vside:NORMALIZED * MIN(0.6, vside:MAG * 3.0).  // Proportional correction
      SET SHIP:CONTROL:STARBOARD TO VDOT(uSide, SHIP:FACING:STARVECTOR).
      SET SHIP:CONTROL:TOP TO VDOT(uSide, SHIP:FACING:TOPVECTOR).
    } ELSE {
      SET SHIP:CONTROL:STARBOARD TO 0.
      SET SHIP:CONTROL:TOP TO 0.
    }

    // Progress logging
    IF TIME:SECONDS >= nextUpdate {
      LOCAL msg3 IS "Breakout: rng=" + ROUND(rng, 1) + "m, cvel=" + ROUND(cvel, 2) + "m/s".
      LOCAL msg4 IS "Target cvel=" + ROUND(targetCvel, 2) + ", |vside|=" + ROUND(vside:MAG, 3) + ", thrust=" + ROUND(SHIP:CONTROL:FORE, 2).
      DISP_LOG_UPDATE(msg3).
      DISP_LOG_UPDATE(msg4).
      SET nextUpdate TO TIME:SECONDS + 1.5.
    }

    WAIT 0.08.  // Tight loop for fine control
  }

  // Timeout
  UTL_KILL_TRANSLATION().
  LOCAL S IS APP_RELSTATE().
  LOCAL msg6 IS "Breakout timeout: cvel=" + ROUND(S["closing"], 2) + " m/s at " + ROUND(S["d"], 1) + " m.".
  DISP_LOG_UPDATE(msg6).
  RETURN TRUE.  // Continue anyway - may still work
}

// Debug function to show velocity profile compliance
FUNCTION DEBUG_VELOCITY_PROFILE {
  PARAMETER currentDist, currentCvel.
  
  LOCAL expectedCvel IS DCK_VSCHEDULE_APPROACH(currentDist).
  LOCAL error IS currentCvel - expectedCvel.
  LOCAL errorPercent IS (error / expectedCvel) * 100.
  
  LOCAL profileStatus IS "ON_PROFILE".
  IF ABS(error) > 0.15 {
    SET profileStatus TO "OFF_PROFILE".
  } ELSE IF ABS(error) > 0.08 {
    SET profileStatus TO "MINOR_DRIFT".
  }
  
  LOCAL msg IS "VelProfile: " + ROUND(currentDist, 1) + "m -> " + ROUND(expectedCvel, 3) + " m/s | Actual: " + ROUND(currentCvel, 3) + " | " + profileStatus.
  DISP_LOG_UPDATE(msg).
  
  RETURN expectedCvel.
}

FUNCTION DCK_VSCHEDULE_APPROACH {
  PARAMETER rng.
  
  // Velocity targets that make sense for the approach phase
  IF rng >= 100 {
    RETURN MIN(2.0, 1.0 + (rng - 100) / 100).  // 1.0 m/s at 100m, scaling up
  } ELSE IF rng >= 70 {
    LOCAL frac IS (rng - 70) / (100 - 70).
    RETURN 0.8 + frac * (1.0 - 0.8).  // 0.8 m/s at 70m to 1.0 m/s at 100m
  } ELSE IF rng >= 50 {
    LOCAL frac IS (rng - 50) / (70 - 50).
    RETURN 0.6 + frac * (0.8 - 0.6).  // 0.6 m/s at 50m to 0.8 m/s at 70m
  } ELSE IF rng >= 40 {
    LOCAL frac IS (rng - 40) / (50 - 40).
    RETURN 0.4 + frac * (0.6 - 0.4).  // 0.4 m/s at 40m to 0.6 m/s at 50m
  } ELSE IF rng >= 30 {
    LOCAL frac IS (rng - 30) / (40 - 30).
    RETURN 0.3 + frac * (0.4 - 0.3).  // 0.3 m/s at 30m to 0.4 m/s at 40m
  } ELSE IF rng >= 20 {
    LOCAL frac IS (rng - 20) / (30 - 20).
    RETURN 0.2 + frac * (0.3 - 0.2).  // 0.2 m/s at 20m to 0.3 m/s at 30m
  } ELSE {
    // Hand off to DCK_FINAL_APPROACH at 20m with proper velocity
    RETURN 0.2.  // 0.2 m/s for final alignment phase
  }
}

// Enhanced DCK_DRIVE with velocity profile following
FUNCTION DCK_DRIVE_VELOCITY_PROFILE {
  PARAMETER vErr, currentCvel, desiredCvel, aggressive IS FALSE.
  
  SET APP_COAST_LOCK TO FALSE.
  
  LOCAL S IS APP_RELSTATE().
  LOCAL los IS S["los"].
  LOCAL vrel IS S["v"].
  LOCAL parallel IS VDOT(vrel, los) * los.
  LOCAL vside IS vrel - parallel.
  
  // Calculate velocity errors
  LOCAL cvelError IS currentCvel - desiredCvel.
  LOCAL forwardErr IS VDOT(vErr, los).
  LOCAL lateralErr IS vErr - (forwardErr * los).
  
  // Explicit velocity profile control
  LOCAL needsAcceleration IS cvelError < -0.08.  // Too slow
  LOCAL needsBraking IS cvelError > 0.08.        // Too fast
  
  IF AP_DEBUG {
    LOCAL diag_msg IS "VelProfile: cvel=" + ROUND(currentCvel, 3) + " vs des=" + ROUND(desiredCvel, 3) + " err=" + ROUND(cvelError, 3).
    DISP_LOG_UPDATE(diag_msg).
    LOCAL diag_msg2 IS "Accel=" + needsAcceleration + ", Brake=" + needsBraking + ", fwdErr=" + ROUND(forwardErr, 3).
    DISP_LOG_UPDATE(diag_msg2).
  }
  
  // Direct ship control for velocity profile adherence
  LOCAL cmdF IS 0.
  LOCAL cmdS IS 0. 
  LOCAL cmdT IS 0.
  
  // Forward control based on closing velocity error
  IF needsAcceleration {
    SET cmdF TO MIN(0.8, 0.3 + ABS(cvelError) * 2.0).  // Proportional acceleration
  } ELSE IF needsBraking {
    SET cmdF TO MAX(-0.8, -0.3 - ABS(cvelError) * 2.0).  // Proportional braking
  } ELSE IF ABS(forwardErr) > 0.05 {
    SET cmdF TO forwardErr * 1.5.  // Fine forward adjustments
  }
  
  // Lateral control
  IF lateralErr:MAG > 0.02 {
    SET cmdS TO VDOT(lateralErr, SHIP:FACING:STARVECTOR) * 2.0.
    SET cmdT TO VDOT(lateralErr, SHIP:FACING:TOPVECTOR) * 2.0.
  }
  
  // Apply controls
  SET SHIP:CONTROL:FORE TO ROUND(cmdF, 3).
  SET SHIP:CONTROL:STARBOARD TO ROUND(cmdS, 3).
  SET SHIP:CONTROL:TOP TO ROUND(cmdT, 3).
  
  // Duration based on error magnitude
  LOCAL duration IS 0.15.
  IF aggressive OR ABS(cvelError) > 0.2 {
    SET duration TO 0.25.
  } ELSE IF ABS(cvelError) < 0.05 {
    SET duration TO 0.08.
  }
  
  WAIT duration.
  UTL_KILL_TRANSLATION().
  
  IF AP_DEBUG {
    LOCAL diag_msg3 IS "Applied: F=" + ROUND(cmdF, 3) + " S=" + ROUND(cmdS, 3) + " T=" + ROUND(cmdT, 3) + " dur=" + ROUND(duration, 3).
    DISP_LOG_UPDATE(diag_msg3).
  }
}

// Enhanced DCK_DRIVE with finer lateral control
FUNCTION DCK_DRIVE_FINE {
  PARAMETER vErr, longOrPulse IS FALSE.
  
  SET APP_COAST_LOCK TO FALSE.
  LOCAL gain IS 1.2.  // Reduced for finer control
  LOCAL dur IS 0.12.   // Shorter pulses
  
  IF longOrPulse {
    SET gain TO 2.5.   // Reduced from 3.5
    SET dur TO 0.3.    // Shorter than DCK_LONG_T
  }
  
  // Extra fine control for small errors
  IF vErr:MAG < 0.2 {
    SET gain TO gain * 0.4.  // Much gentler
    SET dur TO MIN(0.06, dur).
  }
  
  // Lateral error gets special treatment
  LOCAL S IS APP_RELSTATE().
  LOCAL los IS S["los"].
  LOCAL vrel IS S["v"].
  LOCAL parallel IS VDOT(vrel, los) * los.
  LOCAL vside IS vrel - parallel.
  
  // Separate forward and lateral control
  LOCAL forwardErr IS VDOT(vErr, los).
  LOCAL lateralErr IS vErr - (forwardErr * los).
  
  IF AP_DEBUG {
    LOCAL diag_msg IS "DCK_DRIVE_FINE: fwd=" + ROUND(forwardErr, 3) + ", lat=" + ROUND(lateralErr:MAG, 3) + ", |vside|=" + ROUND(vside:MAG, 3).
    DISP_LOG_UPDATE(diag_msg).
  }
  
  // Only drive if significant error
  IF vErr:MAG < 0.08 { 
    LOCAL diag_msg IS "DCK_DRIVE_FINE: Skipped, vErr:MAG = " + ROUND(vErr:MAG, 3) + " < 0.08".
    DISP_LOG_UPDATE(diag_msg).
    RETURN.
  }
  
  // Use proportional control for very fine adjustments
  IF vErr:MAG < 0.3 {
    LOCAL propGain IS 0.8.
    SET SHIP:CONTROL:FORE TO VDOT(vErr, SHIP:FACING:FOREVECTOR) * propGain.
    SET SHIP:CONTROL:STARBOARD TO VDOT(vErr, SHIP:FACING:STARVECTOR) * propGain.
    SET SHIP:CONTROL:TOP TO VDOT(vErr, SHIP:FACING:TOPVECTOR) * propGain.
    WAIT dur.
    UTL_KILL_TRANSLATION().
    RETURN.
  }
  
  // Fall back to original pulse method for larger errors
  APP_DRIVE_RCS(vErr, gain, dur).
  UTL_KILL_TRANSLATION().
}

// Enhanced velocity schedule that matches DCK_FINAL_APPROACH exactly
FUNCTION DCK_VSCHEDULE_ENHANCED {
  PARAMETER rng.
  
  // Match DCK_FINAL_APPROACH velocity schedule exactly
  LOCAL V_AT_50M IS 0.50.
  LOCAL V_AT_10M IS 0.10.
  LOCAL V_MIN IS 0.05.
  
  IF rng >= 50 { 
    RETURN V_AT_50M.  // 0.5 m/s at 50m+
  } ELSE IF rng >= 10 {
    // Linear taper from 0.50 at 50m to 0.10 at 10m
    LOCAL t IS (rng - 10) / (50 - 10).
    LOCAL vset IS V_AT_10M + t * (V_AT_50M - V_AT_10M).
    RETURN MAX(V_MIN, vset).
  } ELSE {
    RETURN V_AT_10M.  // 0.10 m/s below 10m
  }
}

// Also update the original DCK_VSCHEDULE to be more conservative for close approach
FUNCTION DCK_VSCHEDULE_CONSERVATIVE {
  PARAMETER rng.
  
  // Conservative approach matching DCK_FINAL_APPROACH
  IF rng >= 200 {
    LOCAL vset IS MIN(2.0, DCK_V_AT_200M * (rng / 200.0)).  // Cap at 2.0 m/s
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE IF rng >= 100 {
    LOCAL frac IS (rng - 100) / (200 - 100).
    LOCAL vset IS 1.0 + frac * (2.0 - 1.0).  // 2.0 m/s at 200m to 1.0 m/s at 100m
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE IF rng >= 50 {
    LOCAL frac IS (rng - 50) / (100 - 50).
    LOCAL vset IS 0.5 + frac * (1.0 - 0.5).  // 1.0 m/s at 100m to 0.5 m/s at 50m
    IF vset < DCK_V_MIN { SET vset TO DCK_V_MIN. }
    RETURN vset.
  } ELSE {
    // Hand off to DCK_FINAL_APPROACH velocity schedule
    RETURN DCK_VSCHEDULE_ENHANCED(rng).
  }
}

// Below are the key functions modified with display integration.

// Modified DCK_WINDOW_HOLD - unchanged, just ensures stable hold
FUNCTION DCK_WINDOW_HOLD {
  PARAMETER near IS AP_WINDOW_NEAR, far IS AP_WINDOW_FAR, vhold IS AP_STATION_VHOLD, stableS IS AP_HOLD_STABLE_S.

  DISP_LOG_UPDATE("Window hold: acquiring " + near + "-" + far + "m").
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.

  GLOBAL lastPrint IS TIME:SECONDS.
  LOCAL nextPulseUT IS TIME:SECONDS.
  SET DCK_DEADBAND_V TO 0.3.
  SET DCK_PULSE_COOLDOWN TO 2.0.
  
  UNTIL TRUE {
    IF NOT HASTARGET {
      DISP_ERROR("Target lost in window hold").
      SET TARGET TO ORIGINAL_TARGET_NAME.
      IF NOT HASTARGET {
        RETURN FALSE.
      }
    }

    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    LOCK STEERING TO LOOKDIRUP(los, SHIP:UP:VECTOR).

    LOCAL vdes IS vhold.
    IF cvel > vhold + 0.5 AND rng < near {
      SET vdes TO -MIN(0.5, 0.2 + 0.005 * (near - rng)).
    } ELSE IF rng > far {
      SET vdes TO 2.5.
    } ELSE IF cvel <= 0 {
      SET vdes TO 0.8.
    }

    LOCAL vGoal IS los * vdes.
    IF vside:MAG > 0.2 {
      SET vGoal TO vGoal - vside * 1.2.
    }
    LOCAL vErr IS vGoal - vrel.

    IF TIME:SECONDS >= nextPulseUT AND (vErr:MAG > DCK_DEADBAND_V OR cvel > vdes + 0.5) {
      DCK_DRIVE(vErr, vErr:MAG > DCK_BIG_ERR OR cvel > 2.0).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    IF TIME:SECONDS - lastPrint >= 5.0 {
      DISP_LOG_UPDATE("Hold: " + ROUND(rng, 0) + "m, " + ROUND(cvel, 2) + "m/s").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    IF (rng >= near) AND (rng <= far) AND (ABS(cvel - vhold) < 0.12) AND (vrel:MAG < 0.35) {
      DISP_SUCCESS("Window acquired at " + ROUND(rng, 0) + "m").
      RETURN TRUE.
    }

    WAIT 0.16.
  }
}

// Alternative version that waits for target acknowledgment
FUNCTION DCK_PROMPT_PROCEED {
  PARAMETER near IS AP_WINDOW_NEAR, far IS AP_WINDOW_FAR, poll_dt IS 0.5, timeoutS IS 300.
  LOCAL vhold IS AP_STATION_VHOLD.

  // Send approach request message to target
  DISP_STATUS("MSG_SEND", "Requesting approach clearance", "AWAITING RESPONSE").
  
  LOCAL approachMsg IS LIST(
    "DOCKALIGN",
    SHIP:NAME,
    "Requesting clearance for final approach",
    TIME:SECONDS
  ).
  
  LOCAL msgSent IS EMail2Tgt(approachMsg).
  
  IF NOT msgSent {
    DISP_ERROR("Failed to send approach request").
    DISP_ERROR("Cannot proceed without target communication").
    RETURN FALSE.
  }
  
  DISP_SUCCESS("Approach request sent to " + TARGET:NAME).
  DISP_LOG_UPDATE("Waiting for target acknowledgment...").
  DISP_LOG_UPDATE("Or press Y to override / N to abort").
  
  TERMINAL:INPUT:CLEAR.
  
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL nextPulseUT IS TIME:SECONDS.
  SET DCK_DEADBAND_V TO 0.4.
  SET DCK_PULSE_COOLDOWN TO 0.7.
  
  LOCAL waitStart IS TIME:SECONDS.
  LOCAL ackReceived IS FALSE.
  LOCAL proceed IS FALSE.

  UNTIL proceed {
            // Check for messages from target

    IF NOT HASTARGET {
      DISP_ERROR("Target lost during prompt").
      SET TARGET TO ORIGINAL_TARGET_NAME.
      IF NOT HASTARGET {
        TERMINAL:INPUT:CLEAR.
        RETURN FALSE.
      }
    }
    
    // Check for timeout
    IF TIME:SECONDS - waitStart > timeoutS {
      DISP_ERROR("Timeout waiting for target acknowledgment").
      DISP_LOG_UPDATE("Press Y to proceed anyway, N to abort").
      // Continue waiting for manual input
    }

    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    LOCK STEERING TO LOOKDIRUP(los, SHIP:UP:VECTOR).

    // Stationkeeping logic (same as before)
    LOCAL vdes IS vhold.
    IF cvel > vhold + 0.5 AND rng < near {
      SET vdes TO -MIN(0.5, 0.2 + 0.005 * (near - rng)).
    } ELSE IF rng > far {
      SET vdes TO MIN(2.0, 1.0 + (rng - far) / 200).
    } ELSE IF cvel <= 0 {
      SET vdes TO 0.8.
    }

    LOCAL vGoal IS los * vdes.
    IF vside:MAG > 0.25 { SET vGoal TO vGoal - vside * 1.2. }
    LOCAL vErr IS vGoal - vrel.

    IF TIME:SECONDS >= nextPulseUT AND vErr:MAG > DCK_DEADBAND_V {
      DCK_DRIVE(vErr, FALSE).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    // Check for messages from target
    IF SHIP:MESSAGES:LENGTH > 0 {
      LOCAL msg IS SHIP:MESSAGES:POP.
      IF msg:HASSUFFIX("CONTENT") {
        LOCAL content IS msg:CONTENT.
        IF content:LENGTH > 0 {
          LOCAL msgType IS content[0].
          IF msgType = "APPROACH_APPROVED" {
            DISP_STATUS("Target Reponse", "Target approved approach!","MESSAGE RVCD").
            //SET ackReceived TO TRUE.
            //SET proceed TO TRUE.
            RETURN TRUE.
          } ELSE IF msgType = "APPROACH_DENIED" {
            DISP_WARN("Target denied approach request").
            LOCAL abortMsg IS LIST(
              "APPROACH_ABORTED",
              SHIP:NAME,
              "Approach denied by target",
              TIME:SECONDS
            ).
            EMail2Tgt(abortMsg).
            APP_BACKOUT_TO_WINDOW(near, far).
            RETURN FALSE.
          }
        }
      }
    }

    IF TIME:SECONDS - lastPrint >= 5.0 {
      IF ackReceived {
        DISP_LOG_UPDATE("Acknowledged - awaiting proceed").
      } ELSE {
        DISP_LOG_UPDATE("Hold: " + ROUND(rng, 0) + "m, awaiting ack").
      }
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    // Manual override
    IF TERMINAL:INPUT:HASCHAR{
      LOCAL ch IS TERMINAL:INPUT:GETCHAR().
      
      IF ch = "Y" OR ch = "y" {
        IF NOT ackReceived {
          DISP_WARN("Proceeding without target acknowledgment").
        }
        DISP_SUCCESS("Operator authorized proceed").
        
        LOCAL confirmMsg IS LIST(
          "APPROACH_CONFIRMED",
          SHIP:NAME,
          "Beginning final approach sequence",
          TIME:SECONDS
        ).
        EMail2Tgt(confirmMsg).
        
        SET proceed TO TRUE.
      } ELSE IF ch = "N" OR ch = "n" {
        DISP_WARN("Operator aborted - retreating").
        
        LOCAL abortMsg IS LIST(
          "APPROACH_ABORTED",
          SHIP:NAME,
          "Approach sequence aborted by operator",
          TIME:SECONDS
        ).
        EMail2Tgt(abortMsg).
        
        APP_BACKOUT_TO_WINDOW(near, far).
        RETURN FALSE.
      }
    }

    WAIT 0.1.
  }

  RETURN TRUE.
}

// Modified DCK_AP_50M with display integration
FUNCTION DCK_AP_50M {
  PARAMETER near IS 45, far IS 60, vhold IS 0.05, stableS IS AP_HOLD_STABLE_S.

  DISP_LOG_UPDATE("Approaching 45-60m window").
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL nextPulseUT IS TIME:SECONDS.
  SET DCK_DEADBAND_V TO 0.02.
  SET DCK_PULSE_COOLDOWN TO 0.5.
  LOCAL phaseT0 IS TIME:SECONDS.
  LOCAL lastRng IS 0.
  LOCAL stallT0 IS TIME:SECONDS.
  LOCAL stallSec IS 1.0.

  UNTIL FALSE {
    IF NOT HASTARGET {
      DISP_ERROR("Target lost in 50m approach").
      SET TARGET TO ORIGINAL_TARGET_NAME.
      IF NOT HASTARGET {
        RETURN FALSE.
      }
    }

    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    LOCK STEERING TO LOOKDIRUP(los, SHIP:FACING:TOPVECTOR).

    LOCAL vTow IS 0.0.
    IF rng > 300 {
      SET vTow TO 3.0.
    } ELSE IF rng > 200 {
      LOCAL frac IS (rng - 200) / (300 - 200).
      SET vTow TO 2.0 + frac * (3.0 - 2.0).
    } ELSE IF rng > 100 {
      LOCAL frac IS (rng - 100) / (200 - 100).
      SET vTow TO 1.0 + frac * (2.0 - 1.0).
    } ELSE IF rng > far {
      LOCAL frac IS (rng - far) / (100 - far).
      SET vTow TO vhold + frac * (1.0 - vhold).
    } ELSE IF cvel > 0.05 AND rng < near {
      SET vTow TO -MIN(0.8, 0.6 + 0.04 * (near - rng)).
    } ELSE {
      SET vTow TO vhold.
    }

    LOCAL vGoal IS los * vTow.
    IF vside:MAG > 0.1 {
      SET vGoal TO vGoal - vside * 1.2.
    }
    LOCAL vErr IS vGoal - vrel.

    LOCAL pulseDur IS 0.2.
    IF vErr:MAG > 0.5 {
      SET pulseDur TO MIN(0.4, 0.2 * 2).
    } ELSE IF vErr:MAG < 0.2 {
      SET pulseDur TO MAX(0.1, 0.2 / 2).
    }

    IF vErr:MAG > DCK_DEADBAND_V AND TIME:SECONDS >= nextPulseUT {
      APP_DRIVE_VTOW(vGoal, 0.8, pulseDur).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    IF lastRng > 0 {
      IF rng >= lastRng - 0.1 {
        IF TIME:SECONDS - stallT0 >= stallSec {
          APP_PUSH_ALONG(los, 0.4, 0.3).
          SET stallT0 TO TIME:SECONDS.
          SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
        }
      } ELSE {
        SET stallT0 TO TIME:SECONDS.
      }
    } ELSE {
      SET stallT0 TO TIME:SECONDS.
    }
    SET lastRng TO rng.

    IF TIME:SECONDS - lastPrint >= 5.0 {
      DISP_LOG_UPDATE("50m: " + ROUND(rng, 0) + "m, " + ROUND(cvel, 2) + "m/s").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    IF (rng >= near) AND (rng <= far) AND (vrel:MAG < 0.3) {
      DISP_SUCCESS("50m window acquired").
      IF NOT DCK_PROMPT_PROCEED(near, far, AP_PROMPT_POLL) {
        DISP_WARN("Operator hold - remaining at 50m").
        DCK_WINDOW_HOLD(near, far, vhold, AP_HOLD_STABLE_S).
        WAIT 999999.
      }
      RETURN TRUE.
    }

    WAIT 0.12.
  }

  UTL_KILL_TRANSLATION().
  RETURN TRUE.
}

// Modified DCK_ALIGN_PORTS with display integration
FUNCTION DCK_ALIGN_PORTS {
  PARAMETER myTag IS "", tgtTag IS "", maxAng IS 3.0, maxV IS 0.3, tick IS 0.1.

  DISP_LOG_UPDATE("Aligning ports: " + myTag + " to " + tgtTag).

  LOCAL myP IS DCK_GET_MY_PORT(myTag).
  IF myP = "NONE" {
    DISP_ERROR("No local docking port found").
    RETURN FALSE.
  }

  LOCAL tgP IS DCK_GET_TGT_PORT(tgtTag).
  LOCAL tgtRef IS TARGET.
  IF tgP <> "NONE" { SET tgtRef TO tgP. }

  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL nextPulseUT IS TIME:SECONDS.
  LOCAL lastPrint IS TIME:SECONDS.
  
  SET DCK_DEADBAND_V TO 0.03.
  SET DCK_PULSE_COOLDOWN TO 0.3.

  UNTIL FALSE {
    IF NOT HASTARGET {
      DISP_ERROR("Target lost in alignment").
      SET TARGET TO ORIGINAL_TARGET_NAME.
      IF NOT HASTARGET {
        RETURN FALSE.
      }
    }

    LOCAL myPos IS DCK_PORT_POS(myP).
    LOCAL tgPos IS DCK_PORT_POS(tgtRef).
    LOCAL los IS (tgPos - myPos):NORMALIZED.
    LOCAL dist IS (myPos - tgPos):MAG.
    LOCAL vrel IS SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT.
    LOCAL closing IS VDOT(vrel, los).
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    LOCAL tgtUp IS DCK_PORT_UP(tgtRef).
    LOCK STEERING TO LOOKDIRUP(los, tgtUp).

    LOCAL angErr IS VANG(myP:FACING:FOREVECTOR, los).

    LOCAL vdes IS DCK_VSCHEDULE_APPROACH(dist).
    LOCAL vGoal IS los * vdes.
    
    IF vside:MAG > 0.03 {
      LOCAL lateralCorrection IS -vside * MIN(2.0, 1.0 + (vside:MAG * 8.0)).
      SET vGoal TO vGoal + lateralCorrection.
    }
    
    LOCAL vErr IS vGoal - vrel.

    IF TIME:SECONDS - lastPrint >= 3.0 {
      DISP_LOG_UPDATE("Align: " + ROUND(dist, 0) + "m, ang " + ROUND(angErr, 1) + "d").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    IF vErr:MAG > DCK_DEADBAND_V AND TIME:SECONDS >= nextPulseUT {
      DCK_DRIVE_VELOCITY_PROFILE(vErr, closing, vdes, FALSE).
      SET nextPulseUT TO TIME:SECONDS + DCK_PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    IF angErr < maxAng AND vrel:MAG < maxV AND dist < 20 {
      DISP_SUCCESS("Alignment complete").
      BREAK.
    }

    WAIT tick.
  }

  RETURN TRUE.
}

// Modified DCK_FINAL_APPROACH with proper docking verification
// Modified DCK_FINAL_APPROACH with precision thrust control
FUNCTION DCK_FINAL_APPROACH {
  PARAMETER myTag IS "", tgtTag IS "", tick IS 0.12.

  DISP_LOG_UPDATE("Final approach: docking to " + myTag).
  LOCAL V_AT_50M IS 0.50.
  LOCAL V_AT_10M IS 0.10.
  LOCAL V_MIN IS 0.05.
  LOCAL SIDE_CAP0 IS 0.1.
  
  // Precision thrust scaling - reduces RCS authority for smoother control
  LOCAL PRECISION_SCALE IS 0.25.  // 25% thrust (adjust 0.1-0.5 as needed)

  LOCAL myP IS DCK_GET_MY_PORT(myTag).
  IF myP = "NONE" {
    DISP_ERROR("No local docking port found").
    RETURN FALSE.
  }

  LOCAL tgP IS DCK_GET_TGT_PORT(tgtTag).
  LOCAL tgtRef IS TARGET.
  IF tgP <> "NONE" { SET tgtRef TO tgP. }

  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.
  LOCAL nextPulseUT IS TIME:SECONDS.
  LOCAL t0 IS TIME:SECONDS.
  LOCAL contactTime IS -1.
  LOCAL CONTACT_WAIT IS 3.0.

  UNTIL FALSE {
    // Check for actual docking state first
    LOCAL isDocked IS FALSE.
    IF myP <> "NONE" AND myP:HASSUFFIX("STATE") {
      IF myP:STATE:CONTAINS("Docked") OR myP:STATE:CONTAINS("PreAttached") {
        DISP_SUCCESS("Docking state detected: " + myP:STATE).
        SET isDocked TO TRUE.
      }
    }
    
    IF isDocked {
      DISP_SUCCESS("Docking confirmed - securing systems").
      UTL_KILL_TRANSLATION().
      RCS OFF.
      SAS OFF.
      SHIP_RESET().
      WAIT 0.5.
      RETURN TRUE.
    }
    
    IF NOT HASTARGET {
      DISP_ERROR("Target lost during final approach").
      UTL_KILL_TRANSLATION().
      SHIP_RESET().
      RETURN FALSE.
    }

    LOCAL myPos IS DCK_PORT_POS(myP).
    LOCAL tgPos IS DCK_PORT_POS(tgtRef).
    LOCAL los IS (tgPos - myPos):NORMALIZED.
    LOCAL dist IS (tgPos - myPos):MAG.
    LOCAL vrel IS (SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT).
    LOCAL closing IS VDOT(vrel, los).
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.

    // Track contact detection
    IF dist < 1.5 {
      IF contactTime < 0 {
        SET contactTime TO TIME:SECONDS.
        DISP_LOG_UPDATE("Contact detected at " + ROUND(dist, 2) + "m - waiting for dock confirmation").
      }
      
      IF TIME:SECONDS - contactTime > CONTACT_WAIT {
        IF myP <> "NONE" AND myP:HASSUFFIX("STATE") {
          IF myP:STATE:CONTAINS("Docked") OR myP:STATE:CONTAINS("PreAttached") {
            DISP_SUCCESS("Docking confirmed after contact wait").
            UTL_KILL_TRANSLATION().
            RCS OFF.
            SAS OFF.
            SHIP_RESET().
            WAIT 0.5.
            RETURN TRUE.
          } ELSE {
            DISP_WARN("Contact but no dock after " + CONTACT_WAIT + "s - continuing approach").
            SET contactTime TO -1.
          }
        }
      }
    } ELSE {
      SET contactTime TO -1.
    }

    LOCAL vdes IS 0.0.
    IF dist >= 10 { 
      LOCAL t IS (dist - 10) / (50 - 10).
      SET vdes TO V_AT_10M + t * (V_AT_50M - V_AT_10M).
    } ELSE {
      SET vdes TO V_AT_10M.
    }
    SET vdes TO MAX(V_MIN, vdes).

    LOCAL upVec IS DCK_PORT_UP(tgtRef).
    LOCK STEERING TO LOOKDIRUP(los, upVec).

    LOCAL thrustNeeded IS FALSE.
    LOCAL cmdF IS 0.
    
    // Forward/backward control with precision scaling
    IF closing < vdes - 0.02 {  // Tighter deadband for smoother control
      SET cmdF TO VDOT(los, SHIP:FACING:FOREVECTOR) * PRECISION_SCALE.
      SET thrustNeeded TO TRUE.
    } ELSE IF closing > vdes + 0.05 {
      SET cmdF TO VDOT(-los, SHIP:FACING:FOREVECTOR) * 5.0 * PRECISION_SCALE.  // Braking scaled too
      SET thrustNeeded TO TRUE.
    }

    SET SHIP:CONTROL:FORE TO cmdF.

    LOCAL cmdS IS 0.
    LOCAL cmdT IS 0.
    LOCAL sideCap IS MAX(SIDE_CAP0, vdes * 0.5).
    
    // Lateral control with precision scaling
    IF vside:MAG > sideCap {
      LOCAL uSide IS -vside:NORMALIZED * 1.5 * PRECISION_SCALE.  // Apply precision scale
      SET cmdS TO VDOT(uSide, SHIP:FACING:STARVECTOR).
      SET cmdT TO VDOT(uSide, SHIP:FACING:TOPVECTOR).
      SET thrustNeeded TO TRUE.
    }

    SET SHIP:CONTROL:STARBOARD TO cmdS.
    SET SHIP:CONTROL:TOP TO cmdT.

    IF dist < 3.0 {
      RCS OFF.
      UTL_KILL_TRANSLATION().
      DISP_LOG_UPDATE("RCS OFF at 3m - coasting").
    } ELSE IF TIME:SECONDS >= nextPulseUT AND thrustNeeded {
      // Don't call DCK_DRIVE here - we're using direct control above
      SET nextPulseUT TO TIME:SECONDS + 0.8.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    IF TIME:SECONDS - lastPrint >= 5.0 {
      DISP_LOG_UPDATE("Final: " + ROUND(dist, 1) + "m, " + ROUND(closing, 2) + "m/s").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    IF TIME:SECONDS - t0 > 600 {
      DISP_ERROR("Timeout in final approach").
      RETURN FALSE.
    }

    WAIT tick.
  }

  UTL_KILL_TRANSLATION().
  RETURN FALSE.
}