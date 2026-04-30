// ============================================================================
// APOLLO MUN LANDER - CONFIGURATION TEMPLATE
// ============================================================================
// Copy this file and modify parameters for your specific mission
// Save as: landing_config.ks
// Then modify mem.ks to load this config
// ============================================================================

// ============================================================================
// MISSION PROFILE SETTINGS
// ============================================================================

// Starting conditions
GLOBAL PDI_ALTITUDE IS 20000.           // Altitude to begin Powered Descent Initiation (meters)
                                        // Recommended: 20000m for standard Apollo profile
                                        // Apollo equivalent: ~15km scaled to KSP

// Landing target coordinates
GLOBAL TARGET_LATITUDE IS -0.7017.      // Target latitude in degrees
GLOBAL TARGET_LONGITUDE IS 22.7497.     // Target longitude in degrees

// Common landing sites on the Mun:
// *Neil Armstrong Memorial:   0.6936,  22.7608
// Mun Canyon:               -0.5,     50.0
// *East Crater:              -14.6,   79.3  // 14 35 60 S  79 17 59.9 E
// *Farside Crater             1.77,    -56.881 
// Farside Basin:            -2.0,    180.0
// Polar Crater:             85.0,      0.0
// *Lowlands                  -9.604,  10.69222
// Twin Crater              -6.15164938, 138.816
// *NV-FGF                   -12.52916,  0.53416
// *9M8VT7                    20.481388, 0.30833   // 20 28 53 N  0 18 30 E
// ============================================================================
// DESCENT PHASE GATES
// ============================================================================

GLOBAL HIGH_GATE_ALTITUDE IS 150.       // Altitude for transition P63→P64 (meters)
                                        // At this point: pitch-over, target refinement
                                        // Apollo standard: 150m

GLOBAL LOW_GATE_ALTITUDE IS 15.         // Altitude for transition P64→P66 (meters)
                                        // At this point: vertical descent begins
                                        // Apollo standard: 15m

GLOBAL ENGINE_CUTOFF_ALTITUDE IS 2.0.   // Descent engine shutdown altitude (meters)
                                        // ** YOUR REQUESTED VALUE **
                                        // Adjust based on landing gear height
                                        // Lower values (1.5m) = gentler touchdown
                                        // Higher values (3-4m) = safer for rough terrain

// ============================================================================
// VEHICLE SPECIFICATIONS
// ============================================================================

// Stage identification
GLOBAL DESCENT_STAGE_TAG IS "Descent".  // Name tag for descent stage (optional)
GLOBAL ASCENT_STAGE_TAG IS "Ascent".    // Name tag for ascent stage (optional)

// Physical characteristics
GLOBAL LANDING_GEAR_HEIGHT IS 2.5.      // Height from engine bell to ground contact (meters)
                                        // Measure in VAB from engine to gear footpad

// Performance expectations (for information only - script auto-calculates)
// Your vehicle specs:
// Descent Stage: Mass 4552kg, TWR 4.89, Delta-V 1168 m/s
// Ascent Stage:  Mass 2984kg, TWR 4.11, Delta-V 1042 m/s

// ============================================================================
// GUIDANCE & CONTROL PARAMETERS
// ============================================================================

// Radar and sensors
GLOBAL RADAR_ACQUISITION_ALTITUDE IS 10000.  // When landing radar becomes available
                                              // Below this: "LANDING RADAR" callout
                                              // KSP radar typically reliable <10km

// Safety limits
GLOBAL MINIMUM_BRAKING_ALTITUDE IS 2000.     // Minimum safe altitude to start P63
                                              // Prevents low-altitude PDI attempts
                                              
GLOBAL MAX_APPROACH_TILT_ANGLE IS 45.        // Maximum tilt during P64 approach (degrees)
                                              // Limits aggressive maneuvering
                                              // Apollo limit: ~45°

// Control sensitivity
GLOBAL THROTTLE_RESPONSE_RATE IS 0.1.        // Max throttle change per update cycle
                                              // Lower = smoother (0.05)
                                              // Higher = more responsive (0.2)
                                              // Default: 0.1

GLOBAL RCS_TRANSLATION_AUTHORITY IS 1.0.     // RCS translation power (0.0-1.0)
                                              // Affects horizontal corrections
                                              // Usually leave at 1.0

// Velocity thresholds
GLOBAL LOW_GATE_VELOCITY_THRESHOLD IS 0.1.   // Max surface velocity for low gate (m/s)
                                              // Must be nearly stationary
                                              // Too low = may never trigger

// ============================================================================
// ASCENT PROFILE SETTINGS
// ============================================================================

GLOBAL ASCENT_TARGET_ALTITUDE IS 20000.      // Target orbit altitude for P12 (meters)
                                              // Match your CSM orbit
                                              // Standard: 20000m

GLOBAL ASCENT_INITIAL_PITCH IS 45.           // Starting pitch angle for ascent (degrees)
                                              // 90 = straight up (safe)
                                              // 45 = aggressive gravity turn
                                              // Recommend: 45-75°

GLOBAL ASCENT_PITCH_RATE IS 0.5.             // Pitch rate during gravity turn (°/100m)
                                              // Lower = gentler turn (0.3)
                                              // Higher = faster turn (0.7)
                                              // Default: 0.5

// ============================================================================
// DISPLAY & INTERFACE OPTIONS
// ============================================================================

GLOBAL ENABLE_ALTITUDE_CALLOUTS IS TRUE.     // Enable altitude voice callouts
GLOBAL ENABLE_PHASE_CALLOUTS IS TRUE.        // Enable phase transition callouts
GLOBAL ENABLE_RADAR_CALLOUT IS TRUE.         // Enable landing radar acquisition callout

// Callout altitudes (meters) - customize as desired
GLOBAL CALLOUT_100 IS TRUE.                  // "ALTITUDE 100"
GLOBAL CALLOUT_75 IS TRUE.                   // "75"
GLOBAL CALLOUT_50 IS TRUE.                   // "50"
GLOBAL CALLOUT_40 IS TRUE.                   // "40"
GLOBAL CALLOUT_30 IS TRUE.                   // "30"
GLOBAL CALLOUT_20 IS TRUE.                   // "20"
GLOBAL CALLOUT_10 IS TRUE.                   // "10"
GLOBAL CALLOUT_5 IS TRUE.                    // "5"

// ============================================================================
// FUEL MANAGEMENT
// ============================================================================

GLOBAL LOW_FUEL_WARNING_PERCENT IS 15.       // Warn when fuel below this % (0-100)
GLOBAL CRITICAL_FUEL_PERCENT IS 5.           // Critical fuel level for abort

// ============================================================================
// MISSION-SPECIFIC NOTES
// ============================================================================

// Mission: [Your mission name]
// Date: [Mission date]
// Vehicle: [Your vehicle name]
// Crew: [Kerbal names]
// 
// Special considerations:
// - 
// - 
// - 

// ============================================================================
// ADVANCED SETTINGS (USE WITH CAUTION)
// ============================================================================

// P63 Braking Phase
GLOBAL P63_TARGET_VELOCITY_MULTIPLIER IS 0.5.    // Aggressiveness of braking
                                                  // Lower = more conservative (0.3)
                                                  // Higher = faster descent (0.7)
                                                  
GLOBAL P63_THROTTLE_GAIN IS 0.01.                // Throttle response to velocity error
                                                  // Affects braking smoothness

// P64 Approach Phase
GLOBAL P64_DESCENT_RATE_FACTOR IS 20.            // Descent rate = altitude / factor
                                                  // Lower = faster descent (15)
                                                  // Higher = gentler descent (30)
                                                  
GLOBAL P64_TARGET_CORRECTION_FACTOR IS 1.0.      // Horizontal correction strength
                                                  // Higher = more aggressive (1.5)

// P66 Terminal Descent
GLOBAL P66_TARGET_DESCENT_RATE IS -0.5.          // Final descent rate (m/s)
                                                  // More negative = faster (careful!)
                                                  // Less negative = slower (safer)
                                                  
GLOBAL P66_MINIMUM_THROTTLE IS 0.2.              // Minimum throttle in P66 (0.0-1.0)
                                                  // Prevents free-fall if too low

// ============================================================================
// VALIDATION
// ============================================================================

// Automatic parameter validation (don't modify)
IF PDI_ALTITUDE < MINIMUM_BRAKING_ALTITUDE {
    PRINT "WARNING: PDI_ALTITUDE too low!".
    PRINT "Must be above MINIMUM_BRAKING_ALTITUDE.".
}

IF HIGH_GATE_ALTITUDE <= LOW_GATE_ALTITUDE {
    PRINT "ERROR: HIGH_GATE_ALTITUDE must be greater than LOW_GATE_ALTITUDE!".
}

IF ENGINE_CUTOFF_ALTITUDE < 1 {
    PRINT "WARNING: ENGINE_CUTOFF_ALTITUDE very low - risk of hard landing!".
}

IF ENGINE_CUTOFF_ALTITUDE > LOW_GATE_ALTITUDE {
    PRINT "ERROR: ENGINE_CUTOFF_ALTITUDE cannot exceed LOW_GATE_ALTITUDE!".
}

PRINT "Configuration loaded successfully.".
PRINT "Target: " + ROUND(TARGET_LATITUDE, 4) + "° N, " + ROUND(TARGET_LONGITUDE, 4) + "° E".
PRINT "Engine cutoff: " + ENGINE_CUTOFF_ALTITUDE + "m".

// ============================================================================
// END OF CONFIGURATION
// ============================================================================
