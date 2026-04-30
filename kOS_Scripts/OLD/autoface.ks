// ===============================================================
// autoface.ks — run on the *target* vessel
// 1) Pick the chaser (SOI + ORBITING only, sorted by distance).
// 2) Point this vessel's docking port toward the chaser (TARGET).
//    If a target docking port is visible, align roll to it.
// ===============================================================

// ---------- Config ----------
PARAMETER chaserName IS "", myPortTag IS "DOCK_A".

SET AF_ERR_ENTER_DEG  TO 3.0.
SET AF_ERR_EXIT_DEG   TO 5.0.
SET AF_TICK_WAIT      TO 0.1.

// ---------- Minimal UI helpers ----------
FUNCTION ui_header {
  PARAMETER title, l1, l2, l3.
  CLEARSCREEN.
  PRINT title.
  PRINT "".
  PRINT l1.
  PRINT l2.
  PRINT l3.
}

FUNCTION ui_status {
  PARAMETER text.
  PRINT text AT (0, 8).
}

// ---------- Step-1 style target picker (SOI + ORBITING only) ----------
FUNCTION AF_SELECT_CHASER {
  PARAMETER desiredName IS "".

  // If an exact name was provided and found, use it.
  IF desiredName <> "" {
    LIST TARGETS IN TL.
    FOR t IN TL {
      IF t:TYPENAME = "Vessel" AND t:NAME = desiredName AND t:STATUS = "ORBITING" AND t:OBT:BODY = SHIP:OBT:BODY AND t:NAME <> SHIP:NAME {
        SET TARGET TO t.
        RETURN TRUE.
      }
    }
    PRINT "Name '" + desiredName + "' not found; opening picker.".
  }

  // Must be in flight on the active vessel.
  IF KUNIVERSE:ACTIVEVESSEL <> SHIP OR NOT (STATUS = "ORBITING" OR STATUS = "FLYING" OR STATUS = "SUB_ORBITAL" OR STATUS = "LANDED" OR STATUS = "SPLASHED") {
    PRINT "AutoFace: run in flight on the active vessel.".
    RETURN FALSE.
  }

  LOCAL mySOI IS SHIP:OBT:BODY.
  LOCAL allTargets IS LIST().
  LIST TARGETS IN allTargets.

  // Filter: other vessels, same SOI, ORBITING.
  LOCAL candidates IS LIST().
  FOR t IN allTargets {
    IF t:TYPENAME = "Vessel" AND t:OBT:BODY = mySOI AND t:STATUS = "ORBITING" AND t:NAME <> SHIP:NAME {
      candidates:ADD(t).
    }
  }

  IF candidates:LENGTH = 0 {
    PRINT "AutoFace: no orbiting vessels found in " + mySOI:NAME + ".".
    RETURN FALSE.
  }

  // Sort by distance ascending (simple bubble).
  LOCAL n IS candidates:LENGTH.
  LOCAL i IS 0.
  UNTIL i >= n - 1 {
    LOCAL j IS 0.
    UNTIL j >= n - i - 1 {
      LOCAL distA IS (SHIP:POSITION - candidates[j]:POSITION):MAG.
      LOCAL distB IS (SHIP:POSITION - candidates[j + 1]:POSITION):MAG.
      IF distA > distB {
        LOCAL tmp IS candidates[j].
        SET candidates[j] TO candidates[j + 1].
        SET candidates[j + 1] TO tmp.
      }
      SET j TO j + 1.
    }
    SET i TO i + 1.
  }

  // Print list and get choice via GETCHAR digits.
  PRINT "Select chaser (same SOI, ORBITING):".
  LOCAL idx IS 0.
  UNTIL idx >= candidates:LENGTH {
    LOCAL ves IS candidates[idx].
    LOCAL dkm IS ROUND((SHIP:POSITION - ves:POSITION):MAG / 1000, 1).
    PRINT UPPERCASE(STRING(idx + 1)) + ": " + ves:NAME + "  (" + dkm + " km)".
    SET idx TO idx + 1.
  }
  PRINT "Enter number (1-" + candidates:LENGTH + "), then Enter. Any non-digit cancels.".

  LOCAL inputStr IS "".
  UNTIL FALSE {
    LOCAL ch IS TERMINAL:INPUT:GETCHAR().
    IF ch = TERMINAL:INPUT:RETURN { BREAK. }
    ELSE IF ch:TONUMBER(-1) >= 0 AND ch:TONUMBER(-1) <= 9 {
      SET inputStr TO inputStr + ch.
      PRINT ch.
    } ELSE {
      SET inputStr TO "".
      BREAK.
    }
  }

  LOCAL choice IS inputStr:TONUMBER(-1).
  IF choice >= 1 AND choice <= candidates:LENGTH {
    SET TARGET TO candidates[choice - 1].
    PRINT "TARGET set to: " + TARGET:NAME + ".".
    RETURN TRUE.
  } ELSE {
    PRINT "Selection cancelled/invalid.".
    RETURN FALSE.
  }
}

// ---------- Docking-port helpers ----------
FUNCTION AF_FIND_MY_PORT {
  PARAMETER tag IS myPortTag.
  IF SHIP:HASSUFFIX("DOCKINGPORTS") {
    LIST DOCKINGPORTS IN ports.
    IF tag <> "" {
      LOCAL i IS 0.
      UNTIL i >= ports:LENGTH {
        LOCAL dp IS ports[i].
        IF dp:HASSUFFIX("PART") AND dp:PART:HASSUFFIX("TAG") {
          IF dp:PART:TAG = tag { RETURN dp. }
        }
        SET i TO i + 1.
      }
    }
    IF ports:LENGTH > 0 { RETURN ports[0]. }
  }
  // Fallback: scan parts for a docking module.
  LIST PARTS IN ps.
  LOCAL j IS 0.
  UNTIL j >= ps:LENGTH {
    LOCAL pr IS ps[j].
    IF pr:HASSUFFIX("DOCKINGPORT") { RETURN pr:DOCKINGPORT. }
    SET j TO j + 1.
  }
  RETURN "NONE".
}

// Find a docking port on TARGET if loaded; else return 0 (use vessel COM).
FUNCTION DCK_FIND_TARGET_PORT {
  PARAMETER tag IS "".

  IF NOT TARGET:HASSUFFIX("PARTS") { RETURN 0. }
  LOCAL tparts IS TARGET:PARTS.
  IF tparts:LENGTH = 0 { RETURN 0. }

  // Gather docking ports, optionally filtering by part TAG.
  LOCAL candidates IS LIST().
  LOCAL i IS 0.
  UNTIL i >= tparts:LENGTH {
    LOCAL pr IS tparts[i].
    IF pr:HASMODULE("ModuleDockingNode") {
      IF tag <> "" {
        IF pr:HASSUFFIX("TAG") AND pr:TAG = tag { candidates:ADD(pr). }
      } ELSE {
        candidates:ADD(pr).
      }
    }
    SET i TO i + 1.
  }
  IF candidates:LENGTH = 0 { RETURN 0. }

  // Pick the port most facing us.
  LOCAL bestP IS candidates[0].
  LOCAL bestScore IS -1E9.
  LOCAL k IS 0.
  UNTIL k >= candidates:LENGTH {
    LOCAL prt IS candidates[k].
    LOCAL toUs IS (SHIP:POSITION - prt:POSITION):NORMALIZED.
    LOCAL fwd  IS prt:FACING:FOREVECTOR.
    LOCAL score IS VDOT(fwd, toUs).
    IF score > bestScore { SET bestScore TO score. SET bestP TO prt. }
    SET k TO k + 1.
  }
  RETURN bestP.
}

// Utility to get a position for either a docking port object or a part/vessel.
FUNCTION AF_PORT_POS {
  PARAMETER x.
  IF x = 0 { RETURN SHIP:POSITION + TARGET:POSITION. }
  IF x:HASSUFFIX("PORTPOSITION") { RETURN x:PORTPOSITION. }
  IF x:HASSUFFIX("POSITION")     { RETURN x:POSITION. }
  IF x:HASSUFFIX("PART")         { RETURN x:PART:POSITION. }
  RETURN SHIP:POSITION.
}

// Utility to get an "up" vector for roll alignment (if a port is known).
FUNCTION AF_PORT_UP {
  PARAMETER x.
  IF x = 0 { RETURN TARGET:FACING:TOPVECTOR. }
  IF x:HASSUFFIX("PART") AND x:PART:HASSUFFIX("FACING") { RETURN x:PART:FACING:TOPVECTOR. }
  IF x:HASSUFFIX("FACING") { RETURN x:FACING:TOPVECTOR. }
  RETURN TARGET:FACING:TOPVECTOR.
}

// Desired attitude to face our port toward target (and match roll if target port known).
FUNCTION AF_DESIRED_ATT {
  PARAMETER myPort, tgtPortOrVessel.
  LOCAL myPos  IS AF_PORT_POS(myPort).
  LOCAL tgtPos IS AF_PORT_POS(tgtPortOrVessel).
  LOCAL lookVec IS (tgtPos - myPos):NORMALIZED.
  LOCAL upVec   IS SHIP:FACING:TOPVECTOR.
  IF tgtPortOrVessel <> 0 { SET upVec TO AF_PORT_UP(tgtPortOrVessel). }
  RETURN LOOKDIRUP(lookVec, upVec).
}

// ---------- Main ----------
CLEARSCREEN.
ui_header("=== AutoFace (Target Vessel) ===", "", "", "").

// Choose/set the chaser as TARGET.
IF NOT HASTARGET {
  IF NOT AF_SELECT_CHASER(chaserName) {
    PRINT "AutoFace: No TARGET set; aborting.".
    WAIT 999999.
  }
} ELSE {
  // Allow exact-name override if provided.
  IF chaserName <> "" AND TARGET:NAME <> chaserName {
    IF NOT AF_SELECT_CHASER(chaserName) {
      PRINT "Keeping existing TARGET: " + TARGET:NAME + ".".
    }
  }
}

PRINT "Chaser TARGET: " + TARGET:NAME + ".".

// Find my docking port and set control-from if found.
LOCAL myPort IS AF_FIND_MY_PORT(myPortTag).
IF myPort = "NONE" {
  PRINT "No docking port found on this vessel. Using vessel reference.".
} ELSE {
  PRINT "Using docking port: " + myPort:PART:TITLE + ".".
  myPort:CONTROLFROM().
}

// Control loop: face the chaser (and match roll if its port becomes visible).
LOCAL holdMode IS FALSE.

UNTIL FALSE {
  // Try to lock a target docking port once it’s loaded.
  LOCAL tgtPort IS AF_FIND_TARGET_PORT().

  // Desired attitude from our port to theirs (or to vessel COM).
  LOCAL cmdAtt IS AF_DESIRED_ATT(myPort, tgtPort).

  // Error in degrees between current facing and command.
  LOCAL errDeg IS VANG(SHIP:FACING:VECTOR, cmdAtt:VECTOR).

  // Hysteresis: if within enter threshold, hand to SAS hold; else manual steer.
  IF NOT holdMode AND errDeg <= AF_ERR_ENTER_DEG {
    UNLOCK STEERING.
    SAS ON.
    SET SASMODE TO "STABILITYASSIST".
    SET holdMode TO TRUE.
  }
  IF holdMode AND errDeg > AF_ERR_EXIT_DEG {
    SAS OFF.
    SET holdMode TO FALSE.
  }
  IF NOT holdMode { LOCK STEERING TO cmdAtt. }

  LOCAL sasTxt IS "OFF".
  IF SAS { 
    SET sasTxt TO "ON". 
  }
  ui_status("AutoFace | Err " + ROUND(errDeg,2) + " deg | SAS " + sasTxt + " | TARGET " + TARGET:NAME + ".").

  WAIT AF_TICK_WAIT.
}
