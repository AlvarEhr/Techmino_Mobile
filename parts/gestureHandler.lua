-- Gesture-based touch controls for mobile
-- Provides swipe-to-move, tap-to-rotate controls as an alternative to virtual buttons

local TIME=TIME

-- Gesture detection thresholds
local THRESHOLDS = {
    TAP_TIME = 0.2,              -- Max time for tap (seconds)
    TAP_DISTANCE = 10,           -- Max movement for tap (pixels) - reduced for responsiveness

    SWIPE_DISTANCE = 20,         -- Min distance to register as directional movement

    HARD_DROP_VELOCITY = 600,    -- Min downward velocity for hard drop (pixels/second)
    SOFT_DROP_VELOCITY = 100,    -- Min downward velocity for soft drop (pixels/second)
    HOLD_VELOCITY = 400,         -- Min upward velocity for hold (pixels/second)
}

-- Calculate pixels per cell from sensitivity setting
-- Scale 1-100 where 50 = 1:1 feel (54 px/cell matches visual cell size)
-- Sensitivity 1 = 103 px/cell (lowest sensitivity, very big swipes needed)
-- Sensitivity 50 = 54 px/cell (default, 1:1 feel)
-- Sensitivity 100 = 4 px/cell (highest sensitivity, tiny swipes work)
local function getPixelsPerCell()
    return 104 - (SETTING.gestureSensitivity or 50)
end

-- Gesture state tracking
local gesture = {
    active = false,
    touchID = nil,
    startX = 0,
    startY = 0,
    startTime = 0,
    currentX = 0,
    currentY = 0,
    lastX = 0,
    lastY = 0,
    lastTime = 0,
    velocityX = 0,
    velocityY = 0,

    -- Accumulated horizontal movement buffer (in pixels)
    -- When this exceeds getPixelsPerCell(), we move the piece and subtract
    horizontalBuffer = 0,

    -- Track which actions are currently active (for soft drop only now)
    activeActions = {
        softDrop = false,
    },

    -- Prevent double-triggering of instant actions
    instantActionFired = false,
}

local GESTURE = {}

-- Initialize gesture tracking on touch down
function GESTURE.touchDown(x, y, id)
    local now = TIME()

    gesture.active = true
    gesture.touchID = id
    gesture.startX = x
    gesture.startY = y
    gesture.startTime = now
    gesture.currentX = x
    gesture.currentY = y
    gesture.lastX = x
    gesture.lastY = y
    gesture.lastTime = now
    gesture.velocityX = 0
    gesture.velocityY = 0
    gesture.horizontalBuffer = 0
    gesture.instantActionFired = false
end

-- Update gesture state and detect gestures during touch movement
function GESTURE.touchMove(x, y, dx, dy, id, player)
    if not gesture.active or gesture.touchID ~= id then
        return
    end

    local now = TIME()
    local dt = now - gesture.lastTime

    -- Use a minimum dt to prevent velocity spikes
    if dt < 0.016 then dt = 0.016 end  -- Cap at ~60fps equivalent

    -- Update position
    gesture.currentX = x
    gesture.currentY = y

    -- Calculate total displacement from start
    local totalDX = x - gesture.startX
    local totalDY = y - gesture.startY
    local totalDistance = math.sqrt(totalDX * totalDX + totalDY * totalDY)
    local absTotalDX = math.abs(totalDX)
    local absTotalDY = math.abs(totalDY)

    -- Calculate velocity using total displacement over total time (more stable)
    local totalTime = now - gesture.startTime
    if totalTime < 0.016 then totalTime = 0.016 end
    local avgVelocityY = totalDY / totalTime

    -- Detect instant actions (hard drop, hold) - only fire once per gesture
    -- CRITICAL: Only trigger if swipe is PRIMARILY VERTICAL (prevents accidental triggers during horizontal swipes)
    if not gesture.instantActionFired and totalDistance > THRESHOLDS.SWIPE_DISTANCE then
        local isPrimarilyVertical = absTotalDY > absTotalDX * 1.5  -- Must be clearly more vertical than horizontal

        if isPrimarilyVertical then
            -- Fast downward swipe = Hard drop
            if avgVelocityY > THRESHOLDS.HARD_DROP_VELOCITY and totalDY > 50 then
                player:act_hardDrop()
                gesture.instantActionFired = true
                GESTURE._releaseAll(player)
                gesture.active = false
                return
            end

            -- Fast upward swipe = Hold
            if avgVelocityY < -THRESHOLDS.HOLD_VELOCITY and totalDY < -50 then
                player:act_hold()
                gesture.instantActionFired = true
                GESTURE._releaseAll(player)
                gesture.active = false
                return
            end
        end
    end

    -- Process horizontal movement (always, regardless of vertical movement)
    -- Add the frame's horizontal movement to the buffer
    gesture.horizontalBuffer = gesture.horizontalBuffer + dx

    -- Process moves when buffer exceeds threshold
    -- Directly manipulate curX to bypass DAS system entirely
    local pixelsPerCell = getPixelsPerCell()
    while gesture.horizontalBuffer >= pixelsPerCell do
        -- Move right: check collision and move directly
        if player.cur and not player:ifoverlap(player.cur.bk, player.curX + 1, player.curY) then
            player.curX = player.curX + 1
            player:freshMoveBlock()
        end
        gesture.horizontalBuffer = gesture.horizontalBuffer - pixelsPerCell
    end
    while gesture.horizontalBuffer <= -pixelsPerCell do
        -- Move left: check collision and move directly
        if player.cur and not player:ifoverlap(player.cur.bk, player.curX - 1, player.curY) then
            player.curX = player.curX - 1
            player:freshMoveBlock()
        end
        gesture.horizontalBuffer = gesture.horizontalBuffer + pixelsPerCell
    end

    -- Soft drop: only activate if moving primarily downward with sufficient velocity
    local isPrimarilyDown = absTotalDY > absTotalDX and totalDY > 20
    if isPrimarilyDown and avgVelocityY > THRESHOLDS.SOFT_DROP_VELOCITY then
        if not gesture.activeActions.softDrop then
            player:pressKey(7)  -- softDrop
            gesture.activeActions.softDrop = true
        end
    else
        -- Release soft drop if not moving down anymore
        if gesture.activeActions.softDrop then
            player:releaseKey(7)
            gesture.activeActions.softDrop = false
        end
    end

    gesture.lastX = x
    gesture.lastY = y
    gesture.lastTime = now
end

-- Handle touch release - finalize gesture detection
function GESTURE.touchUp(x, y, id, player)
    if not gesture.active or gesture.touchID ~= id then
        return
    end

    -- Calculate total displacement and duration
    local totalDX = x - gesture.startX
    local totalDY = y - gesture.startY
    local totalDistance = math.sqrt(totalDX * totalDX + totalDY * totalDY)
    local totalTime = TIME() - gesture.startTime

    -- Release any active continuous actions
    GESTURE._releaseAll(player)

    -- Detect tap (quick touch with minimal movement)
    if totalTime < THRESHOLDS.TAP_TIME and totalDistance < THRESHOLDS.TAP_DISTANCE then
        if not gesture.instantActionFired then
            player:act_rotRight()  -- Tap = Rotate right
        end
    end

    -- Reset gesture state
    gesture.active = false
    gesture.touchID = nil
    gesture.instantActionFired = false
end

-- Internal: Release all currently active continuous actions
function GESTURE._releaseAll(player)
    -- Only soft drop uses pressKey/releaseKey now
    -- Horizontal movement uses direct act_moveLeft/Right calls
    if gesture.activeActions.softDrop then
        player:releaseKey(7)
        gesture.activeActions.softDrop = false
    end
end

-- Check if gesture system is currently handling a touch
function GESTURE.isActive()
    return gesture.active
end

-- Reset gesture state (e.g., when game is paused)
function GESTURE.reset(player)
    if gesture.active and player then
        GESTURE._releaseAll(player)
    end
    gesture.active = false
    gesture.touchID = nil
    gesture.instantActionFired = false
end

return GESTURE
