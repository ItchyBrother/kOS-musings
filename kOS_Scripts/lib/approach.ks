// ===============================================================
// approach.ks – Step 3: short-range RCS approach (with display integration)
// Requires: utils.ks, display.ks
// ===============================================================

SET AP_RENDER_RANGE       TO 2300.
SET AP_STRICT_COAST       TO TRUE.
SET AP_COAST_LOOP_DT      TO 0.30.
SET AP_VERBOSE_GATE       TO FALSE.
SET AP_START_ON_RENDER    TO TRUE.
SET AP_WINDOW_NEAR        TO 200.
SET AP_WINDOW_FAR         TO 400.
SET AP_STATION_VHOLD      TO 0.08.
SET AP_HOLD_STABLE_S      TO 5.0.
SET AP_PROMPT_POLL        TO 0.20.
SET APP_COAST_LOCK        TO TRUE.
SET APP_PULSE_COOLDOWN    TO 0.6.
SET APP_DEBUG             TO AP_DEBUG.

FUNCTION APP_RELSTATE {
  IF NOT HASTARGET {
    DISP_ERROR("ERROR: No target set in APP_RELSTATE.").
    RETURN LEXICON("d", 0, "v", V(0,0,0), "los", V(0,0,0), "closing", 0).
  }
  LOCAL pos IS TARGET:POSITION.
  LOCAL dist IS pos:MAG.
  LOCAL los IS pos:NORMALIZED.
  LOCAL vrel IS SHIP:VELOCITY:ORBIT - TARGET:VELOCITY:ORBIT.
  LOCAL cvel IS VDOT(vrel, los).
  RETURN LEXICON(
    "d", dist,
    "v", vrel,
    "los", los,
    "closing", cvel
  ).
}

FUNCTION APP_CLAMP {
  PARAMETER x, lo, hi.
  IF x < lo { RETURN lo. }
  IF x > hi { RETURN hi. }
  RETURN x.
}

FUNCTION APP_DRIVE_RCS {
  PARAMETER worldVec, gain, dur.
  IF APP_COAST_LOCK { RETURN. }
  LOCAL mag IS worldVec:MAG.
  IF mag < 1E-6 { RETURN. }
  LOCAL u IS worldVec / mag.
  LOCAL cmd IS u * MIN(1, gain * mag).
  SET SHIP:CONTROL:STARBOARD TO APP_CLAMP(VDOT(cmd, SHIP:FACING:STARVECTOR), -1, 1).
  SET SHIP:CONTROL:TOP       TO APP_CLAMP(VDOT(cmd, SHIP:FACING:TOPVECTOR), -1, 1).
  SET SHIP:CONTROL:FORE      TO APP_CLAMP(VDOT(cmd, SHIP:FACING:FOREVECTOR), -1, 1).
  IF APP_DEBUG AND TIME:SECONDS - lastPrint >= 0.2 {
    LOCAL msg IS "APP_DRIVE_RCS: S=" + ROUND(SHIP:CONTROL:STARBOARD, 3) + ", T=" + ROUND(SHIP:CONTROL:TOP, 3) + ", F=" + ROUND(SHIP:CONTROL:FORE, 3) + ", dur=" + ROUND(dur, 3).
    DISP_LOG_UPDATE(msg).
    SET lastPrint TO TIME:SECONDS.
  }
  WAIT dur.
  UTL_KILL_TRANSLATION().
}

FUNCTION APP_PUSH_ALONG {
  PARAMETER worldVec, mag IS 0.7, dur IS 0.30.
  LOCAL u IS worldVec:NORMALIZED.
  LOCAL axS IS APP_CLAMP(VDOT(u, SHIP:FACING:STARVECTOR) * mag, -1, 1).
  LOCAL axT IS APP_CLAMP(VDOT(u, SHIP:FACING:TOPVECTOR) * mag, -1, 1).
  LOCAL axF IS APP_CLAMP(VDOT(u, SHIP:FACING:FOREVECTOR) * mag, -1, 1).
  SET SHIP:CONTROL:STARBOARD TO axS.
  SET SHIP:CONTROL:TOP       TO axT.
  SET SHIP:CONTROL:FORE      TO axF.
  WAIT dur.
  UTL_KILL_TRANSLATION().
  RETURN TRUE.
}

FUNCTION APP_DUMP_RELVEL_CONT {
  PARAMETER goalMag IS AP_HEAVY_BRAKE_TARGET, maxDur IS AP_HEAVY_MAX_S, dt IS AP_HEAVY_HOLD_DT.
  LOCAL t0 IS TIME:SECONDS.
  UNTIL TIME:SECONDS - t0 >= maxDur {
    LOCAL S IS APP_RELSTATE().
    LOCAL vrel IS S["v"].
    LOCAL mag IS vrel:MAG.
    IF mag <= goalMag { BREAK. }
    LOCAL u IS (-vrel):NORMALIZED.
    SET SHIP:CONTROL:STARBOARD TO APP_CLAMP(VDOT(u, SHIP:FACING:STARVECTOR), -1, 1).
    SET SHIP:CONTROL:TOP       TO APP_CLAMP(VDOT(u, SHIP:FACING:TOPVECTOR), -1, 1).
    SET SHIP:CONTROL:FORE      TO APP_CLAMP(VDOT(u, SHIP:FACING:FOREVECTOR), -1, 1).
    WAIT dt.
  }
  UTL_KILL_TRANSLATION().
  RETURN TRUE.
}

FUNCTION APP_DRIVE_VTOW {
  PARAMETER vGoal, kp IS 0.95, dur IS 0.30.
  LOCAL S IS APP_RELSTATE().
  LOCAL vrel IS S["v"].
  LOCAL err IS vGoal - vrel.
  IF err:MAG < 0.1 { RETURN TRUE. }
  LOCAL ex IS VDOT(err, SHIP:FACING:STARVECTOR) * kp.
  LOCAL ey IS VDOT(err, SHIP:FACING:TOPVECTOR) * kp.
  LOCAL ez IS VDOT(err, SHIP:FACING:FOREVECTOR) * kp.
  IF ex > 1 { SET ex TO 1. } IF ex < -1 { SET ex TO -1. }
  IF ey > 1 { SET ey TO 1. } IF ey < -1 { SET ey TO -1. }
  IF ez > 1 { SET ez TO 1. } IF ez < -1 { SET ez TO -1. }
  LOCAL MINAX IS 0.22.
  IF ex > 0 AND ex < MINAX { SET ex TO MINAX. }
  IF ex < 0 AND ex > -MINAX { SET ex TO -MINAX. }
  IF ey > 0 AND ey < MINAX { SET ey TO MINAX. }
  IF ey < 0 AND ey > -MINAX { SET ey TO -MINAX. }
  IF ez > 0 AND ez < MINAX { SET ez TO MINAX. }
  IF ez < 0 AND ez > -MINAX { SET ez TO -MINAX. }
  SET SHIP:CONTROL:STARBOARD TO ex.
  SET SHIP:CONTROL:TOP       TO ey.
  SET SHIP:CONTROL:FORE      TO ez.
  WAIT dur.
  UTL_KILL_TRANSLATION().
  IF APP_DEBUG AND TIME:SECONDS - lastPrint >= 5.0 {
    LOCAL msg IS "APP_DRIVE_VTOW: vErr=" + ROUND(err:MAG, 2) + ", dur=" + ROUND(dur, 3) + ", S=" + ROUND(ex, 3) + ", T=" + ROUND(ey, 3) + ", F=" + ROUND(ez, 3).
    DISP_LOG_UPDATE(msg).
    SET lastPrint TO TIME:SECONDS.
  }
  RETURN TRUE.
}

FUNCTION CALC_CA {
  PARAMETER maxStep IS 300, initStep IS 10, minStep IS 0.1.

  LOCAL approach_time IS TIME:SECONDS.
  LOCAL step_size IS initStep.
  LOCAL currT IS TIME:SECONDS.

  UNTIL step_size < minStep {
    LOCAL dist_curr IS (POSITIONAT(SHIP, approach_time) - POSITIONAT(TARGET, approach_time)):MAG.
    LOCAL dist_plus IS (POSITIONAT(SHIP, approach_time + step_size) - POSITIONAT(TARGET, approach_time + step_size)):MAG.
    LOCAL dist_minus IS (POSITIONAT(SHIP, approach_time - step_size) - POSITIONAT(TARGET, approach_time - step_size)):MAG.

    IF dist_plus < dist_curr {
      SET approach_time TO approach_time + step_size.
    } ELSE IF dist_minus < dist_curr {
      SET approach_time TO approach_time - step_size.
    } ELSE {
      SET step_size TO step_size / 2.
    }

    IF approach_time - currT > maxStep {
      BREAK.
    }
  }

  LOCAL minDist IS (POSITIONAT(SHIP, approach_time) - POSITIONAT(TARGET, approach_time)):MAG.
  LOCAL minT IS approach_time - currT.

  IF APP_DEBUG AND TIME:SECONDS - lastPrint >= 5.0 {
    LOCAL msg IS "CA: projected d=" + ROUND(minDist,1) + "m at t=" + ROUND(minT,1) + "s.".
    DISP_LOG_UPDATE(msg).
    SET lastPrint TO TIME:SECONDS.
  }

  RETURN LEXICON("d", minDist, "t", minT).
}

FUNCTION APPROACH_RCS {
  PARAMETER renderRange IS AP_RENDER_RANGE, unused IS 0, planUT IS 0, strictLead IS 0.

  LOCAL WIN_NEAR IS 200.
  LOCAL WIN_FAR IS 400.
  LOCAL CAP_REL IS 0.3.
  LOCAL HOLD_DUR IS 0.25.
  LOCAL TICK_DT IS 0.20.
  LOCAL BACKOUTMAX IS 0.6.
  LOCAL KEEP_MIN IS 0.3.
  LOCAL STALL_SEC IS 1.2.
  LOCAL DEADBAND_V IS 0.1.
  LOCAL PULSE_COOLDOWN IS 0.6.
 
  LOCAL S IS APP_RELSTATE().
  LOCAL initialRange IS S["d"].
  DISP_LOG_UPDATE("Initial range: " + ROUND(initialRange, 0) + "m").
  
  IF NOT HASTARGET {
    DISP_ERROR("No target set").
    RETURN FALSE.
  }

  // ===== CRITICAL: RESTART RANGE SAFETY CHECK =====
  // If already within critical ranges, force appropriate hold state
  IF initialRange < WIN_FAR {
    DISP_WARN("RESTART DETECTED: Already at " + ROUND(initialRange, 0) + "m").
    
    // Case 1: Within 50m range - extremely dangerous
    IF initialRange < 60 {
      DISP_WARN("Within 50m zone - initiating emergency procedures").
      RCS ON.
      SAS OFF.
      SET APP_COAST_LOCK TO FALSE.
      
      // Kill all relative velocity first
      DISP_LOG_UPDATE("Emergency brake: nulling relative velocity").
      LOCAL emergencyT0 IS TIME:SECONDS.
      UNTIL TIME:SECONDS - emergencyT0 > 30 {
        LOCAL S_emerg IS APP_RELSTATE().
        LOCAL vrel IS S_emerg["v"].
        IF vrel:MAG < 0.15 { BREAK. }
        
        LOCAL los IS S_emerg["los"].
        LOCK STEERING TO LOOKDIRUP(los, SHIP:FACING:TOPVECTOR).
        
        APP_DUMP_RELVEL_CONT(0.1, 5.0, 0.08).
        WAIT 0.5.
      }
      
      DISP_SUCCESS("Emergency brake complete - entering 50m hold").
      // Don't proceed further - let dock_align.ks handle from here
      RETURN TRUE.
    }
    
    // Case 2: Within 200-400m window
    ELSE IF initialRange >= WIN_NEAR AND initialRange <= WIN_FAR {
      DISP_LOG_UPDATE("Already in 200-400m window - safe restart").
      RCS ON.
      SAS OFF.
      SET APP_COAST_LOCK TO FALSE.
      
      // Gentle velocity capture
      LOCAL S_restart IS APP_RELSTATE().
      IF S_restart["v"]:MAG > 0.5 {
        DISP_LOG_UPDATE("Reducing relative velocity for safety").
        APP_DUMP_RELVEL_CONT(0.3, 10.0, 0.08).
      }
      
      DISP_SUCCESS("Safe velocity achieved in window").
      RETURN TRUE.
    }
    
    // Case 3: Between 60m and 200m - dangerous zone
    ELSE IF initialRange < WIN_NEAR {
      DISP_WARN("In dangerous zone (60-200m) - establishing safe hold").
      RCS ON.
      SAS OFF.
      SET APP_COAST_LOCK TO FALSE.
      
      // Kill velocity and back out to safe window
      DISP_LOG_UPDATE("Phase 1: Nulling relative velocity").
      LOCAL S_danger IS APP_RELSTATE().
      IF S_danger["v"]:MAG > 0.2 {
        APP_DUMP_RELVEL_CONT(0.15, 15.0, 0.08).
      }
      
      DISP_LOG_UPDATE("Phase 2: Backing to 200-400m window").
      LOCAL backoutT0 IS TIME:SECONDS.
      LOCAL nextPulse IS TIME:SECONDS.
      
      UNTIL TIME:SECONDS - backoutT0 > 120 {
        LOCAL S_back IS APP_RELSTATE().
        LOCAL rng IS S_back["d"].
        LOCAL vrel IS S_back["v"].
        LOCAL los IS S_back["los"].
        LOCAL cvel IS S_back["closing"].
        
        LOCK STEERING TO LOOKDIRUP(los, SHIP:FACING:TOPVECTOR).
        
        IF TIME:SECONDS - lastPrint >= 3.0 {
          DISP_LOG_UPDATE("Backout: " + ROUND(rng, 0) + "m, " + ROUND(cvel, 2) + "m/s").
          SET lastPrint TO TIME:SECONDS.
        }
        DISP_TICK().
        
        // Reached safe window
        IF rng >= WIN_NEAR AND rng <= WIN_FAR {
          DISP_SUCCESS("Safe window reached at " + ROUND(rng, 0) + "m").
          UTL_KILL_TRANSLATION().
          RETURN TRUE.
        }
        
        // Backing out too far
        IF rng > WIN_FAR {
          DISP_SUCCESS("Beyond window - will re-approach normally").
          BREAK.
        }
        
        // Control: gentle separation
        LOCAL vTow IS -0.5.  // Negative = backing away
        IF rng > WIN_NEAR - 20 {
          SET vTow TO -0.2.  // Slower as we approach window
        }
        
        LOCAL vGoal IS los * vTow.
        LOCAL vErr IS vGoal - vrel.
        
        IF TIME:SECONDS >= nextPulse AND vErr:MAG > 0.1 {
          APP_DRIVE_VTOW(vGoal, 0.6, 0.25).
          SET nextPulse TO TIME:SECONDS + 0.8.
        } ELSE {
          UTL_KILL_TRANSLATION().
        }
        
        WAIT 0.2.
      }
    }
  }
  // ===== END RESTART SAFETY CHECK =====

  // Wait for intercept time if needed
  IF planUT > TIME:SECONDS AND strictLead > 0 {
    LOCAL waitS IS planUT - strictLead - TIME:SECONDS.
    IF waitS > 0 {
      DISP_LOG_UPDATE("Waiting " + ROUND(waitS, 0) + "s for intercept").
      UNTIL TIME:SECONDS >= planUT - strictLead {
        UTL_SET_RCS(FALSE, "approach wait").
        UTL_KILL_TRANSLATION().
        DISP_TICK().
        WAIT 0.5.
      }
    }
  }

  RCS OFF.
  SAS OFF.
  
  IF AP_START_ON_RENDER {
    LOCAL currentD IS APP_RELSTATE()["d"].
    
    IF S["d"] <= renderRange {
      DISP_LOG_UPDATE("Already within render range").
    } ELSE {
      DISP_LOG_UPDATE("Coasting to render range").
      
      LOCAL coast_start IS TIME:SECONDS.
      LOCAL prevRng IS S["d"] + 1.

      UNTIL FALSE {
        LOCAL S_coast IS APP_RELSTATE().
        LOCAL rng_coast IS S_coast["d"].
        LOCAL cvel_coast IS S_coast["closing"].
        
        IF TIME:SECONDS - lastPrint >= 2.0 {
          DISP_LOG_UPDATE("Coast: " + ROUND(rng_coast, 0) + "m, " + ROUND(cvel_coast, 1) + "m/s").
          SET lastPrint TO TIME:SECONDS.
        }
        DISP_TICK().

        IF rng_coast <= renderRange {
          DISP_SUCCESS("Render range reached").
          BREAK.
        }

        IF rng_coast < 500 {
          DISP_WARN("Safety break at " + ROUND(rng_coast, 0) + "m").
          BREAK.
        }

        LOCK STEERING TO PROGRADE.
        WAIT AP_COAST_LOOP_DT.
      }
    }
  }

  DISP_LOG_UPDATE("Phase A: Velocity capture").
  RCS ON.
  SAS OFF.
  SET APP_COAST_LOCK TO FALSE.

  LOCAL t0 IS TIME:SECONDS.
  LOCAL phaseAIterations IS 0.
  LOCAL nextPulseUT IS TIME:SECONDS.
  
  UNTIL FALSE {
    LOCAL S IS APP_RELSTATE().
    LOCAL vmag IS S["v"]:MAG.
    LOCAL cvel IS S["closing"].
    LOCK STEERING TO LOOKDIRUP(S["los"], SHIP:FACING:TOPVECTOR).
    
    SET phaseAIterations TO phaseAIterations + 1.
    
    IF TIME:SECONDS - lastPrint >= 3.0 {
      DISP_LOG_UPDATE("Ph A: " + ROUND(S["d"], 0) + "m, " + ROUND(vmag, 2) + "m/s").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().
    
    IF vmag <= CAP_REL OR TIME:SECONDS - t0 > 45 {
      DISP_SUCCESS("Phase A complete").
      BREAK.
    }
    
    IF TIME:SECONDS >= nextPulseUT {
      APP_DUMP_RELVEL_CONT(CAP_REL, 8.0, 0.08).
      SET nextPulseUT TO TIME:SECONDS + PULSE_COOLDOWN.
    }
    WAIT 0.08.
  }

  LOCAL lastRng IS 0.
  LOCAL stallT0 IS TIME:SECONDS.
  DISP_LOG_UPDATE("Phase B: Window approach").
  
  LOCAL phaseBT0 IS TIME:SECONDS.
  SET nextPulseUT TO TIME:SECONDS.
  
  UNTIL FALSE {
    LOCAL S IS APP_RELSTATE().
    LOCAL rng IS S["d"].
    LOCAL vrel IS S["v"].
    LOCAL los IS S["los"].
    LOCAL cvel IS S["closing"].
    LOCAL parallel IS VDOT(vrel, los) * los.
    LOCAL vside IS vrel - parallel.
    LOCK STEERING TO LOOKDIRUP(los, SHIP:FACING:TOPVECTOR).
    
    IF TIME:SECONDS - lastPrint >= 3.0 {
      DISP_LOG_UPDATE("Ph B: " + ROUND(rng, 0) + "m, CV " + ROUND(cvel, 2) + "m/s").
      SET lastPrint TO TIME:SECONDS.
    }
    DISP_TICK().

    LOCAL vTow IS 0.0.
    IF rng > WIN_FAR {
      SET vTow TO 5.0.
    } ELSE IF cvel > 0.05 AND rng < WIN_NEAR {
      SET vTow TO -MIN(BACKOUTMAX, 0.4 + 0.005 * (WIN_NEAR - rng)).
    } ELSE {
      SET vTow TO 0.05.
    }
    IF cvel <= 0 AND vTow < KEEP_MIN { SET vTow TO KEEP_MIN. }

    LOCAL vGoal IS los * vTow.
    IF vside:MAG > 0.2 {
      SET vGoal TO vGoal - vside * 1.2.
    }
    LOCAL vErr IS vGoal - vrel.

    LOCAL pulseDur IS HOLD_DUR.
    IF vErr:MAG > 1.0 {
      SET pulseDur TO MIN(0.5, HOLD_DUR * 2).
    } ELSE IF vErr:MAG < 0.3 {
      SET pulseDur TO MAX(0.1, HOLD_DUR / 2).
    }

    IF vErr:MAG > DEADBAND_V AND TIME:SECONDS >= nextPulseUT {
      APP_DRIVE_VTOW(vGoal, 0.8, pulseDur).
      SET nextPulseUT TO TIME:SECONDS + PULSE_COOLDOWN.
    } ELSE {
      UTL_KILL_TRANSLATION().
    }

    IF lastRng > 0 {
      IF rng >= lastRng - 0.2 {
        IF TIME:SECONDS - stallT0 >= STALL_SEC {
          APP_PUSH_ALONG(los, 0.6, 0.40).
          SET stallT0 TO TIME:SECONDS.
          SET nextPulseUT TO TIME:SECONDS + PULSE_COOLDOWN.
        }
      } ELSE {
        SET stallT0 TO TIME:SECONDS.
      }
    } ELSE {
      SET stallT0 TO TIME:SECONDS.
    }
    SET lastRng TO rng.

    IF (rng >= WIN_NEAR) AND (rng <= WIN_FAR) AND (vrel:MAG < 0.5) {
      DISP_SUCCESS("Window acquired: " + ROUND(rng, 0) + "m").
      RETURN TRUE.
    }

    WAIT TICK_DT.
  }

  UTL_KILL_TRANSLATION().
  RETURN TRUE.
}