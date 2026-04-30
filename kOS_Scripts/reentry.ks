// =================================================================
// Simple Ballistic Reentry Script for Mun Free Return
// No burn required - just service module separation and reentry
// =================================================================

// --- UTILITY FUNCTIONS ---
FUNCTION DISPLAY_HEADER {
    PARAMETER title.
    CLEARSCREEN.
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  APOLLO MISSION CONTROL - REENTRY PROGRAM      ║".
    PRINT "╠════════════════════════════════════════════════╣".
    LOCAL header_line IS "║  " + title.
    LOCAL padding IS 48 - title:LENGTH - 2.
    SET header_line TO header_line + SPACESTRING(padding) + "║".
    PRINT header_line.
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
}

FUNCTION SPACESTRING {
    PARAMETER len.
    LOCAL s IS "".
    FROM {LOCAL i IS 0.} UNTIL i >= len STEP {SET i TO i + 1.} DO {
        SET s TO s + " ".
    }
    RETURN s.
}
// Enable capsule APU (NH-24 Monopropellant APU)
FUNCTION EnableAPU {
    LOCAL apuFound IS FALSE.
    
    //PRINT "Searching for APU...".
    
    FOR p IN SHIP:PARTS {
        // Look for the NH-24 APU by name
        IF p:TITLE:CONTAINS("NH-24") OR p:TITLE:CONTAINS("APU") OR p:NAME:CONTAINS("NH-24") {
            //PRINT "Found: " + p:TITLE.
            
            // Check for ModuleResourceConverter (most likely)
            IF p:HASMODULE("ModuleResourceConverter") {
                LOCAL conv IS p:GETMODULE("ModuleResourceConverter").
                
                // Use the correct event name: "start turbine"
                IF conv:HASEVENT("start turbine") {
                    conv:DOEVENT("start turbine").
                    PRINT "APU turbine started.".
                    SET apuFound TO TRUE.
                }
            }
            
            // Check for ModuleGenerator (alternative)
            IF NOT apuFound AND p:HASMODULE("ModuleGenerator") {
                LOCAL gen IS p:GETMODULE("ModuleGenerator").
                IF gen:HASEVENT("start turbine") {
                    gen:DOEVENT("start turbine").
                    PRINT "APU turbine started.".
                    SET apuFound TO TRUE.
                }
            }
        }
    }
    
    IF NOT apuFound {
        PRINT "WARNING: Could not find or activate APU!".
        PRINT "You may need to activate it manually.".
    }
    
    RETURN apuFound.
}

FUNCTION PodRCS {
    LOCAL enabled IS 0.
    
    // Step 1: Toggle RCS on all command pods
    FOR p IN SHIP:PARTS {
        IF p:HASMODULE("ModuleCommand") {
            IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") {
                LOCAL moduleName IS "ModuleRCS".
                IF p:HASMODULE("ModuleRCSFX") { SET moduleName TO "ModuleRCSFX". }
                
                LOCAL rcsModule IS p:GETMODULE(moduleName).
                
                IF rcsModule:ALLACTIONNAMES:CONTAINS("Toggle RCS Thrust") {
                    rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    PRINT "Toggled RCS on: " + p:TITLE.
                    SET enabled TO enabled + 1.
                }
            }
        }
    }
    
    IF enabled = 0 {
        PRINT "No command pod RCS found.".
        RETURN FALSE.
    }
    
    // Step 2: Verify RCS is actually on by testing it
    PRINT "Verifying RCS is active...".
    
    LOCAL monoBefore IS SHIP:MONOPROPELLANT.
    PRINT "MonoProp before test: " + ROUND(monoBefore, 2).
    
    // Enable global RCS and fire a brief roll
    RCS ON.
    WAIT 0.1.
    
    SET SHIP:CONTROL:ROLL TO 0.3.  // Gentle roll
    WAIT 0.5.  // Fire for half a second
    SET SHIP:CONTROL:ROLL TO 0.
    
    WAIT 0.5.  // Let it settle
    
    LOCAL monoAfter IS SHIP:MONOPROPELLANT.
    PRINT "MonoProp after test: " + ROUND(monoAfter, 2).
    
    LOCAL monoUsed IS monoBefore - monoAfter.
    
    IF monoUsed > 0.01 {
        PRINT "RCS VERIFIED ACTIVE - used " + ROUND(monoUsed, 3) + " units.".
        RETURN TRUE.
    } ELSE {
        PRINT "RCS NOT ACTIVE - no monoprop consumed!".
        PRINT "Toggling again...".
        
        // Toggle again (maybe we turned it off by accident)
        FOR p IN SHIP:PARTS {
            IF p:HASMODULE("ModuleCommand") {
                IF p:HASMODULE("ModuleRCS") OR p:HASMODULE("ModuleRCSFX") {
                    LOCAL moduleName IS "ModuleRCS".
                    IF p:HASMODULE("ModuleRCSFX") { SET moduleName TO "ModuleRCSFX". }
                    
                    LOCAL rcsModule IS p:GETMODULE(moduleName).
                    IF rcsModule:ALLACTIONNAMES:CONTAINS("Toggle RCS Thrust") {
                        rcsModule:DOACTION("Toggle RCS Thrust", TRUE).
                    }
                }
            }
        }
        
        // Test again
        SET monoBefore TO SHIP:MONOPROPELLANT.
        SET SHIP:CONTROL:ROLL TO 0.3.
        WAIT 0.5.
        SET SHIP:CONTROL:ROLL TO 0.
        WAIT 0.5.
        SET monoAfter TO SHIP:MONOPROPELLANT.
        SET monoUsed TO monoBefore - monoAfter.
        
        IF monoUsed > 0.01 {
            PRINT "RCS NOW ACTIVE after second toggle - used " + ROUND(monoUsed, 3) + " units.".
            RETURN TRUE.
        } ELSE {
            PRINT "RCS STILL NOT ACTIVE - may not have monoprop or RCS thrusters.".
            RETURN FALSE.
        }
    }
}

FUNCTION StageWithRetry {
    PARAMETER maxRetries IS 5.
    
    LOCAL partCountBefore IS SHIP:PARTS:LENGTH.
    LOCAL attempts IS 0.
    
    UNTIL SHIP:PARTS:LENGTH < partCountBefore OR attempts >= maxRetries {
        STAGE.
        WAIT 0.5.
        SET attempts TO attempts + 1.
    }
    
    RETURN SHIP:PARTS:LENGTH < partCountBefore.
}

// Returns TRUE once a chute is actually out (semi/full) because "Cut" becomes available.
FUNCTION HAS_CUT_EVENT {
  PARAMETER m.
  RETURN m:HASEVENT("Cut Parachute") OR m:HASEVENT("Cut Chute") OR m:HASEVENT("Cut").
}

FUNCTION WATCH_CHUTES {
  PARAMETER drogueWord IS "Drogue".
  PARAMETER mainWord   IS "Main".

  LOCAL drogues IS LIST().
  LOCAL mains   IS LIST().

  LIST PARTS IN parts.
  FOR p IN parts {
    IF p:HASMODULE("ModuleParachute") {
      LOCAL m IS p:GETMODULE("ModuleParachute").
      LOCAL title IS p:TITLE.
      IF title:FIND(drogueWord) >= 0 {
        drogues:ADD(m).
      } ELSE IF title:FIND(mainWord) >= 0 {
        mains:ADD(m).
      } ELSE {
        mains:ADD(m).
      }
    } ELSE IF p:HASMODULE("RealChuteModule") {
      LOCAL m IS p:GETMODULE("RealChuteModule").
      LOCAL title IS p:TITLE.
      IF title:FIND(drogueWord) >= 0 {
        drogues:ADD(m).
      } ELSE IF title:FIND(mainWord) >= 0 {
        mains:ADD(m).
      } ELSE {
        mains:ADD(m).
      }
    }
  }

  IF drogues:LENGTH = 0 { PRINT "WATCH_CHUTES: no drogues found ('" + drogueWord + "').". }
  IF mains:LENGTH   = 0 { PRINT "WATCH_CHUTES: no mains found ('" + mainWord + "').". }

  // 1) Print once when any drogue deploys (Cut event appears)
  LOCAL drogueAnnounced IS FALSE.
  UNTIL drogueAnnounced OR drogues:LENGTH = 0 {
    FOR d IN drogues {
      IF HAS_CUT_EVENT(d) {
        PRINT "Drogue deployed.". //on " + d:PART:TITLE + ".".
        SET drogueAnnounced TO TRUE.
        BREAK.
      }
    }
    WAIT 0.1.
  }

  // 2) When any main deploys, pulse AG1 to cut drogues and print once
  LOCAL mainHandled IS FALSE.
  UNTIL mainHandled OR mains:LENGTH = 0 {
    FOR m IN mains {
      IF HAS_CUT_EVENT(m) {
        PRINT "Mains deployed — cutting drogue(s).".
        FOR d IN drogues {
          IF HAS_CUT_EVENT(d) {d:DOEVENT("Cut Parachute").}
        }
        SET mainHandled TO TRUE.
        BREAK.
      }
    }
    WAIT 0.1.
  }
}


// --- MAIN REENTRY SEQUENCE ---
CLEARSCREEN.
// PRINT "=== Mun Free Return - Ballistic Reentry ===".
// PRINT " ".

DISPLAY_HEADER(" ").

PRINT "Current altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
PRINT " ".

// Phase 1: Wait for 110km altitude
PRINT "Waiting for 110 km altitude for service".
PRINT "module separation.".
WAIT UNTIL SHIP:ALTITUDE < 170000. {
    KUNIVERSE:TIMEWARP:CANCELWARP().
    WAIT UNTIL KUNIVERSE:TIMEWARP:ISSETTLED.
}

PRINT " ".
PRINT "=== 110 KM - PREPARING FOR SEPARATION ===".

// Enable capsule systems
PRINT "Enabling Capsule APU.".
EnableAPU().
LIGHTS ON.
RCS ON.

PRINT " ".
PRINT "Aligning to surface normal for clean separation...".
SAS OFF.
LOCK STEERING TO VCRS(SHIP:VELOCITY:ORBIT, BODY:POSITION).

UNTIL VANG(SHIP:FACING:VECTOR, VCRS(SHIP:VELOCITY:ORBIT, BODY:POSITION)) < 2 {
    WAIT 0.1.
}

PRINT "Aligned. Separating service module in 3 seconds...".
WAIT 3.

PRINT "Enabling Capsule RCS System.".
PodRCS().

PRINT "STAGING - Service Module Separation".
IF NOT StageWithRetry(3) {
    PRINT "CRITICAL FAILURE!".  
    PRINT "Staging has failed. Handing over manual control.".
    WAIT UNTIL FALSE.
}
WAIT 15.

// Phase 2: Align for reentry
PRINT " ".
PRINT "=== REENTRY ALIGNMENT ===".
PRINT "Aligning to surface retrograde...".
LOCK STEERING TO SHIP:RETROGRADE.

WAIT UNTIL VANG(SHIP:FACING:VECTOR, SHIP:RETROGRADE:VECTOR) < 2. {
    WAIT 0.1.
}

PRINT "Aligned. Holding retrograde attitude...".

// Phase 3: Coast until 40km
PRINT " ".
PRINT "Coasting to 40 km...".
WAIT UNTIL SHIP:ALTITUDE <= 40000.

PRINT " ".
PRINT "=== 40 KM - RCS & STEERING OFF ===".
RCS OFF.
WAIT 0.1.
UNLOCK STEERING.
WAIT 0.1.
SET SHIP:CONTROL:NEUTRALIZE TO TRUE.
WAIT 0.1.
SAS OFF.
WAIT 0.1.

PRINT "Waiting for parachute altitude...".

// Phase 4: Deploy parachutes
WAIT UNTIL SHIP:ALTITUDE <= 15000.

PRINT " ".
PRINT "=== 15 KM - DEPLOYING PARACHUTES ===".
STAGE.
PRINT "Parachute cover jettisoned.".
WAIT 2.
ChutesSafe ON.
PRINT "All Parachutes Armed, ready for deployment.".
WATCH_CHUTES().

// Phase 5: Wait for landing
PRINT " ".
PRINT "Descending under chutes...".
WAIT UNTIL SHIP:STATUS = "LANDED" OR SHIP:STATUS = "SPLASHED".

// Landing report
PRINT " ".
PRINT "=== LANDING REPORT ===".
LOCAL curLat IS SHIP:LATITUDE.
LOCAL curLon IS SHIP:LONGITUDE.

PRINT "Status: " + SHIP:STATUS.
PRINT "Position: " + ROUND(curLat, 6) + "°, " + ROUND(curLon, 6) + "°".

PRINT " ".
PRINT "Mission complete!".
WAIT 10.

PRINT "Shutting down Processor.".
SHUTDOWN.
