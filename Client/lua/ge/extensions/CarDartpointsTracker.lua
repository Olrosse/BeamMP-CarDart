local M = {}

local pointTargets = {}
local pointTriggers = {}
local triggerPoints = {}
local currentPoint = 0
local loadedLevel = ""

M.drawTargetDebug = false
--CarDartpointsTracker.drawTargetDebug = true

local function calculateTargetPoints(name,target,trigger)
    local triggerData = {}
    triggerData.position = trigger:getPosition() -- used as the center of the 2d circle, but i plan on doing something so we can have targets of different shapes
    triggerData.rotation = quat(trigger:getRotation()) -- this is to allow angled targets
    triggerData.targetPos = target:getPosition() -- currently used to calculate distance from the target surface, would need a height offset field to be accurate
    triggerData.disableGliderHeight = tonumber(trigger:getField("glider disable height",""))
    --triggerData.shape = trigger:getField("shape","")

    triggerData.totalPointSpaces = tonumber(trigger:getField("total point spaces","")) or 5
    triggerData.firstPoints = tonumber(trigger:getField("starting points","")) or triggerData.totalPointSpaces
    triggerData.pointsType = trigger:getField("points type","")
    local distanceMultiplier = tonumber(trigger:getField("distance multiplier","")) or 1
    triggerData.pointsStartDistance = (tonumber(trigger:getField("points start distance","")) or 0) * distanceMultiplier
    triggerData.pointsEndDistance = (tonumber(trigger:getField("points end distance","")) or 0) * distanceMultiplier

    triggerData.points = trigger:getField("points","") -- when using direct this is the points you get from entering the trigger
    return triggerData
end

local function findTriggers(targetName,target,iteration) -- uses the same iteration system as targets, just that it checks all triggers specified in the fields of the target object
    iteration = (iteration or 0) + 1
    local triggerName = target:getField("trigger"..iteration.."","")
    if triggerName ~= "" then
        local trigger = scenetree.findObject(triggerName)
        if trigger then -- if trigger exist, store the needed data
            local triggerData = calculateTargetPoints(targetName,target,trigger)
            pointTargets[targetName][triggerName] = triggerData
            pointTriggers[triggerName] = triggerData
            triggerPoints[triggerName] = 0
        end
        findTriggers(targetName,target,iteration)
    end
end

local function loopTargets(name,iteration) -- loop through all objects in the prefab that starts with the prefab name + iteration number, this should allow for multiple targets with different meshes
    iteration = (iteration or 0) + 1
    local targetName = name .. iteration
    local target = scenetree.findObject(name .."target"..iteration.."")
    if target then
        if not pointTargets[targetName] then
            pointTargets[targetName] = {}
        end
        findTriggers(targetName,target) -- find all triggers for this target
        loopTargets(name,iteration) -- if a target was found check again for another with the next number iteration
    end
end

local function addTargets(name)
    loopTargets(name)
    loadedLevel = name
end

local function clearAllTargets()
    pointTargets = {}
    pointTriggers = {}
    triggerPoints = {}
    currentPoint = 0
    loadedLevel = ""
end

local queueRecalculatePoints = false
local queueDelay = 0.100
local queueTimer = 0
local queueTimerFailSafe = 0

local function recalculatePoint() -- iterate through all triggers to find the highest scoring one
    local newPoint = 0

    for _,triggerPoint in pairs(triggerPoints) do
        newPoint = math.max(newPoint,triggerPoint)
    end

    if newPoint ~= currentPoint then
        currentPoint = newPoint
        TriggerServerEvent("CDSetScore", currentPoint or "0")
    end
end

local function onCDPointsTrackerTrigger(triggerData) --TODO make it possible to scale the target in all directions
	if not MPVehicleGE.isOwn(triggerData.subjectID) then return end
    local triggerCache = pointTriggers[triggerData.triggerName]
    if not triggerCache then return end
    if triggerData.event == "tick" or triggerData.event == "enter" and triggerData.shape then
        local newPoint
        local veh = be:getObjectByID(triggerData.subjectID)
        local carCenterPos = vec3(be:getObjectOOBBCenterXYZ(triggerData.subjectID))
        local carHeight = veh:getInitialHeight()
        local firstPoints = triggerCache.firstPoints
        local totalPointSpaces = triggerCache.totalPointSpaces
        local pointsType = triggerCache.pointsType
        local pointsStartDistance = triggerCache.pointsStartDistance or 0
        local pointsEndDistance = triggerCache.pointsEndDistance or 10
        local triggerRot = triggerCache.rotation
        local disableGliderHeight = triggerCache.disableGliderHeight
        local distanceFromTriggerCenter

        local carRelativePos = (vec3(carCenterPos) - triggerCache.position):rotated(triggerRot:inversed()) -- make car position relative to the trigger so the target can be in any rotation
        if disableGliderHeight and carRelativePos.z - (carHeight/2) < disableGliderHeight and triggerPoints[triggerData.triggerName] > 0 then
            CarDart.CDSetFreeze(1) -- if we are close enough to the ground then freeze pedals and disable glider
        end
        if triggerData.shape == "circle" then
            carRelativePos.z = 0 -- remove the Z coordinate so it acts as a circle instead of a sphere
            distanceFromTriggerCenter = vec3():distance(carRelativePos)

        elseif triggerData.shape == "direct" then -- directly set the points of the trigger,this won't be consistent with different vehicles since it's not using the center

            newPoint = triggerData.points or 0
        elseif triggerData.shape == "square" then

            carRelativePos.z = 0 -- remove the Z coordinate so it calculates in a square and not a cube
            distanceFromTriggerCenter = math.max(math.max(math.abs(carRelativePos.x), math.abs(carRelativePos.y)), math.abs(carRelativePos.z))
        elseif triggerData.shape == "triangle" then
            --TODO add logic for triangle shaped triggers
        end
        if distanceFromTriggerCenter then
            local range = ((math.max(0,distanceFromTriggerCenter - pointsStartDistance)/(pointsEndDistance - pointsStartDistance)))
            newPoint = math.floor(lerp(firstPoints,firstPoints - totalPointSpaces,range) + 1)
        end
        if pointsType == "inverse distance" then
            newPoint = (firstPoints - newPoint) + 1
        end
        if newPoint <= firstPoints - totalPointSpaces or newPoint > firstPoints then
            newPoint = 0
        end
        if newPoint then
            newPoint = math.max(0,newPoint)
        end
        if newPoint and newPoint ~= triggerPoints[triggerData.triggerName] then -- check to only update the point if it changed
            triggerPoints[triggerData.triggerName] = newPoint
            if newPoint == 0 then
                queueTimer = queueDelay
                queueRecalculatePoints = true
            else
                recalculatePoint()
            end
        end
    elseif triggerData.event == "exit" then
        triggerPoints[triggerData.triggerName] = 0
        queueTimer = queueDelay
        queueRecalculatePoints = true
    end
end

local isEditorActive = false
if editor and editor.isEditorActive() then
    isEditorActive = true
end

local colorMap = {}
colorMap[5] = ColorF(255/255, 170/255, 0/255,0.4)
colorMap[4] = ColorF(255/255, 0/255, 0/255, 0.4)
colorMap[3] = ColorF(0/255, 139/255, 255/255, 0.4)
colorMap[2] = ColorF(0/255, 0/255, 0/255, 0.4)
colorMap[1] = ColorF(255/255, 255/255, 255/255, 0.4)

local function targetDebugRenderer(dt)
    if not isEditorActive and not M.drawTargetDebug then return end
    for triggerName, data in pairs(pointTriggers) do
        local trigger = scenetree.findObject(triggerName)
        if trigger then
            local debugEnabled = trigger:getField("debugInEditor","")

            if debugEnabled == "1" or M.drawTargetDebug then
                local shape = trigger:getField("shape","")
                if shape == "circle" then
                    local triggerRot = quat(trigger:getRotation())
                    local triggerPos = trigger:getPosition()
                    local totalPointSpaces = tonumber(trigger:getField("total point spaces","")) or 5
                    local pointsType = trigger:getField("points type","")
                    local distanceMultiplier = tonumber(trigger:getField("distance multiplier","")) or 1
                    local pointsStartDistance = (tonumber(trigger:getField("points start distance","")) or 0) * distanceMultiplier
                    local pointsEndDistance = (tonumber(trigger:getField("points end distance","")) or 0) * distanceMultiplier
                    local firstPoints = tonumber(trigger:getField("starting points","")) or totalPointSpaces

                    local disableGliderHeight = tonumber(trigger:getField("glider disable height",""))
                    local frontLeftC =  triggerPos + vec3(pointsEndDistance *1.3,-pointsEndDistance*1.3,disableGliderHeight):rotated(triggerRot)
                    local frontRightC = triggerPos + vec3(-pointsEndDistance*1.3,-pointsEndDistance*1.3,disableGliderHeight):rotated(triggerRot)
                    local rearRightC =  triggerPos + vec3(-pointsEndDistance*1.3,pointsEndDistance *1.3,disableGliderHeight):rotated(triggerRot)
                    local rearLeftC =   triggerPos + vec3(pointsEndDistance *1.3,pointsEndDistance *1.3,disableGliderHeight):rotated(triggerRot)
                    local clr = color(128,128,128,128)
                    debugDrawer:drawTriSolid(frontLeftC, frontRightC, rearRightC, clr)
                    debugDrawer:drawTriSolid(rearRightC, rearLeftC, frontLeftC, clr)

                    debugDrawer:drawTriSolid(frontLeftC, rearLeftC, rearRightC, clr)
                    debugDrawer:drawTriSolid(rearRightC, frontRightC, frontLeftC, clr)

                    for i=1,totalPointSpaces do
                        local pointStart = lerp(pointsStartDistance,pointsEndDistance, (i-1)/totalPointSpaces)
                        local pointEnd = lerp(pointsStartDistance,pointsEndDistance, i/totalPointSpaces)
                        local middle = lerp(pointStart,pointEnd,0.5)
                        local range = ((math.max(0,middle - pointsStartDistance)/(pointsEndDistance - pointsStartDistance)))
                        local point = math.floor(lerp(firstPoints,firstPoints - totalPointSpaces,range) + 1)
                        local scale = pointEnd-pointStart
                        if pointsType == "inverse distance" then
                            point = (firstPoints - point) + 1
                        end
                        if point <= firstPoints - totalPointSpaces or point > firstPoints then
                            point = 0
                        end
                        if point then
                            point = math.max(0,point)
                        end
                        local count = math.floor(10*i)
                        local lastRot = quatFromAxisAngle(vec3(0,0,1),math.rad(lerp(0,360,0/count)))
                        for b=1,count do
                            local rot = quatFromAxisAngle(vec3(0,0,1),math.rad(lerp(0,360,b/count)))
                            local pos = vec3(middle,0,0):rotated(lastRot)
                            pos = pos:rotated(triggerRot)
                            local newpos = vec3(middle,0,0):rotated(rot)
                            newpos = newpos:rotated(triggerRot)
                            debugDrawer:drawCylinder(triggerPos + pos, triggerPos + newpos, scale/2, colorMap[point] or ColorF(255/255, 255/255, 255/255, 0.1))
                            lastRot = rot
                        end
                    end
                elseif shape == "square" then
                    local triggerRot = quat(trigger:getRotation())
                    local triggerPos = trigger:getPosition()
                    local totalPointSpaces = tonumber(trigger:getField("total point spaces",""))
                    local pointsType = trigger:getField("points type","")
                    local distanceMultiplier = tonumber(trigger:getField("distance multiplier","")) or 1
                    local pointsStartDistance = (tonumber(trigger:getField("points start distance","")) or 0) * distanceMultiplier
                    local pointsEndDistance = (tonumber(trigger:getField("points end distance","")) or 0) * distanceMultiplier
                    local firstPoints = tonumber(trigger:getField("starting points","")) or totalPointSpaces

                    local disableGliderHeight = tonumber(trigger:getField("glider disable height",""))
                    local frontLeftC =  triggerPos + vec3(pointsEndDistance,-pointsEndDistance,disableGliderHeight):rotated(triggerRot)
                    local frontRightC = triggerPos + vec3(-pointsEndDistance,-pointsEndDistance,disableGliderHeight):rotated(triggerRot)
                    local rearRightC =  triggerPos + vec3(-pointsEndDistance,pointsEndDistance,disableGliderHeight):rotated(triggerRot)
                    local rearLeftC =   triggerPos + vec3(pointsEndDistance,pointsEndDistance,disableGliderHeight):rotated(triggerRot)

                    debugDrawer:drawTriSolid(frontLeftC, frontRightC, rearRightC, color(128,128,128,128))
                    debugDrawer:drawTriSolid(rearRightC, rearLeftC, frontLeftC, color(128,128,128,128))

                    for i=1,totalPointSpaces do
                        local pointStart = lerp(pointsStartDistance,pointsEndDistance, (i-1)/totalPointSpaces)
                        local pointEnd = lerp(pointsStartDistance,pointsEndDistance, i/totalPointSpaces)
                        local middle = lerp(pointStart,pointEnd,0.5)
                        local posL = vec3(pointEnd,middle,0):rotated(triggerRot)
                        local posR = vec3(-pointEnd,middle,0):rotated(triggerRot)
                        local range = ((math.max(0,middle - pointsStartDistance)/(pointsEndDistance - pointsStartDistance)))
                        local point = math.floor(lerp(firstPoints,firstPoints - totalPointSpaces,range) + 1)
                        local size = pointEnd-pointStart
                        if pointsType == "inverse distance" then
                            point = (firstPoints - point) + 1
                        end
                        if point <= firstPoints - totalPointSpaces or point > firstPoints then
                            point = 0
                        end
                        if point then
                            point = math.max(0,point)
                        end
                        debugDrawer:drawSquarePrism(triggerPos + posL, triggerPos + posR, Point2F(size,size), Point2F(size,size), colorMap[point] or  ColorF(255/255, 255/255, 255/255, 0.1))

                        posL = vec3(pointEnd,-middle,0):rotated(triggerRot)
                        posR = vec3(-pointEnd,-middle,0):rotated(triggerRot)
                        debugDrawer:drawSquarePrism(triggerPos + posL, triggerPos + posR, Point2F(size,size), Point2F(size,size), colorMap[point] or  ColorF(255/255, 255/255, 255/255, 0.1))

                        posL = vec3(-middle,pointStart,0):rotated(triggerRot)
                        posR = vec3(-middle,-pointStart,0):rotated(triggerRot)
                        debugDrawer:drawSquarePrism(triggerPos + posL, triggerPos + posR, Point2F(size,size), Point2F(size,size), colorMap[point] or  ColorF(255/255, 255/255, 255/255, 0.1))

                        posL = vec3(middle,pointStart,0):rotated(triggerRot)
                        posR = vec3(middle,-pointStart,0):rotated(triggerRot)
                        debugDrawer:drawSquarePrism(triggerPos + posL, triggerPos + posR, Point2F(size,size), Point2F(size,size), colorMap[point] or  ColorF(255/255, 255/255, 255/255, 0.1))
                    end
                end
            end
        end
    end
end

local function onUpdate(dt)
    targetDebugRenderer(dt)
    if queueRecalculatePoints then
        queueTimer = queueTimer - dt
        queueTimerFailSafe = queueTimerFailSafe + dt
        if queueTimer < 0 or queueTimerFailSafe > 1 then
            queueRecalculatePoints = false
            queueTimerFailSafe = 0
            recalculatePoint()
        end
    end
end

local function onEditorActivated()
    isEditorActive = true
end

local function onEditorDeactivated()
    isEditorActive = false
end

M.onUpdate = onUpdate
M.addTargets = addTargets
M.clearAllTargets = clearAllTargets
M.onCDPointsTrackerTrigger = onCDPointsTrackerTrigger
M.onEditorActivated = onEditorActivated
M.onEditorDeactivated = onEditorDeactivated

return M