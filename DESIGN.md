# Downrange

A first-draft tycoon about a launch company. The fantasy is the business, not a specific vehicle. Names in the catalog are original.

## Loop

The player buys a short list of components into a hangar, assigns one part to each slot, and sells the flight to a contract. The left-hand preview is the same integrator as the launch. A predicted failure can still be flown. Purchases need cash. Range fees, pad repair, and payroll can put the company in debt.

Slots, one choice each: core, engine, booster, upper stage, cabin, aero, gimbal, legs, fairing. There is no part tree and no custom part counts.

Starting cash is $4,500,000. The sounding stack (Spar, PS-80, instrument cabin, fixed fins) is $1,560,000. What remains cannot buy the GG-620. The FF-1900 is $26,000,000.

## What the money buys

- Weld cell: 30% off future cores and the kick stage.
- Reuse program: a landing reserve, if the stack also has a gimbal, legs, and grid fins or body flaps. Fixed fins cannot land. Recovery returns the core, engine, aero, gimbal, and legs. The kick stage, fairing, and strap-on boosters are always expended. A crew cabin comes home on a successful suborbital hop.
- Payload office: the house weather satellite.
- Second pad: turnaround drops from 12 days to 4.
- Station shop: requires one orbital success. Unlocks the truss contract.

Payroll is $180,000 every 30 days, first due on day 30. The range fee is $90,000. Pad repair ($250,000) is only for a buckle or a rocket that never lifts. A flown miss above 20 km can sell the data for $200,000.

## Ascent

`scripts/ascent.gd` is a 2D spherical point-mass. Pitch is degrees from the local horizontal. Suborbital flights loft and stay near vertical. Orbital flights fly a slow gravity turn, cut off once apogee is set, coast, and circularize on the kick stage. Escape is not a success.

The structural limit is not a real 30 kPa. Small high-thrust rockets throttle in a max-q bucket that starts at 30% of the core's limit. Solids do not throttle. Do not raise `max_q` to silence a buckle without re-running `sim_check.gd`: the bucket moves with the limit.

A single SRB is mounted on +X and tumbles without a gimbal. Too much thrust for the core buckles on the pad. A PS-80 does not lift a Keel.

## Art

The rocket is an original lathe mesh with a hull shader: warm off-white, graphite skirt, copper band. Storable propellant is clean, kerolox is sooty, methalox frosts. One bell per engine, scaled with thrust. The pad uses Poly Haven PBR textures and a handful of CC0 props. The sky is `kloofendal_43d_clear_puresky`. The sun light is aimed at the brightest pixel of that image so the disk and the shadows agree.

Downrange is -Z, toward the water. The camera starts on the land side. Godot's positive X rotation takes +Y toward +Z, so a pitch of 0 (horizontal, toward the sea) is `rotation.x = deg_to_rad(pitch - 90)`.

## Save

`user://downrange.json`, written after purchases and flights. Reset is a second click on the yard tab. Screenshot mode (`-- --shot`) uses a fresh company and does not touch the save.
