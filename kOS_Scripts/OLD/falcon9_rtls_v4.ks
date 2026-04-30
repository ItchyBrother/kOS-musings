// ============================================================
//  falcon9_rtls_v4.ks
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
//    BB_STOP_EAST_M   — east margin to stop boostback (300 is good)
//    AERO_MAX_LEAN    — fin lean authority in AERO phase (degrees)
//
//  Usage:
//    RUN falcon9_rtls_v4(PAD_LAT, PAD_LNG, PAD_ALT).
//
//  Action Groups:
//    AG1  Grid fins deploy
//    AG2  Enable 3 center engines
//    GEAR Landing legs
// ============================================================

@LAZYGLOBAL OFF.

PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.
PARAMETER PAD_ALT IS 67.

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
LOCAL BB_STOP_EAST_M     IS 400.    // vacuum predictor ~400m east; AERO east guidance closes the remaining gap
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
LOCAL LAND_MAX_VEL      IS 8.0.
LOCAL LAND_MAX_VEL_LOW  IS 3.0.
LOCAL LAND_VEL_KP       IS 0.18.
LOCAL LAND_VEL_KP_LOW   IS 0.24.
LOCAL LAND_MAX_ACC      IS 7.0.
LOCAL LAND_MAX_ACC_LOW  IS 3.0.
LOCAL LAND_MAX_TILT     IS 22.0.
LOCAL LAND_MAX_TILT_LOW IS 10.0.
LOCAL LAND_THR_KP       IS 0.60.
LOCAL LAND_THR_KP_LOW   IS 0.90.
LOCAL TOUCHDOWN_VS      IS -3.5.
LOCAL TOUCHDOWN_HS      IS 2.5.
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
LOCAL lastPredTime    IS -999.
LOCAL lastLogTime     IS -999.
LOCAL bbStartTime     IS 0.
LOCAL finsOut         IS FALSE.
LOCAL finsAeroSet     IS FALSE.
LOCAL finsLandSet     IS FALSE.
LOCAL legsOut         IS FALSE.
LOCAL touchdownSeen   IS FALSE.

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
    LOCAL retroVec  IS SHIP:SRFRETROGRADE:FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90, 0):FOREVECTOR.

    LOCAL eastPosErr IS eastErrM().
    LOCAL eastVelNow IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    LOCAL desE IS Clamp(eastPosErr * 0.015, -6.0, 6.0).
    IF ABS(eastPosErr) < 30 { SET desE TO 0. }

    LOCAL accE IS Clamp((desE - eastVelNow) * 0.06, -1.5, 1.5).

    LOCAL latVec IS eastAxis * accE.
    IF latVec:MAG < 0.05 {
        RETURN LOOKDIRUP(retroVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxMag IS 18.0 * TAN(4.0).
    IF latVec:MAG > maxMag { SET latVec TO latVec:NORMALIZED * maxMag. }

    LOCAL steerVec IS (retroVec * 18.0 + latVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
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
FUNCTION landingGuideDir {
    LOCAL altAGL IS terrainAGL().
    LOCAL upVec  IS UP:FOREVECTOR.
    LOCAL hsLand IS hSpeed().
    LOCAL padM   IS distKm(SHIP:GEOPOSITION, padGeo) * 1000.

    IF altAGL < LAND_GUIDE_ALT OR (padM < 25 AND hsLand < 1.0) {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL posKp  IS LAND_POS_KP.    LOCAL maxVel IS LAND_MAX_VEL.
    LOCAL velKp  IS LAND_VEL_KP.    LOCAL maxAcc IS LAND_MAX_ACC.
    LOCAL maxTlt IS LAND_MAX_TILT.
    IF altAGL < 600 {
        SET posKp  TO LAND_POS_KP_LOW. SET maxVel TO LAND_MAX_VEL_LOW.
        SET velKp  TO LAND_VEL_KP_LOW. SET maxAcc TO LAND_MAX_ACC_LOW.
        SET maxTlt TO LAND_MAX_TILT_LOW.
    }

    LOCAL northAxis IS HEADING(0,0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90,0):FOREVECTOR.
    LOCAL northPos IS northErrM(). LOCAL eastPos IS eastErrM().
    LOCAL northVel IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eastVel  IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    LOCAL desN IS Clamp(northPos * posKp, -maxVel, maxVel).
    LOCAL desE IS Clamp(eastPos  * posKp, -maxVel, maxVel).
    IF ABS(northPos) < 5 { SET desN TO 0. }
    IF ABS(eastPos)  < 5 { SET desE TO 0. }

    LOCAL accN IS Clamp((desN - northVel) * velKp, -maxAcc, maxAcc).
    LOCAL accE IS Clamp((desE - eastVel)  * velKp, -maxAcc, maxAcc).

    LOCAL latVec IS northAxis*accN + eastAxis*accE.
    IF latVec:MAG < 0.03 { RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR). }

    LOCAL maxMag IS LAND_UP_BIAS_ACC * TAN(maxTlt).
    IF latVec:MAG > maxMag { SET latVec TO latVec:NORMALIZED * maxMag. }

    LOCAL steerVec IS (upVec * LAND_UP_BIAS_ACC + latVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

FUNCTION landingThrottle {
    LOCAL aglM IS MAX(0, terrainAGL()).
    LOCAL gravAcc IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL thrKp IS LAND_THR_KP.
    LOCAL tgt IS -MAX(25, MIN(220, aglM * 0.09)).
    IF aglM < 400 {
        SET thrKp TO LAND_THR_KP_LOW.
        IF aglM > 200      { SET tgt TO -25.  }
        ELSE IF aglM > 100 { SET tgt TO -14.  }
        ELSE IF aglM > 40  { SET tgt TO -7.   }
        ELSE IF aglM > 15  { SET tgt TO -3.   }
        ELSE               { SET tgt TO -1.5. }
    }
    RETURN Clamp((SHIP:MASS*(gravAcc+(tgt-SHIP:VERTICALSPEED)*thrKp))/MAXTHRUST, 0, 1).
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START - Pad:"+PAD_LAT+"/"+PAD_LNG+"/"+PAD_ALT).

PRINT "+------------------------------------+" AT (0,0).
PRINT "| F9 RTLS v4 — PREDICTOR GUIDED     |" AT (0,1).
PRINT "+------------------------------------+" AT (0,2).
PRINT "Pad: "+ROUND(PAD_LAT,6)+" / "+ROUND(PAD_LNG,6) AT (0,3).
PRINT "Alt: "+ROUND(PAD_ALT,0)+"m" AT (0,4).
PRINT "No biases. Predictor guides all phases." AT (0,5).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF. RCS ON.
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
    // NORTH: velocity feedback. Measure actual northward velocity component
    //   with VDOT and steer to drive it to zero. If the burn bearing is
    //   adding southward drift, this detects it instantly and corrects.
    //   No predictor noise. No static offsets. Works for any pad.
    // EAST:  raw predictor stop condition (fast, no lag).
    ELSE IF phase = PH_BOOSTBACK {
        LOCAL bbElapsed IS TIME:SECONDS - bbStartTime.

        // Measure northward velocity. Target = 0 m/s at cutoff.
        LOCAL northAxisVec IS HEADING(0, 0):FOREVECTOR.
        LOCAL northVelNow  IS VDOT(SHIP:VELOCITY:SURFACE, northAxisVec).
        // Positive northVelNow = drifting north  -> steer south (negative offset)
        // Negative northVelNow = drifting south  -> steer north (positive offset)
        // FEEDFORWARD + FEEDBACK:
        //   Base: 270 deg (due west). This gives zero north/south thrust
        //   component regardless of pad location — no constant disturbance.
        //   Feedback: trim bearing north or south of 270 to control north velocity.
        //   Equilibrium sits at desNVel naturally. Previously, aiming at padBrng
        //   (~265 deg) had built-in southward thrust that the feedback could
        //   never overcome with a 5 deg cap (265+5=270, never above = never north).
        LOCAL northPosErrM IS (PAD_LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
        LOCAL desNVel      IS Clamp(northPosErrM * BB_NORTH_VEL_GAIN, -6.0, 6.0).
        LOCAL fbCorr       IS Clamp(-(northVelNow - desNVel) * BB_VEL_GAIN,
                                    -BB_MAX_CORR_DEG, BB_MAX_CORR_DEG).
        LOCAL aimBrng      IS 270 + fbCorr.  // 270=west, +north, -south
        LOCK STEERING TO HEADING(aimBrng, 0).

        // Throttle ramp based on raw predictor east error.
        LOCAL bbImpGeo   IS predictImpact_cached().
        LOCAL bbEastErr  IS (PAD_LNG - bbImpGeo:LNG) * KERBIN_M_PER_DEG * COS(PAD_LAT).
        LOCAL bbNorthErr IS (PAD_LAT - bbImpGeo:LAT) * KERBIN_M_PER_DEG.

        LOCAL bbThr IS 0.12.
        IF      bbEastErr < BB_FULL_THR_EAST { SET bbThr TO 1.0. }
        ELSE IF bbEastErr < BB_MID_THR_EAST  { SET bbThr TO 0.60. }
        ELSE IF bbEastErr < BB_LOW_THR_EAST  { SET bbThr TO 0.30. }
        LOCK THROTTLE TO bbThr.

        PRINT "[BB] nVel:"+ROUND(northVelNow,1)+" desV:"+ROUND(desNVel,1)+" corr:"+ROUND(fbCorr,1)+"  " AT (0,8).
        PRINT "pos:"+nsText(ROUND(northPosErrM,0))+" "+ewText(ROUND(bbEastErr,0))+" thr:"+ROUND(bbThr*100,0)+"  " AT (0,9).
        logPeriodic("bb nVel:"+ROUND(northVelNow,1)
                    +" desV:"+ROUND(desNVel,1)
                    +" corr:"+ROUND(fbCorr,1)
                    +" pos:"+nsText(ROUND(northPosErrM,0))+" "+ewText(ROUND(bbEastErr,0))
                    +" thr:"+ROUND(bbThr*100,0)
                    +" brg:"+ROUND(aimBrng,1)
                    +" hspd:"+ROUND(hspd,1)).

        IF bbEastErr >= BB_STOP_EAST_M OR bbElapsed > BB_MAX_TIME {
            LOCK THROTTLE TO 0.
            SET phase TO PH_COAST.
            SET lastPredTime TO -999.
            logEvent("BOOSTBACK end nVel:"+ROUND(northVelNow,1)
                     +" desV:"+ROUND(desNVel,1)
                     +" pos:"+nsText(ROUND(northPosErrM,0))+" "+ewText(ROUND(bbEastErr,0))
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
        LOCK STEERING TO aeroEastGuideDir().  // Retrograde + gentle east-only lean.

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
            RCS OFF.
            logEvent("Landing fin auth:"+FIN_AUTH_LAND+"%").
        }

        IF NOT legsOut AND aglNow < LEG_DEPLOY_ALT {
            GEAR ON.
            SET legsOut TO TRUE.
            SET vesselBounds TO SHIP:BOUNDS.
            logEvent("LEGS deployed at "+ROUND(terrainAGL(),0)+"m").
        }

        LOCK STEERING TO landingGuideDir().
        LOCAL thrCmd IS landingThrottle().
        LOCK THROTTLE TO thrCmd.

        LOCAL posN IS northErrM(). LOCAL posE IS eastErrM().
        PRINT "[LAND] agl:"+ROUND(altAGL,0)+" vs:"+ROUND(SHIP:VERTICALSPEED,1)+"  " AT (0,8).
        PRINT "thr:"+ROUND(thrCmd*100,0)+" "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))+"  " AT (0,9).
        logPeriodic("land thr:"+ROUND(thrCmd*100,0)
                    +" vs:"+ROUND(SHIP:VERTICALSPEED,1)
                    +" hspd:"+ROUND(hspd,1)
                    +" "+nsText(ROUND(posN,0))+" "+ewText(ROUND(posE,0))).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET touchdownSeen TO TRUE.
        }
        IF touchdownSeen OR (altAGL < 2
            AND SHIP:VERTICALSPEED > TOUCHDOWN_VS
            AND SHIP:VERTICALSPEED < 1
            AND hspd < TOUCHDOWN_HS) {
            SET phase TO PH_TOUCHDOWN.
            logEvent("TOUCHDOWN vs:"+ROUND(SHIP:VERTICALSPEED,1)
                     +" hs:"+ROUND(hspd,1)
                     +" pad:"+ROUND(padKm,2)
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
