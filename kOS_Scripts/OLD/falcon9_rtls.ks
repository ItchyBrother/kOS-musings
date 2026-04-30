// ============================================================
//  falcon9_rtls_v3.ks
//
//  ARCHITECTURE — one job per phase, no waste:
//
//   FLIP       : rotate to face pad
//   BOOSTBACK  : burn until predictor says you'll coast home.
//                Steers direct to pad bearing (no N bias needed).
//                East-error stop condition limits fuel. Light burn.
//   COAST      : passive retrograde + gentle lean toward pad.
//                RCS stays ON so attitude hold gives real lateral
//                correction. A puff here and there.
//   ENTRY      : ONLY fires if speed > ENTRY_SPEED_THRESHOLD.
//                If you're already slow, this phase is skipped.
//   AERO       : velocity-tracking lean toward pad, no thrust.
//                Continuous self-correction, no trim needed.
//   LANDING    : fast approach, PD controller kills horizontal
//                velocity directly over pad, straight down.
//   TOUCHDOWN  : last 300m, engine + guidance hold position.
//
//  Knobs you may need to touch (in order of likelihood):
//    BB_NORTH_BIAS_M        — meters north of pad to aim during boostback (default 670)
//    BB_STOP_EAST_M         — how far west the predictor must show before stopping (default 300)
//    ENTRY_SPEED_THRESHOLD  — m/s above which the entry burn fires (default 650)
//
//  Usage:
//    RUN falcon9_rtls_v3(PAD_LAT, PAD_LNG, PAD_ALT).
//
//  Action Groups:
//    AG1  Grid fins deploy
//    AG2  Enable 3 center engines
//    GEAR Landing legs
// ============================================================

@LAZYGLOBAL OFF.

// ============================================================
//  PAD PARAMETERS
// ============================================================
PARAMETER PAD_LAT IS -0.0972.
PARAMETER PAD_LNG IS -74.5577.
PARAMETER PAD_ALT IS 67.

// ============================================================
//  TUNING
// ============================================================
LOCAL KERBIN_M_PER_DEG IS 10471.
LOCAL LOG_FILE         IS "0:/rtls_log.txt".
LOCAL LOG_INTERVAL     IS 2.0.

// ---- Boostback ----
// Steering: nose aimed at a fixed point BB_NORTH_BIAS_M north of pad.
//   Direct bearing to pad is ~263 deg (south-of-west). That angle
//   slowly imparts southward velocity over the ~26s burn. Aiming at a
//   point ~670m north shifts bearing to ~270 deg and neutralizes this.
//   The atmosphere closes the remaining gap during coast + aero.
//
//   Dynamic correction (BB_NORTH_CORR) was tried and abandoned. The
//   predictor is unreliable during active maneuvering -- noisy orbital
//   velocity causes it to saturate the clamp and thrash bearing wildly.
//   Static bias is stable and repeatable.
//
//   BB_NORTH_BIAS_M = 670 is calibrated for this vehicle/trajectory.
//   Land consistently north of pad: lower it (try 500).
//   Land consistently south of pad: raise it (try 800).
//   East/west misses: adjust BB_STOP_EAST_M only.
LOCAL BB_PRED_INTERVAL IS 0.5.
LOCAL BB_NORTH_BIAS_M  IS 770.     // aim this many meters north of pad during boostback
LOCAL BB_STOP_EAST_M   IS 300.     // stop when predicted impact is this far west of pad (m)
LOCAL BB_FULL_THR_EAST IS -8000.   // full throttle while predicted east miss > 8 km
LOCAL BB_MID_THR_EAST  IS -3000.   // 60%  throttle while > 3 km east
LOCAL BB_LOW_THR_EAST  IS -800.    // 30%  throttle while > 800 m east
LOCAL BB_MAX_TIME      IS 90.

// ---- Entry (braking) ----
// Entry burn fires ONLY when speed exceeds ENTRY_SPEED_THRESHOLD.
// At this trajectory's ~300-400 m/s entry speed it will be skipped.
// Increase ENTRY_ALT if you need to catch fast re-entries higher up.
LOCAL ENTRY_ALT              IS 40000.
LOCAL ENTRY_SPEED_THRESHOLD  IS 650.   // m/s — don't burn if slower than this
LOCAL ENTRY_END_SPEED        IS 350.   // m/s — burn down to this speed

// ---- Fins ----
LOCAL FIN_AUTH_COAST IS 15.
LOCAL FIN_AUTH_AERO  IS 35.
LOCAL FIN_AUTH_LAND  IS 8.

// ---- Coast guidance (gentle lean + RCS, high altitude) ----
// Provides small corrections during the long unpowered coast.
// Lean is small; RCS attitude hold provides the actual lateral push.
LOCAL COAST_POS_KP   IS 0.012.   // m/s desired lateral vel per m error
LOCAL COAST_MAX_HVEL IS 6.0.     // m/s max desired lateral speed
LOCAL COAST_VEL_KP   IS 0.06.    // lean acc per m/s velocity error
LOCAL COAST_MAX_ACC  IS 1.0.     // m/s² max lateral accel command
LOCAL COAST_UP_BIAS  IS 18.0.
LOCAL COAST_MAX_LEAN IS 3.0.     // degrees max lean off retrograde

// ---- Aero guidance (velocity-tracking, no thrust) ----
// More authority than coast — fins are effective in thick air.
LOCAL AERO_POS_KP   IS 0.020.
LOCAL AERO_MAX_HVEL IS 20.0.
LOCAL AERO_VEL_KP   IS 0.12.
LOCAL AERO_MAX_ACC  IS 3.0.
LOCAL AERO_UP_BIAS  IS 18.0.
LOCAL AERO_MAX_LEAN IS 8.0.

// ---- Landing ----
LOCAL LEG_DEPLOY_ALT    IS 500.
LOCAL LAND_GUIDE_ALT    IS 250.
LOCAL LAND_UP_BIAS_ACC  IS 21.0.
LOCAL LAND_POS_KP       IS 0.020.
LOCAL LAND_POS_KP_LOW   IS 0.008.
LOCAL LAND_MAX_VEL      IS 8.0.
LOCAL LAND_MAX_VEL_LOW  IS 3.0.
LOCAL LAND_VEL_KP       IS 0.18.
LOCAL LAND_VEL_KP_LOW   IS 0.24.
LOCAL LAND_MAX_ACC      IS 7.0.
LOCAL LAND_MAX_ACC_LOW  IS 3.0.
LOCAL LAND_MAX_TILT     IS 14.0.
LOCAL LAND_MAX_TILT_LOW IS 6.0.
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
LOCAL phase         IS PH_FLIP.
LOCAL padGeo        IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL lastPredTime  IS -999.
LOCAL cachedImpact  IS LATLNG(PAD_LAT, PAD_LNG).
LOCAL lastLogTime   IS -999.
LOCAL bbStartTime   IS 0.
LOCAL finsOut       IS FALSE.
LOCAL finsAeroSet   IS FALSE.
LOCAL finsLandSet   IS FALSE.
LOCAL legsOut       IS FALSE.
LOCAL touchdownSeen IS FALSE.

// ============================================================
//  UTILITY
// ============================================================
FUNCTION Clamp {
    PARAMETER valueIn, lowIn, highIn.
    IF valueIn < lowIn { RETURN lowIn. }
    IF valueIn > highIn { RETURN highIn. }
    RETURN valueIn.
}

FUNCTION distKm {
    PARAMETER geoA, geoB.
    RETURN (geoA:POSITION - geoB:POSITION):MAG / 1000.
}

FUNCTION bearingTo {
    PARAMETER targetGeo.
    LOCAL latNow  IS SHIP:GEOPOSITION:LAT.
    LOCAL brngDeg IS ARCTAN2(
        (targetGeo:LNG - SHIP:GEOPOSITION:LNG) * COS(latNow),
        targetGeo:LAT - latNow
    ).
    IF brngDeg < 0 { SET brngDeg TO brngDeg + 360. }
    RETURN brngDeg.
}

FUNCTION hSpeed {
    RETURN SQRT(MAX(0, SHIP:VELOCITY:SURFACE:MAG^2 - SHIP:VERTICALSPEED^2)).
}

FUNCTION terrainAGL {
    LOCAL altRadar IS vesselBounds:BOTTOMALTRADAR.
    IF altRadar < 0 { RETURN 0. }
    RETURN altRadar.
}

FUNCTION rotVec {
    PARAMETER vecIn, axisIn, angleDeg.
    LOCAL cosA IS COS(angleDeg).
    LOCAL sinA IS SIN(angleDeg).
    RETURN vecIn * cosA + VCRS(axisIn, vecIn) * sinA
           + axisIn * VDOT(axisIn, vecIn) * (1 - cosA).
}

FUNCTION northErrM {
    PARAMETER targetGeo.
    RETURN (targetGeo:LAT - SHIP:LATITUDE) * KERBIN_M_PER_DEG.
}

FUNCTION eastErrM {
    PARAMETER targetGeo.
    RETURN (targetGeo:LNG - SHIP:LONGITUDE) * KERBIN_M_PER_DEG * COS(SHIP:LATITUDE).
}

FUNCTION nsText {
    PARAMETER northMeters.
    IF northMeters >= 0 { RETURN "N:" + ROUND(northMeters,0). }
    RETURN "S:" + ROUND(ABS(northMeters),0).
}

FUNCTION ewText {
    PARAMETER eastMeters.
    IF eastMeters >= 0 { RETURN "E:" + ROUND(eastMeters,0). }
    RETURN "W:" + ROUND(ABS(eastMeters),0).
}

// ============================================================
//  LOGGING
// ============================================================
FUNCTION logOpen {
    IF EXISTS(LOG_FILE) { DELETEPATH(LOG_FILE). }
    LOG "RTLS Log v3 - Pad: " + PAD_LAT + " / " + PAD_LNG + " / " + PAD_ALT TO LOG_FILE.
    LOG "T+sec | Phase | Alt km | VS m/s | Hspd m/s | Pad km | Thr% | Message" TO LOG_FILE.
    LOG "----------------------------------------------------------------------" TO LOG_FILE.
}

FUNCTION logLine {
    PARAMETER msgText.
    LOCAL tsVal  IS ROUND(TIME:SECONDS, 1).
    LOCAL altKm  IS ROUND(SHIP:ALTITUDE / 1000, 2).
    LOCAL vsVal  IS ROUND(SHIP:VERTICALSPEED, 1).
    LOCAL hsVal  IS ROUND(hSpeed(), 1).
    LOCAL padVal IS ROUND(distKm(SHIP:GEOPOSITION, padGeo), 2).
    LOCAL thrVal IS ROUND(THROTTLE * 100, 0).
    LOCAL phName IS PHASE_NAMES[phase].
    LOG "T+" + tsVal + " | " + phName + " | " + altKm + "km | VS:" + vsVal
        + " | H:" + hsVal + " | Pad:" + padVal + "km | Thr:" + thrVal
        + "% | " + msgText TO LOG_FILE.
}

FUNCTION logEvent {
    PARAMETER msgText.
    logLine("*** " + msgText + " ***").
}

FUNCTION logPeriodic {
    PARAMETER msgText IS "".
    IF (TIME:SECONDS - lastLogTime) >= LOG_INTERVAL {
        logLine(msgText).
        SET lastLogTime TO TIME:SECONDS.
    }
}

// ============================================================
//  ACTION GROUPS AND PART HELPERS
// ============================================================
FUNCTION activateAG {
    PARAMETER agNum.
    IF agNum = 1 { AG1 ON. }
    ELSE IF agNum = 2 { AG2 ON. }
    ELSE IF agNum = 3 { AG3 ON. }
    ELSE IF agNum = 4 { AG4 ON. }
    ELSE IF agNum = 5 { AG5 ON. }
}

FUNCTION setFinAuthority {
    PARAMETER authPct.
    FOR partItem IN SHIP:PARTS {
        IF partItem:HASMODULE("ModuleControlSurface") {
            LOCAL finMod IS partItem:GETMODULE("ModuleControlSurface").
            IF finMod:HASFIELD("authority limiter") {
                finMod:SETFIELD("authority limiter", authPct).
            }
        }
    }
}

// ============================================================
//  BALLISTIC PREDICTOR
//  Vacuum only. Accurate at boostback altitudes (25-40 km).
//  Not used after boostback — no need.
// ============================================================
FUNCTION predictImpact {
    LOCAL muVal    IS BODY:MU.
    LOCAL bodyRad  IS BODY:RADIUS.
    LOCAL bodyPos0 IS BODY:POSITION.
    LOCAL posVec   IS -bodyPos0.
    LOCAL velOrb   IS SHIP:VELOCITY:ORBIT.
    LOCAL rotPer   IS BODY:ROTATIONPERIOD.
    LOCAL rotAxis  IS V(0, 1, 0).
    IF BODY:ANGULARVEL:MAG > 0.000001 {
        SET rotAxis TO BODY:ANGULARVEL:NORMALIZED.
    }
    LOCAL dtVal  IS 5.
    LOCAL tofVal IS 0.
    UNTIL tofVal > 1500 {
        LOCAL posMag IS posVec:MAG.
        LOCAL accVec IS -(muVal / (posMag^3)) * posVec.
        LOCAL posMid IS posVec + velOrb * (dtVal / 2).
        LOCAL velMid IS velOrb + accVec * (dtVal / 2).
        LOCAL accMid IS -(muVal / (posMid:MAG^3)) * posMid.
        SET posVec TO posVec + velMid * dtVal.
        SET velOrb TO velOrb + accMid * dtVal.
        SET tofVal TO tofVal + dtVal.
        IF posVec:MAG - bodyRad <= PAD_ALT {
            LOCAL rotDeg IS 360 * tofVal / rotPer.
            LOCAL posAdj IS rotVec(posVec, rotAxis, -rotDeg).
            RETURN BODY:GEOPOSITIONOF(posAdj + bodyPos0).
        }
    }
    RETURN SHIP:GEOPOSITION.
}

FUNCTION getImpact {
    IF (TIME:SECONDS - lastPredTime) >= BB_PRED_INTERVAL {
        SET cachedImpact TO predictImpact().
        SET lastPredTime TO TIME:SECONDS.
    }
    RETURN cachedImpact.
}

// ============================================================
//  LATERAL GUIDANCE
//  Shared by coast and aero — same math, different gain sets.
//
//  posKp:   desired lateral m/s per meter of position error
//  maxHvel: cap on desired lateral speed (m/s)
//  velKp:   lean acceleration per m/s of velocity error
//  maxAcc:  cap on lateral acceleration command (m/s²)
//  upBias:  retrograde weight in lean blend (determines max lean)
//  maxLean: hard cap on lean from retrograde (degrees)
//
//  How it works:
//   1. Compute desired lateral velocity from position error.
//   2. Compute lateral acceleration to achieve that velocity.
//   3. Blend that acceleration into the retrograde vector as a lean.
//   4. The vehicle's autopilot uses fins + RCS to hold that attitude.
//   5. Drag vector (and RCS) provides the actual lateral correction.
// ============================================================
FUNCTION guideDir {
    PARAMETER posKp, maxHvel, velKp, maxAcc, upBias, maxLean.

    LOCAL srfRetroVec IS SHIP:SRFRETROGRADE:FOREVECTOR.
    LOCAL northAxis   IS HEADING(0, 0):FOREVECTOR.
    LOCAL eastAxis    IS HEADING(90, 0):FOREVECTOR.

    LOCAL northPosErr IS northErrM(padGeo).
    LOCAL eastPosErr  IS eastErrM(padGeo).
    LOCAL northVelNow IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eastVelNow  IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    // Desired lateral velocity proportional to position error.
    LOCAL desNorthVel IS Clamp(northPosErr * posKp, -maxHvel, maxHvel).
    LOCAL desEastVel  IS Clamp(eastPosErr  * posKp, -maxHvel, maxHvel).
    IF ABS(northPosErr) < 25 { SET desNorthVel TO 0. }
    IF ABS(eastPosErr)  < 25 { SET desEastVel  TO 0. }

    // Lateral acceleration to reach desired velocity.
    LOCAL northAccCmd IS Clamp((desNorthVel - northVelNow) * velKp, -maxAcc, maxAcc).
    LOCAL eastAccCmd  IS Clamp((desEastVel  - eastVelNow)  * velKp, -maxAcc, maxAcc).

    LOCAL latAccVec IS northAxis * northAccCmd + eastAxis * eastAccCmd.
    IF latAccVec:MAG < 0.05 {
        RETURN LOOKDIRUP(srfRetroVec, SHIP:FACING:TOPVECTOR).
    }

    // Cap to max lean angle.
    LOCAL maxLatMag IS upBias * TAN(maxLean).
    IF latAccVec:MAG > maxLatMag {
        SET latAccVec TO latAccVec:NORMALIZED * maxLatMag.
    }

    LOCAL steerVec IS (srfRetroVec * upBias + latAccVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

// ============================================================
//  LANDING GUIDANCE (unchanged from v1 — works well)
// ============================================================
FUNCTION ignitionAlt {
    LOCAL vertSpd   IS MAX(0, -SHIP:VERTICALSPEED).
    LOCAL gravAccel IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL aMax      IS (MAXTHRUST / SHIP:MASS) - gravAccel.
    IF aMax < 0.5 { RETURN 5000. }
    RETURN (vertSpd * vertSpd) / (2 * aMax) * 0.88 + 30.
}

FUNCTION landingGuideDir {
    LOCAL altAGL    IS terrainAGL().
    LOCAL upVec     IS UP:FOREVECTOR.
    LOCAL hsVal     IS hSpeed().
    LOCAL padMeters IS distKm(SHIP:GEOPOSITION, padGeo) * 1000.

    IF altAGL < LAND_GUIDE_ALT OR (padMeters < 25 AND hsVal < 1.0) {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL posKpVal   IS LAND_POS_KP.
    LOCAL maxVelVal  IS LAND_MAX_VEL.
    LOCAL velKpVal   IS LAND_VEL_KP.
    LOCAL maxAccVal  IS LAND_MAX_ACC.
    LOCAL maxTiltVal IS LAND_MAX_TILT.

    IF altAGL < 600 {
        SET posKpVal   TO LAND_POS_KP_LOW.
        SET maxVelVal  TO LAND_MAX_VEL_LOW.
        SET velKpVal   TO LAND_VEL_KP_LOW.
        SET maxAccVal  TO LAND_MAX_ACC_LOW.
        SET maxTiltVal TO LAND_MAX_TILT_LOW.
    }

    LOCAL northAxis IS HEADING(0, 0):FOREVECTOR.
    LOCAL eastAxis  IS HEADING(90, 0):FOREVECTOR.

    LOCAL northPosErr IS northErrM(padGeo).
    LOCAL eastPosErr  IS eastErrM(padGeo).
    LOCAL northVelVal IS VDOT(SHIP:VELOCITY:SURFACE, northAxis).
    LOCAL eastVelVal  IS VDOT(SHIP:VELOCITY:SURFACE, eastAxis).

    LOCAL desNorthVel IS Clamp(northPosErr * posKpVal, -maxVelVal, maxVelVal).
    LOCAL desEastVel  IS Clamp(eastPosErr  * posKpVal, -maxVelVal, maxVelVal).
    IF ABS(northPosErr) < 12 { SET desNorthVel TO 0. }
    IF ABS(eastPosErr)  < 12 { SET desEastVel  TO 0. }

    LOCAL northAccCmd IS Clamp((desNorthVel - northVelVal) * velKpVal, -maxAccVal, maxAccVal).
    LOCAL eastAccCmd  IS Clamp((desEastVel  - eastVelVal)  * velKpVal, -maxAccVal, maxAccVal).

    LOCAL latAccVec IS northAxis * northAccCmd + eastAxis * eastAccCmd.
    IF latAccVec:MAG < 0.03 {
        RETURN LOOKDIRUP(upVec, SHIP:FACING:TOPVECTOR).
    }

    LOCAL maxLatMag IS LAND_UP_BIAS_ACC * TAN(maxTiltVal).
    IF latAccVec:MAG > maxLatMag {
        SET latAccVec TO latAccVec:NORMALIZED * maxLatMag.
    }

    LOCAL steerVec IS (upVec * LAND_UP_BIAS_ACC + latAccVec):NORMALIZED.
    RETURN LOOKDIRUP(steerVec, SHIP:FACING:TOPVECTOR).
}

FUNCTION landingThrottle {
    LOCAL altAGL    IS MAX(0, terrainAGL()).
    LOCAL gravAccel IS BODY:MU / ((BODY:RADIUS + SHIP:ALTITUDE)^2).
    LOCAL kpVal     IS LAND_THR_KP.
    LOCAL tgtVSpd   IS -MAX(25, MIN(220, altAGL * 0.09)).

    IF altAGL < 400 {
        SET kpVal TO LAND_THR_KP_LOW.
        IF altAGL > 200      { SET tgtVSpd TO -25.  }
        ELSE IF altAGL > 100 { SET tgtVSpd TO -14.  }
        ELSE IF altAGL > 40  { SET tgtVSpd TO -7.   }
        ELSE IF altAGL > 15  { SET tgtVSpd TO -3.   }
        ELSE                 { SET tgtVSpd TO -1.5. }
    }

    LOCAL accCmd IS gravAccel + (tgtVSpd - SHIP:VERTICALSPEED) * kpVal.
    LOCAL thrCmd IS Clamp((SHIP:MASS * accCmd) / MAXTHRUST, 0, 1).
    RETURN thrCmd.
}

// ============================================================
//  INITIALIZATION
// ============================================================
CLEARSCREEN.
logOpen().
logEvent("SCRIPT START - Pad:" + PAD_LAT + "/" + PAD_LNG + "/" + PAD_ALT).

PRINT "+--------------------------------------+" AT (0, 0).
PRINT "| F9 RTLS v3                          |" AT (0, 1).
PRINT "+--------------------------------------+" AT (0, 2).
PRINT "Pad lat:      " + ROUND(PAD_LAT,6)       AT (0, 3).
PRINT "Pad lng:      " + ROUND(PAD_LNG,6)       AT (0, 4).
PRINT "Pad alt:      " + ROUND(PAD_ALT,0) + "m" AT (0, 5).
PRINT "BB NORTH: " + BB_NORTH_BIAS_M + " BB EAST: " + BB_STOP_EAST_M AT (0, 6).
PRINT "Entry thresh: " + ENTRY_SPEED_THRESHOLD + " m/s" AT (0, 7).

LOCK THROTTLE TO 0.
LOCK STEERING TO UP.
SAS OFF.
RCS ON.
activateAG(2).
logEvent("AG2 fired - 3 engines enabled").

// ============================================================
//  MAIN LOOP
// ============================================================
UNTIL phase = PH_TOUCHDOWN {

    LOCAL altAGLVal    IS terrainAGL().
    LOCAL hsVal        IS hSpeed().
    LOCAL padDistKmVal IS distKm(SHIP:GEOPOSITION, padGeo).

    // =====================
    // FLIP
    // =====================
    IF phase = PH_FLIP {
        LOCAL padBrng IS bearingTo(padGeo).
        LOCK STEERING TO HEADING(padBrng, 0).

        LOCAL flipErr IS VANG(SHIP:FACING:FOREVECTOR, HEADING(padBrng, 0):FOREVECTOR).
        PRINT "[FLIP] err:" + ROUND(flipErr,1) + "   " AT (0, 8).
        PRINT "brg:" + ROUND(padBrng,1) + " alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "k" AT (0, 9).
        logPeriodic("flip err:" + ROUND(flipErr,1) + " brg:" + ROUND(padBrng,1)).

        IF flipErr < 10 {
            SET bbStartTime TO TIME:SECONDS.
            SET phase TO PH_BOOSTBACK.
            SET lastPredTime TO -999.
            logEvent("FLIP complete brg:" + ROUND(padBrng,1)).
        }
    }

    // =====================
    // BOOSTBACK
    // =====================
    // Steering: nose toward a fixed point BB_NORTH_BIAS_M north of pad.
    //   This shifts bearing from ~263 to ~270 deg, canceling the
    //   southward velocity imparted by the burn angle. Static bias is
    //   stable; predictor-based north correction thrashes during
    //   maneuvering due to noisy orbital velocity. Don't change this.
    // Stop: when predicted east miss crosses BB_STOP_EAST_M.
    ELSE IF phase = PH_BOOSTBACK {
        LOCAL impactGeo    IS getImpact().
        LOCAL predEastErr  IS (PAD_LNG - impactGeo:LNG)
                              * KERBIN_M_PER_DEG * COS(PAD_LAT).
        LOCAL predNorthErr IS (PAD_LAT - impactGeo:LAT) * KERBIN_M_PER_DEG.
        LOCAL bbElapsedVal IS TIME:SECONDS - bbStartTime.

        // Static aimpoint north of pad. Bearing converges to ~270 deg.
        LOCAL aimGeo  IS LATLNG(PAD_LAT + BB_NORTH_BIAS_M / KERBIN_M_PER_DEG, PAD_LNG).
        LOCAL aimBrng IS bearingTo(aimGeo).
        LOCK STEERING TO HEADING(aimBrng, 0).

        // Throttle ramp: full burn when far east, back off as we approach.
        LOCAL bbThrCmd IS 0.12.
        IF      predEastErr < BB_FULL_THR_EAST { SET bbThrCmd TO 1.0.  }
        ELSE IF predEastErr < BB_MID_THR_EAST  { SET bbThrCmd TO 0.60. }
        ELSE IF predEastErr < BB_LOW_THR_EAST  { SET bbThrCmd TO 0.30. }
        LOCK THROTTLE TO bbThrCmd.

        PRINT "[BB] " + nsText(predNorthErr) + " " + ewText(predEastErr) + "  " AT (0, 8).
        PRINT "thr:" + ROUND(bbThrCmd*100,0) + " h:" + ROUND(hsVal,1) + " brg:" + ROUND(aimBrng,1) + "  " AT (0, 9).
        logPeriodic("bb pred " + nsText(predNorthErr) + " " + ewText(predEastErr)
                    + " thr:" + ROUND(bbThrCmd*100,0)
                    + " hspd:" + ROUND(hsVal,1)
                    + " brg:" + ROUND(aimBrng,1)).

        IF predEastErr >= BB_STOP_EAST_M OR bbElapsedVal > BB_MAX_TIME {
            LOCK THROTTLE TO 0.
            SET phase TO PH_COAST.
            SET lastPredTime TO -999.
            logEvent("BOOSTBACK end " + nsText(predNorthErr) + " " + ewText(predEastErr)
                     + " hspd:" + ROUND(hsVal,1)
                     + " t:" + ROUND(bbElapsedVal,0)).
        }
    }

    // =====================
    // COAST
    // =====================
    // Passive coast with gentle lateral guidance.
    // RCS stays ON — attitude hold against the lean gives real lateral push.
    // Think of it as small persistent corrections, not a constant battle.
    ELSE IF phase = PH_COAST {
        LOCK THROTTLE TO 0.

        IF SHIP:ALTITUDE < 45000 AND SHIP:VERTICALSPEED < -50 AND NOT finsOut {
            activateAG(1).
            setFinAuthority(FIN_AUTH_COAST).
            SET finsOut TO TRUE.
            // RCS stays ON intentionally — provides lateral correction
            // force through attitude hold of the guidance lean.
            logEvent("Fins deployed auth:" + FIN_AUTH_COAST + "% RCS:ON").
        }

        // During descent: lean gently toward pad (fins + RCS correct position).
        // During ascent or top of arc: hold retrograde or up.
        IF SHIP:VERTICALSPEED < -10 {
            LOCK STEERING TO guideDir(
                COAST_POS_KP, COAST_MAX_HVEL,
                COAST_VEL_KP, COAST_MAX_ACC,
                COAST_UP_BIAS, COAST_MAX_LEAN
            ).
        } ELSE IF SHIP:VERTICALSPEED < -1 {
            LOCK STEERING TO SHIP:SRFRETROGRADE.
        } ELSE {
            LOCK STEERING TO UP.
        }

        LOCAL northNow IS northErrM(padGeo).
        LOCAL eastNow  IS eastErrM(padGeo).

        PRINT "[COAST] alt:" + ROUND(SHIP:ALTITUDE/1000,1) + "k   " AT (0, 8).
        PRINT nsText(northNow) + " " + ewText(eastNow) + " pad:" + ROUND(padDistKmVal,1) + " " AT (0, 9).
        logPeriodic("coast " + nsText(northNow) + " " + ewText(eastNow)
                    + " pad:" + ROUND(padDistKmVal,1)
                    + " hspd:" + ROUND(hsVal,1)).

        IF SHIP:VERTICALSPEED < -1 AND SHIP:ALTITUDE < ENTRY_ALT {
            // Only go to entry burn if actually fast.
            IF SHIP:VELOCITY:SURFACE:MAG > ENTRY_SPEED_THRESHOLD {
                SET phase TO PH_ENTRY.
                logEvent("COAST->ENTRY spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                         + " pad:" + ROUND(padDistKmVal,2)).
            } ELSE {
                // Slow enough — skip entry burn, go straight to aero guidance.
                IF finsOut AND NOT finsAeroSet {
                    setFinAuthority(FIN_AUTH_AERO).
                    SET finsAeroSet TO TRUE.
                }
                SET phase TO PH_AERO.
                logEvent("COAST->AERO (no burn spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                         + " < " + ENTRY_SPEED_THRESHOLD + ") pad:" + ROUND(padDistKmVal,2)).
            }
        }
    }

    // =====================
    // ENTRY (braking)
    // =====================
    // Only reached if speed was above ENTRY_SPEED_THRESHOLD.
    // Fires retrograde at 100% until speed drops to ENTRY_END_SPEED.
    ELSE IF phase = PH_ENTRY {
        LOCK STEERING TO SHIP:SRFRETROGRADE.
        LOCK THROTTLE TO 1.0.

        IF finsOut AND NOT finsAeroSet {
            setFinAuthority(FIN_AUTH_AERO).
            SET finsAeroSet TO TRUE.
        }

        PRINT "[ENTRY] spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0) + "   " AT (0, 8).
        PRINT "pad:" + ROUND(padDistKmVal,2) + " h:" + ROUND(hsVal,1) + "   " AT (0, 9).
        logPeriodic("entry spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                    + " pad:" + ROUND(padDistKmVal,2)
                    + " hspd:" + ROUND(hsVal,1)).

        IF SHIP:VELOCITY:SURFACE:MAG <= ENTRY_END_SPEED {
            LOCK THROTTLE TO 0.
            SET phase TO PH_AERO.
            logEvent("ENTRY->AERO spd:" + ROUND(SHIP:VELOCITY:SURFACE:MAG,0)
                     + " pad:" + ROUND(padDistKmVal,2)).
        }
    }

    // =====================
    // AERO
    // =====================
    // No thrust. Velocity-tracking lateral guidance.
    // Continuously measures position error vs pad, commands
    // lean to achieve desired lateral velocity. Self-corrects
    // every cycle — no trim offset needed.
    ELSE IF phase = PH_AERO {
        LOCK THROTTLE TO 0.
        LOCK STEERING TO guideDir(
            AERO_POS_KP, AERO_MAX_HVEL,
            AERO_VEL_KP, AERO_MAX_ACC,
            AERO_UP_BIAS, AERO_MAX_LEAN
        ).

        LOCAL ignAltVal IS ignitionAlt().
        LOCAL northNow  IS northErrM(padGeo).
        LOCAL eastNow   IS eastErrM(padGeo).

        PRINT "[AERO] pad:" + ROUND(padDistKmVal,2) + "   " AT (0, 8).
        PRINT nsText(northNow) + " " + ewText(eastNow) + " h:" + ROUND(hsVal,1) + " ign:" + ROUND(ignAltVal,0) + "  " AT (0, 9).
        logPeriodic("aero pad:" + ROUND(padDistKmVal,2)
                    + " " + nsText(northNow) + " " + ewText(eastNow)
                    + " hspd:" + ROUND(hsVal,1)
                    + " ign:" + ROUND(ignAltVal,0)).

        IF altAGLVal <= ignAltVal {
            LOCK THROTTLE TO 0.
            SET phase TO PH_LANDING.
            logEvent("AERO->LANDING agl:" + ROUND(altAGLVal,0)
                     + " vs:" + ROUND(SHIP:VERTICALSPEED,0)
                     + " hspd:" + ROUND(hsVal,1)
                     + " pad:" + ROUND(padDistKmVal,2)).
        }
    }

    // =====================
    // LANDING
    // =====================
    // Fast approach. PD controller steers to kill horizontal
    // velocity directly over the pad. Comes straight down.
    // Throttle holds descent profile and kills vertical speed.
    ELSE IF phase = PH_LANDING {
        SET vesselBounds TO SHIP:BOUNDS.
        LOCAL altAGL IS terrainAGL().

        IF finsOut AND NOT finsLandSet {
            setFinAuthority(FIN_AUTH_LAND).
            SET finsLandSet TO TRUE.
            RCS OFF.
            logEvent("Landing fin auth:" + FIN_AUTH_LAND + "%").
        }

        IF NOT legsOut AND altAGL < LEG_DEPLOY_ALT {
            GEAR ON.
            SET legsOut TO TRUE.
            SET vesselBounds TO SHIP:BOUNDS.
            SET altAGL TO terrainAGL().
            logEvent("LEGS deployed at " + ROUND(altAGL,0) + "m").
        }

        LOCK STEERING TO landingGuideDir().
        LOCAL thrCmdVal IS landingThrottle().
        LOCK THROTTLE TO thrCmdVal.

        LOCAL northNow IS northErrM(padGeo).
        LOCAL eastNow  IS eastErrM(padGeo).

        PRINT "[LAND] agl:" + ROUND(altAGLVal,0) + " vs:" + ROUND(SHIP:VERTICALSPEED,1) + "  " AT (0, 8).
        PRINT "thr:" + ROUND(thrCmdVal*100,0) + " " + nsText(northNow) + " " + ewText(eastNow) + " " AT (0, 9).
        logPeriodic("land thr:" + ROUND(thrCmdVal*100,0)
                    + " vs:" + ROUND(SHIP:VERTICALSPEED,1)
                    + " hspd:" + ROUND(hsVal,1)
                    + " " + nsText(northNow) + " " + ewText(eastNow)).

        IF SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED" {
            SET touchdownSeen TO TRUE.
        }

        IF touchdownSeen
        OR (altAGLVal < 2
            AND SHIP:VERTICALSPEED > TOUCHDOWN_VS
            AND SHIP:VERTICALSPEED < 1
            AND hsVal < TOUCHDOWN_HS) {
            SET phase TO PH_TOUCHDOWN.
            logEvent("TOUCHDOWN vs:" + ROUND(SHIP:VERTICALSPEED,1)
                     + " hs:" + ROUND(hsVal,1)
                     + " pad:" + ROUND(padDistKmVal,2)
                     + " lat:" + ROUND(SHIP:LATITUDE,4)
                     + " lng:" + ROUND(SHIP:LONGITUDE,4)).
        }
    }

    WAIT 0.
}

// ============================================================
//  TOUCHDOWN CLEANUP
// ============================================================
LOCK THROTTLE TO 0.
WAIT 1.
UNLOCK STEERING.
WAIT 1.
UNLOCK THROTTLE.
WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
RCS OFF.
SAS OFF.
setFinAuthority(0).

LOCAL finalPadKm IS distKm(SHIP:GEOPOSITION, padGeo).
logEvent("SCRIPT END - lat:" + ROUND(SHIP:LATITUDE,4)
         + " lng:" + ROUND(SHIP:LONGITUDE,4)
         + " pad:" + ROUND(finalPadKm,2) + "km").

PRINT "                                  " AT (0, 8).
PRINT "                                  " AT (0, 9).
PRINT "+----------------------------+" AT (0, 8).
PRINT "| TOUCHDOWN / SCRIPT END    |" AT (0, 9).
PRINT "+----------------------------+" AT (0, 8).
PRINT "Pad miss: " + ROUND(finalPadKm * 1000, 0) + "m" AT (0, 9).
SAS OFF.
WAIT 1.
UNLOCK ALL.
WAIT 1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
WAIT 1.
PRINT "Booster disabled." AT (0, 10).
PRINT "END PROGRAM."      AT (0, 11).
