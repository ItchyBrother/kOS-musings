//First launch script
clearScreen.

Print "Counting down:".
From {local countdown is 5.} until countdown = 0 step {set countdown to countdown -1.} Do {
    Print "..." + countdown.
    wait 1.
}
Stage.
Wait 2.
//Stage.
Print "Ignition!".
lock steering to up.
lock throttle to 1.
local Mode is 0.
When maxthrust = 0 then {
    Print "Stage activated.".
    set Mode to Mode +1.
    Print "Mode:" + Mode.
    if Mode = 1 {
        wait until ship:altitude > 70000.
    }
    //Stage.
    Preserve.
}

if Mode > 3 and ship:altitude < 1000.{
    //Stage.
    //lock throttle to 0.
}