// ============================================================
//  falcon9_rtls.ks
//
//  CORE PRINCIPLE:
//    Every phase guides against the PREDICTED LANDING POINT,
//    not against current position. Current position tells you
//    where you are. The predictor tells you where you'll land.
//    Those are very different things during a ballistic arc.
//
//  PHASES:
//    FLIP       : rotate nose to pad bearing
//    BOOSTBACK  : smoothed-predictor guidance, both N and E axes
//    COAST      : predictor-guided fin steering (reliable — no thrust)
//    ENTRY      : entry burn only if speed > threshold
//    AERO       : velocity-tracking toward pad, higher authority
//    LANDING    : PD kill horizontal, straight down
//    TOUCHDOWN  : cleanup
//
//  NO STATIC BIASES. The predictor handles both axes.
//
//  TUNING (only if needed):
//    BB_STOP_ATM_M    — atmospheric predictor stop radius (default 200m)
//    AERO_MAX_LEAN    — fin lean authority in AERO phase (degrees)
//
//  Usage:
//    RUN falcon9_rtls(PAD_LAT, PAD_LNG).
//
//  Action Groups:
//    AG1  Grid fins deploy
//    AG2  Enable 3 center engines
//    GEAR Landing legs
// ============================================================

@LAZYGLOBAL OFF.

PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.

// ============================================================
//  CONSTANTS
// ============================================================
LOCAL KERBIN_M_PER_DEG IS 10471.
LOCAL LOG_FILE         IS "0:/rtls_log.txt".
LOCAL LOG_INTERVAL     IS 2.0.

// ---- Boostback ----
// NORTH AXIS: feedforward + velocity feedback.
//   The pad bearing is ~265 deg (south of west). A pure pad-bearing burn
//   has built-in southward thrust that the feedback alone cannot overcome
//   (feedback max of 5 deg only reaches 270 deg = neutral, never northward).
//
//   Fix: aim at 270 deg (due west = zero north/south component) as the base,
//   then add velocity feedback for north/south trim. This way:
//     equilibrium is at desNVel (no constant disturbance to fight)
//     feedback only handles transients
//     works for any pad bearing — 270 is always north/south neutral
//
//   aimBrng = 270 + Clamp(-(northVelNow - desNVel) * BB_VEL_GAIN, -cap, +cap)
//
// EAST AXIS: raw predictor stop condition (proven, fast).
LOCAL BB_PRED_INTERVAL   IS 0.5.
LOCAL BB_VEL_GAIN        IS 1.5.    // velocity feedback gain (deg per m/s)
LOCAL BB_NORTH_VEL_GAIN  IS 0.007.  // position-to-desired-velocity scale
LOCAL BB_MAX_CORR_DEG    IS 8.0.    // max bearing offset from 270 deg
// BB_STOP_EAST_M: vacuum predictor stop margin (m east of pad).
//   Stop when vacuum predictor shows impact this far east of pad.
//   Atmosphere shortens range ~600m, so 600 ≈ lands on pad.
//   Tune: land west → raise, land east → lower.
LOCAL BB_STOP_EAST_M     IS 600.
// BB_STOP_ATM_M retained for reference (atm predictor too inaccurate
// for stop decisions — 2s steps give 3-4km error over 300s trajectory).
LOCAL BB_STOP_ATM_M      IS 0.
LOCAL BB_FULL_THR_EAST IS -8000.
LOCAL BB_MID_THR_EAST  IS -3000.
LOCAL BB_LOW_THR_EAST  IS -800.
LOCAL BB_MAX_TIME      IS 90.

// ---- Entry ----
LOCAL ENTRY_ALT             IS 40000.
LOCAL ENTRY_SPEED_THRESHOLD IS 650.
LOCAL ENTRY_END_SPEED       IS 350.

// ---- Fins ----
LOCAL FIN_AUTH_COAST IS 15.
LOCAL FIN_AUTH_AERO  IS 35.
LOCAL FIN_AUTH_LAND  IS 8.

// ---- Aero guidance (position/velocity tracking) ----
// Higher Kp and lower max vel prevents the overshoot we saw.
// Reduced deadband (10m) ensures correction continues close in.
LOCAL AERO_POS_KP    IS 0.020.
LOCAL AERO_MAX_HVEL  IS 10.0.
LOCAL AERO_VEL_KP    IS 0.28.
LOCAL AERO_MAX_ACC   IS 3.5.
LOCAL AERO_UP_BIAS   IS 18.0.
LOCAL AERO_MAX_LEAN  IS 10.0.
LOCAL AERO_DEADBAND  IS 10.0.

// ---- Landing ----
LOCAL LEG_DEPLOY_ALT    IS 500.
LOCAL LAND_GUIDE_ALT    IS 250.
LOCAL LAND_UP_BIAS_ACC  IS 21.0.
LOCAL LAND_POS_KP       IS 0.030.
LOCAL LAND_POS_KP_LOW   IS 0.014.
LOCAL LAND_MAX_VEL      IS 5.0.
LOCAL LAND_MAX_VEL_LOW  IS 2.0.
LOCAL LAND_VEL_KP       IS 0.18.
LOCAL LAND_VEL_KP_LOW   IS 0.24.
LOCAL LAND_MAX_ACC      IS 15.0.
LOCAL LAND_MAX_ACC_LOW  IS 3.0.
LOCAL LAND_MAX_TILT     IS 35.0.
LOCAL LAND_MAX_TILT_LOW IS 10.0.
LOCAL LAND_THR_KP       IS 0.60.
LOCAL LAND_THR_KP_LOW   IS 0.90.
LOCAL TOUCHDOWN_VS      IS -3.5.
LOCAL TOUCHDOWN_HS      IS 2.5.
LOCAL TERM_LOCK_MISS          IS 120.
LOCAL TERM_LOCK_HS            IS 35.
LOCAL TERM_LOCK_LEAN          IS 7.
LOCAL TERM_LOCK_LEAN_EARLY    IS 12.
LOCAL TERM_CAPTURE_VEL_KP     IS 0.55.
LOCAL TERM_CAPTURE_POS_KP     IS 0.010.
LOCAL TERM_CAPTURE_MAXVEL     IS 1.6.
LOCAL TERM_CAPTURE_MAXACC     IS 14.0.
LOCAL TERM_CAPTURE_MAXACC_LOW IS 7.0.
LOCAL TERM_UP_BIAS            IS 22.0.
LOCAL TERM_GEAR_ALT           IS 180.
LOCAL TERM_GEAR_TTD           IS 3.2.
LOCAL vesselBounds      IS SHIP:BOUNDS.

// ============================================================
//  PHASE IDS
// ============================================================
LOCAL PH_FLIP      IS 0.
LOCAL PH_BOOSTBACK IS 1.
LOCAL PH_COAST     IS 2.
LOCAL PH_ENTRY     IS 3.
LOCAL PH_AERO      IS 4.
LOCAL PH_LANDING   IS 5.
LOCAL PH_TOUCHDOWN IS 6.

LOCAL PHASE_NAMES IS LIST(
    "FLIP", "BOOSTBACK", "COAST", "ENTRY", "AERO", "LANDING", "TOUCHDOWN"
).

// ============================================================
//  STATE
// ============================================================
LOCAL phase           IS PH_FLIP.
LOCAL padGeo          IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL PAD_ALT         IS padGeo:TERRAINHEIGHT.
LOCAL lastPredTime    IS -999.
LOCAL lastLogTime     IS -999.
LOCAL bbStartTime     IS 0.
LOCAL finsOut         IS FALSE.
LOCAL finsAeroSet     IS FALSE.
LOCAL finsLandSet     IS FALSE.
LOCAL legsOut         IS FALSE.
LOCAL termLocked      IS FALSE.
LOCAL gearForced      IS FALSE.
LOCAL touchdownSeen   IS FALSE.
LOCAL DRAG_SAVE_FILE  IS "0:/rtls_cdam.txt". // persists CdAm between flights
LOCAL dragCdAm        IS 0.010.  // CdA/mass (m²/kg). Updated by calibration.
LOCAL dragCalibrated  IS FALSE.  // TRUE once we have a real measurement.
LOCAL atmPredReady    IS FALSE.
LOCAL dragLastVel     IS 0.
LOCAL dragLastTime    IS -999.

// Smoothed predictor state (EMA).

// ============================================================
//  UTILITY
// ============================================================
FUNCTION Clamp {
    PARAMETER valIn, loIn, hiIn.
    IF valIn < loIn { RETURN loIn. }
    IF valIn > hiIn { RETURN hiIn. }
    RETURN valIn.
}

FUNCTION distKm {
    PARAMETER geoA, geoB.
    RETURN (geoA:POSITION - geoB:POSITION):MAG / 1000.
}

FUNCTION bearingTo {
    PARAMETER targetGeo.
    LOCAL lat IS SHIP:GEOPOSITION:LAT.
    LOCAL bDeg IS ARCTAN2(
        (targetGeo:LNG - SHIP:GEOPOSITION:LNG) * COS(lat),
        targetGeo:LAT - lat
    ).
    IF bDeg < 0 { SET bDeg TO bDeg + 360. }
    RETURN bDeg.
}

FUNCTION hSpeed {
    RETURN SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
}

FUNCTION terrainAGL {
    LOCAL radarAlt IS vesselBounds:BOTTOMALTRADAR.
    IF radarAlt < 0 { RETURN 0. }
    RETURN radarAlt.
}

FUNCTION rotVec {
    PARAMETER vecIn, axisIn, deg.
    LOCAL cosA IS COS(deg). LOCAL sinA IS SIN(deg).
    RETURN vecIn*cosA + VCRS(axisIn,vecIn)*sinA + axisIn*VDOT(axisIn,vecIn)*(1-cosA).
}

FUNCTION northErrM {
    RETURN (PAD_LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
}

FUNCTION eastErrM {
    RETURN (PAD_LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE).
}

FUNCTION nsText {
    PARAMETER mVal.
    IF mVal >= 0 { RETURN "N:" + ROUND(mVal,0). }
    RETURN "S:" + ROUND(ABS(mVal),0).
}

FUNCTION ewText {
    PARAMETER mVal.
    IF mVal >= 0 { RETURN "E:" + ROUND(mVal,0). }
    RETURN "W:" + ROUND(ABS(mVal),0).
}

// ============================================================
//  LOGGING
// ============================================================
FUNCTION logOpen {
    IF EXISTS(LOG_FILE) { DELETEPATH(LOG_FILE). }
    LOG "RTLS Log v4 - Pad: " + PAD_LAT + " / " + PAD_LNG + " / " + PAD_ALT TO LOG_FILE.
    LOG "T+sec | Phase | Alt km | VS m/s | Hspd m/s | Pad km | Thr% | Message" TO LOG_FILE.
    LOG "----------------------------------------------------------------------" TO LOG_FILE.
}

FUNCTION logLine {
    PARAMETER msg.
    LOCAL tsVal IS ROUND(TIME:SECONDS,1).
    LOCAL altKm IS ROUND(SHIP:ALTITUDE/1000,2).
    LOCAL vsVal IS ROUND(SHIP:VERTICALSPEED,1).
    LOCAL hsVal IS ROUND(hSpeed(),1).
    LOCAL padVal IS ROUND(distKm(SHIP:GEOPOSITION,padGeo),2).
    LOCAL thrPct IS ROUND(THROTTLE*100,0).
    LOG "T+"+tsVal+" | "+PHASE_NAMES[phase]+" | "+altKm+"km | VS:"+vsVal
        +" | H:"+hsVal+" | Pad:"+padVal+"km | Thr:"+thrPct+"% | "+msg TO LOG_FILE.
}

FUNCTION logEvent {
    PARAMETER msg.
    logLine("*** "+msg+" ***").
}

FUNCTION logPeriodic {
    PARAMETER msg IS "".
    IF (TIME:SECONDS - lastLogTime) >= LOG_INTERVAL {
        logLine(msg).
        SET lastLogTime TO TIME:SECONDS.
    }
}

// ============================================================
//  ACTION GROUPS AND FINS
// ============================================================
FUNCTION activateAG {
    PARAMETER agNum.
    IF agNum=1 { AG1 ON. } ELSE IF agNum=2 { AG2 ON. }
    ELSE IF agNum=3 { AG3 ON. } ELSE IF agNum=4 { AG4 ON. }
}

FUNCTION setFinAuthority {
    PARAMETER pct.
    FOR partRef IN SHIP:PARTS {
        IF partRef:HASMODULE("ModuleControlSurface") {
            LOCAL finMod IS partRef:GETMODULE("ModuleControlSurface").
            IF finMod:HASFIELD("authority limiter") { finMod:SETFIELD("authority limiter",pct). }
        }
    }
}

// ============================================================
//  BALLISTIC PREDICTOR
//  Reliable when not thrusting (coast phase).
//  Noisy when thrusting (boostback) — use EMA to smooth.
// ============================================================
FUNCTION predictImpact {
    LOCAL muVal    IS BODY:MU.
    LOCAL bodyRad IS BODY:RADIUS.
    LOCAL bPos0   IS BODY:POSITION.
    LOCAL pos     IS -bPos0.
    LOCAL vel     IS SHIP:VELOCITY:ORBIT.
    LOCAL rotPer  IS BODY:ROTATIONPERIOD.
    LOCAL rotAxis IS V(0,1,0).
    IF BODY:ANGULARVEL:MAG > 0.000001 { SET rotAxis TO BODY:ANGULARVEL:NORMALIZED. }

    LOCAL dtStep IS 5. LOCAL tofVal IS 0.
    UNTIL tofVal > 1500 {
        LOCAL posMag IS pos:MAG.
        LOCAL acc0  IS -(muVal/(posMag^3))*pos.
        LOCAL posMid IS pos + vel*(dtStep/2).
        LOCAL velMid IS vel + acc0*(dtStep/2).
        LOCAL accMid IS -(muVal/(posMid:MAG^3))*posMid.
        SET pos TO pos + velMid*dtStep.
        SET vel TO vel + accMid*dtStep.
        SET tofVal TO tofVal + dtStep.
        IF pos:MAG - bodyRad <= PAD_ALT {
            LOCAL rotDeg IS 360*tofVal/rotPer.
            RETURN BODY:GEOPOSITIONOF(rotVec(pos,rotAxis,-rotDeg)+bPos0).
        }
    }
    RETURN SHIP:GEOPOSITION.
}

// Simple cached predictor — avoids calling full predictor every cycle.
LOCAL cachedImpact IS LATLNG(PAD_LAT, PAD_LNG).

FUNCTION predictImpact_cached {
    IF (TIME:SECONDS - lastPredTime) >= BB_PRED_INTERVAL {
        SET cachedImpact TO predictImpact().
        SET lastPredTime TO TIME:SECONDS.
    }
    RETURN cachedImpact.
}

// ============================================================
//  AERO EAST-ONLY GUIDANCE
//  North: pure retrograde (no lean — prevents the velocity reversal
//         oscillation that plagued earlier versions).
//  East:  gentle lean to correct east/west trajectory errors.
//         Safe because east lean acts AGAINST the ~95 m/s westward
//         velocity (drag-like), so it slows westward drift rather than
//         reversing it. No oscillation risk.
//  Max lean: 4 degrees. Gain: conservative to avoid amplification.
// ============================================================
FUNCTION aeroEastGuideDir {
    // East-only lateral guidance. North stays pure retrograde.
    //
    // Key safety rule: desired east velocity capped at 2 m/s.
    // This prevents the guidance building up large eastward velocity
    // when east error is large (e.g. 4km+). With 80+ m/s eastward
    // at landing ignition the landing guidance cannot recover.
    //
    // Additional guard: if already moving east faster than desE,
    // command zero (don't keep pushing east). This stops overshoot
    // regardless of how large the position error is.
    LOCAL retroVec  IS SHIP:SRFRETROGRADE:FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90, 0):FOREVECTOR.

    LOCAL eastPosErr IS eastErrM().
    LOCAL eastVelNow IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    // Desired east velocity: small cap regardless of position error.
    LOCAL desE IS Clamp(eastPosErr * 0.015, -2.0, 2.0).
    IF ABS(eastPosErr) < 30 { SET desE TO 0. }

    // If already moving in the correction direction faster than desired,
    // don't add more — let the natural trajectory carry us.
    IF desE > 0 AND eastVelNow >= desE { RETURN LOOKDIRUP(retroVec, SHIP:FACING:TOPVECTOR). }
    IF desE < 0 AND eastVelNow <= desE { RETURN LOOKDIRUP(retroVec, SHIP:FACING:TOPVECTOR). }

    LOCAL accE IS Clamp((desE - eastVelNow) * 0.06, -1.0, 1.0).

    LOCAL latVec IS eastAxis * accE.
    IF latVec:MAG < 0.05 {
        RETURN LOOKDIRUP(retroVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxMag IS 18.0 * TAN(3.0).
    IF latVec:MAG > maxMag { SET latVec TO latVec:NORMALIZED * maxMag. }

    LOCAL steerVec IS (retroVec * 18.0 + latVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  ATMOSPHERIC DRAG PREDICTOR
//
//  Kerbin exponential atmosphere:
//    rho(alt) = RHO0 * e^(-alt / H_SCALE)
//    RHO0 = 1.225 kg/m³,  H_SCALE = 5600 m
//
//  Drag deceleration:
//    a_drag = 0.5 * rho * v² * (CdA/mass)
//
//  CdA/mass is calibrated once from actual flight data in early AERO.
//  After calibration, the atmospheric predictor gives accurate landing
//  predictions — no pad-specific stop margin needed.
//
//  Integration: simple Euler, 2-second steps, stops at PAD_ALT.
//  At boostback altitudes (35-40 km) the atmosphere is thin enough
//  that 2s steps give < 50m error in predicted landing position.
// ============================================================

LOCAL ATM_RHO0   IS 1.225.   // sea-level density kg/m³
LOCAL ATM_HSCALE IS 5600.    // scale height m

FUNCTION atmDensity {
    PARAMETER altM.
    IF altM > 70000 { RETURN 0. }
    RETURN ATM_RHO0 * CONSTANT:E ^ (-altM / ATM_HSCALE).
}

// Calibrate CdA/mass from observed deceleration.
// Call once during early AERO when we have real aero forces.
FUNCTION calibrateDrag {
    // Measure drag by comparing velocity over a short interval.
    // No sensor part required — just velocity and time.
    // Call every cycle in AERO (engines off). After two samples
    // separated by at least 1 second, compute deceleration,
    // subtract gravity, attribute remainder to drag, solve for CdA/mass.
    LOCAL velMag IS SHIP:VELOCITY:SURFACE:MAG.
    LOCAL nowT   IS TIME:SECONDS.

    IF dragLastTime < 0 {
        // First call — just record baseline
        SET dragLastVel  TO velMag.
        SET dragLastTime TO nowT.
        RETURN.
    }

    LOCAL dtVal IS nowT - dragLastTime.
    IF dtVal < 1.0 { RETURN. }   // wait for meaningful interval

    LOCAL dvVal    IS dragLastVel - velMag.  // positive = decelerating
    LOCAL measAccel IS dvVal / dtVal.        // total decel magnitude

    LOCAL gravAccel IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL rhoNow    IS atmDensity(SHIP:ALTITUDE).

    // Drag decel = total decel minus vertical gravity component
    // (during retrograde descent, gravity adds to speed, drag removes it)
    // Net: measAccel ≈ dragAccel - gravAccel*cos(angle) but during steep
    // near-vertical descent cos≈1, so: dragAccel ≈ measAccel + gravAccel
    LOCAL dragAccel IS measAccel + gravAccel.

    IF dragAccel < 0.5 OR velMag < 100 OR rhoNow < 0.0001 {
        SET dragLastVel  TO velMag.
        SET dragLastTime TO nowT.
        RETURN.
    }

    LOCAL cdamCalc IS (2 * dragAccel) / (rhoNow * velMag * velMag).
    IF cdamCalc > 0.001 AND cdamCalc < 0.05 {
        SET dragCdAm       TO cdamCalc.
        SET dragCalibrated TO TRUE.
        // Save to disk so next flight can use it during boostback.
        IF EXISTS(DRAG_SAVE_FILE) { DELETEPATH(DRAG_SAVE_FILE). }
        LOG cdamCalc TO DRAG_SAVE_FILE.
        logEvent("Drag calibrated CdAm:"+ROUND(dragCdAm,5)
                 +" rho:"+ROUND(rhoNow,4)
                 +" dragA:"+ROUND(dragAccel,2)
                 +" dt:"+ROUND(dtVal,1)
                 +" v:"+ROUND(velMag,0)).
    }
    // Keep sampling to refine estimate
    SET dragLastVel  TO velMag.
    SET dragLastTime TO nowT.
}

// Atmospheric trajectory predictor.
// Integrates forward from current position with drag.
// Returns predicted geoposition at pad altitude.
FUNCTION predictImpactAtm {
    LOCAL muVal    IS BODY:MU.
    LOCAL bodyRad  IS BODY:RADIUS.
    LOCAL rotPer   IS BODY:ROTATIONPERIOD.
    LOCAL rotAxis  IS V(0,1,0).
    IF BODY:ANGULARVEL:MAG > 0.000001 {
        SET rotAxis TO BODY:ANGULARVEL:NORMALIZED.
    }

    // Work in body-fixed vectors (surface velocity)
    LOCAL posVec IS -BODY:POSITION.         // ship pos relative to body center
    LOCAL velSrf IS SHIP:VELOCITY:SURFACE.  // surface-relative velocity
    // Convert to orbital-frame velocity for integration
    LOCAL bodyAngVel IS BODY:ANGULARVEL.
    LOCAL velOrb IS velSrf + VCRS(bodyAngVel, posVec).

    LOCAL tofVal IS 0.

    UNTIL tofVal > 600 {  // 600s covers full trajectory
        // Adaptive step: coarse above 25km (thin air),
        // fine below 25km where drag dominates accuracy.
        LOCAL dtStep IS 2.0.
        LOCAL altNowKm IS (posVec:MAG - bodyRad) / 1000.
        IF altNowKm < 25 { SET dtStep TO 1.0. }
        IF altNowKm < 10 { SET dtStep TO 0.5. }
        LOCAL posMag   IS posVec:MAG.
        // Gravity
        LOCAL gravAcc IS -(muVal / (posMag^3)) * posVec.

        // Drag (surface-velocity based)
        LOCAL velSrfNow IS velOrb - VCRS(bodyAngVel, posVec).
        LOCAL velMag    IS velSrfNow:MAG.
        LOCAL altNow    IS posMag - bodyRad.
        LOCAL rhoNow    IS atmDensity(altNow).
        LOCAL dragMag   IS 0.5 * rhoNow * velMag * velMag * dragCdAm.
        LOCAL dragVec   IS V(0,0,0).
        IF velMag > 0.1 {
            SET dragVec TO -(velSrfNow:NORMALIZED) * dragMag.
        }

        LOCAL totalAcc IS gravAcc + dragVec.

        // Euler step
        SET posVec TO posVec + velOrb * dtStep.
        SET velOrb TO velOrb + totalAcc * dtStep.
        SET tofVal TO tofVal + dtStep.

        IF posVec:MAG - bodyRad <= PAD_ALT {
            LOCAL rotDeg IS 360 * tofVal / rotPer.
            RETURN BODY:GEOPOSITIONOF(rotVec(posVec, rotAxis, -rotDeg) + BODY:POSITION).
        }
    }
    RETURN SHIP:GEOPOSITION.
}

// ============================================================
//  IGNITION ALTITUDE
// ============================================================
FUNCTION ignitionAlt {
    LOCAL vsAbs  IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL gravAcc IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL aMax IS (MAXTHRUST / SHIP:MASS) - gravAcc.
    IF aMax < 0.5 { RETURN 5000. }
    RETURN (vsAbs*vsAbs)/(2*aMax)*0.88 + 30.
}


// ============================================================
//  AERO GUIDANCE
//  Velocity-tracking toward pad. Higher authority than coast.
//  Uses actual position/velocity, not predictor (aero not modeled
//  in vacuum predictor, so predictor is inaccurate below ~30km).
// ============================================================
FUNCTION aeroGuideDir {
    LOCAL retroVec IS SHIP:SRFRETROGRADE:FOREVECTOR.
    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.

    // Position error: where is pad relative to us?
    LOCAL northPos IS northErrM().
    LOCAL eastPos  IS eastErrM().

    // Velocity components.
    LOCAL northVel IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eastVel  IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    // Desired lateral velocity proportional to position error.
    LOCAL desN IS Clamp(northPos * AERO_POS_KP, -AERO_MAX_HVEL, AERO_MAX_HVEL).
    LOCAL desE IS Clamp(eastPos  * AERO_POS_KP, -AERO_MAX_HVEL, AERO_MAX_HVEL).
    IF ABS(northPos) < AERO_DEADBAND { SET desN TO 0. }
    IF ABS(eastPos)  < AERO_DEADBAND { SET desE TO 0. }

    // Lateral acceleration to reach desired velocity.
    LOCAL accN IS Clamp((desN - northVel) * AERO_VEL_KP, -AERO_MAX_ACC, AERO_MAX_ACC).
    LOCAL accE IS Clamp((desE - eastVel)  * AERO_VEL_KP, -AERO_MAX_ACC, AERO_MAX_ACC).

    LOCAL latVec IS northAxis*accN + eastAxis*accE.
    IF latVec:MAG < 0.05 {
        RETURN LOOKDIRUP(retroVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxMag IS AERO_UP_BIAS * TAN(AERO_MAX_LEAN).
    IF latVec:MAG > maxMag { SET latVec TO latVec:NORMALIZED * maxMag. }

    LOCAL steerVec IS (retroVec * AERO_UP_BIAS + latVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  LANDING GUIDANCE
// ============================================================
FUNCTION timeToTouchdown {
    LOCAL aglM IS MAX(0, terrainAGL()).
    LOCAL vsDn IS MAX(0.1, -SHIP:VERTICALSPEED).
    RETURN aglM / vsDn.
}

FUNCTION maybeDeployGear {
    IF gearForced { RETURN. }
    LOCAL aglM IS terrainAGL().
    LOCAL ttd  IS timeToTouchdown().
    IF aglM < TERM_GEAR_ALT OR ttd < TERM_GEAR_TTD {
        GEAR ON.
        SET gearForced TO TRUE.
        SET legsOut TO TRUE.
        logEvent("GEAR ON agl:"+ROUND(aglM,0)+" ttd:"+ROUND(ttd,1)).
    }
}

FUNCTION landingGuideDir {
    LOCAL altAGL IS terrainAGL().
    LOCAL upVec  IS UP:FOREVECTOR.
    LOCAL hsLand IS hSpeed().
    LOCAL nErr   IS northErrM().
    LOCAL eErr   IS eastErrM().
    LOCAL missM  IS SQRT(nErr*nErr + eErr*eErr).

    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.
    LOCAL nVel      IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eVel      IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    IF NOT termLocked {
        IF (missM < TERM_LOCK_MISS AND hsLand < TERM_LOCK_HS)
           OR (ABS(nErr) < 60 AND ABS(eErr) < 60) {
            SET termLocked TO TRUE.
        }
    }

    LOCAL maxTlt IS TERM_LOCK_LEAN_EARLY.
    LOCAL maxAcc IS TERM_CAPTURE_MAXACC.
    IF altAGL < 800 {
        SET maxTlt TO TERM_LOCK_LEAN.
        SET maxAcc TO TERM_CAPTURE_MAXACC_LOW.
    }

    LOCAL accN IS 0.
    LOCAL accE IS 0.

    IF termLocked {
        LOCAL desN IS Clamp(nErr * TERM_CAPTURE_POS_KP, -TERM_CAPTURE_MAXVEL, TERM_CAPTURE_MAXVEL).
        LOCAL desE IS Clamp(eErr * TERM_CAPTURE_POS_KP, -TERM_CAPTURE_MAXVEL, TERM_CAPTURE_MAXVEL).
        IF ABS(nErr) < 20 { SET desN TO 0. }
        IF ABS(eErr) < 20 { SET desE TO 0. }
        SET accN TO Clamp((desN - nVel) * TERM_CAPTURE_VEL_KP, -maxAcc, maxAcc).
        SET accE TO Clamp((desE - eVel) * TERM_CAPTURE_VEL_KP, -maxAcc, maxAcc).
    } ELSE {
        LOCAL desN IS Clamp(nErr * 0.020, -8, 8).
        LOCAL desE IS Clamp(eErr * 0.020, -8, 8).
        SET accN TO Clamp((desN - nVel) * 0.35, -maxAcc, maxAcc).
        SET accE TO Clamp((desE - eVel) * 0.35, -maxAcc, maxAcc).
    }

    LOCAL latVec IS northAxis*accN + eastAxis*accE.
    IF latVec:MAG < 0.03 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxMag IS TERM_UP_BIAS * TAN(maxTlt).
    IF latVec:MAG > maxMag { SET latVec TO latVec:NORMALIZED * maxMag. }

    LOCAL steerVec IS (upVec * TERM_UP_BIAS + latVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

FUNCTION landingThrottle {
    LOCAL aglM     IS MAX(0, terrainAGL()).
    LOCAL gravAcc  IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL vsNow    IS SHIP:VERTICALSPEED.
    LOCAL tgtVs    IS -110.
    LOCAL thrKp    IS 0.85.

    IF aglM > 2500      { SET tgtVs TO -130. }
    ELSE IF aglM > 1200 { SET tgtVs TO -110. }
    ELSE IF aglM > 600  { SET tgtVs TO -85.  }
    ELSE IF aglM > 250  { SET tgtVs TO -55.  }
    ELSE IF aglM > 120  { SET tgtVs TO -28.  }
    ELSE IF aglM > 60   { SET tgtVs TO -14.  }
    ELSE IF aglM > 20   { SET tgtVs TO -6.   }
    ELSE                { SET tgtVs TO -2.5. }

    IF aglM > 120 {
        IF vsNow > -0.3 { RETURN 0. }
        IF vsNow > tgtVs + 8 { RETURN 0.05. }
    }

    LOCAL rawThr IS (SHIP:MASS * (gravAcc + (tgtVs - vsNow) * thrKp)) / MAXTHRUST.
    LOCAL outThr IS Clamp(rawThr, 0, 1).

    IF aglM > 120 AND vsNow < -80 {
        IF outThr < 0.18 { SET outThr TO 0.18. }
    }

    RETURN outThr.
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START - Pad:"+PAD_LAT+"/"+PAD_LNG+" terrainAlt:"+ROUND(PAD_ALT,2)).

// Load persisted drag coefficient from previous flight (if available).
// This allows the atmospheric predictor to be accurate during boostback.
IF EXISTS(DRAG_SAVE_FILE) {
    LOCAL fileContent IS OPEN(DRAG_SAVE_FILE):READALL.
    LOCAL savedCdAm   IS fileContent:STRING:TONUMBER.
    IF savedCdAm > 0.001 AND savedCdAm < 0.05 {
        SET dragCdAm      TO savedCdAm.
        SET dragCalibrated TO TRUE.
        logEvent("Loaded saved CdAm:"+ROUND(dragCdAm,5)).
    }
}

PRINT "+------------------------------------+" AT (0,0).
PRINT "| F9 RTLS v4 — PREDICTOR GUIDED     |" AT (0,1).
PRINT "+------------------------------------+" AT (0,2).
PRINT "Pad: "+ROUND(PAD_LAT,6)+" / "+ROUND(PAD_LNG,6) AT (0,3).
PRINT "Alt: "+ROUND(PAD_ALT,0)+"m" AT (0,4).
PRINT "Terrain alt auto from target LAT/LNG." AT (0,5).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF. RCS ON.
SET termLocked TO FALSE.
SET gearForced TO FALSE.
GEAR OFF.
SET legsOut TO FALSE.
activateAG(2).
logEvent("AG2 fired - 3 engines enabled").

// ============================================================
//  MAIN LOOP
// ============================================================
UNTIL phase = PH_TOUCHDOWN {

    LOCAL altAGL IS terrainAGL().
    LOCAL hspd    IS hSpeed().
    LOCAL padKm  IS distKm(SHIP:GEOPOSITION, padGeo).

    // =====================
    // FLIP
    // =====================
    IF phase = PH_FLIP {
        LOCAL brng IS bearingTo(padGeo).
        LOCK STEERING TO HEADING(brng, 0).
        LOCAL err IS VANG(SHIP:FACING:FOREVECTOR, HEADING(brng,0):FOREVECTOR).
        PRINT "[FLIP] err:"+ROUND(err,1)+" brg:"+ROUND(brng,1)+"    " AT (0,8).
        logPeriodic("flip err:"+ROUND(err,1)+" brg:"+ROUND(brng,1)).
        IF err < 10 {
            SET bbStartTime TO TIME:SECONDS.
            SET phase TO PH_BOOSTBACK.
            SET lastPredTime TO -999.
            logEvent("FLIP complete brg:"+ROUND(brng,1)).
        }
    }

    // =====================
    // BOOSTBACK
    // =====================
    // North: feedforward + velocity feedback (unchanged, working well).
    // East stop: atmospheric trajectory predictor — accounts for drag,
    //   so BB_STOP_EAST_M calibration per-pad is no longer needed.
    //   Uses vacuum predictor until drag is calibrated (first few seconds),
    //   then switches to atmospheric predictor for accurate stop.
    ELSE IF phase = PH_BOOSTBACK {
        LOCAL bbElapsed IS TIME:SECONDS - bbStartTime.

        // North velocity feedback (unchanged)
        LOCAL northAxisVec IS HEADING(0, 0):FOREVECTOR.
        LOCAL northVelNow  IS VDOT(SHIP:VELOCITY:SURFACE, northAxisVec).
        LOCAL northPosErrM IS (PAD_LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
        LOCAL desNVel      IS Clamp(northPosErrM * BB_NORTH_VEL_GAIN, -6.0, 6.0).
        LOCAL fbCorr       IS Clamp(-(northVelNow - desNVel) * BB_VEL_GAIN,
                                    -BB_MAX_CORR_DEG, BB_MAX_CORR_DEG).
        LOCAL aimBrng      IS 270 + fbCorr.
        LOCK STEERING TO HEADING(aimBrng, 0).

        // Throttle ramp based on vacuum east error (fast, no lag)
        LOCAL vacImpGeo  IS predictImpact_cached().
        LOCAL vacEastErr IS (PAD_LNG - vacImpGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
        LOCAL bbThr IS 0.12.
        IF      vacEastErr < BB_FULL_THR_EAST { SET bbThr TO 1.0. }
        ELSE IF vacEastErr < BB_MID_THR_EAST  { SET bbThr TO 0.60. }
        ELSE IF vacEastErr < BB_LOW_THR_EAST  { SET bbThr TO 0.30. }
        LOCK THROTTLE TO bbThr.

        // Stop condition: use atmospheric predictor once drag is calibrated,
        // otherwise fall back to vacuum predictor with fixed margin.
        LOCAL stopNow IS FALSE.
        IF dragCalibrated {
            LOCAL atmImpGeo  IS predictImpactAtm().
            // STOP on vacuum predictor (proven accurate, no integration drift).
            // Atmospheric predictor runs in parallel for diagnostics only.
            LOCAL atmNorthM  IS (PAD_LAT - atmImpGeo:LAT) * KERBIN_M_PER_DEG.
            LOCAL atmEastErr IS (PAD_LNG - atmImpGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
            LOCAL vacEastErr IS (PAD_LNG - vacImpGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
            SET stopNow TO vacEastErr >= BB_STOP_EAST_M.
            PRINT "[BB] vac:"+ewText(ROUND(vacEastErr,0))+" atm:"+ewText(ROUND(atmEastErr,0))+"  " AT (0,8).
            PRINT "nVel:"+ROUND(northVelNow,1)+" desV:"+ROUND(desNVel,1)+" corr:"+ROUND(fbCorr,1)+"  " AT (0,9).
            logPeriodic("bb nVel:"+ROUND(northVelNow,1)
                        +" desV:"+ROUND(desNVel,1)
                        +" corr:"+ROUND(fbCorr,1)
                        +" vac:"+ewText(ROUND(vacEastErr,0))
                        +" atm:"+nsText(ROUND(atmNorthM,0))+" "+ewText(ROUND(atmEastErr,0))
                        +" thr:"+ROUND(bbThr*100,0)
                        +" brg:"+ROUND(aimBrng,1)
                        +" hspd:"+ROUND(hspd,1)).
        } ELSE {
            // Vacuum predictor (used when drag not yet calibrated).
            LOCAL vacNorthM IS (PAD_LAT - vacImpGeo:LAT) * KERBIN_M_PER_DEG.
            LOCAL vacErrFb  IS (PAD_LNG - vacImpGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
            SET stopNow TO vacErrFb >= BB_STOP_EAST_M.
            PRINT "[BB] vac:"+nsText(ROUND(vacNorthM,0))+" "+ewText(ROUND(vacErrFb,0))+" (uncal)  " AT (0,8).
            PRINT "nVel:"+ROUND(northVelNow,1)+" desV:"+ROUND(desNVel,1)+" corr:"+ROUND(fbCorr,1)+"  " AT (0,9).
            logPeriodic("bb vac:"+nsText(ROUND(vacNorthM,0))+" "+ewText(ROUND(vacErrFb,0))
                        +" thr:"+ROUND(bbThr*100,0)
                        +" brg:"+ROUND(aimBrng,1)
                        +" hspd:"+ROUND(hspd,1)).
        }

        IF stopNow OR bbElapsed > BB_MAX_TIME {
            LOCK THROTTLE TO 0.
            SET phase TO PH_COAST.
            SET lastPredTime TO -999.
            logEvent("BOOSTBACK end nVel:"+ROUND(northVelNow,1)
                     +" desV:"+ROUND(desNVel,1)
                     +" CdAmCalib:"+dragCalibrated
                     +" hspd:"+ROUND(hspd,1)
                     +" t:"+ROUND(bbElapsed,0)).
        }
    }

    // =====================
    // COAST
    // =====================
    // Passive retrograde hold. RCS stays ON for attitude authority.
    // Fins deploy and provide some passive stability / drag correction.
    // No predictor steering here: the vacuum predictor ignores drag and
    // gives false "overshoot" readings below 40km, which would steer
    // the vehicle in the wrong direction.
    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.

        IF SHIP:ALTITUDE < 45000 AND SHIP:VERTICALSPEED < -50 AND NOT finsOut {
            activateAG(1).
            setFinAuthority(FIN_AUTH_COAST).
            SET finsOut TO TRUE.
            logEvent("Fins deployed auth:"+FIN_AUTH_COAST+"% RCS:ON").
        }

        IF SHIP:VERTICALSPEED < -1 {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        } ELSE {
            LOCK STEERING TO UP.
        }

        LOCAL posN IS northErrM(). LOCAL posE IS eastErrM().
        PRINT "[COAST] alt:"+ROUND(SHIP:ALTITUDE/1000,1)+"k   " AT (0,8).
        PRINT nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))+" pad:"+ROUND(padKm,1)+"  " AT (0,9).
        logPeriodic("coast "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))
                    +" pad:"+ROUND(padKm,1)+" hspd:"+ROUND(hspd,1)).

        IF SHIP:VERTICALSPEED < -1 AND SHIP:ALTITUDE < ENTRY_ALT {
            IF SHIP:VELOCITY:SURFACE:MAG > ENTRY_SPEED_THRESHOLD {
                IF finsOut AND NOT finsAeroSet {
                    setFinAuthority(FIN_AUTH_AERO).
                    SET finsAeroSet TO TRUE.
                }
                SET phase TO PH_ENTRY.
                logEvent("COAST->ENTRY spd:"+ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                         +" pad:"+ROUND(padKm,2)).
            } ELSE {
                IF finsOut AND NOT finsAeroSet {
                    setFinAuthority(FIN_AUTH_AERO).
                    SET finsAeroSet TO TRUE.
                }
                SET phase TO PH_AERO.
                logEvent("COAST->AERO (skip entry spd:"+ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                         +") pad:"+ROUND(padKm,2)).
            }
        }
    }

    // =====================
    // ENTRY
    // =====================
    ELSE IF phase = PH_ENTRY {
        LOCK STEERING TO SHIP:SRFRETROGRADE.
        LOCK THROTTLE TO 1.0.
        IF finsOut AND NOT finsAeroSet {
            setFinAuthority(FIN_AUTH_AERO).
            SET finsAeroSet TO TRUE.
        }
        PRINT "[ENTRY] spd:"+ROUND(SHIP:VELOCITY:SURFACE:MAG,0)+"   " AT (0,8).
        PRINT "pad:"+ROUND(padKm,2)+" h:"+ROUND(hspd,1)+"   " AT (0,9).
        logPeriodic("entry spd:"+ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                    +" pad:"+ROUND(padKm,2)+" hspd:"+ROUND(hspd,1)).
        IF SHIP:VELOCITY:SURFACE:MAG <= ENTRY_END_SPEED {
            LOCK THROTTLE TO 0.
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:"+ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     +" pad:"+ROUND(padKm,2)).
        }
    }

    // =====================
    // AERO
    // =====================
    // East-only AERO guidance (aeroEastGuideDir).
    // North: pure retrograde — prevents the velocity reversal oscillation
    //        that previously sent the ship 11 m/s northward into landing.
    //        Boostback velocity (BB_NORTH_VEL_GAIN) handles north.
    // East:  gentle 4-degree lean toward pad east/west position.
    //        Safe against oscillation: east lean slows westward drift
    //        (drag-like) rather than reversing it. Corrects ~100-300m
    //        of east error for different pad positions.
    ELSE IF phase = PH_AERO {
        LOCK THROTTLE TO 0.
        // Calibrate drag from observed deceleration (engines off, known velocity)
        IF NOT dragCalibrated { calibrateDrag(). }

        LOCK STEERING TO SHIP:SRFRETROGRADE.  // Pure retrograde — natural westward decel carries ship to pad.

        LOCAL ignAlt IS ignitionAlt().
        LOCAL posN IS northErrM(). LOCAL posE IS eastErrM().

        PRINT "[AERO] pad:"+ROUND(padKm,2)+" ign:"+ROUND(ignAlt,0)+"   " AT (0,8).
        PRINT nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))+" h:"+ROUND(hspd,1)+"   " AT (0,9).
        logPeriodic("aero pad:"+ROUND(padKm,2)
                    +" "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))
                    +" hspd:"+ROUND(hspd,1)
                    +" ign:"+ROUND(ignAlt,0)).

        IF altAGL <= ignAlt {
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING agl:"+ROUND(altAGL,0)
                     +" vs:"+ROUND(SHIP:VERTICALSPEED,0)
                     +" hspd:"+ROUND(hspd,1)
                     +" pad:"+ROUND(padKm,2)).
        }
    }

    // =====================
    // LANDING
    // =====================
    ELSE IF phase = PH_LANDING {
        SET vesselBounds TO SHIP:BOUNDS.
        LOCAL aglNow IS terrainAGL().

        IF finsOut AND NOT finsLandSet {
            setFinAuthority(FIN_AUTH_LAND).
            SET finsLandSet TO TRUE.
            RCS ON.
            logEvent("Landing fin auth:"+FIN_AUTH_LAND+"%").
        }

        maybeDeployGear().

        LOCK STEERING TO landingGuideDir().
        LOCAL thrCmd IS landingThrottle().
        LOCK THROTTLE TO thrCmd.

        LOCAL posN IS northErrM().
        LOCAL posE IS eastErrM().
        LOCAL missNow IS SQRT(posN*posN + posE*posE).
        PRINT "[LAND] agl:"+ROUND(aglNow,0)+" vs:"+ROUND(SHIP:VERTICALSPEED,1)+"  " AT (0,8).
        PRINT "thr:"+ROUND(thrCmd*100,0)+" hold:"+termLocked+" "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))+"  " AT (0,9).
        logPeriodic("land thr:"+ROUND(thrCmd*100,0)
                    +" vs:"+ROUND(SHIP:VERTICALSPEED,1)
                    +" hspd:"+ROUND(hspd,1)
                    +" hold:"+termLocked
                    +" miss:"+ROUND(missNow,0)
                    +" "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET touchdownSeen TO TRUE.
        }
        IF touchdownSeen OR (aglNow < 2
            AND SHIP:VERTICALSPEED > TOUCHDOWN_VS
            AND SHIP:VERTICALSPEED < 1
            AND hspd < TOUCHDOWN_HS) {
            SET phase TO PH_TOUCHDOWN.
            logEvent("TOUCHDOWN vs:"+ROUND(SHIP:VERTICALSPEED,1)
                     +" hs:"+ROUND(hspd,1)
                     +" miss:"+ROUND(missNow,0)
                     +" lat:"+ROUND(SHIP:LATITUDE,4)
                     +" lng:"+ROUND(SHIP:LONGITUDE,4)).
        }
    }

    WAIT 0.
}

// ============================================================
//  TOUCHDOWN CLEANUP
// ============================================================
LOCK THROTTLE TO 0. WAIT 1.
UNLOCK STEERING. WAIT 1.
UNLOCK THROTTLE. WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
RCS OFF. SAS OFF.
setFinAuthority(0).

LOCAL finalKm IS distKm(SHIP:GEOPOSITION, padGeo).
logEvent("SCRIPT END - lat:"+ROUND(SHIP:LATITUDE,4)
         +" lng:"+ROUND(SHIP:LONGITUDE,4)
         +" pad:"+ROUND(finalKm,2)+"km").

PRINT "+----------------------------+" AT (0,8).
PRINT "| TOUCHDOWN / SCRIPT END    |" AT (0,9).
PRINT "+----------------------------+" AT (0,10).
PRINT "Pad miss: "+ROUND(finalKm*1000,0)+"m" AT (0,11).
SAS OFF. WAIT 1.
UNLOCK ALL. WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE. WAIT 1.
PRINT "END PROGRAM." AT (0,12).
