# Folding Flappy

A Flappy Bird clone for the foldable iPhone Duo. You flap by closing and
opening the phone. The game is 100% SwiftUI: no SpriteKit, no image assets.
All graphics are vector drawing in a `Canvas`.

## Controls

| Action | Result |
| --- | --- |
| Close or open the Duo | Flap (each fold and each unfold is one flap) |
| Tap the screen | Flap (for the Simulator and phones that do not fold) |

A flap also starts the game, and restarts it after a game over.

## How the fold detection works

SwiftUI has no hinge-angle API. `FoldSensor` looks at the size that SwiftUI
gives the scene:

- When you fold or unfold the Duo, the scene moves between the cover display
  and the inner display (or it is resized), so its **area** changes a lot.
  A change of more than 25 % is a flap.
- A rotation only swaps width and height and keeps the area, so it is ignored.
- If the phone switches the display off when you close it, the scene goes
  inactive. A close and open in less than 2 seconds is also a flap.

The world is always 1000 points tall and as wide as the screen. When you fold
or unfold, the world gets narrower or wider while you play.

## Graphics

- Day and night cycle: morning, day, sunset, night with stars and moon, dawn
- Five parallax layers: far and near mountains, clouds, hills, bushes
- Pipes with gradients, highlights and drop shadows
- A bird with an animated wing, tilt that follows its speed, and X eyes on a crash
- Particles: air puffs, feathers, sparkles and dust
- Screen shake, crash flash, vignette, medals and a best score

## Build

Open `FoldingFlappy.xcodeproj` in Xcode 16 or later. The target is iOS 17.

## Files

| File | Contents |
| --- | --- |
| `GameView.swift` | The SwiftUI view: timeline, canvas, fold and tap input, haptics |
| `FoldSensor.swift` | Converts fold and unfold into flap events |
| `GameWorld.swift` | Physics, pipes, score, particles |
| `GameRenderer.swift` | All drawing |
| `Palette.swift` | Colors for the day and night cycle |
