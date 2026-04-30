@LAZYGLOBAL OFF.

// =====================================================
// MUN RETURN LANDING PREDICTOR
// =====================================================
// Uses the 4-step rotation method to predict Kerbin landing site
// Based on Pe position and Kerbin rotation during descent
// =====================================================

CLEARSCREEN.

// =====================================================
// CONFIGURATION
// =====================================================

GLOBAL TARGET_PE_ALT IS 25000.  // Target Pe altitude in meters (25 km)

// =====================================================
// UTILITY FUNCTIONS
// =====================================================

FUNCTION normalize_angle {
    PARAMETER angle.
    SET angle TO MOD(angle, 360).
    IF angle < 0 { SET angle TO angle + 360. }
    RETURN angle.
}

FUNCTION angle_to_west_longitude {
    PARAMETER angle.
    // Convert 0-360 angle to -180 to +180 longitude
    IF angle > 180 {
        RETURN angle - 360.
    }
    RETURN angle.
}

// =====================================================
// LANDING PREDICTION FUNCTIONS
// =====================================================

// Step 1-2: Get Pe location and time
FUNCTION get_pe_info_for_kerbin_return {
    PARAMETER target_pe_alt.
    
    // Calculate what our orbit will look like after return burn
    // This is approximate - assumes Hohmann-ish transfer
    LOCAL current_r IS MUN:ORBIT:SEMIMAJORAXIS.
    LOCAL target_r IS KERBIN:RADIUS + target_pe_alt.
    
    // Transfer time (approximate)
    LOCAL a_transfer IS (current_r + target_r) / 2.
    LOCAL transfer_time IS CONSTANT:PI * SQRT(a_transfer^3 / KERBIN:MU).
    
    // After transfer, we'll be at Pe in Kerbin orbit
    // Approximate time to Pe after entering Kerbin SOI
    LOCAL time_to_soi IS transfer_time * 0.95.  // Most of transfer is to SOI
    LOCAL time_in_soi_to_pe IS 1800.  // ~30 minutes from SOI to Pe (approximate)
    
    LOCAL total_time_to_pe IS time_to_soi + time_in_soi_to_pe.
    
    // Where will the Pe be?
    LOCAL future_time IS TIME:SECONDS + total_time_to_pe.
    
    // Calculate Kerbin's rotation angle at that time
    LOCAL kerbin_rotation_angle IS MOD(future_time / KERBIN:ROTATIONPERIOD * 360, 360).
    
    // Get current angle to Kerbin from Mun
    LOCAL to_kerbin IS KERBIN:POSITION - SHIP:POSITION.
    LOCAL to_kerbin_angle IS ARCTAN2(to_kerbin:X, to_kerbin:Z).
    
    // Pe will be roughly where Kerbin is when we arrive
    LOCAL pe_absolute_angle IS normalize_angle(to_kerbin_angle + kerbin_rotation_angle).
    
    RETURN LEXICON(
        "pe_altitude", target_pe_alt,
        "time_to_pe_seconds", total_time_to_pe,
        "time_to_pe_hours", FLOOR(total_time_to_pe / 3600),
        "time_to_pe_minutes", FLOOR(MOD(total_time_to_pe, 3600) / 60),
        "pe_longitude", pe_absolute_angle,
        "transfer_time", transfer_time
    ).
}

// Better approach: If already in Kerbin SOI, use actual Pe data
FUNCTION get_current_pe_info {
    IF SHIP:BODY <> KERBIN {
        PRINT "ERROR: Not in Kerbin SOI yet!".
        RETURN LEXICON("valid", FALSE).
    }
    
    // Step 1: Get Pe location
    LOCAL pe_eta IS ETA:PERIAPSIS.
    LOCAL pe_time IS TIME:SECONDS + pe_eta.
    
    // Get position at Pe
    LOCAL ship_pos IS POSITIONAT(SHIP, pe_time).
    LOCAL kerbin_pos IS POSITIONAT(KERBIN, pe_time).
    LOCAL pe_rel IS ship_pos - kerbin_pos.
    
    // Get geographic position of Pe
    LOCAL geo IS KERBIN:GEOPOSITIONOF(pe_rel).
    
    // Step 2: Time to Pe (hours and minutes only - no days!)
    LOCAL pe_seconds IS MOD(pe_eta, 21600).  // Remove full Kerbin days (6 hours each)
    LOCAL pe_hours IS FLOOR(pe_seconds / 3600).
    LOCAL pe_minutes IS FLOOR(MOD(pe_seconds, 3600) / 60).
    
    RETURN LEXICON(
        "valid", TRUE,
        "pe_latitude", geo:LAT,
        "pe_longitude", geo:LNG,
        "pe_altitude", SHIP:PERIAPSIS,
        "time_to_pe_seconds", pe_seconds,
        "time_to_pe_hours", pe_hours,
        "time_to_pe_minutes", pe_minutes,
        "time_to_pe_total", pe_eta
    ).
}

// Step 3-4: Calculate landing site from Pe info
FUNCTION calculate_landing_site {
    PARAMETER pe_info.
    
    // Step 3: Calculate Kerbin rotation during descent
    // Kerbin rotates 60° per hour and 1° per minute
    LOCAL rotation_degrees IS (pe_info["time_to_pe_hours"] * 60) + 
                              (pe_info["time_to_pe_minutes"] * 1).
    
    // Step 4: Landing site is WEST of Pe by rotation amount
    // BUT atmospheric descent adds ~31° EAST correction
    // (Time from Pe at 25km to surface = ~31 minutes)
    LOCAL atmospheric_correction IS 31.
    LOCAL landing_longitude IS pe_info["pe_longitude"] - rotation_degrees + atmospheric_correction.
    
    // Normalize to -180 to +180 range
    UNTIL landing_longitude >= -180 { SET landing_longitude TO landing_longitude + 360. }
    UNTIL landing_longitude <= 180 { SET landing_longitude TO landing_longitude - 360. }
    
    RETURN LEXICON(
        "landing_latitude", pe_info["pe_latitude"],
        "landing_longitude", landing_longitude,
        "rotation_degrees", rotation_degrees,
        "pe_longitude", pe_info["pe_longitude"],
        "atmospheric_correction", atmospheric_correction
    ).
}

// =====================================================
// ORBIT DELAY ANALYSIS
// =====================================================

FUNCTION show_orbit_delay_options {
    PARAMETER mun_orbit_period.
    
    PRINT " ".
    PRINT "═════════════════════════════════════════".
    PRINT "ORBIT DELAY OPTIONS".
    PRINT "═════════════════════════════════════════".
    PRINT " ".
    PRINT "Each Mun orbit delay shifts landing westward.".
    PRINT "Current Mun orbit period: " + ROUND(mun_orbit_period/60, 1) + " minutes".
    PRINT " ".
    
    // Calculate how much each orbit shifts the landing
    // During one Mun orbit, Kerbin rotates:
    LOCAL kerbin_rotation_per_mun_orbit IS (mun_orbit_period / KERBIN:ROTATIONPERIOD) * 360.
    
    PRINT "Kerbin rotation per Mun orbit: " + ROUND(kerbin_rotation_per_mun_orbit, 1) + "°".
    PRINT " ".
    PRINT "Delay    Landing Shift".
    PRINT "─────    ─────────────".
    PRINT "0 orbits      0° (immediate return)".
    
    FROM {LOCAL i IS 1.} UNTIL i > 5 STEP {SET i TO i + 1.} DO {
        LOCAL shift IS i * kerbin_rotation_per_mun_orbit.
        LOCAL time_delay IS i * mun_orbit_period.
        LOCAL orbit_text IS " orbit".
        IF i > 1 { SET orbit_text TO " orbits". }
        PRINT i + orbit_text + 
            "   ~" + ROUND(shift, 0) + "° west (+" + 
            ROUND(time_delay/60, 0) + " min)".
    }
    
    PRINT " ".
}

// =====================================================
// MAIN PROGRAM
// =====================================================

FUNCTION main {
    CLEARSCREEN.
    
    PRINT "╔════════════════════════════════════════════════╗".
    PRINT "║  MUN RETURN LANDING PREDICTOR                  ║".
    PRINT "║  Test Version - Rotation Method                ║".
    PRINT "╚════════════════════════════════════════════════╝".
    PRINT " ".
    
    // Check if we're in the right place
    IF SHIP:BODY <> KERBIN AND SHIP:BODY <> MUN {
        PRINT "ERROR: Must be in Mun or Kerbin SOI!".
        RETURN.
    }
    
    // Get current orbit info
    IF SHIP:BODY = MUN {
        PRINT "Current Status: In Mun SOI".
        PRINT "  Altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
        PRINT "  Orbit Period: " + ROUND(SHIP:ORBIT:PERIOD/60, 1) + " minutes".
        PRINT "  Pe: " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
        PRINT "  Ap: " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
        PRINT " ".
        
        // Show orbit delay information
        show_orbit_delay_options(SHIP:ORBIT:PERIOD).
        
        PRINT "═════════════════════════════════════════".
        PRINT " ".
        PRINT "To use this predictor:".
        PRINT "1. Execute return burn to Kerbin".
        PRINT "2. Enter Kerbin SOI with Pe at ~25-35 km".
        PRINT "3. Run this script again in Kerbin SOI".
        PRINT " ".
        PRINT "The script will then predict your landing site.".
        
    } ELSE IF SHIP:BODY = KERBIN {
        PRINT "Current Status: In Kerbin SOI".
        PRINT "  Altitude: " + ROUND(SHIP:ALTITUDE/1000, 1) + " km".
        PRINT "  Pe: " + ROUND(SHIP:PERIAPSIS/1000, 1) + " km".
        PRINT "  Ap: " + ROUND(SHIP:APOAPSIS/1000, 1) + " km".
        PRINT " ".
        
        // Get actual Pe information
        LOCAL pe_info IS get_current_pe_info().
        
        IF NOT pe_info["valid"] {
            PRINT "Cannot calculate - invalid Pe data.".
            RETURN.
        }
        
        PRINT "═════════════════════════════════════════".
        PRINT "PE INFORMATION".
        PRINT "═════════════════════════════════════════".
        PRINT " ".
        PRINT "Step 1: Pe Location".
        PRINT "  Latitude:  " + ROUND(pe_info["pe_latitude"], 2) + "°".
        PRINT "  Longitude: " + ROUND(pe_info["pe_longitude"], 2) + "°".
        PRINT "  Altitude:  " + ROUND(pe_info["pe_altitude"]/1000, 1) + " km".
        PRINT " ".
        
        PRINT "Step 2: Time to Pe (no days)".
        PRINT "  Hours:   " + pe_info["time_to_pe_hours"].
        PRINT "  Minutes: " + pe_info["time_to_pe_minutes"].
        PRINT "  (Total: " + ROUND(pe_info["time_to_pe_seconds"]/60, 1) + " minutes)".
        PRINT " ".
        
        // Calculate landing site
        LOCAL landing IS calculate_landing_site(pe_info).
        
        PRINT "Step 3: Kerbin Rotation Calculation".
        PRINT "  Formula: (hours × 60°) + (minutes × 1°)".
        PRINT "  = (" + pe_info["time_to_pe_hours"] + " × 60°) + (" + 
              pe_info["time_to_pe_minutes"] + " × 1°)".
        PRINT "  = " + ROUND(landing["rotation_degrees"], 1) + "°".
        PRINT " ".
        
        PRINT "Step 4: Landing Site Prediction".
        PRINT "  Pe Longitude:  " + ROUND(landing["pe_longitude"], 2) + "°".
        PRINT "  - Rotation:    " + ROUND(landing["rotation_degrees"], 1) + "°".
        PRINT "  + Atmospheric: " + ROUND(landing["atmospheric_correction"], 1) + "°".
        PRINT "  ─────────────────────────────".
        PRINT "  Landing Long:  " + ROUND(landing["landing_longitude"], 2) + "°".
        PRINT "  Landing Lat:   " + ROUND(landing["landing_latitude"], 2) + "°".
        PRINT " ".
        
        PRINT "═════════════════════════════════════════".
        PRINT "PREDICTED LANDING SITE".
        PRINT "═════════════════════════════════════════".
        PRINT " ".
        PRINT "  Coordinates: " + ROUND(landing["landing_latitude"], 2) + "°, " +
              ROUND(landing["landing_longitude"], 2) + "°".
        PRINT " ".
        PRINT "NOTES:".
        PRINT "  - Calculation assumes Pe at " + ROUND(TARGET_PE_ALT/1000, 0) + " km".
        PRINT "  - Actual Pe: " + ROUND(pe_info["pe_altitude"]/1000, 1) + " km".
        PRINT "  - Atmospheric correction: +" + ROUND(landing["atmospheric_correction"], 0) + "° (descent time)".
        PRINT "  - Correction calibrated for Pe ~25-30 km".
        PRINT "  - Higher Pe (35+ km) may need +2-4° additional correction".
        PRINT "  - Expected accuracy: ±5° longitude, ±1° latitude".
        PRINT " ".
        PRINT " ".
        PRINT "══════════════════════════════════════════".
        PRINT " ".
        PRINT "Record this prediction, then compare to where".
        PRINT "you actually land to validate the calculation!".
        PRINT " ".
    }
}

main().
