# Folding Flappy

A Flappy Bird clone for the foldable iPhone Duo. You flap by closing and
opening the phone. The game is 100% SwiftUI: no SpriteKit, no image assets.
All graphics are vector drawing in a `Canvas`.

## Controls

| Action | Result |
| --- | --- |
| Close or open the Duo by 8° or more | Flap. The next flap comes when you move the hinge back the other way. |
| Tap the screen | Flap (for phones that do not fold) |

A flap also starts the game, and restarts it after a game over.
While the hinge sends data, the bird's wing follows the hinge angle.

## How the fold detection works

The main input is Apple's hinge API: the SwiftUI modifier `onHingeChange`
(iOS 27.1 SDK). It gives a `DeviceHingeContext`. Its `hinge` property
(`DeviceHinge?`) has an `angle` (0° closed, 180° flat) and a `status`
(`.closed`, `.partiallyOpen`, `.fullyOpen`).

`HingeFlapDetector` turns the angle into flaps. A flap is a fold stroke of
at least 8° in either direction (for example half open to fully open, then
back). A long movement in one direction is one flap. This also stops sensor
noise from making extra flaps.

When the Duo is partially open, the system blurs and darkens the half of
the inner display left of the fold. No public API can switch this off. So on
the inner display, the game is played right of the fold: the bird, the score
and the menus stay in the clear half. The fold position comes from
`GeometryProxy.reservedRegions(kind: .division, options: .includeInactive)`.
The scenery and the pipes that you passed still move through the left half.

Fallback when there is no hinge data (for example iOS 27.0):

- `FoldSensor` looks at the scene size. A fold or unfold moves the scene
  between the cover display and the inner display, so the **area** changes
  a lot. A change of more than 25 % is a flap. A rotation keeps the area,
  so it is ignored.
- If the display goes off when you close the phone, the scene goes
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

Open `FoldingFlappy.xcodeproj` in Xcode 27.1 or later (the hinge API is in the
iOS 27.1 SDK). The app runs on iOS 17 and later; the hinge input works on
iOS 27.1 and later. To test in the iPhone Duo Simulator, change the hinge
angle with Xcode's device controls.

## Files

| File | Contents |
| --- | --- |
| `GameView.swift` | The SwiftUI view: timeline, canvas, fold and tap input, haptics |
| `HingeSensor.swift` | Reads the hinge angle and converts closing strokes into flaps |
| `FoldSensor.swift` | Fallback: converts scene size changes into flaps |
| `GameWorld.swift` | Physics, pipes, score, particles |
| `GameRenderer.swift` | All drawing |
| `Palette.swift` | Colors for the day and night cycle |
