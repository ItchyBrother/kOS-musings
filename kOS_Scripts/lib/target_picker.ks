FUNCTION TGT_SELECT_ORBITING {
  PARAMETER desiredName IS "".
  CLEARSCREEN.

  IF desiredName <> "" {
    LIST TARGETS IN TL.
    FOR t IN TL {
      IF t:TYPENAME = "Vessel" AND t:NAME = desiredName {
        SET TARGET TO t.
        RETURN TRUE.
      }
    }
    PRINT "Name '" + desiredName + "' not found; opening picker.".
  }

  IF KUNIVERSE:ACTIVEVESSEL <> SHIP OR NOT (STATUS = "ORBITING" OR STATUS = "FLYING" OR STATUS = "SUB_ORBITAL" OR STATUS = "LANDED" OR STATUS = "SPLASHED") {
    PRINT "Error: run in flight on the active vessel.".
    RETURN FALSE.
  }

  LOCAL mySOI IS SHIP:OBT:BODY.
  LOCAL allTargets IS LIST().
  LIST TARGETS IN allTargets.
  LOCAL soiVessels IS LIST().
  FOR tgt IN allTargets {
    IF tgt:TYPENAME = "Vessel" AND tgt:OBT:BODY = mySOI AND tgt:NAME <> SHIP:NAME AND tgt:STATUS = "ORBITING" {
      soiVessels:ADD(tgt).
    }
  }

  IF soiVessels:LENGTH = 0 {
    PRINT "No orbiting vessels in " + mySOI:NAME + ".".
    RETURN FALSE.
  }

  // Sort by distance (bubble).
  LOCAL n IS soiVessels:LENGTH.
  LOCAL i IS 0.
  UNTIL i >= n - 1 {
    LOCAL j IS 0.
    UNTIL j >= n - i - 1 {
      LOCAL distA IS (SHIP:POSITION - soiVessels[j]:POSITION):MAG.
      LOCAL distB IS (SHIP:POSITION - soiVessels[j + 1]:POSITION):MAG.
      IF distA > distB {
        LOCAL tmp IS soiVessels[j].
        SET soiVessels[j] TO soiVessels[j + 1].
        SET soiVessels[j + 1] TO tmp.
      }
      SET j TO j + 1.
    }
    SET i TO i + 1.
  }

  PRINT "Select target:".
  LOCAL k IS 0.
  UNTIL k >= soiVessels:LENGTH {
    LOCAL ves IS soiVessels[k].
    PRINT (k + 1) + ": " + ves:NAME + "  (Dist: " + ROUND((SHIP:POSITION - ves:POSITION):MAG/1000,1) + " km).".
    SET k TO k + 1.
  }

  PRINT "Enter number and press Enter. Any non-digit cancels.".
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
  IF choice >= 1 AND choice <= soiVessels:LENGTH {
    LOCAL selectedVes IS soiVessels[choice - 1].
    SET TARGET TO selectedVes.
    PRINT "Target set to: " + selectedVes:NAME + ".".
    RETURN TRUE.
  } ELSE {
    PRINT "Invalid input or cancelled.".
    RETURN FALSE.
  }
}
