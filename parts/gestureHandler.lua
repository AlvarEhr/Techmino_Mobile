-- Gesture-based touch controls for mobile
-- Provides swipe-to-move, tap-to-rotate controls as an alternative to virtual buttons

local TIME=TIME

-- Gesture detection thresholds
local THRESHOLDS = {
    TAP_TIME = 0.2,              -- Max time for tap (seconds)
    TAP_DISTANCE = 15,           -- Max movement for tap (pixels)

    SWIPE_DISTANCE = 30,         -- Min distance to register as directional movement

    HARD_DROP_VELOCITY = 600,    -- Min downward velocity for hard drop (pixels/second)
    SOFT_DROP_VELOCITY = 100,    -- Min downward velocity for soft drop (pixels/second)
    HOLD_VELOCITY = 400,         -- Min upward velocity for hold (pixels/second)

    HORIZONTAL_THRESHOLD = 20,   -- Min horizontal movement for left/right
}

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

    -- Track which actions are currently active (for continuous movement)
    activeActions = {
        moveLeft = false,
        moveRight = false,
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
    gesture.instantActionFired = false
end

-- Update gesture state and detect gestures during touch movement
function GESTURE.touchMove(x, y, dx, dy, id, player)
    if not gesture.active or gesture.touchID ~= id then
        return
    end

    local now = TIME()
    local dt = now - gesture.lastTime

    -- Avoid division by zero
    if dt < 0.001 then dt = 0.001 end

    -- Update position and velocity
    gesture.currentX = x
    gesture.currentY = y

    -- Calculate velocity (pixels per second)
    gesture.velocityX = dx / dt
    gesture.velocityY = dy / dt

    -- Calculate total displacement from start
    local totalDX = x - gesture.startX
    local totalDY = y - gesture.startY
    local totalDistance = math.sqrt(totalDX * totalDX + totalDY * totalDY)

    -- Detect instant actions (hard drop, hold) - only fire once per gesture
    if not gesture.instantActionFired and totalDistance > THRESHOLDS.SWIPE_DISTANCE then
        -- Fast downward swipe = Hard drop
        if gesture.velocityY > THRESHOLDS.HARD_DROP_VELOCITY then
            player:act_hardDrop()
            gesture.instantActionFired = true
            GESTURE._releaseAll(player)
            gesture.active = false
            return
        end

        -- Fast upward swipe = Hold
        if gesture.velocityY < -THRESHOLDS.HOLD_VELOCITY then
            player:act_hold()
            gesture.instantActionFired = true
            GESTURE._releaseAll(player)
            gesture.active = false
            return
        end
    end

    -- Continuous actions (movement, soft drop)
    -- Only activate if we've moved beyond the tap threshold
    if totalDistance > THRESHOLDS.TAP_DISTANCE then
        -- Horizontal movement (left/right)
        if math.abs(dx) > math.abs(dy) then
            -- Primarily horizontal movement
            if dx < -THRESHOLDS.HORIZONTAL_THRESHOLD then
                -- Moving left
                if not gesture.activeActions.moveLeft then
                    GESTURE._releaseAll(player)
                    player:pressKey(1)  -- moveLeft
                    gesture.activeActions.moveLeft = true
                end
            elseif dx > THRESHOLDS.HORIZONTAL_THRESHOLD then
                -- Moving right
                if not gesture.activeActions.moveRight then
                    GESTURE._releaseAll(player)
                    player:pressKey(2)  -- moveRight
                    gesture.activeActions.moveRight = true
                end
            end
        else
            -- Primarily vertical movement
            -- Slow downward movement = Soft drop
            if gesture.velocityY > THRESHOLDS.SOFT_DROP_VELOCITY then
                if not gesture.activeActions.softDrop then
                    GESTURE._releaseAll(player)
                    player:pressKey(7)  -- softDrop
                    gesture.activeActions.softDrop = true
                end
            end
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
    if gesture.activeActions.moveLeft then
        player:releaseKey(1)
        gesture.activeActions.moveLeft = false
    end
    if gesture.activeActions.moveRight then
        player:releaseKey(2)
        gesture.activeActions.moveRight = false
    end
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
