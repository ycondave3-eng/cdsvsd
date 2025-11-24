local Config = shared.cider

local uis = game:GetService("UserInputService")
local rs = game:GetService("RunService")
local players = game:GetService("Players")
local workspace = game:GetService("Workspace")
local coreGui = game:GetService("CoreGui")
local vm = game:GetService("VirtualInputManager")

local plr = players.LocalPlayer
local cam = workspace.CurrentCamera
local mouse = plr:GetMouse()

'Keybinds'] = {
        ['Aim Assist'] = 'Z',
        ['Silent Aim'] = 'Q',
        ['Trigger Bot Target'] = 'C',
        ['Trigger Bot Activate'] = 'MouseButton1',
        ['Speed'] = 'T',
        ['Inventory Sorter'] = 'F2',
        ['Panic'] = 'L',

local bodyParts = {
    "Head", "UpperTorso", "HumanoidRootPart", "LowerTorso",
    "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
    "LeftHand", "RightHand", "LeftUpperLeg", "RightUpperLeg",
    "LeftLowerLeg", "RightLowerLeg", "LeftFoot", "RightFoot"
}

local cameraAimbotLocked = false
local cameraAimbotTarget = nil
local characterList = {}
local lastUpdate = 0
local fovVisualizer = nil
local fovLines = {}
local speedModActive = false



local function getKey(key)
    return keycodes[key:upper()] or Enum.KeyCode.Unknown
end

local function isInFirstPerson()
    if not plr.Character or not plr.Character:FindFirstChild("Head") then return false end
    local distance = (cam.CFrame.Position - plr.Character.Head.Position).Magnitude
    return distance < 2
end

local function isValidCameraMode()
    local isFP = isInFirstPerson()
    local thirdPersonEnabled = Config['Camera Aimbot']['Camera Mode']['Third Person']
    local firstPersonEnabled = Config['Camera Aimbot']['Camera Mode']['First Person']

    if isFP then
        return firstPersonEnabled
    else
        return thirdPersonEnabled
    end
end

local function hasForcefield(char)
    if not Config['Universal Checks']['Forcefield'] then return false end
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("ForceField") then return true end
    end
    return false
end

local function validChar(char)
    if not char or not char.Parent then return false end

    if hasForcefield(char) then return false end

    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end

    return char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function wallCheck(targetPart)
    if not Config['Universal Checks']['Wall'] then return true end

    local origin = cam.CFrame.Position
    local direction = (targetPart.Position - origin)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { plr.Character }
    rayParams.IgnoreWater = true

    local result = workspace:Raycast(origin, direction, rayParams)

    if not result then return true end
    return targetPart.Parent:IsAncestorOf(result.Instance)
end

local function getClosestPoint(part, useCameraDirection)
    if not part or not part:IsA("BasePart") then return part.Position end

    local cf = part.CFrame
    local size = part.Size

    local rayOrigin, rayDirection

    if useCameraDirection then
        rayOrigin = cam.CFrame.Position
        rayDirection = cam.CFrame.LookVector
    else
        local mousePos = uis:GetMouseLocation()
        local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
        rayOrigin = mouseRay.Origin
        rayDirection = mouseRay.Direction
    end

    if size.Magnitude < 2 then
        lastBestPos = part.Position
        lastPointCheck = now
        return part.Position
    end

    local bestPos = part.Position
    local closestDist = math.huge

    local halfSize = size * 0.5


    for x = -1, 1, 0.2 do
        for y = -1, 1, 0.2 do
            for z = -1, 1, 0.2 do
                if math.abs(x) > 0.99 or math.abs(y) > 0.99 or math.abs(z) > 0.99 then
                    local localPos = Vector3.new(
                        x * halfSize.X,
                        y * halfSize.Y,
                        z * halfSize.Z
                    )

                    local worldPos = cf:PointToWorldSpace(localPos)
                    local pointToRay = worldPos - rayOrigin
                    local projectionLength = pointToRay:Dot(rayDirection)
                    local closestPointOnRay = rayOrigin + rayDirection * projectionLength
                    local distanceToRay = (worldPos - closestPointOnRay).Magnitude

                    if distanceToRay < closestDist then
                        closestDist = distanceToRay
                        bestPos = worldPos
                    end
                end
            end
        end
    end
    return bestPos
end

local function applyPrediction(part, position)
    if not part then return position end

    local velocity = part.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    local prediction = Config['Camera Aimbot']['Prediction']

    return position + Vector3.new(
        velocity.X * prediction.X,
        velocity.Y * prediction.Y,
        velocity.Z * prediction.Z
    )
end

local function getAllPlayers()
    local chars = {}

    for _, player in ipairs(players:GetPlayers()) do
        if player ~= plr and player.Character and validChar(player.Character) then
            table.insert(chars, player.Character)
        end
    end

    local botsFolder = workspace:FindFirstChild('Bots')
    if botsFolder then
        for _, bot in ipairs(botsFolder:GetChildren()) do
            if bot:FindFirstChild('Humanoid') and bot:FindFirstChild('HumanoidRootPart') and validChar(bot) then
                table.insert(chars, bot)
            end
        end
    end

    return chars
end

local function getCharacters()
    local now = tick()
    if now - lastUpdate > 0.5 then
        characterList = getAllPlayers()
        lastUpdate = now
    end
    return characterList
end

local function findTarget(char, useCameraDirection)
    if not char then return nil, nil end

    local hitTarget = Config['Camera Aimbot']['Hit Target']['Style']
    local bestPart, bestPos, bestDist = nil, nil, math.huge

    local rayOrigin, rayDirection
    if useCameraDirection then
        rayOrigin = cam.CFrame.Position
        rayDirection = cam.CFrame.LookVector
    else
        local mousePos = uis:GetMouseLocation()
        local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
        rayOrigin = mouseRay.Origin
        rayDirection = mouseRay.Direction
    end

    if hitTarget ~= "Closest Point" and hitTarget ~= "Closest Part" then
        local part = char:FindFirstChild(hitTarget)
        if part and part:IsA("BasePart") and wallCheck(part) then
            if hitTarget == "Closest Point" then
                bestPos = getClosestPoint(part, useCameraDirection)
            else
                bestPos = part.Position
            end
            return part, bestPos
        end
        return nil, nil
    end

    if hitTarget == "Closest Point" then
        local mousePos = uis:GetMouseLocation()
        local closestScreenDist = math.huge

        for _, partName in ipairs(bodyParts) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") and wallCheck(part) then
                local screenPos, onScreen = cam:WorldToViewportPoint(part.Position)
                if onScreen and screenPos.Z > 0 then
                    local screenDist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                    if screenDist < closestScreenDist then
                        closestScreenDist = screenDist
                        bestPart = part
                    end
                end
            end
        end

        if bestPart then
            bestPos = getClosestPoint(bestPart, useCameraDirection)
        end
    else
        for _, partName in ipairs(bodyParts) do
            local part = char:FindFirstChild(partName)
            if part and part:IsA("BasePart") then
                if wallCheck(part) then
                    local pos = part.Position

                    local pointToRay = pos - rayOrigin
                    local projectionLength = pointToRay:Dot(rayDirection)
                    local closestPointOnRay = rayOrigin + rayDirection * projectionLength
                    local distanceToRay = (pos - closestPointOnRay).Magnitude

                    if distanceToRay < bestDist then
                        bestDist = distanceToRay
                        bestPart = part
                        bestPos = pos
                    end
                end
            end
        end
    end

    return bestPart, bestPos
end

local function isWithinBoxFov(targetPos, char)
    if not char or not char:FindFirstChild("HumanoidRootPart") then return false end

    local rootPart = char:FindFirstChild("HumanoidRootPart")
    local fovX = Config['Camera Aimbot']['FOV']['X']
    local fovY = Config['Camera Aimbot']['FOV']['Y']

    local mousePos = uis:GetMouseLocation()

    local screenPos, visible = cam:WorldToViewportPoint(rootPart.Position)
    if not visible then return false end

    local boxWidth = fovX
    local boxHeight = fovY
    local boxCenter = Vector2.new(screenPos.X, screenPos.Y - 5)

    local mouseX, mouseY = mousePos.X, mousePos.Y
    local centerX, centerY = boxCenter.X, boxCenter.Y

    local inX = mouseX >= (centerX - boxWidth / 2) and mouseX <= (centerX + boxWidth / 2)
    local inY = mouseY >= (centerY - boxHeight / 2) and mouseY <= (centerY + boxHeight / 2)

    return inX and inY
end

local function getBestTarget()
    local chars = getCharacters()
    local bestChar, bestPart, bestPos = nil, nil, nil
    local closestDist = math.huge

    local mousePos = uis:GetMouseLocation()

    for _, char in ipairs(chars) do
        local part, pos = findTarget(char, false)
        if part and pos then
            local screenPos = cam:WorldToViewportPoint(pos)
            if screenPos.Z > 0 then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude

                if dist < closestDist then
                    closestDist = dist
                    bestChar = char
                    bestPart = part
                    bestPos = pos
                end
            end
        end
    end

    return bestChar, bestPart, bestPos
end

local function createFovVisualizer()
    if #fovLines > 0 then return end

    local circle = Drawing.new("Circle")
    circle.Visible = false
    circle.Color = Color3.fromRGB(50, 50, 50)
    circle.Transparency = 0.925
    circle.Thickness = 2
    circle.NumSides = 64
    circle.Filled = false
    table.insert(fovLines, circle)
end

local function destroyFovVisualizer()
    for _, line in ipairs(fovLines) do
        if line then
            line:Remove()
        end
    end
    fovLines = {}
end

local function isMouseInFov(mousePos, targetChar)
    if not targetChar then return false end

    local fov = math.rad(Config['Camera Aimbot']['FOV']['Value'])
    local fovRadius = (cam.ViewportSize.Y / 2) * math.tan(fov / 2)


    for _, partName in ipairs(bodyParts) do
        local part = targetChar:FindFirstChild(partName)
        if part and part:IsA("BasePart") and wallCheck(part) then
            local closestPoint = getClosestPoint(part, false)
            local screenPos, visible = cam:WorldToViewportPoint(closestPoint)

            if visible then
                local targetPoint = Vector2.new(screenPos.X, screenPos.Y)
                local mouseToTarget = targetPoint - mousePos
                local distance = mouseToTarget.Magnitude

                if distance <= fovRadius then
                    return true
                end
            end
        end
    end

    return false
end

local function getFovCirclePosition(targetChar)
    if not targetChar then return nil, nil, nil end

    local rootPart = targetChar:FindFirstChild("HumanoidRootPart")
    if not rootPart then return nil, nil, nil end

    local screenPos, visible = cam:WorldToViewportPoint(rootPart.Position)
    if not visible then return nil, nil, nil end

    local screenCenter = Vector2.new(cam.ViewportSize.X / 2, cam.ViewportSize.Y / 2)
    local fovRadius = math.tan(math.rad(Config['Camera Aimbot']['FOV']['Value'] / 2)) * cam.ViewportSize.Y
    local centerPoint = Vector2.new(screenPos.X, screenPos.Y - 5)

    return centerPoint, fovRadius, true
end

local function updateFovVisualizer()
    if not Config['Camera Aimbot']['FOV']['Visualize FOV'] then
        if #fovLines > 0 then
            for _, circle in ipairs(fovLines) do
                circle.Visible = false
            end
        end
        return
    end

    if #fovLines == 0 then createFovVisualizer() end
    if #fovLines == 0 then return end

    if Config['Camera Aimbot']['Enabled'] then
        local mousePos = uis:GetMouseLocation()
        local fov = math.rad(Config['Camera Aimbot']['FOV']['Value'])
        local fovRadius = (cam.ViewportSize.Y / 2) * math.tan(fov / 2)

        fovLines[1].Position = mousePos
        fovLines[1].Radius = fovRadius
        fovLines[1].Visible = true
    else
        fovLines[1].Visible = false
    end
end

local function updateCamera()
    if not cameraAimbotLocked or not cameraAimbotTarget then return end

    if not isValidCameraMode() then
        cameraAimbotLocked = false
        cameraAimbotTarget = nil
        return
    end

    if not validChar(cameraAimbotTarget) then
        cameraAimbotLocked = false
        cameraAimbotTarget = nil
        return
    end

    local part, pos = findTarget(cameraAimbotTarget, true)
    if not part or not pos then
        return
    end

    pos = applyPrediction(part, pos)

    local targetCF = CFrame.lookAt(cam.CFrame.Position, pos)

    local smoothing = Config['Camera Aimbot']['Smoothing']
    if not smoothing['Enabled'] then
        cam.CFrame = targetCF
        return
    end

    local easingStyleFirst = smoothing['Easing Style First']
    local easingStyleSecond = smoothing['Easing Style Second']
    local easingDirection = smoothing['EasingDirection']

    local smoothnessX = smoothing['Snappiness']['X']
    local smoothnessY = smoothing['Snappiness']['Y']
    local smoothnessZ = smoothing['Snappiness']['Z']

    local currentLookVector = cam.CFrame.LookVector
    local targetLookVector = targetCF.LookVector

    local yawDiff = math.atan2(targetLookVector.X, targetLookVector.Z) -
        math.atan2(currentLookVector.X, currentLookVector.Z)
    local pitchDiff = math.asin(targetLookVector.Y) - math.asin(currentLookVector.Y)

    local smoothness = smoothnessX
    if math.abs(yawDiff) > math.abs(pitchDiff) then
        smoothness = smoothnessX
    else
        if math.abs(pitchDiff) > 0.5 then
            smoothness = smoothnessY
        else
            smoothness = smoothnessZ
        end
    end

    if smoothing['Stick'] then
        local stickFactor = math.min(math.max(smoothness, 0), 1)
        smoothness = stickFactor
    end

    local function applyEasing(t, style, direction)
        if style == "Sine" then
            if direction == "In" then
                return 1 - math.cos(t * math.pi / 2)
            elseif direction == "Out" then
                return math.sin(t * math.pi / 2)
            elseif direction == "InOut" then
                return -(math.cos(t * math.pi) - 1) / 2
            end
        elseif style == "Quad" then
            if direction == "In" then
                return t * t
            elseif direction == "Out" then
                return 1 - (1 - t) * (1 - t)
            elseif direction == "InOut" then
                return t < 0.5 and 2 * t * t or 1 - math.pow(-2 * t + 2, 2) / 2
            end
        elseif style == "Cubic" then
            if direction == "In" then
                return t * t * t
            elseif direction == "Out" then
                return 1 - math.pow(1 - t, 3)
            elseif direction == "InOut" then
                return t < 0.5 and 4 * t * t * t or 1 - math.pow(-2 * t + 2, 3) / 2
            end
        elseif style == "Quart" then
            if direction == "In" then
                return t * t * t * t
            elseif direction == "Out" then
                return 1 - math.pow(1 - t, 4)
            elseif direction == "InOut" then
                return t < 0.5 and 8 * t * t * t * t or 1 - math.pow(-2 * t + 2, 4) / 2
            end
        elseif style == "Quint" then
            if direction == "In" then
                return t * t * t * t * t
            elseif direction == "Out" then
                return 1 - math.pow(1 - t, 5)
            elseif direction == "InOut" then
                return t < 0.5 and 16 * t * t * t * t * t or 1 - math.pow(-2 * t + 2, 5) / 2
            end
        elseif style == "Expo" then
            if direction == "In" then
                return t == 0 and 0 or math.pow(2, 10 * (t - 1))
            elseif direction == "Out" then
                return t == 1 and 1 or 1 - math.pow(2, -10 * t)
            elseif direction == "InOut" then
                if t == 0 then
                    return 0
                elseif t == 1 then
                    return 1
                elseif t < 0.5 then
                    return math.pow(2, 20 * t - 10) / 2
                else
                    return (2 - math.pow(2, -20 * t + 10)) / 2
                end
            end
        elseif style == "Circ" then
            if direction == "In" then
                return 1 - math.sqrt(1 - t * t)
            elseif direction == "Out" then
                return math.sqrt(1 - (t - 1) * (t - 1))
            elseif direction == "InOut" then
                return t < 0.5 and (1 - math.sqrt(1 - math.pow(2 * t, 2))) / 2 or
                    (math.sqrt(1 - math.pow(-2 * t + 2, 2)) + 1) / 2
            end
        elseif style == "Back" then
            local c1 = 1.70158
            local c2 = c1 + 1
            local c3 = c1 * 1.525
            if direction == "In" then
                return c3 * t * t * t - c1 * t * t
            elseif direction == "Out" then
                return 1 + c3 * math.pow(t - 1, 3) + c1 * math.pow(t - 1, 2)
            elseif direction == "InOut" then
                return t < 0.5 and (math.pow(2 * t, 2) * ((c2 + 1) * 2 * t - c2)) / 2 or
                    (math.pow(2 * t - 2, 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2
            end
        elseif style == "Elastic" then
            local c5 = (2 * math.pi) / 3
            local c6 = (2 * math.pi) / 4.5
            if direction == "In" then
                if t == 0 then
                    return 0
                elseif t == 1 then
                    return 1
                else
                    return -math.pow(2, 10 * (t - 1)) * math.sin((t * 10 - 10.75) * c6)
                end
            elseif direction == "Out" then
                if t == 0 then
                    return 0
                elseif t == 1 then
                    return 1
                else
                    return math.pow(2, -10 * t) * math.sin((t * 10 - 0.75) * c6) + 1
                end
            elseif direction == "InOut" then
                if t == 0 then
                    return 0
                elseif t == 1 then
                    return 1
                elseif t < 0.5 then
                    return -(math.pow(2, 20 * t - 10) * math.sin((20 * t - 11.125) * c5)) / 2
                else
                    return (math.pow(2, -20 * t + 10) * math.sin((20 * t - 11.125) * c5)) / 2 + 1
                end
            end
        elseif style == "Bounce" then
            local function bounceOut(t)
                local n1 = 7.5625
                local d1 = 2.75
                if t < 1 / d1 then
                    return n1 * t * t
                elseif t < 2 / d1 then
                    return n1 * (t - 1.5 / d1) * (t - 1.5 / d1) + 0.75
                elseif t < 2.5 / d1 then
                    return n1 * (t - 2.25 / d1) * (t - 2.25 / d1) + 0.9375
                else
                    return n1 * (t - 2.625 / d1) * (t - 2.625 / d1) + 0.984375
                end
            end
            if direction == "In" then
                return 1 - bounceOut(1 - t)
            elseif direction == "Out" then
                return bounceOut(t)
            elseif direction == "InOut" then
                return t < 0.5 and (1 - bounceOut(1 - 2 * t)) / 2 or (1 + bounceOut(2 * t - 1)) / 2
            end
        end
        return t
    end

    local eased = smoothness
    local halfPoint = 0.5

    if easingStyleFirst ~= easingStyleSecond then
        if smoothness < halfPoint then
            eased = applyEasing(smoothness * 2, easingStyleFirst, easingDirection)
            eased = eased / 2
        else
            eased = applyEasing((smoothness - halfPoint) * 2, easingStyleSecond, easingDirection)
            eased = (eased + 1) / 2
        end
    else
        eased = applyEasing(smoothness, easingStyleFirst, easingDirection)
    end

    cam.CFrame = cam.CFrame:Lerp(targetCF, eased)
end

local function toggleCameraAimbot()
    if cameraAimbotLocked then
        cameraAimbotLocked = false
        cameraAimbotTarget = nil
    else
        if not isValidCameraMode() then return end

        local target, part, pos = getBestTarget()
        if target then
            local mousePos = uis:GetMouseLocation()
            if isMouseInFov(mousePos, target) then
                cameraAimbotLocked = true
                cameraAimbotTarget = target
            end
        end
    end
end

uis.InputBegan:Connect(function(input, processed)
    if processed then return end

    local cameraAimbotKey = getKey(Config['Keybinds']['Camera Aimbot'])
    if input.KeyCode == cameraAimbotKey and Config['Camera Aimbot']['Enabled'] then
        toggleCameraAimbot()
    end

    local speedKey = getKey(Config['Keybinds']['Speed'])
    if input.KeyCode == speedKey then
        speedModActive = not speedModActive
    end
end)

rs.RenderStepped:Connect(function()
    if not Config['Camera Aimbot']['Enabled'] then
        if #fovLines > 0 then
            for _, circle in ipairs(fovLines) do
                circle.Visible = false
            end
        end
        return
    end

    updateFovVisualizer()

    if cameraAimbotLocked then
        updateCamera()
    end
end)

players.PlayerRemoving:Connect(function(player)
    if cameraAimbotTarget == player.Character then
        cameraAimbotLocked = false
        cameraAimbotTarget = nil
    end
end)

local TriggerBotConfig = Config['Trigger Bot']

local triggerBotLocked = false
local triggerBotLockedTarget = nil
local lastTriggerTime = 0
local triggerBotFovLines = {}

local function validCharTriggerBot(char)
    if not char or not char.Parent then return false end
    local humanoid = char:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return false end
    return char:FindFirstChild("HumanoidRootPart") ~= nil
end

local function getClosestPointTriggerBot(part, useCameraDirection)
    if not part or not part:IsA("BasePart") then return part.Position end

    local cf = part.CFrame
    local size = part.Size

    local rayOrigin, rayDirection

    if useCameraDirection then
        rayOrigin = cam.CFrame.Position
        rayDirection = cam.CFrame.LookVector
    else
        local mousePos = uis:GetMouseLocation()
        local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
        rayOrigin = mouseRay.Origin
        rayDirection = mouseRay.Direction
    end

    if size.Magnitude < 2 then
        return part.Position
    end

    local bestPos = part.Position
    local closestDist = math.huge

    local halfSize = size * 0.5

    for x = -1, 1, 0.2 do
        for y = -1, 1, 0.2 do
            for z = -1, 1, 0.2 do
                if math.abs(x) > 0.99 or math.abs(y) > 0.99 or math.abs(z) > 0.99 then
                    local localPos = Vector3.new(
                        x * halfSize.X,
                        y * halfSize.Y,
                        z * halfSize.Z
                    )

                    local worldPos = cf:PointToWorldSpace(localPos)
                    local pointToRay = worldPos - rayOrigin
                    local projectionLength = pointToRay:Dot(rayDirection)
                    local closestPointOnRay = rayOrigin + rayDirection * projectionLength
                    local distanceToRay = (worldPos - closestPointOnRay).Magnitude

                    if distanceToRay < closestDist then
                        closestDist = distanceToRay
                        bestPos = worldPos
                    end
                end
            end
        end
    end
    return bestPos
end

local function getCharacterFromPartTriggerBot(part)
    if not part then return nil end

    if part.Parent then
        local humanoid = part.Parent:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return part.Parent
        end
    end

    local current = part
    for i = 1, 5 do
        if not current or not current.Parent then break end
        current = current.Parent
        local humanoid = current:FindFirstChildOfClass("Humanoid")
        if humanoid then
            return current
        end
    end

    return nil
end

local function findTargetTriggerBot(char)
    if not char then return nil, nil end

    local bestPart, bestPos, bestDist = nil, nil, math.huge

    local mousePos = uis:GetMouseLocation()
    local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction

    for _, partName in ipairs(bodyParts) do
        local part = char:FindFirstChild(partName)
        if part and part:IsA("BasePart") and wallCheck(part) then
            local pos = getClosestPointTriggerBot(part, false)

            local pointToRay = pos - rayOrigin
            local projectionLength = pointToRay:Dot(rayDirection)
            local closestPointOnRay = rayOrigin + rayDirection * projectionLength
            local distanceToRay = (pos - closestPointOnRay).Magnitude

            if distanceToRay < bestDist then
                bestDist = distanceToRay
                bestPart = part
                bestPos = pos
            end
        end
    end

    return bestPart, bestPos
end

local function isCrosshairOnTarget(targetChar)
    if not targetChar or not targetChar:FindFirstChild("HumanoidRootPart") then return false end

    local mousePos = uis:GetMouseLocation()
    local mouseRay = cam:ViewportPointToRay(mousePos.X, mousePos.Y)

    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Blacklist
    rayParams.FilterDescendantsInstances = { plr.Character }
    rayParams.IgnoreWater = true

    local result = workspace:Raycast(mouseRay.Origin, mouseRay.Direction * 10000, rayParams)

    if not result or not result.Instance then return false end

    local hitChar = getCharacterFromPartTriggerBot(result.Instance)
    if hitChar and hitChar == targetChar then
        return true
    end

    return false
end

local function isTargetInFovTriggerBot(targetChar)
    if not targetChar then return false end

    local hrp = targetChar:FindFirstChild("HumanoidRootPart")
    if not hrp then return false end

    local fovValue = TriggerBotConfig['FOV']['Value']
    local mousePos = uis:GetMouseLocation()

    local screenPoint = cam:WorldToViewportPoint(hrp.Position)
    if screenPoint.Z <= 0 then return false end

    local screenPos = Vector2.new(screenPoint.X, screenPoint.Y)
    local distance = (screenPos - mousePos).Magnitude

    return distance <= fovValue
end

local function getBestTriggerBotTarget()
    local chars = getCharacters()
    local mousePos = uis:GetMouseLocation()
    local bestChar, bestPart, bestPos, bestDist = nil, nil, nil, math.huge

    for _, char in ipairs(chars) do
        local part, pos = findTargetTriggerBot(char)
        if part and pos then
            local screenPos = cam:WorldToViewportPoint(pos)
            if screenPos.Z > 0 then
                local dist = (Vector2.new(screenPos.X, screenPos.Y) - mousePos).Magnitude
                if dist < bestDist then
                    bestDist = dist
                    bestChar = char
                    bestPart = part
                    bestPos = pos
                end
            end
        end
    end

    return bestChar, bestPart, bestPos
end

local function shouldTrigger()
    if not TriggerBotConfig['Enabled'] then return false end
    if not triggerBotLocked or not triggerBotLockedTarget then return false end
    if not validCharTriggerBot(triggerBotLockedTarget) then
        triggerBotLocked = false
        triggerBotLockedTarget = nil
        return false
    end

    if TriggerBotConfig['Target Mode'] == "FOV" then
        if not isTargetInFovTriggerBot(triggerBotLockedTarget) then
            return false
        end
    elseif TriggerBotConfig['Target Mode'] == "Hitbox" then
        if not isCrosshairOnTarget(triggerBotLockedTarget) then
            return false
        end
    end

    local timingEnabled = TriggerBotConfig['Timing']['Enabled']
    local interval = timingEnabled and (TriggerBotConfig['Timing']['Interval'] / 1000) or 0.00000

    local now = tick()
    if now - lastTriggerTime < interval then
        return false
    end

    return true
end

local function performTrigger()
    if not shouldTrigger() then return end

    local mousePos = uis:GetMouseLocation()
    vm:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, true, game, 1)
    task.wait(0.05)

    mousePos = uis:GetMouseLocation()
    vm:SendMouseButtonEvent(mousePos.X, mousePos.Y, 0, false, game, 1)

    lastTriggerTime = tick()
end



local function updateTriggerBotFov()
    if not TriggerBotConfig['FOV']['Visualize FOV'] then
        if #triggerBotFovLines > 0 then
            for _, circle in ipairs(triggerBotFovLines) do
                circle.Visible = false
            end
        end
        return
    end

    if #triggerBotFovLines == 0 then
        local circle = Drawing.new("Circle")
        circle.Visible = false
        circle.Color = Color3.fromRGB(255, 255, 255)
        circle.Transparency = 1
        circle.Thickness = 2
        circle.NumSides = 64
        circle.Filled = false
        table.insert(triggerBotFovLines, circle)
    end

    local mousePos = uis:GetMouseLocation()
    local fovValue = TriggerBotConfig['FOV']['Value']

    triggerBotFovLines[1].Position = mousePos
    triggerBotFovLines[1].Radius = fovValue
    triggerBotFovLines[1].Visible = true
end

uis.InputBegan:Connect(function(input, processed)
    if processed or not TriggerBotConfig['Enabled'] then return end

    local key = getKey(Config['Keybinds']['Trigger Bot Target'])
    if input.KeyCode == key then
        if triggerBotLocked then
            triggerBotLocked = false
            triggerBotLockedTarget = nil
        else
            local targetChar, targetPart, targetPos = getBestTriggerBotTarget()
            if targetChar then
                triggerBotLocked = true
                triggerBotLockedTarget = targetChar
            end
        end
    end
end)

rs.RenderStepped:Connect(function()
    if not TriggerBotConfig['Enabled'] then return end

    updateTriggerBotFov()

    if triggerBotLocked and triggerBotLockedTarget then
        performTrigger()
    end
end)

players.PlayerRemoving:Connect(function(player)
    if triggerBotLockedTarget == player.Character then
        triggerBotLocked = false
        triggerBotLockedTarget = nil
    end
end)

local SilentAimConfig = Config['Silent Aim']

local silentAimTarget = nil
local panicMode = false

local silentFov = Drawing.new('Circle')
silentFov.Thickness = 1
silentFov.Radius = math.rad(SilentAimConfig['FOV']['Value']) * 100
silentFov.Color = Color3.fromRGB(0, 100, 255)
silentFov.Filled = false
silentFov.Transparency = 1
silentFov.Visible = SilentAimConfig['FOV']['Visualize'] and not panicMode

local silentTargetLine = Drawing.new('Line')
silentTargetLine.Thickness = 1
silentTargetLine.Color = Color3.fromRGB(255, 255, 255)
silentTargetLine.Transparency = 1
silentTargetLine.Visible = false

local function getGunBarrelSilent()
    local char = plr.Character
    if not char then return nil end
    for _, tool in pairs(char:GetChildren()) do
        if tool:IsA("Tool") and tool:FindFirstChild("Handle") then
            return tool.Handle
        end
    end
    return nil
end

local function calculate3DAngleSilent(origin, direction, targetPos)
    local toTarget = (targetPos - origin).Unit
    local dotProduct = direction:Dot(toTarget)
    dotProduct = math.clamp(dotProduct, -1, 1)
    local angleRadians = math.acos(dotProduct)
    return math.deg(angleRadians)
end

local function getClosestBodyPartSilent(player)
    if not player or not player.Character then return nil end
    if not validChar(player.Character) then return nil end

    local mousePos = uis:GetMouseLocation()
    local closestPart = nil
    local closestDistance = math.huge

    for _, partName in pairs(bodyParts) do
        local part = player.Character:FindFirstChild(partName)
        if part and wallCheck(part) then
            local worldPos = part.CFrame.Position
            local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
            if onScreen and screenPos.Z > 0 then
                local screenPosition = Vector2.new(screenPos.X, screenPos.Y)
                local deltaX = mousePos.X - screenPosition.X
                local deltaY = mousePos.Y - screenPosition.Y
                local distance = math.sqrt(deltaX ^ 2 + deltaY ^ 2)
                if distance < closestDistance then
                    closestDistance = distance
                    closestPart = part
                end
            end
        end
    end

    return closestPart, closestDistance
end

local function getClosestPlayerSilent()
    local mousePos = uis:GetMouseLocation()
    local closestPlayer = nil
    local closestDistance = math.huge

    for _, player in pairs(players:GetPlayers()) do
        if player ~= plr and player.Character and validChar(player.Character) then
            local part, distance = getClosestBodyPartSilent(player)
            if part and distance < closestDistance then
                closestPlayer = player
                closestDistance = distance
            end
        end
    end

    return closestPlayer
end

local function getClosestPointSilent(part)
    if not part or not part:IsA("BasePart") then return part.Position end

    local cf = part.CFrame
    local size = part.Size

    local mousePos = uis:GetMouseLocation()
    local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)
    local rayOrigin = mouseRay.Origin
    local rayDirection = mouseRay.Direction

    if size.Magnitude < 2 then
        return part.Position
    end

    local bestPos = part.Position
    local closestDist = math.huge

    local halfSize = size * 0.5

    for x = -1, 1, 0.2 do
        for y = -1, 1, 0.2 do
            for z = -1, 1, 0.2 do
                if math.abs(x) > 0.99 or math.abs(y) > 0.99 or math.abs(z) > 0.99 then
                    local localPos = Vector3.new(
                        x * halfSize.X,
                        y * halfSize.Y,
                        z * halfSize.Z
                    )

                    local worldPos = cf:PointToWorldSpace(localPos)
                    local pointToRay = worldPos - rayOrigin
                    local projectionLength = pointToRay:Dot(rayDirection)
                    local closestPointOnRay = rayOrigin + rayDirection * projectionLength
                    local distanceToRay = (worldPos - closestPointOnRay).Magnitude

                    if distanceToRay < closestDist then
                        closestDist = distanceToRay
                        bestPos = worldPos
                    end
                end
            end
        end
    end
    return bestPos
end

rs.RenderStepped:Connect(function()
    local mousePos = uis:GetMouseLocation()
    silentFov.Position = mousePos
    silentFov.Radius = math.rad(SilentAimConfig['FOV']['Value']) * 100
    silentFov.Visible = SilentAimConfig['FOV']['Visualize'] and not panicMode

    if SilentAimConfig['Target Line'] and silentAimTarget and silentAimTarget.Character and not panicMode then
        local hrpPart = silentAimTarget.Character:FindFirstChild('HumanoidRootPart')
        if hrpPart then
            local hrpWorldPos = hrpPart.CFrame.Position
            local hrpScreenPos, onScreen = cam:WorldToViewportPoint(hrpWorldPos)
            if onScreen and hrpScreenPos.Z > 0 then
                local hrpPosition = Vector2.new(hrpScreenPos.X, hrpScreenPos.Y)

                silentTargetLine.From = hrpPosition
                silentTargetLine.To = mousePos
                silentTargetLine.Visible = true
            else
                silentTargetLine.Visible = false
            end
        else
            silentTargetLine.Visible = false
        end
    else
        silentTargetLine.Visible = false
    end
end)

uis.InputBegan:Connect(function(input, processed)
    if processed then return end

    if input.KeyCode == getKey(Config['Keybinds']['Silent Aim']) then
        if SilentAimConfig['Target Mode'] == 'Target' then
            if silentAimTarget then
                silentAimTarget = nil
            else
                silentAimTarget = getClosestPlayerSilent()
            end
        end
    end
end)

local oldIndex
oldIndex = hookmetamethod(game, '__index', function(self, key)
    if self == mouse and key:lower() == 'hit' and SilentAimConfig['Enabled'] and not panicMode then
        local targetPlayer = nil

        if SilentAimConfig['Target Mode'] == 'Target' and silentAimTarget then
            targetPlayer = silentAimTarget
        elseif SilentAimConfig['Target Mode'] == 'Automatic' then
            targetPlayer = getClosestPlayerSilent()
        end

        if not targetPlayer then
            local dummy = workspace:FindFirstChild('Bots') and workspace.Bots:FindFirstChild('Dummy')
            if dummy and dummy:FindFirstChild('HumanoidRootPart') and dummy:FindFirstChild('Humanoid') and dummy.Humanoid.Health > 0 then
                targetPlayer = { Character = dummy, Name = 'Dummy' }
            end
        end

        if targetPlayer and targetPlayer.Character then
            local targetPart = nil
            local targetPosition = nil

            if SilentAimConfig['Hit Target']['Hit Part'] == 'Closest Part' then
                targetPart = getClosestBodyPartSilent(targetPlayer)
                if targetPart then
                    targetPosition = targetPart.Position
                end
            elseif SilentAimConfig['Hit Target']['Hit Part'] == 'Closest Point' then
                targetPart = getClosestBodyPartSilent(targetPlayer)
                if targetPart then
                    targetPosition = getClosestPointSilent(targetPart)
                end
            else
                targetPart = targetPlayer.Character:FindFirstChild(SilentAimConfig['Hit Target']['Hit Part'])
                if targetPart then
                    targetPosition = targetPart.Position
                end
            end

            if targetPart and targetPosition then
                local mousePos = uis:GetMouseLocation()
                local worldPos = targetPosition
                local screenPos, onScreen = cam:WorldToViewportPoint(worldPos)
                if onScreen and screenPos.Z > 0 then
                    local screenPosition = Vector2.new(screenPos.X, screenPos.Y)
                    local deltaX = mousePos.X - screenPosition.X
                    local deltaY = mousePos.Y - screenPosition.Y
                    local distance = math.sqrt(deltaX ^ 2 + deltaY ^ 2)

                    if distance <= (math.rad(SilentAimConfig['FOV']['Value']) * 100) then
                        local antiCurve = SilentAimConfig['FOV']['Anti Curve']

                        if antiCurve['Enabled'] and antiCurve['Mode'] == 'Angles' then
                            local gunBarrel = getGunBarrelSilent()
                            if gunBarrel then
                                local barrelPos = gunBarrel.Position
                                local targetPos = targetPosition
                                local cameraPos = cam.CFrame.Position
                                local mouseRay = cam:ScreenPointToRay(mousePos.X, mousePos.Y)

                                local toTarget = (targetPos - cameraPos).Unit
                                local aimDirection = mouseRay.Direction.Unit

                                local dotProduct = toTarget:Dot(aimDirection)
                                dotProduct = math.clamp(dotProduct, -1, 1)
                                local angle = math.deg(math.acos(dotProduct))

                                local distanceToTarget = (targetPos - barrelPos).Magnitude
                                local maxDistance = antiCurve['Angles']['Distance Threshold']
                                local maxAngle = antiCurve['Angles']['Max Angle']

                                if antiCurve['Angles']['Debug Print'] then
                                    print(string.format(
                                        "[Anti-Curve Debug] Current Angle: %.2f° | Max Angle: %.2f° | Distance: %.2f studs | Threshold: %.2f studs",
                                        angle, maxAngle, distanceToTarget, maxDistance))
                                end

                                if distanceToTarget <= maxDistance and angle > maxAngle then
                                    return oldIndex(self, key)
                                end
                            end
                        end

                        local velocity = targetPart.Parent:FindFirstChild('HumanoidRootPart') and
                            targetPart.Parent.HumanoidRootPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                        local predConfig = SilentAimConfig['Prediction']

                        local prediction
                        if predConfig['Power']['Enabled'] then
                            local predPower = predConfig['Power']['Prediction Power']
                            prediction = Vector3.new(
                                velocity.X * predConfig['X'] * predPower,
                                velocity.Y * predConfig['Y'] * predPower,
                                velocity.Z * predConfig['Z'] * predPower
                            )
                        else
                            prediction = Vector3.new(
                                velocity.X * predConfig['X'],
                                velocity.Y * predConfig['Y'],
                                velocity.Z * predConfig['Z']
                            )
                        end
                        local predictedPosition = targetPosition + prediction
                        return CFrame.new(predictedPosition)
                    end
                end
            end
        end
    end

    return oldIndex(self, key)
end)

players.PlayerRemoving:Connect(function(player)
    if silentAimTarget == player then
        silentAimTarget = nil
    end
end)


rs.RenderStepped:Connect(function()
    if not plr.Character then return end

    local humanoid = plr.Character:FindFirstChildOfClass("Humanoid")
    local rootPart = plr.Character:FindFirstChild("HumanoidRootPart")

    if not humanoid or not rootPart then return end

    local movementConfig = Config['Player Modification']['Movement']

    if not movementConfig or not movementConfig['Enable'] then return end


    local speedConfig = movementConfig['Speed Modification']
    if speedConfig and speedConfig['Enable'] and speedModActive then
        local speedValue = speedConfig['Value'] or 0.2

        humanoid.WalkSpeed = speedValue * 100
    end


    local slowdownConfig = movementConfig['Slowdown Modification']
    if slowdownConfig and slowdownConfig['Enable'] then
        local slowdownValue = slowdownConfig['Value'] or 1.0

        slowdownValue = math.clamp(slowdownValue, 0, 1)

        local friction = 1.0 * slowdownValue
        rootPart.CustomPhysicalProperties = PhysicalProperties.new(100, friction, 0.5)
    end
end)
