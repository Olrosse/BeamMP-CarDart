--Author : Olrosse

local M = {}

--Variables-- 
-- can be changed live by replacing M with the lua file name and entering it into the VE console, 
-- for example to change the delay you would paste this into the console with your car selected speedExplosion.explosionDelay = your number

M.active = false -- if true it runs the code
M.explotionTriggerSpeed = 22.352 -- meters per second
M.autoEngage = true -- if true the "bomb" is armed as soon as you go above the set speed
M.explosionDelay = 5 -- how long you have to be under the TriggerSpeed for the car to explode
M.explosionIntensity = 1 -- how big the explosion is
M.explosionType = 1 -- type of explosion, 
-- 1 parts fly off and the car jumps in the air, 
-- 2 jumps in the air, but no parts intentially fly off
-- 3 parts fly off but car does't jump
-- 4 neither parts fly off nor does the car jump in the air, powertrain is still broken

local cog = vec3(0,0,0)
local exploding = false
local hasExploded = false
local explodingTimer = 0
local explosionDelayTimer = 0
local bombActive = false
local explosionDirectionalPush = vec3(0,0,6)

local function onExtensionLoaded()
    local totalMass = 0
    for k,v in pairs(v.data.nodes) do
        local mass = obj:getNodeMass(v.cid)
        local pos = v.pos
        cog = cog + (pos*mass)
        totalMass = totalMass + mass
    end
    cog = cog/totalMass
    electrics.values.explode = 0
end

local function explode()
    if not v.mpVehicleType or v.mpVehicleType == "L" or electrics.values.explode == 1 then
        electrics.values.explode = 1 --for beamMP sync
        fire.explodeVehicle()
        exploding = true
    end
end

local function isExploding(dt)

    -- enabling these can make the explosion more spectacular by sending all the parts flying off, but will look less realistic
    if M.explosionType == 1 or M.explosionType == 3 then
        beamstate.breakAllBreakgroups() -- all breakable parts fly off
        --beamstate.breakHinges() -- only things like doors will fly off

        -- if using any of the above then this loop should be enabled as well so doors dont stick at the latches
        for k, v in pairs(controller.getControllersByType("advancedCouplerControl")) do 
            v.detachGroup()
        end
    end

    for k,beam in pairs(v.data.beams) do -- breaks all breakable textures like lights and windows
        if beam.deformSwitches then
            material.switchBrokenMaterial(beam)
        end
    end

    for k,device in pairs(powertrain.getDevices()) do -- breaks all powertrain devices like the engine and such
        if device.onBreak then
            device:onBreak()
        end
    end
    
    local totalForce = vec3()

    local rot = quat(obj:getRotation())
    for k,node in pairs(v.data.nodes) do -- loops trough every node and applies a force away from the center of mass
        local cid = node.cid
        local forcedir = (node.pos-cog):rotated(rot):normalized()
        obj:applyForceVector(cid,forcedir*50000*M.explosionIntensity)
    end

    local cogRel = (cog):rotated(rot)
    local rvel = vec3(3,-3,0):rotated(quat(obj:getRotation()))
    local vel = (explosionDirectionalPush*M.explosionIntensity) + cogRel:cross(rvel)
    if M.explosionType == 1 or M.explosionType == 2 then
        obj:applyClusterLinearAngularAccel(0, vel*2000, rvel*2000) -- gives an upwards force to make the vehicle jump slightly
    end
 end

local function updateGFX(dt)

    if v.mpVehicleType and v.mpVehicleType == "R" then
        if electrics.values.explode == 1 and not hasExploded and not exploding then
            explode()
        end
    end

    if exploding then
        explodingTimer = explodingTimer + dt
        if explodingTimer > 0.06 and not hasExploded then
            isExploding(dt)
            hasExploded = true
        end
    end

    if not M.active or v.mpVehicleType and v.mpVehicleType == "R" then return end

    local speed = obj:getGroundSpeed()

    if bombActive and not hasExploded and speed < M.explotionTriggerSpeed then
        ui_message({txt = "You are too slow, exploding in "..math.floor((M.explosionDelay - explosionDelayTimer)+1,1)..""}, dt, "vehicle.explosiontimer","warning")
        explosionDelayTimer = explosionDelayTimer + dt
        if explosionDelayTimer > M.explosionDelay then
            explode()
        end
    elseif bombActive and not hasExploded and speed > M.explotionTriggerSpeed then
        if explosionDelayTimer ~= 0 then
            ui_message({txt = "good you are safe, recharging timer "..math.floor((M.explosionDelay - explosionDelayTimer)+1,1)..""}, dt, "vehicle.explosiontimer","timer")
        end
        explosionDelayTimer = math.max(0,explosionDelayTimer - dt)
    end

    if speed > M.explotionTriggerSpeed + 1 and M.autoEngage then
        bombActive = true
    end
end

local function onReset()
    electrics.values.explode = false
    exploding = false
    hasExploded = false
    bombActive = false
    explodingTimer = 0
    explosionDelayTimer = 0
end

M.updateGFX = updateGFX
M.onReset = onReset
M.onExtensionLoaded = onExtensionLoaded
M.explode = explode

return M