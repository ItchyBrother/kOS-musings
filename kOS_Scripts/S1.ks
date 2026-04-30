// Ultimate Mun-return pinpoint predictor – only works when it’s allowed to
clearscreen.
print "Ultimate Mun → Kerbin pinpoint predictor".

if ship:body:name <> "Kerbin" {
  print " ".
  print "ERROR: You are still in Mun (or Sun) SOI!".
  print "Wait until you cross into Kerbin SOI, THEN run this script.".
  print "Until then the prediction is garbage.".
  wait until false.
}

set t_pe to time:seconds + eta:periapsis.
set vec_at_pe to positionat(ship, t_pe) - ship:position.  // relative vector

set landing_geo to kerbin:geopositionof(vec_at_pe).

set pred_lng to landing_geo:lng - (eta:periapsis / 60).  // the one true rule
set pred_lat to landing_geo:lat.
set pred_lng to mod(pred_lng + 540, 360) - 180.

print " ".
print "ETA:Periapsis : " + round(eta:periapsis/60,1) + " min".
print "Predicted landing site:".
print "   Lat : " + round(pred_lat,4).
print "   Lng : " + round(pred_lng,4).
print " ".

print "Your four perfect targets:".
print "  KSC Atlantic     0°    –73°".
print "  Nye Island       5.7°  108.7°".
print "  Sandy Island    –8.2°  –42.5°".
print "  Hazard Shallows –14°   155.3°".
print " ".
print "Wait extra ~45-min Mun orbits until predicted Lng ≈ target Lng".

wait until false.