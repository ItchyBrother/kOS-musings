// ===============================================================
// dock.ks - Main Docking Script with Integrated Display System
// ===============================================================

GLOBAL lastPrint IS TIME:SECONDS.
GLOBAL INTERCEPT_T  IS 0.
GLOBAL INTERCEPT_D  IS 0.
GLOBAL INTERCEPT_VR IS 0.

// Mission-specific overrides
SET AP_PREBRAKE_START     TO 2500.
SET AP_PREBRAKE_VHIGH     TO 45.
SET AP_DEBUG              TO FALSE.
SET AP_START_ON_RENDER    TO TRUE.
SET AP_RENDER_RANGE       TO 2300.
SET AP_TRIGGER_Fallback   TO 0.
SET AP_STRICT_COAST       TO TRUE.
SET AP_ACTIVE_RANGE       TO 800.
SET AP_STRICT_LEAD        TO 10.
SET AP_VERBOSE_GATE       TO FALSE.
SET AP_WARPFACTOR         TO FALSE.

// Load all libraries
RUN ONCE "0:/lib/utils.ks".
RUN ONCE "0:/lib/display.ks".  // Display system first
RUN ONCE "0:/lib/target_picker.ks".
RUN ONCE "0:/lib/intercept_scan.ks".
RUN ONCE "0:/lib/refine_phase.ks".
RUN ONCE "0:/lib/approach.ks".
RUN ONCE "0:/lib/dock_align.ks".

PARAMETER targetName IS "", scanOrbits IS 5, samplesPerOrbit IS 300.

// Initialize the display system
DISP_INIT(SHIP:NAME, "AUTOMATED DOCKING").
DISP_STATUS("STARTUP", "Docking sequence initiated", "INITIALIZING").

// Reset systems
SHIP_RESET().
SAS OFF.
DISP_LOG_UPDATE("Systems reset complete").
WAIT 5.

// Align to prograde
RCS OFF.
//LOCK STEERING TO PROGRADE.
//DISP_LOG_UPDATE("Aligned to prograde").

// ===== STEP 1: TARGET SELECTION =====
DISP_STATUS("TARGET_SELECT", "Scanning for targets", "SCANNING").

IF NOT HASTARGET {
  IF NOT TGT_SELECT_ORBITING(targetName) {
    DISP_ERROR("Target selection failed - aborting").
    WAIT UNTIL FALSE.
  }
} ELSE {
  IF targetName <> "" AND TARGET:NAME <> targetName {
    IF NOT TGT_SELECT_ORBITING(targetName) {
      DISP_LOG_UPDATE("Keeping existing target: " + TARGET:NAME).
    }
  }
}
// Redraw display after target picker overwrites screen
DISP_FORCE_REDRAW().

GLOBAL ORIGINAL_TARGET_NAME IS TARGET:NAME.
DISP_SUCCESS("Target acquired: " + TARGET:NAME).

// Clear message queues before starting
DISP_LOG_UPDATE("Clearing message queues").
LOCAL clearedShip IS 0.
LOCAL clearedCore IS 0.
UNTIL SHIP:MESSAGES:EMPTY {
  LOCAL oldMsg IS SHIP:MESSAGES:POP.
  SET clearedShip TO clearedShip + 1.
}
UNTIL CORE:MESSAGES:EMPTY {
  LOCAL oldMsg IS CORE:MESSAGES:POP.
  SET clearedCore TO clearedCore + 1.
}
IF clearedShip > 0 OR clearedCore > 0 {
  DISP_LOG_UPDATE("Cleared " + clearedShip + " SHIP, " + clearedCore + " CORE messages").
}

// ===== STEP 1.5: RESUME CHECK =====
DISP_STATUS("RESUME_CHECK", "Analyzing trajectories", "SCANNING").

LOCAL resume IS RESUME_LOCK_NEARPASS(2500, 900, 3, 400).
LOCAL isResume IS resume["ok"].

IF isResume {
  DISP_SUCCESS("Resume trajectory found").
  DISP_LOG_UPDATE("Sep: " + ROUND(resume["d"]/1000, 1) + "km, ETA: " + ROUND((resume["t"] - TIME:SECONDS)/60, 1) + "min").
  
  SET INTERCEPT_T TO resume["t"].
  SET INTERCEPT_D TO resume["d"].
  SET INTERCEPT_VR TO resume["v"].
  DISP_SET_INTERCEPT(INTERCEPT_T, INTERCEPT_D, INTERCEPT_VR).
  
  DISP_STATUS("", "Using existing intercept", "TRAJECTORY LOCKED").
}

// ===== STEP 2: RENDEZVOUS (IF NOT RESUMING) =====
IF NOT isResume {
  DISP_STATUS("RENDEZVOUS", "Computing rendezvous", "CALCULATING").
  
  LOCAL rendezvous_success IS RENDEZVOUS_EXECUTE(AP_ACTIVE_RANGE).
  
  IF NOT rendezvous_success {
    DISP_SET_GUIDANCE("DOCKING SYSTEM FAILED").
    DISP_UPDATE().
    DISP_ERROR("Rendezvous planning failed").
    DISP_ERROR("Please do manual Rendezvous..").
    DISP_ERROR("..or restart Docking Process.").
    WAIT UNTIL FALSE.
  }
  
  DISP_SET_INTERCEPT(INTERCEPT_T, INTERCEPT_D, INTERCEPT_VR).
  DISP_SUCCESS("Rendezvous trajectory computed").
  DISP_LOG_UPDATE("Sep: " + ROUND(INTERCEPT_D, 0) + "m, ETA: " + ROUND((INTERCEPT_T - TIME:SECONDS)/60, 1) + "min").
}

// ===== STEP 3: APPROACH =====
SET approach_t TO INTERCEPT_T.
DISP_STATUS("APPROACH", "Long-range RCS approach", "EXECUTING").

IF NOT APPROACH_RCS(2300, 0, approach_t, 0) {
  DISP_ERROR("Approach sequence failed").
  WAIT UNTIL FALSE.
}

// Verify we're in proper window
LOCAL S_check IS APP_RELSTATE().
IF S_check["d"] > AP_WINDOW_FAR {
  DISP_WARN("Not in 200-400m window - retrying").
  
  IF NOT APPROACH_RCS(2300, 0, 0, 0) {
    DISP_ERROR("Approach retry failed").
    WAIT UNTIL FALSE.
  }
  
  SET S_check TO APP_RELSTATE().
  IF S_check["d"] > AP_WINDOW_FAR {
    DISP_ERROR("Still not in window - aborting").
    WAIT UNTIL FALSE.
  }
}

DISP_SUCCESS("Approach complete").

// ===== STEP 4: WINDOW HOLD (200-400m) =====
SET APP_COAST_LOCK TO FALSE.
SAS OFF.
RCS ON.

DISP_STATUS("WINDOW_HOLD", "Stationkeeping 200-400m", "HOLDING").
DCK_WINDOW_HOLD(AP_WINDOW_NEAR, AP_WINDOW_FAR, AP_STATION_VHOLD, AP_HOLD_STABLE_S).

// ===== STEP 5: PROMPT FOR 200-400m PROCEED =====
DISP_STATUS("PROMPT_200M", "Awaiting operator input", "OPERATOR INPUT REQUIRED").

IF NOT DCK_PROMPT_PROCEED(AP_WINDOW_NEAR, AP_WINDOW_FAR, AP_PROMPT_POLL, 300) {
  DISP_LOG_UPDATE("Operator aborted - holding position").
  DISP_STATUS("WINDOW_HOLD", "Manual hold", "HOLDING").
  WAIT 999999.
}

DISP_SUCCESS("Operator authorized proceed").

// ===== STEP 6: APPROACH TO 50m =====
DISP_STATUS("APPROACH_50M", "Close approach to 50m", "PRECISION APPROACH").

IF NOT DCK_AP_50M(45, 55, AP_STATION_VHOLD, AP_HOLD_STABLE_S) {
  LOCAL S_err IS APP_RELSTATE().
  DISP_ERROR("50m approach failed at " + ROUND(S_err["d"], 1) + "m").
  WAIT UNTIL FALSE.
}

DISP_SUCCESS("50m window acquired").

// ===== STEP 6.5: BREAKOUT =====
DISP_STATUS("BREAKOUT", "Breaking out for approach", "BREAKOUT").

IF NOT DCK_BREAKOUT_FORWARD(0.8, 12, 40) {
  LOCAL S_warn IS APP_RELSTATE().
  DISP_WARN("Breakout incomplete - continuing").
}

DISP_SUCCESS("Breakout complete").

// ===== STEP 7: PORT ALIGNMENT =====
DISP_STATUS("ALIGN_PORTS", "Aligning docking ports", "PRECISION CONTROL").
DCK_ALIGN_PORTS("DOCK_A", "DOCK_A", 3.0, 5.0, 0.1).
DISP_SUCCESS("Ports aligned").

// ===== STEP 8: FINAL APPROACH =====
DISP_STATUS("FINAL_DOCK", "Final docking sequence", "TERMINAL GUIDANCE").

IF NOT DCK_FINAL_APPROACH("DOCK_A", "DOCK_A", 0.12) {
  LOCAL S_err IS APP_RELSTATE().
  DISP_ERROR("Final approach failed at " + ROUND(S_err["d"], 1) + "m").
  WAIT UNTIL FALSE.
}

// ===== MISSION COMPLETE =====
DISP_STATUS("COMPLETE", "Docking successful", "MISSION COMPLETE").
DISP_LOG_UPDATE("All systems nominal").
DISP_LOG_UPDATE("Mission elapsed time: " + ROUND((TIME:SECONDS - DISP_PHASE_START_TIME)/60, 1) + " minutes").
WAIT 5.
UTL_KILL_TRANSLATION().
SHIP_RESET().