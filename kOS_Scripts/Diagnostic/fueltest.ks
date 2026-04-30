LOCAL fuel_pct IS GET_FUEL_PERCENT().

// ---------------------------------------------------------------
//  GET_FUEL_PERCENT – kOS 1.5 – 100% MATCHES DEBUG
// ---------------------------------------------------------------

FUNCTION GET_FUEL_PERCENT {
    LOCAL enabled_amt IS 0.
    LOCAL enabled_cap IS 0.

    // Use SAME variable name and logic as debug
    LIST PARTS IN all_parts.
    FOR p IN all_parts {
        FOR r IN p:RESOURCES {
            IF (r:NAME = "LiquidFuel" OR r:NAME = "Oxidizer") AND r:ENABLED {
                SET enabled_amt TO enabled_amt + r:AMOUNT.
                SET enabled_cap TO enabled_cap + r:CAPACITY.
            }
        }
    }

    IF enabled_cap = 0 {
        RETURN 0.
    }

    RETURN ROUND((enabled_amt / enabled_cap) * 100, 1).
}

GET_FUEL_PERCENT().
PRINT "FUEL PERCENTAGE IS: " + fuel_pct + "%".