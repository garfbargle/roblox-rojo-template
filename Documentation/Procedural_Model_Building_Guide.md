# Procedural Model Building Guide

_A practical spec for an AI agent (or human) building procedural models, rigs, and
structures in Roblox/Luau — the companion to `IKControls_Implementation_Guide.md`._

That guide covers how to make a rig **move** (IK, gaits, swings, look). This guide
covers everything **before** the motion:

- the engine primitives that silently lie about their shape
- coplanar-face z-fighting and how to find it by arithmetic, not by eye
- assembling multi-part structures in local coordinates without a live preview
- rig topology (so IK and procedural motion have something to drive)
- the offline render discipline that catches all of the above

## Why this document exists

Procedural building has **no live preview while you edit**. You write coordinates,
sizes, and rotation signs blind, and the same handful of mistakes recur on every
model: a cylinder comes out sideways, a trim flickers against the shell it sits on,
a roof flies off because a rotation sign was backwards, a "ball" shrinks to a dot, a
finished model lies down when the game places it because its PrimaryPart carried a
rotation, a character's pose does nothing because the rig has no joints to drive.

None of these are hard once you know them, and none are discoverable by reading the
code back — the code looks correct. They are only visible in-engine, or in a render.
This document is the checklist of what to get right the first time, and the render
loop that catches what you got wrong.

> **The single most important habit:** render every model you build or change and
> *look at it* before declaring it done. Everything below makes that render
> trustworthy and tells you how to read it.

---

# Part A: Engine Primitives That Lie

Roblox's basic part shapes do not behave the way their `Size` suggests. Two of them
will silently produce geometry you did not intend, and a parts-only renderer that
fakes them will *hide* the bug — your preview looks great and the game looks broken.
Build to the real rules.

## 1. `Cylinder` extrudes along its local X axis

A `Part` with `Shape = Cylinder` is a tube whose **length is `Size.X`** and whose
**circular cross-section lies in Y–Z**. An un-rotated cylinder is therefore a
**sideways slab**, not a flat disc lying on the ground.

- To lay a disc **flat** (axis vertical, like a coin on a table):
  `CFrame.Angles(0, 0, math.rad(90))` and `Size = (thickness, diameterY, diameterZ)`.
- The circular face is only ever as round as the smaller of the two cross-section
  axes; a non-square Y–Z makes an **elliptical** tube, which is occasionally what
  you want and usually not.

If a wheel, coin, ring, plate, or pole renders as a flat box pointing the wrong way,
this is why. Reason about which way the **local X** points after your rotation.

## 2. `Ball` is a sphere of the *smallest* Size axis

A `Part` with `Shape = Ball` renders as a sphere whose **diameter is the smallest of
the three `Size` axes**. A non-uniform `Size` does **not** make an ellipsoid — the
extra length on the larger axes is simply ignored, and an elongated "ball" collapses
to a dot the size of its thinnest dimension.

- Want a uniform sphere → set all three Size axes equal; only that value matters.
- Want an elongated rounded detail (an egg, a finger, a tail segment) → use a
  `Cylinder` (rounded tube) or a `Block`, **not** a stretched Ball.
- This is also why **head-covering shells, helmets, and masks should be Blocks**,
  not Balls, in a blocky art style — a Ball reads as a smooth perfect sphere of its
  smallest axis and looks out of place against boxy geometry.

## 3. The renderer must obey these too

If you preview models with a parts-only offline renderer (see Part F), it **must**
sample `Cylinder` along local X and treat `Ball` as a min-axis sphere — otherwise it
fakes the shapes, your preview looks correct, and the in-game geometry is wrong. This
is a real failure mode: "renders look amazing, in-game looks crazy" was a renderer
faking these two shapes and hiding builder bugs, not a lighting problem.

**Audit rule:** when you adopt these fixes, every existing `Cylinder` in the codebase
is suspect — un-rotated ones were probably authored as sideways slabs by accident.
Sweep them per-model.

## 4. A rotated `PrimaryPart` tips the whole model over on placement

A `Model`'s pivot is its `PrimaryPart`'s CFrame — **rotation included**
(`GetPivot() = PrimaryPart.CFrame * PrimaryPart.PivotOffset`, and `PivotOffset`
defaults to identity). Every placement done with `model:PivotTo(uprightTarget)`
aligns that pivot to the target, so whatever rotation is baked into the
PrimaryPart's CFrame gets **un-rotated out of the entire model**.

The killer combination is section 1: standing a cylinder up (trunk, post, basin,
mound, fountain wall) bakes a 90° axis-fix rotation into its CFrame. Make that
part the PrimaryPart — the natural choice, it's the base of the model — and every
`PivotTo`-based placement lays the model **on its side**. A merely *tilted*
primary is the same bug at smaller scale: a 13°-leaning easel leg as PrimaryPart
leans the whole easel 13° in its display bay.

**Real shipped bug:** half a model library displayed sideways in its warehouse.
The symptom pattern was the diagnosis: every sideways model had a cylinder
PrimaryPart (palm trunk, signpost post, pond basin, meadow mound); every upright
model had a box. And because the offline renderer draws raw part CFrames and
never consults the pivot (Part F), **every snapshot looked perfect** while the
warehouse was wrong.

**The fix — normalize the pivot once, in the shared finalize path:**

```lua
model.PrimaryPart = primary
-- pivot becomes the build-space origin with identity rotation:
-- upright, at the ground point under the model, facing -Z
primary.PivotOffset = primary.CFrame:Inverse()
```

Since `CFrame * CFrame:Inverse() == identity`, the model's pivot is now exactly
the build convention (origin on the ground plane, un-rotated) regardless of which
part is primary or how that part is rotated. Put this in the shared
`finalize` / `EnsurePrimaryPart` code, not in individual builders — per-model
fixes miss the next model. The offset travels with clones, so downstream
`PivotTo` placement is correct everywhere, not just in one display system.

**Symptom → cause:** "renders fine offline, sideways (or subtly tilted) when
placed in-game" ⇒ check the PrimaryPart's rotation before suspecting anything
else.

---

# Part B: Z-Fighting — The Coplanar-Face Rule

Z-fighting is two coplanar faces at the same depth flickering against each other as
the camera moves. In procedural builds it has **one dominant cause and a purely
arithmetic test** — you can find it without ever running the game.

## 5. The cause

Two parts under the **same anchor/parent** whose face planes **coincide on one axis**
while they **overlap on the other two**. It is *visible* when the two faces differ in
**Color or Material** (a trim, seam, or `Neon` accent sitting flush against the shell
it decorates). Two same-colored coincident faces don't visibly fight, but they're
still wrong — fix them anyway.

A part of `Size (sx, sy, sz)` centered at local offset `(ox, oy, oz)` has its faces at:

```
x faces: ox ± sx/2
y faces: oy ± sy/2
z faces: oz ± sz/2
```

## 6. The detection test

Two parts **A** and **B** z-fight when, **on exactly one axis**,

```
offA ± sizeA/2  ==  offB ± sizeB/2      (same ± sign = same outward-facing side)
```

**and** their projections **overlap on the other two axes**.

- Same sign matters: `+x` face of A coinciding with the `+x` face of B is a fight;
  A's `+x` meeting B's `−x` (i.e. they share a contact plane back-to-back) is normal
  adjacency, not a fight.
- Cross-axis "near" values are **not** coincidences. `A.x face == B.z face` is
  meaningless — they're different planes.
- `CFrame.Angles` **about the face-normal axis** preserves the plane (a disc spun in
  its own plane still coincides). Rotations about a *different* axis tilt the face off
  the plane — those parts are off-plane and can be skipped (blades, bow limbs, faceted
  gems, angled roof slabs).

## 7. The fix

Nudge the **decorative** part's offset **proud** of the shell by ~`0.02`–`0.04` studs
along the contested axis, so its outward face sits just outside the shell's face
instead of exactly on it. The classic bug: a trim *meant* to sit proud of a shell,
but equal thickness cancels the offset so the front (`−Z`) or top (`+Y`) faces land
flush.

A recurring concrete instance worth memorizing: a handle **wrap** sized
`z = shell_thickness − 0.04` placed at `z = +0.02` puts its front face at exactly
`shell_thickness/2` — flush with the shell's front. Bump the wrap's Z size `+0.04` so
the front sits proud `0.02` and the back stays inset.

**Audit workflow:** for each anchor, enumerate sibling part pairs that differ in
color/material, run the test on all three axes, and list the coincident ones. This
parallelizes cleanly — one pass per builder file.

---

# Part C: Assembling Structures in Local Coordinates

Big hand-placed builds (a lodge, a shop, a landmark) are anchored parts in **local
coordinates** parented to one named `Model`. There is no live preview, so the same
mistakes recur. Check every one of these before calling a structure done — they look
fine in code and break in-game.

## 8. A local-offset placement helper

Copy this pattern. It places a part by **local offset** from the structure center,
treats `oy` as an **absolute world Y** when you need a real floor height, and lets an
explicit `opts.CFrame` **override** the computed transform for rotated/cylinder parts:

```lua
local function box(name, sx, sy, sz, ox, oy, oz, color, material, opts)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Size = Vector3.new(sx, sy, sz)
    p.Color = color
    p.Material = material
    p.CFrame = (opts and opts.CFrame) or (centerCFrame * CFrame.new(ox, oy, oz))
    p.CanCollide = (opts and opts.CanCollide) ~= false
    p.Parent = model
    return p
end
```

The point is one consistent frame of reference for the whole build so you can reason
about positions, plus a clean escape hatch (`opts.CFrame`) for the parts that need a
bespoke rotation.

## 9. Orientation / rotation sign — reason, don't eyeball

`CFrame.Angles` follows the right-hand rule and the sign is easy to get backwards
(this inverted *every* roof on a first pass). Don't guess — decide **which edge must
end up lower**, then pick the sign:

- **Tilting a slab about Z:** a *positive* angle lifts the `+X` edge **up**; a
  *negative* angle drops it. A gable's east (`+X`) slab needs its outer edge **down**,
  so `Angles(0, 0, −pitch)`; the west (`−X`) slab uses `+pitch`. Generalize as
  `−sx * pitch` where `sx` is the side sign.
- **Tilting about X:** a *positive* angle drops the `+Z` edge **down**. An awning
  sloping toward `+Z` uses `+angle`.

When a roof, awning, or ramp looks inverted or flies off, the sign is wrong. Flip it.

## 10. Connectivity — stairs and floors you can actually use

- A stair is only usable if you can **walk off the top**. The top step must land
  **flush on a real floor panel** — never over a void (you fall through), never
  *under* a panel (you bonk your head; there must be an **opening above** the
  landing). Cleanest trick: route the stair up through an intentional **atrium void**
  so nothing is overhead, and land it at the **edge** of the floor band.
- Build multi-room floors as **non-overlapping panels with deliberate gaps**
  (stairwell holes, atrium voids). Two coplanar panels that **overlap** z-fight; two
  that leave a **seam** are fine. Don't floor a space you can't enter — give it a
  door/stair or don't cap it.

## 11. Sealing rooms — a gap is a free entrance

- A "wall" with a gap is a door you didn't mean to make. When gating with a teleport
  ward (a collidable veil + prompt), the veil only blocks **its own opening** — you
  must still wall **above the door** up to the ceiling and **close the corners** where
  two walls nearly meet. A 2–3 stud corner gap is walk-through.
- Verify there is **exactly one** intended way into a gated room.

## 12. Terrain carving breaches and the ground-height trap

- `carveCavern` / `carveTunnel`-style terrain cuts can **breach the hillside**: a cave
  whose ceiling rises above the (often lower-than-you-think) surface pokes a visible
  hole. Keep caverns **under a building footprint or deep under high ground**, give
  the ceiling a rock cap, and keep the only opening the intended shaft.
- For cave water, use **real terrain water**
  (`workspace.Terrain:FillCylinder(cf, h, r, Enum.Material.Water)`) — it reflects,
  renders, and is swimmable — not a translucent glass slab.
- **Ground height is not where you think.** A "surface Y" raycast typically hits
  **terrain only** and ignores anchored deck/floor parts. Props placed by it sit on
  the *terrain*, roughly level with a thin deck on top. Keep room floors at terrain
  height and don't assume the visible floor is the surface. When something floats or
  sinks, re-derive the floor Y from the terrain, not from your deck part.

## 13. Collision policy

Players forgive a lot but they notice walking **through a roof**. Make roof slabs,
awnings, and walls **collidable**; keep tiny trim (ridge beams, rails, gable caps,
decorative seams) **non-collidable** so players don't snag on them. Default decorative
parts to `CanCollide = false` and opt the structural ones back in.

## 14. Sittable furniture — the seat faces −Z

A visible cushion is not a seat. Add a real `Instance.new("Seat")` at cushion-top
height; the engine auto-seats whoever steps on it. The occupant **faces the seat's
`LookVector` (its −Z axis)** — a default-oriented seat faces −Z, so builders
constantly seat people backward or sideways. Orient unambiguously:

```lua
seat.CFrame = CFrame.lookAt(pos, pos + faceDir)   -- sitter ends up looking toward faceDir
```

Prompts still fire while seated, so a bench inside an interaction's activation radius
lets players use that interaction sitting down.

## 15. Reuse the real model, not a look-alike

For static display of something that exists as a gameplay model (a held weapon, a
prop), **build the actual in-game model** and freeze it, rather than re-modeling a
look-alike that will drift out of sync:

```lua
local m = WeaponBuilder.Build("FishingPole", accent, fancy)   -- the real held pole
for _, d in m:GetDescendants() do
    if d:IsA("BasePart") then d.Anchored = true; d.CanCollide = false end
end
m:PivotTo(displayCFrame)
```

---

# Part D: Rig Topology — Give Motion Something to Drive

Before any procedural animation (Part E, and the whole IKControls guide) can work, the
rig has to be built so the joints exist and the skeleton actually hangs off the joints
you intend to animate. Two failures here make perfectly-correct animation code a
silent no-op.

## 16. Motor6D rigs vs constraint rigs — know which you have

- **Classic / custom rigs** join parts with `Motor6D`. You pose them by writing
  `Motor6D.Transform` (or `.C0`). This is what you get when you build a rig by hand.
- **Modern avatar rigs** (e.g. `CreateHumanoidModelFromDescription`, current R15
  characters) join limbs with `AnimationConstraint` / `BallSocketConstraint`, **not
  Motor6D**. Writing `Motor6D.Transform` to such a rig **does nothing and logs no
  error** — the joints aren't there.

**Quick check:** count the `Motor6D`s on the character. Zero ⇒ it's a constraint rig.

**Consequence:** `IKControl` rotates **whatever joints the chain actually has**, so it
works on both classic and modern rigs — it is the reliable poser when you don't
control how the rig was built. Reach for `Motor6D.Transform`/`.C0` only on rigs you
built yourself and know have Motor6Ds.

## 17. The skeleton must hang off the joint you animate

A procedural body-bob / lean / breathe is applied as a `Motor6D.C0` offset on a hub
joint **between** the kinematic root and the rest of the skeleton. For it to do
anything, the body, limb roots, neck, and tail must all parent **through** that hub —
not be welded directly to the root as siblings of it.

```text
Root (kinematic)
  Weld → HipAnchor
    Motor6D (bob/lean C0 each frame) → BobHub      ← the hub the skeleton hangs off
      ├─ Body / saddle
      ├─ Motor6D → UpperLeg     (IKControl owns the leg-joint Transform below here)
      ├─ Motor6D → Neck / Head
      └─ Motor6D → Tail
```

**Real shipped bug:** the bob `Motor6D` existed and its `C0` was animated every frame
— but its child part had **nothing parented below it**. Everything was welded straight
to the root, so the bob moved an invisible orphan and the creature never bounced.
Everything *looked* wired up.

**Diagnostic:** if a sibling secondary motion using the *same* `C0` mechanism works
(the tail wags) but the bob doesn't, the motors are fine — the bobbed part just isn't
carrying the skeleton.

## 18. IK and C0 don't fight when they target different joints

Leg IK writes the **leg-joint** `Transform`; the bob/lean writes the **hip-hub** `C0`;
the tail sway writes the **tail-joint** `C0`. Because they target different joints they
compose cleanly and never conflict. This layering — IK for ground contact and aim, C0
for secondary motion — is the whole trick to combining the two systems.

## 19. Build a real bend into the rest pose, or the limb can't stride

A leg built as a straight line from hip to foot (`mid = hip:Lerp(foot, 0.5)`) makes the
two bone segments sum to *exactly* the hip→foot drop. The limb stands fully extended,
so the IK solver has **zero slack**: any foot target placed forward or back is farther
from the hip than the leg can reach, and the foot just lifts/lags near straight-down —
the creature **shuffles in place** no matter how you tune step distance.

Build the bend in so the bones sum **longer** than the drop:

```lua
-- straight (no reach): |upper| + |lower| == drop, zero stride room
-- bent  (has reach):   push the knee off the straight line; bones now sum > drop
local mid = root.CFrame:PointToWorldSpace(Vector3.new(x, midY, kneeBendZ))
```

Horizontal ground reach is then `sqrt(legLen² − drop²)`; pick the bend so that
comfortably exceeds your stride amplitude, and keep the leg under ~95% extension at
the stride extremes or the knee locks and the foot looks stiff. (A *backward* knee
offset also gives avian/reverse-knee legs — see the IKControls guide.)

---

# Part E: The One Animation Rule This Doc Adds

The IKControls guide covers IK motion in full. The single principle worth repeating
here, because it recurs in **every** system that places a limb on a **moving** body —
IK feet, IK guard hands, even Motor6D secondary motion — is:

## 20. Smooth in body-LOCAL space, not world space

If you ease (lerp / exponential-approach) a target's **world** position toward a goal
that is rigidly offset from a moving root, the smoothed value **lags the body** by an
amount proportional to its speed. The limb trails backward (feet bury in the belly
while falling; arms fly back into the head while running) and only catches up when the
body stops.

The fix, every time:

```lua
-- once, on the frame the gesture blends in:
state.local = root.CFrame:PointToObjectSpace(endEffector.Position)
-- each frame:
state.local = state.local:Lerp(goalLocal, 1 - math.exp(-dt * k))
target.Position = root.CFrame:PointToWorldSpace(state.local)
```

The body's translation/rotation is applied **instantly** (via the fresh `root.CFrame`)
and only the gesture's *shape* eases. Clear the cached local offset when the gesture
ends.

**This applies only to targets rigidly attached to the body.** A target that is an
independent world point — a foe you're aiming at, a planted foot meant to stay put
during a stride — is correctly smoothed in **world** space; don't "fix" those. And
targets you recompute from scratch every frame and assign **without** easing (elbow
poles) don't lag — leave them.

Drive these in a `RenderStep` bound **after** the body settles (`Character` priority +
1) so the offset reads against this frame's final body position.

## 21. Two more secondary-motion notes

- **Cadence:** scale the bob / arm-swing phase **with the gait**. A fast runner whose
  upper body heaves at a fixed slow cadence reads as weak and disconnected. And watch
  the smoothing — an exponential approach toward an oscillating goal **attenuates the
  amplitude** once the goal frequency nears the smoothing rate, so scale the follow
  rate up with cadence too: `approach(self.bob, goal, dt, math.max(12, cadence*1.6))`.
- **Framerate-independent smoothing:** `value = value:Lerp(goal, 1 - math.exp(-dt*k))`
  (equivalently the `approach()` helper) is the **correct** framerate-*independent*
  form. Do not "fix" it to a plain `dt*k` lerp — a reviewer flagging it as
  frame-dependent is wrong.

---

# Part F: The Offline Render Discipline

This is what makes everything above checkable. A two-step offline pipeline —
**export** a JSON snapshot of a model's parts (run the real builders under a CLI shim
of the engine globals), then **rasterize** that JSON to a PNG — lets you eyeball a
model in ~0.5s without opening the editor. Render every model you build or change and
**show the PNG** so it can be judged.

## 22. What the renderer mirrors, and what it can't

It **does** mirror the real shape rules (Part A): `Cylinder` along local X, `Ball` as
a min-axis sphere, real `CFrame.lookAt` orientation — so geometry is trustworthy.

It **does not** model:

- **Lighting, materials, `Neon` glow, lights, particles** — a Neon part's color wash
  won't appear; judge shape, not glow.
- **Terrain.** Rooms carved into terrain have rock walls/ceiling that are **not**
  `BasePart`s, so a parts-only render shows the furniture on its floor slab with **no
  shell**. Expected, not a bug.
- **Runtime-set appearance.** Properties set *after* build by runtime code (a gate's
  transparency toggled later, GUIs, dynamic lights) — the CLI captures **build-time
  state only**.
- **Pivots and placement.** The renderer draws each part's raw world CFrame and
  never consults `GetPivot`/`PivotOffset`, so a broken model pivot (section 4)
  renders perfectly and only fails when the game `PivotTo`s the model into place.
  Verify pivots with arithmetic (`GetPivot()` rotation must be identity), not with
  a render.

## 23. Read interiors with a top-down PLAN view, not an oblique angle

A simple rasterizer has **no per-pixel z-buffer** — it sorts whole parts by center
depth. In a packed interior an oblique 3/4 view reads ambiguously: furniture occludes
furniture and a part can **look misplaced when it isn't**. A near-top-down shot
(`--yaw 0 --pitch 88`) reads like a blueprint and shows the true X–Z layout with no
occlusion confusion. **Cross-check an oblique view against a plan view before
concluding a part is in the wrong place.**

## 24. Frame embedded builds with focus + span

Auto-fit frames the whole bounding box. A landmark with a long approach (a tunnel, a
distant signpost) blows the box out so the room renders tiny. Aim the camera with a
`--focus "x,y,z"` point and set the zoom with a `--span N` (world units) so the room
fills the frame.

## 25. The shim is a *partial* emulation — failures are silent or wrong, not loud

The CLI shim stubs engine globals (`Instance`, `CFrame`, `Vector3`, …) so builders run
headless. It is **partial**. Gaps surface two ways:

1. **Loud:** `attempt to call/index a nil value` — an un-stubbed API.
2. **Silent and worse:** *wrong geometry*. A stubbed `CFrame.lookAt` that returned
   identity once flattened an entire landmark built off a lookAt room frame — it ran
   clean and rendered wrong.

So: a clean render is necessary but not sufficient — confirm the shapes you *expect*
are actually there. When you add a builder that uses a new engine constructor, the
shim must provide it; an unlisted global is `nil` offline and the build aborts
mid-model (or, worse, silently degrades). Add new engine surface to the shim's core,
not to per-game adapters, so every pipeline benefits.

**One bespoke model = one file.** Give each *distinct* model its own builder file and
register it; don't grow a shared multi-model file or an `if id == …` chain. Reused,
generic looks (rarity-tinted kind-models, shared recipes that recolor by palette) stay
shared on purpose — the one-file rule is about *bespoke* models, each individually
renderable.

---

# Part G: Before You Call It Done — Checklist

**Geometry**
- [ ] No un-rotated `Cylinder` meant to be a flat disc (it's a sideways slab).
- [ ] No stretched `Ball` meant to be elongated (it's a min-axis sphere); shells/helmets are Blocks.
- [ ] Model pivot has identity rotation (`PivotOffset = PrimaryPart.CFrame:Inverse()` in finalize) — a rotated cylinder/tilted PrimaryPart otherwise lays the model sideways on `PivotTo`.
- [ ] Ran the coplanar-face test on color/material-differing sibling pairs; trims sit ~0.02–0.04 proud.

**Structure**
- [ ] Every rotation sign reasoned from "which edge ends up lower," not guessed.
- [ ] Stairs land flush on a real floor panel with an opening above; no overlapping coplanar floors.
- [ ] Gated rooms have exactly one opening; walls reach the ceiling; corners closed.
- [ ] Roofs/walls collidable; tiny trim non-collidable.
- [ ] Seats face the intended direction (`CFrame.lookAt`, occupant looks toward −Z).
- [ ] Terrain caverns don't breach the surface; floor heights re-derived from terrain.

**Rig & motion**
- [ ] Confirmed Motor6D vs constraint rig before choosing the poser.
- [ ] The animated bob/lean joint actually carries the skeleton below it.
- [ ] Rest pose has a real limb bend (bones sum longer than the drop) so feet can stride.
- [ ] Body-attached eased targets smoothed in **local** space; world points left in world space.

**Verification**
- [ ] Rendered the model and **looked at it**; showed the PNG.
- [ ] Used a plan view to check interior layout before trusting an oblique angle.
- [ ] Confirmed the shapes I expected are actually present (shim runs clean ≠ correct).

---

# References

- `IKControls_Implementation_Guide.md` — the companion: making rigs move (IK gaits,
  swings, punches, look/aim, tails, and the full production-lessons appendix).
- Roblox Creator Hub — `BasePart.Shape` / `PartType`, `IKControl`, `Motor6D`,
  `CFrame`, terrain `FillCylinder`.
