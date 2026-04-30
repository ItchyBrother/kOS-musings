FUNCTION INT_FIND_MINIMA {
  PARAMETER orbits, samples.

  LOCAL P1 IS SHIP:OBT:PERIOD.
  LOCAL P2 IS TARGET:OBT:PERIOD.
  LOCAL window IS MAX(P1, P2) * orbits.
  LOCAL steps IS MAX(10, orbits * samples).
  LOCAL dt IS window / steps.
  LOCAL ut0 IS TIME:SECONDS.

  LOCAL mins IS LIST(). // each: LEXICON("t", ut, "d", m, "v", m/s).
  LOCAL stepAccum IS 0.
  LOCAL d2 IS 1E99.
  LOCAL d1 IS 1E98.

  UNTIL stepAccum > window {
    LOCAL t IS ut0 + stepAccum.
    LOCAL rT IS POSITIONAT(TARGET, t).
    LOCAL rS IS POSITIONAT(SHIP, t).
    LOCAL d IS (rT - rS):MAG.

    IF (d1 < d2) AND (d1 < d) {
      LOCAL tmin IS t - dt.
      LOCAL vT IS VELOCITYAT(TARGET, tmin):ORBIT.
      LOCAL vS IS VELOCITYAT(SHIP, tmin):ORBIT.
      LOCAL vrelmag IS (vS - vT):MAG.
      mins:ADD( LEXICON("t", tmin, "d", d1, "v", vrelmag) ).
    }

    SET d2 TO d1.
    SET d1 TO d.
    SET stepAccum TO stepAccum + dt.
  }

  RETURN mins.
}

FUNCTION INT_SORT_BY_D {
  PARAMETER arr.
  LOCAL n IS arr:LENGTH.
  LOCAL i IS 0.
  UNTIL i >= n - 1 {
    LOCAL j IS 0.
    UNTIL j >= n - i - 1 {
      IF arr[j + 1]["d"] < arr[j]["d"] {
        LOCAL tmp IS arr[j].
        SET arr[j] TO arr[j + 1].
        SET arr[j + 1] TO tmp.
      }
      SET j TO j + 1.
    }
    SET i TO i + 1.
  }
  RETURN arr.
}

FUNCTION INT_CHOOSE_BEST {
  PARAMETER mins, vCap IS 60, dPref IS 2000.

  IF mins:LENGTH = 0 {
    PRINT "INT_CHOOSE_BEST: no candidates.".
    RETURN LEXICON("t", TIME:SECONDS, "d", 1E99, "v", 0).
  }

  // 1) If any pass is under dPref with v <= vCap, pick the closest of those.
  LOCAL found IS FALSE.
  LOCAL best IS mins[0].
  LOCAL i IS 0.
  UNTIL i >= mins:LENGTH {
    LOCAL dNow IS mins[i]["d"].
    LOCAL vNow IS mins[i]["v"].
    IF dNow < dPref AND vNow <= vCap {
      IF NOT found OR dNow < best["d"] { SET best TO mins[i]. SET found TO TRUE. }
    }
    SET i TO i + 1.
  }
  IF found { RETURN best. }

  // 2) Otherwise, minimize a weighted score: distance + W * relative-speed.
  LOCAL W IS 3000. // meters per (m/s) — penalize big v a lot.
  SET best TO mins[0].
  LOCAL bestScore IS best["d"] + W * best["v"].
  SET i TO 1.
  UNTIL i >= mins:LENGTH {
    LOCAL score IS mins[i]["d"] + W * mins[i]["v"].
    IF score < bestScore {
      SET best TO mins[i].
      SET bestScore TO score.
    }
    SET i TO i + 1.
  }
  RETURN best.
}

// Sort minima by time (ascending).
FUNCTION INT_SORT_BY_T {
  PARAMETER arr.
  LOCAL n IS arr:LENGTH.
  LOCAL i IS 0.
  UNTIL i >= n - 1 {
    LOCAL j IS 0.
    UNTIL j >= n - i - 1 {
      IF arr[j + 1]["t"] < arr[j]["t"] {
        LOCAL tmp IS arr[j].
        SET arr[j] TO arr[j + 1].
        SET arr[j + 1] TO tmp.
      }
      SET j TO j + 1.
    }
    SET i TO i + 1.
  }
  RETURN arr.
}

// Return the next few time-ordered minima over a window.
FUNCTION INT_NEXT_MINIMA {
  PARAMETER orbits IS 3, samples IS 400, limit IS 8.
  LOCAL mins IS INT_FIND_MINIMA(orbits, samples).
  IF mins:LENGTH = 0 { RETURN LIST(). }
  LOCAL sortedT IS INT_SORT_BY_T(mins).
  LOCAL out IS LIST().
  LOCAL maxN IS MIN(limit, sortedT:LENGTH).
  LOCAL k IS 0.
  UNTIL k >= maxN {
    out:ADD(sortedT[k]).
    SET k TO k + 1.
  }
  RETURN out.
}

// Find a near-term pass and lock it by UT so restarts don't blow the CA.
FUNCTION RESUME_LOCK_NEARPASS {
  PARAMETER maxRange IS 2500, maxETA IS 900, orbits IS 2, samples IS 400.

  LOCAL mins IS INT_NEXT_MINIMA(orbits, samples, 8).
  IF mins:LENGTH = 0 { RETURN LEXICON("ok", FALSE). }

  LOCAL nowUT IS TIME:SECONDS.
  LOCAL found IS FALSE.
  LOCAL best IS mins[0].
  LOCAL i IS 0.
  UNTIL i >= mins:LENGTH {
    LOCAL x IS mins[i].
    LOCAL dt IS x["t"] - nowUT.
    IF (x["d"] <= maxRange) AND (dt >= 0) AND (dt <= maxETA) {
      IF NOT found OR x["d"] < best["d"] { SET best TO x. SET found TO TRUE. }
    }
    SET i TO i + 1.
  }

  IF NOT found { RETURN LEXICON("ok", FALSE). }
  RETURN LEXICON("ok", TRUE, "t", best["t"], "d", best["d"], "v", best["v"]).
}

// Lock the earliest upcoming pass with separation ≤ maxRange (ignores ETA limits).
FUNCTION RESUME_LOCK_NEARPASS_CUR {
  PARAMETER maxRange IS 2500, orbits IS 3, samples IS 400, limit IS 8.

  LOCAL mins IS INT_NEXT_MINIMA(orbits, samples, limit).
  IF mins:LENGTH = 0 { RETURN LEXICON("ok", FALSE). }

  LOCAL found IS FALSE.
  LOCAL best IS mins[0].
  LOCAL i IS 0.
  UNTIL i >= mins:LENGTH {
    LOCAL x IS mins[i].
    IF x["d"] <= maxRange {
      IF NOT found OR x["t"] < best["t"] {
        SET best TO x.
        SET found TO TRUE.
      }
    }
    SET i TO i + 1.
  }

  IF NOT found { RETURN LEXICON("ok", FALSE). }
  RETURN LEXICON("ok", TRUE, "t", best["t"], "d", best["d"], "v", best["v"]).
}
