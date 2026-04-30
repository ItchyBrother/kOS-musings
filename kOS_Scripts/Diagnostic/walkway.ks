LOCAL walkwayParts IS SHIP:PARTSNAMED("AM.MLP.GeneralCrewElevatorMiniArmS").
IF walkwayParts:LENGTH > 0 {
    SET walkwayPart TO walkwayParts[0].
    
    // The retract module has showToggle = True, so it should have more events
    // Try looking for ANY event that contains "Crew Arm"
    LOCAL foundEvent IS FALSE.
    
    FOR moduleName IN walkwayPart:ALLMODULES {
        IF moduleName = "ModuleAnimateGenericExtra" {
            LOCAL mymod IS walkwayPart:GETMODULE(moduleName).
            
            // Check all events for anything with "Crew Arm"
            FOR evt IN mymod:ALLEVENTNAMES {
                PRINT "Checking event: " + evt AT (0, 10).
                IF evt:CONTAINS("Crew") OR evt:CONTAINS("Retract") OR evt:CONTAINS("Extend") {
                    PRINT "Found event: " + evt AT (0, 11).
                    mymod:DOEVENT(evt).
                    SET foundEvent TO TRUE.
                    BREAK.
                }
            }
            
            IF foundEvent { BREAK. }
        }
    }
    
    IF NOT foundEvent {
        PRINT "No suitable event found" AT (0, 12).
    }
}

TERMINAL:INPUT:GETCHAR().