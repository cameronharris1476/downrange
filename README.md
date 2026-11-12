# Downrange

A launch-industry tycoon. You start with one cheap rocket at Cape Halcyon and spend the profit on the yard: welding, reuse, a second pad, your own satellites, and a station shop.

The vehicles are fictional. The business is the familiar one: fly something that pays, then stop throwing the expensive parts away.

## Play

Open the project in Godot 4.7 (Forward+) and press Play.

1. Buy the sounding stack. The shop has one button for Spar, the PS-80, an instrument cabin, and fixed fins. That is the only engine the company can afford.
2. The university contract is already selected. The left panel runs the same ascent the launch will fly.
3. Commit the launch. You do not pilot it. The cabin does.
4. Hardware is expended. Repeat the sounding flights until a Keel and a GG-620 are on the table.
5. Orbital contracts need a kick stage and a fairing. A crew cabin can fly without a fairing.
6. The yard is where the company changes. A weld cell discounts cores. Reuse brings a booster home if it has a gimbal, legs, and grid fins or flaps. A second pad cuts turnaround. The station shop waits until you have put something in orbit.

Right-drag orbits the pad. The wheel zooms. The banner is the flight prediction: a red one can still be launched, and you will pay for it.

A full-flow methalox engine (FF-1900) and the heavy Mast core are late purchases. They are what the station truss is for.

## Check the flight model

```
Godot_v4.7.2-stable_win64_console.exe --headless --path . -s res://scripts/sim_check.gd
```

The check asserts the progression, not exact altitudes: the sounding rocket clears 180 km and misses 500 km, a single booster buckles a Spar, LEO needs the kick stage, and the truss needs the Mast with the full-flow engine.

## License

Code in this repository is MIT. See `LICENSE`.

Textures, the sky, and the pad props are Poly Haven CC0. The fonts are OFL. None of those assets are MIT. See `ASSETS.md`.
