# IKControls Implementation Guide

_A practical spec for an AI agent implementing procedural creature and character motion in Roblox/Luau._

This document explains how to use Roblox `IKControl` instances as a reusable procedural animation layer for things like:

- animal legs walking, running, stepping over uneven ground, and planting feet
- tails wagging, curling, aiming, and reacting to motion
- human punches, reaches, grabs, sword swings, blocks, and aim poses
- blending procedural motion with ordinary keyframed animations

The goal is **not** to replace all animation. The best result is usually:

> **Base animation gives the body style and rhythm. IKControls correct, aim, plant, reach, and adapt the limbs to the real world.**

---

## 1. Core Mental Model

### Forward Kinematics vs Inverse Kinematics

Most normal animations are **forward kinematics**:

- Rotate shoulder.
- Rotate elbow.
- Rotate wrist.
- Hand ends up somewhere.

IK is the reverse:

- Choose where the hand, foot, head, tail tip, or weapon grip should end up.
- The IK solver rotates the chain to make the end reach that target.

In Roblox, an `IKControl` is an object placed under a `Humanoid` or `AnimationController` that tells the character’s `Animator`:

> “Move this chain of joints so this end piece reaches or points toward this target.”

---

## 2. The Four Required IKControl Properties

Every useful IKControl needs these four properties set:

```lua
ik.Type = Enum.IKControlType.Position -- or Transform, Rotation, LookAt
ik.ChainRoot = upperLimbOrStartOfChain
ik.EndEffector = handFootHeadTailTipOrBone
ik.Target = targetPartOrAttachment
```

### `ChainRoot`

The **first part/bone in the chain the solver may move**.

Examples:

- Human arm: `LeftUpperArm`
- Human leg: `LeftUpperLeg`
- Dog front leg: `FrontLeftUpperLeg`
- Tail: first tail bone, such as `Tail01`
- Neck/head look: `UpperTorso` or `NeckBase`, depending on rig

Avoid using the entire character root as `ChainRoot` unless you truly want the whole body to bend. For arms, legs, tails, heads, and weapons, keep the chain small and intentional.

### `EndEffector`

The **last part/bone in the chain** that should reach, point, or align.

Examples:

- Human arm: `LeftHand`
- Human leg: `LeftFoot`
- Animal leg: `FrontLeftPaw`
- Tail: `TailTip`
- Head look: `Head`
- Sword swing assist: weapon grip attachment or hand

### `Target`

The **world-space object the EndEffector tries to reach, face, or match**.

Usually create invisible anchored/non-colliding target parts or attachments. Move these every frame with scripts.

Examples:

- foot target part on the ground
- hand target part in front of the enemy
- sword arc target moving along a curve
- tail tip target oscillating behind the body
- look target on enemy head/chest

### `Type`

Controls what kind of match the solver tries to satisfy.

Use these defaults:

| Type | Meaning | Use For |
|---|---|---|
| `Position` | Move end effector position to target position | feet, paws, reaching hands, simple tail tip |
| `Transform` | Match both position and orientation | weapon grips, exact hand poses, two-handed holds |
| `Rotation` | Match only rotation | wrist/hand orientation, head/weapon orientation corrections |
| `LookAt` | Make end effector point its forward axis toward target | head look, torso aim, tail pointing, eye/head tracking |

---

## 3. Important Optional Properties

### `Weight`

How much the IK affects the final pose.

- `0` = no intended IK influence
- `1` = full IK influence
- tween between values for smooth blends

Do not rely on `Weight = 0` as the only way to disable an IKControl. In Roblox, smoothing and pole behavior can still affect pose in edge cases. If it should be truly off, set:

```lua
ik.Enabled = false
```

Recommended pattern:

```lua
ik.Enabled = true
ik.Weight = math.clamp(alpha, 0, 1)

if alpha <= 0.001 then
    ik.Enabled = false
end
```

### `SmoothTime`

How quickly the IK end follows the target.

- `0` = immediate/snappy
- `0.03` to `0.08` = responsive game feel
- `0.1` to `0.25` = heavier, smoother, more animal-like

Examples:

| Motion | SmoothTime |
|---|---:|
| sword impact correction | `0` to `0.03` |
| punching reach | `0.02` to `0.06` |
| foot planting | `0.04` to `0.12` |
| heavy creature foot movement | `0.10` to `0.20` |
| lazy tail wag | `0.10` to `0.30` |

### `Priority`

When multiple IKControls affect overlapping body parts, higher priority controls resolve later and may override lower-priority results.

Suggested convention:

| Priority | Layer |
|---:|---|
| `0` | passive idle helpers, subtle look controls |
| `1` | locomotion foot planting and tail motion |
| `2` | combat aiming, weapon pose, shield pose |
| `3` | hard interactions: grab ledge, hold item, exact cutscene pose |

### `Pole`

A pole target helps control which way the joint bends.

Use poles for knees, elbows, hocks, and other hinge-like chains.

Examples:

- human elbow pole: in front/outside of the torso
- human knee pole: in front of the knee
- dog/cat knee/hock pole: placed according to that limb’s natural bend direction
- spider leg pole: slightly outward from body so legs do not collapse inward

Without poles, elbows and knees can flip or choose ugly bend directions when the target crosses the chain line.

### `Offset`

Applies an extra CFrame on top of the target. Use this when the target should represent a general goal but the actual end effector needs a local adjustment.

Examples:

- make a hand grab a sword by the correct grip angle
- keep a foot sole flat even if the foot part’s pivot is centered
- rotate a paw so claws point forward
- offset fist contact slightly past the enemy chest for a punch follow-through

---

## 4. Recommended Rig Setup

### Humanoid Characters

For an R15-like humanoid rig:

```text
Humanoid
  Animator
  IKControl_LeftFoot
  IKControl_RightFoot
  IKControl_LeftHand
  IKControl_RightHand
  IKControl_HeadLook
```

Each IKControl is parented to the `Humanoid` or `AnimationController` that owns the `Animator`.

### Custom Animal / Creature Rigs

For custom animal rigs, an `AnimationController` is usually cleaner:

```text
WolfModel
  AnimationController
    Animator
    IK_FrontLeftLeg
    IK_FrontRightLeg
    IK_BackLeftLeg
    IK_BackRightLeg
    IK_Tail01
    IK_Tail02
    IK_HeadLook
  Root
  Spine01
  Spine02
  Neck
  Head
  Tail01
  Tail02
  Tail03
  TailTip
  FrontLeftUpperLeg
  FrontLeftLowerLeg
  FrontLeftPaw
  ...
```

Important rigging rules:

1. Name bones/parts clearly.
2. Keep limb chains simple: upper → lower → foot/paw/hand.
3. Add pole target parts for each bendable limb.
4. Add hidden target parts/attachments for each controlled end effector.
5. Keep targets in a folder like `Model.IKTargets` for debugging.
6. Start with one limb working before scaling to all limbs.

---

## 5. Helper: Create an IKControl

```lua
local function createIKControl(params)
    local ik = Instance.new("IKControl")
    ik.Name = params.Name or "IKControl"
    ik.Type = params.Type or Enum.IKControlType.Position
    ik.ChainRoot = assert(params.ChainRoot, "Missing ChainRoot")
    ik.EndEffector = assert(params.EndEffector, "Missing EndEffector")
    ik.Target = assert(params.Target, "Missing Target")
    ik.Weight = params.Weight or 1
    ik.SmoothTime = params.SmoothTime or 0.05
    ik.Priority = params.Priority or 0

    if params.Pole then
        ik.Pole = params.Pole
    end

    if params.Offset then
        ik.Offset = params.Offset
    end

    ik.Parent = assert(params.Parent, "Missing Humanoid or AnimationController parent")
    return ik
end
```

---

## 6. Helper: Invisible IK Target Part

Use visible targets while debugging, then hide them later.

```lua
local function createIKTarget(name, parent, cframe, debugVisible)
    local p = Instance.new("Part")
    p.Name = name
    p.Size = Vector3.new(0.25, 0.25, 0.25)
    p.Shape = Enum.PartType.Ball
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.Massless = true
    p.CFrame = cframe or CFrame.new()
    p.Transparency = debugVisible and 0.25 or 1
    p.Parent = parent
    return p
end
```

---

## 7. Update Loop Pattern

Most IK target movement should happen on the client for player-controlled visuals, usually in `RunService.RenderStepped` or `BindToRenderStep`.

Server should handle gameplay truth:

- hit detection
- damage
- ability cooldowns
- movement authority
- NPC behavior states

Client should handle visual IK:

- exact foot placement
- arm reach polish
- tail sways
- head look
- weapon follow-through

For NPCs, server can run simple target decisions, while clients can still render cosmetic IK locally if the rig is replicated.

Basic pattern:

```lua
local RunService = game:GetService("RunService")

RunService.RenderStepped:Connect(function(dt)
    -- 1. Read character state: speed, velocity, grounded, combat state, target enemy.
    -- 2. Compute desired target CFrames.
    -- 3. Smooth target parts manually if needed.
    -- 4. Set IKControl Weight/Enabled based on state.
end)
```

---

# Part A: Animal Legs Walking and Running

## 8. Animal Leg IK Overview

For each leg:

```text
Body/Spine
  UpperLeg  <- ChainRoot
    LowerLeg
      Paw   <- EndEffector

IKTarget_Leg = where the paw should be planted
IKPole_Leg   = controls knee/hock direction
```

A convincing procedural leg system needs four concepts:

1. **Home position**: where the foot wants to be relative to the body.
2. **Ground probe**: raycast down to find real ground height/normal.
3. **Step trigger**: decide when the planted foot is too far from home.
4. **Step arc**: lift foot, move it forward, plant it again.

---

## 9. Leg Data Structure

```lua
local Leg = {}
Leg.__index = Leg

function Leg.new(config)
    local self = setmetatable({}, Leg)
    self.Name = config.Name
    self.Root = config.Root
    self.HomeAttachment = config.HomeAttachment -- attachment on body showing default foot area
    self.Target = config.Target
    self.Pole = config.Pole
    self.IK = config.IK
    self.StepHeight = config.StepHeight or 1.0
    self.StepDuration = config.StepDuration or 0.18
    self.StepDistance = config.StepDistance or 2.0
    self.RaycastLength = config.RaycastLength or 8.0
    self.GroundOffset = config.GroundOffset or 0.08
    self.IsStepping = false
    self.StepT = 0
    self.StepStart = self.Target.CFrame
    self.StepGoal = self.Target.CFrame
    self.LastPlanted = self.Target.Position
    return self
end
```

---

## 10. Ground Probe

```lua
local function raycastGround(origin, length, ignoreList)
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = ignoreList or {}

    local result = workspace:Raycast(origin, Vector3.new(0, -length, 0), params)
    if result then
        return result.Position, result.Normal, result.Instance
    end

    return origin - Vector3.new(0, length, 0), Vector3.yAxis, nil
end
```

---

## 11. Foot Orientation From Ground Normal

This makes paws/feet align to slopes.

```lua
local function cframeFromPositionNormalForward(pos, normal, forward)
    local up = normal.Unit
    local f = forward - up * forward:Dot(up)

    if f.Magnitude < 0.001 then
        f = Vector3.zAxis
    end

    f = f.Unit
    local right = f:Cross(up).Unit
    local correctedForward = up:Cross(right).Unit

    return CFrame.fromMatrix(pos, right, up, -correctedForward)
end
```

Note: Roblox CFrames use a negative look vector convention in many APIs, so test visual orientation and flip forward if your paw faces backward.

---

## 12. Step Trigger

A planted foot should stay still while the body moves over it. It should step only when its desired home point gets too far away.

```lua
function Leg:getDesiredGroundCFrame(ignoreList, bodyForward)
    local homeWorld = self.HomeAttachment.WorldPosition
    local probeOrigin = homeWorld + Vector3.new(0, self.RaycastLength * 0.5, 0)
    local groundPos, groundNormal = raycastGround(probeOrigin, self.RaycastLength, ignoreList)
    groundPos += groundNormal * self.GroundOffset

    return cframeFromPositionNormalForward(groundPos, groundNormal, bodyForward)
end

function Leg:shouldStep(desiredCFrame)
    local distance = (self.LastPlanted - desiredCFrame.Position).Magnitude
    return distance > self.StepDistance
end
```

---

## 13. Step Arc

Use an arc so the foot lifts instead of sliding.

```lua
local function easeInOut(t)
    return t * t * (3 - 2 * t)
end

local function stepArcPosition(startPos, endPos, t, height)
    local alpha = easeInOut(t)
    local pos = startPos:Lerp(endPos, alpha)
    local lift = math.sin(math.pi * t) * height
    return pos + Vector3.new(0, lift, 0)
end
```

---

## 14. Leg Update

```lua
function Leg:update(dt, ignoreList, bodyForward)
    local desired = self:getDesiredGroundCFrame(ignoreList, bodyForward)

    if not self.IsStepping and self:shouldStep(desired) then
        self.IsStepping = true
        self.StepT = 0
        self.StepStart = self.Target.CFrame
        self.StepGoal = desired
    end

    if self.IsStepping then
        self.StepT += dt / self.StepDuration
        local t = math.clamp(self.StepT, 0, 1)

        local pos = stepArcPosition(
            self.StepStart.Position,
            self.StepGoal.Position,
            t,
            self.StepHeight
        )

        local rot = self.StepStart.Rotation:Lerp(self.StepGoal.Rotation, easeInOut(t))
        self.Target.CFrame = CFrame.new(pos) * rot

        if t >= 1 then
            self.IsStepping = false
            self.LastPlanted = self.StepGoal.Position
            self.Target.CFrame = self.StepGoal
        end
    else
        -- Stay planted. Do not slide.
        self.Target.CFrame = CFrame.new(self.LastPlanted) * self.Target.CFrame.Rotation
    end
end
```

---

## 15. Gait Coordination

Do not let every leg step at once. Use gait groups.

### Quadruped Walk

Common alternating pattern:

```text
Group A: FrontLeft + BackRight
Group B: FrontRight + BackLeft
```

Allow Group A to step while Group B is planted, then alternate.

### Quadruped Run / Bound

For faster motion:

```text
Phase 1: back legs push
Phase 2: body airborne/compressed
Phase 3: front legs catch
Phase 4: back legs recover
```

For Roblox game feel, fake this with timing and stronger body bob; do not simulate true biomechanics unless needed.

### Spider / Insect

Tripod gait:

```text
Group A: LeftFront + RightMiddle + LeftBack
Group B: RightFront + LeftMiddle + RightBack
```

This produces stable, readable movement.

---

## 16. Leg Manager Example

```lua
local LegManager = {}
LegManager.__index = LegManager

function LegManager.new(model, legs)
    local self = setmetatable({}, LegManager)
    self.Model = model
    self.Legs = legs
    self.ActiveGroup = 1
    self.Groups = {
        { "FrontLeft", "BackRight" },
        { "FrontRight", "BackLeft" },
    }
    return self
end

function LegManager:anyLegInGroupStepping(group)
    for _, legName in ipairs(group) do
        if self.Legs[legName].IsStepping then
            return true
        end
    end
    return false
end

function LegManager:update(dt)
    local root = self.Model.PrimaryPart
    local bodyForward = root.CFrame.LookVector
    local ignore = { self.Model }

    local currentGroup = self.Groups[self.ActiveGroup]
    local otherGroupIndex = self.ActiveGroup == 1 and 2 or 1

    -- Update active group normally.
    for _, legName in ipairs(currentGroup) do
        self.Legs[legName]:update(dt, ignore, bodyForward)
    end

    -- Keep inactive group planted.
    for _, legName in ipairs(self.Groups[otherGroupIndex]) do
        local leg = self.Legs[legName]
        if not leg.IsStepping then
            leg.Target.Position = leg.LastPlanted
        end
    end

    if not self:anyLegInGroupStepping(currentGroup) then
        self.ActiveGroup = otherGroupIndex
    end
end
```

This is intentionally simple. A production version should allow urgent steps if a foot is extremely far from home, even if it is not that group’s turn.

---

# Part B: Tail Wagging, Curling, and Aiming

## 17. Tail IK Overview

A tail usually has multiple bones:

```text
Tail01 -> Tail02 -> Tail03 -> TailTip
```

There are two main approaches:

### Approach 1: One IKControl for the whole tail

```text
ChainRoot = Tail01
EndEffector = TailTip
Target = TailTipTarget
Type = Position or LookAt
```

This is simple and good for:

- basic wag
- tail pointing toward/away from something
- creature tail dragging behind body

### Approach 2: Multiple IKControls or procedural bone rotations

Use this for:

- snake-like motion
- scorpion tail curls
- dragon tail swipes
- thick tails with many segments

For many tails, IK for the tip plus simple per-bone sway works best.

---

## 18. Tail Target Wag

```lua
local function updateTailWag(tailTarget, rootCFrame, speed, intensity, verticalIntensity, time)
    local back = -rootCFrame.LookVector
    local right = rootCFrame.RightVector
    local up = rootCFrame.UpVector

    local base = rootCFrame.Position + back * 3 + up * 1.2
    local wag = math.sin(time * speed) * intensity
    local lift = math.sin(time * speed * 2 + 0.7) * verticalIntensity

    tailTarget.Position = base + right * wag + up * lift
end
```

Recommended values:

| Tail Mood | Speed | Intensity | Vertical |
|---|---:|---:|---:|
| relaxed | `2` | `0.25` | `0.05` |
| happy dog | `8` | `1.0` | `0.20` |
| alert wolf | `3` | `0.35` | `0.35` |
| scared/tucked | no wag | target low/under body | low |
| dragon heavy sway | `1` | `1.5` | `0.25` |

---

## 19. Tail Follow-Through From Velocity

Make the tail lag behind movement direction.

```lua
local previousVelocity = Vector3.zero

local function updateTailWithVelocity(tailTarget, root, velocity, time, dt)
    local speed = velocity.Magnitude
    local rootCf = root.CFrame

    local back = -rootCf.LookVector
    local up = rootCf.UpVector
    local right = rootCf.RightVector

    local lateralSway = math.sin(time * 5) * math.clamp(speed / 16, 0, 1) * 0.6
    local drag = speed > 0.1 and -velocity.Unit * math.clamp(speed / 8, 0, 2) or back

    local desired = root.Position
        + back * 2.5
        + drag * 0.8
        + right * lateralSway
        + up * 1.1

    tailTarget.Position = tailTarget.Position:Lerp(desired, 1 - math.exp(-dt * 8))
    previousVelocity = velocity
end
```

---

## 20. Tail Curl / Scorpion / Dragon Pose

For a curl, place the target above and forward/side of the body and use `LookAt` or `Position` depending on the rig.

```lua
local function setTailCurlTarget(tailTarget, rootCFrame, curlSide, curlHeight, curlForward)
    local side = rootCFrame.RightVector * curlSide
    local up = rootCFrame.UpVector
    local forward = rootCFrame.LookVector

    tailTarget.Position = rootCFrame.Position
        + side * 1.5
        + up * curlHeight
        + forward * curlForward
end
```

Use cases:

- scorpion tail ready to strike
- dragon tail raised before slam
- cat tail curl while idle
- monkey tail balancing while climbing

---

# Part C: Person Punching

## 21. Punching With IKControls

A good punch combines:

1. Base animation: shoulders, torso twist, weight shift.
2. IK hand target: makes fist reach exact point.
3. Look/torso IK: aims body at target.
4. Timing curve: windup → strike → follow-through → recover.
5. Hit detection: gameplay handled separately, usually around strike timing.

Do not simply snap the hand to the enemy. Move the target through a short punch path.

---

## 22. Punch Phases

```text
Windup        0.00 - 0.25
Strike        0.25 - 0.45
Impact        around 0.40
FollowThrough 0.45 - 0.60
Recover       0.60 - 1.00
```

Punch target path:

```text
start near shoulder -> pull back -> enemy chest/jaw -> slightly through target -> return to guard
```

---

## 23. Punch Target Solver

```lua
local function bezier3(a, b, c, t)
    local ab = a:Lerp(b, t)
    local bc = b:Lerp(c, t)
    return ab:Lerp(bc, t)
end

local function updatePunchTarget(handTarget, root, enemyAimPoint, punchSide, normalizedTime)
    local cf = root.CFrame
    local side = cf.RightVector * punchSide
    local up = cf.UpVector
    local forward = cf.LookVector

    local guard = root.Position + side * 1.1 + up * 1.4 + forward * 0.7
    local windup = root.Position + side * 1.2 + up * 1.35 - forward * 0.35
    local impact = enemyAimPoint
    local through = enemyAimPoint + forward * 0.45

    local t = math.clamp(normalizedTime, 0, 1)
    local pos

    if t < 0.25 then
        pos = guard:Lerp(windup, t / 0.25)
    elseif t < 0.45 then
        pos = bezier3(windup, guard + forward * 1.5, impact, (t - 0.25) / 0.20)
    elseif t < 0.60 then
        pos = impact:Lerp(through, (t - 0.45) / 0.15)
    else
        pos = through:Lerp(guard, (t - 0.60) / 0.40)
    end

    handTarget.CFrame = CFrame.lookAt(pos, enemyAimPoint)
end
```

Recommended IK settings for punch arm:

```lua
ik.Type = Enum.IKControlType.Transform
ik.Weight = punchAlpha -- 0 to 1
ik.SmoothTime = 0.02
ik.Priority = 2
```

---

## 24. Punch Weight Curve

```lua
local function punchIKWeight(t)
    if t < 0.10 then
        return t / 0.10
    elseif t > 0.85 then
        return 1 - ((t - 0.85) / 0.15)
    else
        return 1
    end
end
```

This prevents sudden arm snapping at the beginning and end.

---

## 25. Punch Gameplay Hit Window

Do gameplay damage only during the strike/impact window.

```lua
local function isPunchHitWindow(t)
    return t >= 0.34 and t <= 0.47
end
```

Keep visual IK separate from damage. The IK can look cool even when the server decides no hit occurred.

---

# Part D: Person Swinging a Sword

## 26. Sword Swing IK Overview

A sword swing is not just the hand reaching a point. It needs:

- body rotation from animation
- weapon arc path
- leading hand IK
- optional offhand IK for two-handed grip
- blade orientation
- collision/hit window
- follow-through

Usually the sword itself should be attached to the hand by a Motor6D/Weld. IK moves the hand/arm; the weapon follows.

For exact weapon control, use a `Transform` IKControl on the weapon hand or hand attachment.

---

## 27. Sword Arc Target

Represent a swing as an arc around the character.

```lua
local function swordArcPoint(rootCf, radius, height, side, t)
    -- t: 0..1
    -- side: 1 for right-handed swing, -1 for left-handed mirror
    local angleStart = math.rad(130 * side)
    local angleEnd = math.rad(-70 * side)
    local angle = angleStart + (angleEnd - angleStart) * t

    local forward = rootCf.LookVector
    local right = rootCf.RightVector
    local up = rootCf.UpVector

    local horizontal = (right * math.sin(angle) + forward * math.cos(angle)) * radius
    local vertical = up * (height + math.sin(t * math.pi) * 0.4)

    return rootCf.Position + horizontal + vertical
end
```

---

## 28. Sword Swing Target Update

```lua
local function updateSwordSwingTarget(handTarget, root, t, side)
    local cf = root.CFrame
    local eased = t * t * (3 - 2 * t)

    local pos = swordArcPoint(cf, 2.4, 1.5, side, eased)
    local nextPos = swordArcPoint(cf, 2.4, 1.5, side, math.clamp(eased + 0.03, 0, 1))

    -- Aim the hand/weapon along the path direction.
    local direction = (nextPos - pos)
    if direction.Magnitude < 0.001 then
        direction = cf.LookVector
    end

    handTarget.CFrame = CFrame.lookAt(pos, pos + direction.Unit)
end
```

Recommended IK settings:

```lua
ik.Type = Enum.IKControlType.Transform
ik.SmoothTime = 0.01
ik.Priority = 2
ik.Weight = attackIKWeight
```

---

## 29. Two-Handed Sword

For a two-handed weapon:

- Main hand drives the sword.
- Offhand IK target follows a grip attachment on the weapon.
- Offhand IK has slightly lower or equal priority.

```lua
-- Every frame after the sword has moved:
offhandTarget.CFrame = swordModel.OffhandGrip.WorldCFrame
```

Suggested setup:

```text
RightHand IK: Transform, target = main swing target, priority 2
LeftHand IK: Transform, target = weapon offhand grip, priority 3
```

This lets the main hand define the weapon arc while the offhand sticks to the handle.

---

## 30. Sword Hit Timing

```lua
local function swordHitWindow(t)
    return t >= 0.25 and t <= 0.58
end
```

For hit detection, use one of these:

1. Swept raycasts between previous blade points and current blade points.
2. Temporary hitbox parts attached to the blade.
3. Region/overlap queries during the hit window.

Do not rely on IK target contact for damage. IK is visual; hit detection must be authoritative.

---

# Part E: Looking, Aiming, and Head/Torso Tracking

## 31. Head LookAt

```lua
local headIK = Instance.new("IKControl")
headIK.Type = Enum.IKControlType.LookAt
headIK.ChainRoot = upperTorsoOrNeckBase
headIK.EndEffector = head
headIK.Target = lookTarget
headIK.Weight = 0.6
headIK.SmoothTime = 0.12
headIK.Priority = 1
headIK.Parent = humanoidOrAnimationController
```

Move `lookTarget` to:

- enemy head/chest
- interesting object
- camera aim point
- dialogue speaker
- direction of travel

Clamp the target direction so heads do not spin backward.

```lua
local function clampLookTarget(rootCf, desiredWorldPos, maxYawDegrees)
    local localPos = rootCf:PointToObjectSpace(desiredWorldPos)
    local yaw = math.atan2(localPos.X, -localPos.Z)
    local maxYaw = math.rad(maxYawDegrees)
    yaw = math.clamp(yaw, -maxYaw, maxYaw)

    local distance = math.max(localPos.Magnitude, 4)
    local clampedLocal = Vector3.new(
        math.sin(yaw) * distance,
        localPos.Y,
        -math.cos(yaw) * distance
    )

    return rootCf:PointToWorldSpace(clampedLocal)
end
```

---

## 32. Aim Layer for Ranged Attacks or Magic

Use a torso/head `LookAt` IK plus hand/weapon `Transform` IK.

```text
Torso LookAt: low weight, broad body aiming
Head LookAt: medium weight, eye contact/readability
RightHand Transform: exact wand/bow/gun/sword aim
LeftHand Transform: support hand on weapon/item
```

Suggested weights:

| Control | Weight |
|---|---:|
| torso aim | `0.25` to `0.45` |
| head aim | `0.40` to `0.70` |
| weapon hand | `0.80` to `1.00` |
| support hand | `0.70` to `1.00` |

---

# Part F: Blending IK With Normal Animations

## 33. Layering Rule

Use normal animations for:

- personality
- anticipation
- body rhythm
- recoil
- big silhouette changes
- idle/walk/run cycles

Use IK for:

- exact contacts
- exact aiming
- adapting to terrain
- holding objects
- matching hands to weapons
- head/eye attention
- procedural tails and secondary motion

---

## 34. Common Blend Curves

```lua
local function smoothstep(t)
    t = math.clamp(t, 0, 1)
    return t * t * (3 - 2 * t)
end

local function fadeInOut(t, fadeInEnd, fadeOutStart)
    if t < fadeInEnd then
        return smoothstep(t / fadeInEnd)
    elseif t > fadeOutStart then
        return 1 - smoothstep((t - fadeOutStart) / (1 - fadeOutStart))
    else
        return 1
    end
end
```

Example:

```lua
ik.Weight = fadeInOut(attackT, 0.12, 0.82)
```

---

## 35. Animation + IK Attack Pattern

```text
1. Play base attack animation.
2. During windup, fade IK from 0 to 1.
3. During strike, move IK target along punch/sword/reach path.
4. During impact, run authoritative hit detection.
5. During follow-through, keep target moving past impact.
6. During recovery, fade IK back to 0 or disable control.
```

---

# Part G: Debugging and Tuning

## 36. Debug Visualization

During development:

- make IK target parts visible
- color foot targets differently
- color pole targets differently
- draw raycast hit points
- print current IK weights
- show whether each foot is planted or stepping

Basic debug folder:

```text
Character
  IKTargets
    LeftFootTarget
    LeftFootPole
    RightFootTarget
    RightFootPole
    LeftHandTarget
    SwordTarget
    TailTarget
```

---

## 37. Common Problems and Fixes

### Problem: Limb bends backward or flips

Likely causes:

- missing pole target
- pole is on the wrong side
- target crosses directly through the chain line
- chain root/end effector are wrong

Fixes:

- add a pole target in front of the knee/elbow
- keep target slightly offset from perfect straight-line extension
- reduce reach distance
- verify chain order

### Problem: Foot slides on the ground

Likely causes:

- target follows home position every frame
- no planted-foot state
- step duration too long while body moves fast

Fixes:

- store `LastPlanted`
- do not move planted target until step triggers
- shorten step duration at higher speed
- increase step distance for large creatures

### Problem: Foot penetrates ground

Likely causes:

- missing ground offset
- target pivot is inside foot
- ground normal not applied

Fixes:

- add `GroundOffset`
- use `Offset` or target CFrame adjustment
- align foot to ground normal

### Problem: Character twists unnaturally

Likely causes:

- chain root too high, like full torso/root
- `LookAt` target behind character
- IK weight too high
- no base animation keeping body stable

Fixes:

- use smaller chain root
- clamp look direction
- lower `Weight`
- play an idle/pose animation under IK

### Problem: IK snaps on/off

Likely causes:

- directly setting `Enabled` without fading `Weight`
- target starts far away from current end effector

Fixes:

- set target to current end-effector CFrame before enabling
- fade `Weight`
- use small `SmoothTime`

### Problem: Sword or punch feels weak

Likely causes:

- only moving the arm, no torso/body animation
- target path is straight and robotic
- no anticipation/follow-through

Fixes:

- play a strong base attack animation
- move target on an arc or bezier path
- add windup and overshoot
- rotate torso/hips in animation

---

# Part H: Implementation Checklist for an AI Agent

## 38. General IK Checklist

For each IK feature:

1. Identify the rig chain.
2. Pick the `ChainRoot`.
3. Pick the `EndEffector`.
4. Create target part/attachment.
5. Create pole target if the chain bends like knee/elbow.
6. Create IKControl under the Humanoid/AnimationController.
7. Set `Type`, `Weight`, `SmoothTime`, and `Priority`.
8. Create an update loop that moves the target.
9. Fade weight in/out by state.
10. Debug with visible targets.
11. Hide debug targets when stable.

---

## 39. Animal Walk/Run Checklist

For each leg:

- upper leg is `ChainRoot`
- paw/foot is `EndEffector`
- foot target raycasts to ground
- pole target controls bend
- foot has a home attachment relative to body
- foot remains planted until too far from home
- stepping foot moves along lifted arc
- leg groups alternate according to gait
- step speed/height/distance scale with creature speed and size

Creature polish:

- body bobs slightly with gait
- spine leans into turns
- head tracks movement/combat target
- tail counterbalances speed/turning
- footstep sounds play when step lands

---

## 40. Tail Checklist

- tail root is `ChainRoot`
- tail tip is `EndEffector`
- target is behind/above/around body depending on mood
- wag is sine/noise based, not random teleporting
- target lags behind velocity
- use lower weights for subtle motion
- use higher weights for combat tail swipes or scorpion stings
- optionally rotate intermediate tail bones for more wave-like motion

---

## 41. Punch Checklist

- play base punch animation
- hand IK target starts near guard
- target pulls back during windup
- target moves through enemy aim point during strike
- hit window is time-limited
- damage is server-authoritative
- hand target overshoots during follow-through
- IK fades out during recovery
- torso/head aim toward target for readability

---

## 42. Sword Swing Checklist

- play base sword animation
- weapon attached to main hand
- main hand IK follows arc target
- offhand IK follows weapon grip for two-handed weapons
- blade orientation follows path direction
- hit detection uses blade sweep/hitbox, not IK contact
- follow-through continues after hit window
- IK fades out smoothly after attack

---

# Part I: Minimal Full Example - Humanoid Foot IK

```lua
local RunService = game:GetService("RunService")

local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local root = character:WaitForChild("HumanoidRootPart")

local targetsFolder = Instance.new("Folder")
targetsFolder.Name = "IKTargets"
targetsFolder.Parent = character

local leftFoot = character:WaitForChild("LeftFoot")
local leftUpperLeg = character:WaitForChild("LeftUpperLeg")

local leftTarget = createIKTarget(
    "LeftFootTarget",
    targetsFolder,
    leftFoot.CFrame,
    true
)

local leftPole = createIKTarget(
    "LeftKneePole",
    targetsFolder,
    leftFoot.CFrame + root.CFrame.LookVector * 2,
    true
)

local leftIK = createIKControl({
    Name = "IK_LeftFoot",
    Type = Enum.IKControlType.Transform,
    ChainRoot = leftUpperLeg,
    EndEffector = leftFoot,
    Target = leftTarget,
    Pole = leftPole,
    Weight = 1,
    SmoothTime = 0.06,
    Priority = 1,
    Parent = humanoid,
})

RunService.RenderStepped:Connect(function(dt)
    local origin = leftFoot.Position + Vector3.new(0, 4, 0)
    local hitPos, normal = raycastGround(origin, 8, { character })

    local forward = root.CFrame.LookVector
    local groundCf = cframeFromPositionNormalForward(
        hitPos + normal * 0.05,
        normal,
        forward
    )

    leftTarget.CFrame = leftTarget.CFrame:Lerp(groundCf, 1 - math.exp(-dt * 20))
    leftPole.Position = root.Position + root.CFrame.LookVector * 2 + root.CFrame.RightVector * -0.5
end)
```

This minimal example plants one foot. To make it walk well, upgrade it with the full leg stepping state machine from the earlier sections.

---

# Part J: Minimal Full Example - Sword Swing IK

```lua
local attackDuration = 0.55
local attacking = false
local attackStart = 0

local function startSwordAttack()
    attacking = true
    attackStart = os.clock()
    swordIK.Enabled = true
end

RunService.RenderStepped:Connect(function(dt)
    if not attacking then
        return
    end

    local t = math.clamp((os.clock() - attackStart) / attackDuration, 0, 1)

    updateSwordSwingTarget(rightHandTarget, root, t, 1)
    swordIK.Weight = fadeInOut(t, 0.10, 0.82)

    if swordHitWindow(t) then
        -- Run visual hitbox checks locally if desired.
        -- Server should validate actual hit/damage.
    end

    if t >= 1 then
        attacking = false
        swordIK.Weight = 0
        swordIK.Enabled = false
    end
end)
```

---

# Part K: Design Principles

## 43. Make IK Serve the Animation, Not Replace It

Bad:

> Move the hand target around and expect the whole punch to look good.

Good:

> Play a punch animation for body mechanics, then use IK to make the fist land exactly where needed.

## 44. Targets Should Move Like Real Intentions

A target is not just a coordinate. It represents intent:

- foot wants stable ground
- fist wants impact then follow-through
- sword wants an arc
- tail wants mood plus balance
- head wants attention

If the target moves naturally, IK looks natural.

## 45. Always Think in States

Most procedural animation should be state-based:

```text
Foot: planted -> stepping -> planted
Punch: idle -> windup -> strike -> recover
Sword: ready -> swing -> follow-through -> ready
Tail: relaxed -> alert -> happy -> attack -> tired
Head: forward -> tracking -> forced aim -> released
```

Each state decides:

- target position
- target orientation
- IK weight
- smooth time
- priority
- whether control is enabled

## 46. Keep Targets Debuggable

If an IK system looks wrong, the first question is:

> “Where is the target?”

Visible targets make issues obvious. Hide them only after tuning.

---

# Part L: Lessons from Production (Warblox)

## 47. Airborne feet must move in body-local space

**Problem:** while a creature is falling, world-space lerping of foot targets lags
behind the descending body. The body falls faster than the eased target catches up,
so feet end up buried in the belly on landing. Looks like momentum threw them up
into the body.

**Rule:** whenever the creature is airborne, convert the foot's current world
position into body-local space on the first airborne frame, ease that local offset
toward the tuck pose each frame, then convert back to world:

```lua
if not leg.airLocal then
    leg.airLocal = root.CFrame:PointToObjectSpace(leg.target.Position)
end
leg.airLocal = leg.airLocal:Lerp(tuckLocal, 1 - math.exp(-dt * 10))
leg.target.Position = root.CFrame:PointToWorldSpace(leg.airLocal)
```

Clear `airLocal` the moment the creature lands. This makes feet fall at exactly the
same rate as the body with no lag — the local offset is rigidly coupled to the
body, so only the leg *shape* eases in, not the vertical position.

---

## 48. Post-landing foot settle: drop the `moving` guard on the step trigger

**Problem:** after landing, `lastPlanted` still holds the tucked-up airborne
position. If the step trigger only fires while moving, a standing creature keeps
its feet floating near the belly until it walks somewhere.

**Fix:** allow steps whenever drift exceeds a threshold, but use a *tighter*
threshold when standing still so the feet settle silently without marching in place:

```lua
local threshold = if moving then stepDistance else stepDistance * 0.55
local canStep = (isActiveTurn) and drift > threshold
```

---

## 49. Avian / reverse-knee legs via pole placement

Birds, raptors, and owl-bears have legs that appear to bend backward at the knee
(actually the ankle — the real knee is hidden in feathers). The IK solver itself
does not care; the bend direction is entirely controlled by the pole target.

Place the pole *behind* the body (along `+LookVector`) instead of in front:

```lua
-- Positive kneeBend = forward (mammal knee, tree roots)
-- Negative kneeBend = backward (avian ankle, reverse-knee)
local poleWorld = mid - root.CFrame.LookVector * kneeBend
```

A negative `kneeBend` constant bends the joint rearward. No solver changes needed.

---

## 50. IKControl on a custom AnimationController rig

All of the above examples use a `Humanoid`-owned `Animator`. For creature rigs that
should not have a Humanoid (no health bar, no pathfinding side-effects), the same
`IKControl` approach works under an `AnimationController`:

```text
Model
  AnimationController
    Animator
    IKControl_FL  ← parent here, not under a Part
    IKControl_FR
    ...
```

The `IKControl` must be a direct child of the `AnimationController` (not the
`Animator`). ChainRoot and EndEffector must be `BasePart` descendants of the same
`Model`. Behavior is otherwise identical to the Humanoid case.

---

## 51. Body-bob layering under IK

Procedural body bob (the gentle rise-and-fall that makes a creature feel heavy and
alive) should be applied as a `Motor6D.C0` offset on a hip joint that sits *between*
the kinematic root and the rest of the skeleton — not on the root itself. This
keeps it entirely separate from the leg IK:

```text
PlayerRoot (kinematic)
  WeldConstraint → HipAnchor
    Motor6D (C0 bob/lean each frame) → Body
      Motor6D → UpperLeg (IKControl owns transform below here)
```

IK writes the leg-joint `Transform`; the bob writes the hip `C0`. They never
conflict because they target different joints.

---

## 52. A straight-built limb has *no* stride room — build the bend in

**Problem:** a leg built as a straight line from hip to foot (`mid =
hip:Lerp(foot, 0.5)`) makes the two bone segments sum to *exactly* the hip→foot
drop. The limb stands at full extension, so the IK solver has zero slack: any foot
target placed forward or back along the ground is farther from the hip than the leg
can reach, and the foot just lifts/lags near straight-down. The creature *shuffles
in place* no matter how you tune step distance — because the feet physically cannot
move horizontally and stay on the ground.

**Rule:** build a real bend into the rest pose so the bones sum **longer** than the
drop. Offset the mid (knee) joint off the straight line:

```lua
-- straight (no reach): mid is the midpoint, |upper|+|lower| == drop
-- bent  (has reach):   push mid back along +Z (or fwd), bones now sum > drop
local mid = root.CFrame:PointToWorldSpace(Vector3.new(x, midY, kneeBendZ))
```

A backward `kneeBendZ` also gives the avian Z-fold (see §49). Horizontal ground
reach is then `sqrt(legLen² − drop²)`; pick the bend so that comfortably exceeds
your stride amplitude. The leg should never be more than ~95% extended at the stride
extremes, or the knee locks and the foot looks stiff/reaching.

---

## 53. Fast bodies outrun two-foot alternation — plant the feet *forward*

**Problem:** when body speed is high relative to the leg's turnover, a strict
alternating biped (only one foot steps at a time) can't keep up. Each planted foot
is held in world space while the body races over it, so by the time its turn to step
comes it has been dragged far *behind* the hips — often past the leg's reach, where
it stretches out and floats. The feet visibly trail behind the creature.

**Rule:** plant each foot well *ahead* of the hips (a large "foot lead" in the move
direction). The body then sweeps over it and it ends up symmetrically *behind* by
lift-off — a centred stride (one foot forward, one back) instead of a backward drag.
Tune the lead to roughly half the per-step drag:

```lua
drag        = bodySpeed * stepDuration      -- how far a planted foot slides back
lead       ≈ drag / 2                       -- plant this far ahead → stride centres on the hips
swingLength = drag + lead                   -- the visible forward throw per step
```

Counter-intuitively, the fix for "feet stuck behind" is to reach them *further
forward*, not to step more often. Keep both stride extremes inside the reach from
§52.

---

## 54. Procedural bob/lean is inert unless the skeleton hangs off the bobbed joint

**Problem (a real shipped bug):** the bob `Motor6D` (§51) existed and its `C0` was
animated every frame — but its `Part1` (a "bob proxy") had **nothing parented below
it**. The body, legs, head, and tail were all welded directly to the kinematic root,
so driving the bob joint moved an invisible orphan and the creature never bounced or
leaned. Everything *looked* wired up; the bounce was simply a no-op.

**Rule:** the bobbed joint must be the **hub the skeleton hangs off**, not a
dead-end sibling. Body, limb roots, neck, and tail all parent through the bob proxy;
only the IK foot *targets* stay in world space:

```text
Root → Weld → HipAnchor → Motor6D(bob C0) → BobProxy
                                              ├─ Body / saddle
                                              ├─ Motor6D → UpperLeg  (IK foot pinned to ground)
                                              ├─ Motor6D → Neck/Head
                                              └─ Motor6D → Tail
```

Diagnostic: if a sibling secondary motion that uses the *same* `Motor6D.C0`
mechanism works (e.g. the tail wags) but the bob doesn't, the motors are fine — the
bobbed part just isn't carrying the skeleton.

---

## 55. Match secondary-motion cadence (and its smoothing) to the real foot turnover

A fast runner's legs cycle several times a second. If the body bob and arm swing run
at a fixed, slower cadence, the upper body heaves in slow motion over sprinting legs
and the whole run reads as weak and disconnected. Scale the cadence that drives bob /
arm-swing phase up with the gait so the bounce lands with the footfalls.

Then watch the *smoothing*: an exponential `approach()` toward an oscillating goal
attenuates the amplitude badly once the goal's frequency approaches the smoothing
rate. A fast bounce fed through a slow follow gets flattened to nothing. Scale the
follow rate with the cadence:

```lua
self.bob = approach(self.bob, bobGoal, dt, math.max(12, cadence * 1.6))
```

---

## 56. Position IK leaves the foot pointing wherever the chain lands

`Position`-type foot IK matches only *where* the foot lands; the solver is free to
leave its orientation wherever the chain happens to resolve. Round paws hide this,
but a foot with a clear front (talons, toes) ends up pointing sideways/backward as
the leg swings.

For directional feet, drive orientation explicitly. The cleanest is `Transform` IK
with the target carrying a full CFrame — face the toes along the body's travel and
align the sole to the ground normal (§11), set every frame after the position logic
so it covers every gait branch:

```lua
local up  = grounded and groundNormalAt(pos) or Vector3.yAxis
local fwd = (bodyForward - up * bodyForward:Dot(up)).Unit   -- flatten onto the ground plane
footTarget.CFrame = CFrame.lookAt(pos, pos + fwd, up)        -- -Z (toes) forward, sole down
```

As always with Roblox's negative-look convention, confirm visually and flip `fwd` if
the foot faces backward.

---

## 57. Look/aim "is this the local player?" gates miss ridden mounts — and non-players want an autonomous gaze

A camera-led head look usually gates on `LocalPlayer.Character == self.character`. A
**ridden mount's `character` is the mount model, not the rider**, so that gate is
always false and the head locks dead ahead. Accept the owning rider too:

```lua
if LocalPlayer.Character == (self.rideOwner or self.character) then ... end
```

And not every rig has a camera or a target. Give NPC/mob heads an **autonomous
wandering gaze** — every few seconds pick a fresh small yaw/pitch within a fraction
of the look range and ease toward it. A head that just glances around on its own
reads as alive with no target at all, and it layers cleanly under the gait-synced
neck pump (a per-stride fore/aft head bob; §51's cadence advice applies).

---

# References

- Roblox Creator Hub, `IKControl` class documentation.
- Roblox Creator Hub, `IKControlType` enum documentation.
- Roblox Creator Hub, Inverse Kinematics documentation.

