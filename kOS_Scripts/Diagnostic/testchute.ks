    // 9) Chute deployment
    WAIT UNTIL SHIP:ALTITUDE <= 15000.
    STAGE.  // ARMS CHUTES. If there is a cover, this eject it at this time to expose chutes.
    // WATCH_CHUTES function will watch deployment as set in VAB.
    WATCH_CHUTES().

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
        PRINT "Drogue deployed on " + d:PART:TITLE + ".".
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
        PRINT "Main deployed on " + m:PART:TITLE + " — cutting drogue(s).".
        FOR d IN drogues {
          IF HAS_CUT_EVENT(d) {d:DOEVENT("Cut Parachute").}
        }
        // AG1 ON.
        // WAIT 0.1.
        // AG1 OFF.
        SET mainHandled TO TRUE.
        BREAK.
      }
    }
    WAIT 0.1.
  }
}
