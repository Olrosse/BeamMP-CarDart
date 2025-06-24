local M = {} --metatable
local trackPrefabObj
local trackPrefabName
local currentArenaName
local currentLoadedArenaName
local allPoints = {[0] = true}
local ramps = {}
local blockedInputActionsOnRoundStart = {'slower_motion','faster_motion','toggle_slow_motion','modify_vehicle','vehicle_selector','saveHome','loadHome', 'reset_all_physics','toggleTraffic', "recover_vehicle", "recover_vehicle_alt", "recover_to_last_road", "reload_vehicle", "reload_all_vehicles", "parts_selector", "dropPlayerAtCamera", "nodegrabberRender",'reset_physics','dropPlayerAtCameraNoReset'} 
local colors = {{255,50,50,255}--[[Red]],{50,50,160,255}--[[Light Blue]],{50,255,50,255}--[[Green]],{200,200,25,255}--[[Yellow]],{150,50,195,255}--[[Purple]]}
local team = nil
local useFieldSystem

local arenaOffset = vec3()
local arenaRotOffsetEuler = vec3()
local arenaRotOffsetQuat = quat()
local floorHeight

local function customDump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. customDump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

local function CDAllowedResets(data, allowed)
	extensions.core_input_actionFilter.setGroup('sumo', data)
	extensions.core_input_actionFilter.addAction(0, 'sumo', not allowed)
end

local function CDGetTeamByID(ID)
	local metadata = jsonReadFile("art/" .. currentArenaName .. ".metadata.json")
	return (ID % #metadata.spawnLocations) + 1 --number of spawnLocations is the same as number of ramps, thus number of teams
end

local function CDSetTeamColor(applyTeamColor) --TODO: Fix this only working for owned vehicles
	for ID,veh in pairs(MPVehicleGE.getVehicles()) do 
		local vehicle = be:getObjectByID(veh.gameVehicleID)
		if not vehicle.originalColor then
			vehicle.originalColor = vehicle.color
		end
		if not vehicle.originalcolorPalette0 then
			vehicle.originalcolorPalette0 = vehicle.colorPalette0
		end
		if not vehicle.originalcolorPalette1 then
			vehicle.originalcolorPalette1 = vehicle.colorPalette1
		end
		if applyTeamColor then			
			vehicle.color 		  = ColorF(colors[CDGetTeamByID(veh.ownerID)][1] / 255, colors[CDGetTeamByID(veh.ownerID)][2] / 255, colors[CDGetTeamByID(veh.ownerID)][3] / 255, vehicle.originalColor.w):asLinear4F()
			vehicle.colorPalette0 = ColorF(colors[CDGetTeamByID(veh.ownerID)][1] / 255, colors[CDGetTeamByID(veh.ownerID)][2] / 255, colors[CDGetTeamByID(veh.ownerID)][3] / 255, vehicle.originalcolorPalette0.w):asLinear4F()
			vehicle.colorPalette1 = ColorF(colors[CDGetTeamByID(veh.ownerID)][1] / 255, colors[CDGetTeamByID(veh.ownerID)][2] / 255, colors[CDGetTeamByID(veh.ownerID)][3] / 255, vehicle.originalcolorPalette1.w):asLinear4F()
		else
			vehicle.color = ColorF(vehicle.originalColor.x, vehicle.originalColor.y, vehicle.originalColor.z, vehicle.originalColor.w):asLinear4F()
			vehicle.colorPalette0 = ColorF(vehicle.originalcolorPalette0.x, vehicle.originalcolorPalette0.y, vehicle.originalcolorPalette0.z, vehicle.originalcolorPalette0.w):asLinear4F()
			vehicle.colorPalette1 = ColorF(vehicle.originalcolorPalette1.x, vehicle.originalcolorPalette1.y, vehicle.originalcolorPalette1.z, vehicle.originalcolorPalette1.w):asLinear4F()
		end
	end
end

local function CDThisPlayerID()
	for ID,veh in pairs(MPVehicleGE.getOwnMap()) do return veh.ownerID end --don't know of an easier way to do this
end

local function CDTeleportToStart()
	local metadata = jsonReadFile("art/" .. currentArenaName .. ".metadata.json")
	local spawnLocations = metadata.spawnLocations[team]
	local spawnLocation = spawnLocations[(CDThisPlayerID() % #spawnLocations) + 1]
	for vehID, vehData in pairs(MPVehicleGE.getOwnMap()) do
		local veh = be:getObjectByID(vehID)
		if not veh then break end
		local finalSpawnPos = vec3(spawnLocation.x,spawnLocation.y,spawnLocation.z):rotated(arenaRotOffsetQuat)
		local q = quatFromEuler(math.rad(spawnLocation.rx), math.rad(spawnLocation.ry), math.rad(spawnLocation.rz)) * arenaRotOffsetQuat
		veh:setPositionRotation(finalSpawnPos.x + arenaOffset.x, finalSpawnPos.y + arenaOffset.y, finalSpawnPos.z + arenaOffset.z, q.x, q.y, q.z, q.w)
		veh:queueLuaCommand("recovery.startRecovering()") --fix up the car because it might have been damaged
		veh:queueLuaCommand("recovery.stopRecovering()")
	end
end


local function CDSetTeam()
	team = CDGetTeamByID(CDThisPlayerID())
	TriggerServerEvent("CDSetTeam", team)
end

local function CDRemoveArena()
	print("CDRemoveArena")
	CarDartpointsTracker.clearAllTargets()
	removePrefab(trackPrefabName)
	floorHeight = nil
	extensions['util_trackBuilder_splineTrack'].removeTrack()
	for _, objectName in pairs(scenetree.getAllObjects()) do
		if objectName:find("^procMesh") then 
			scenetree.findObject(objectName):delete()
		end
	end
	be:reloadStaticCollision()
	currentLoadedArenaName = nil
end

local function CDSetFreeze(freeze)
	for ID, veh in pairs(MPVehicleGE.getOwnMap()) do --freeze all the owned cars
		local vehicle = be:getObjectByID(ID)
		if vehicle then
			vehicle:queueLuaCommand('controller.setFreeze(' .. freeze .. ')')
			if tonumber(freeze) == 1 then
				vehicle:queueLuaCommand('if gliderPhysics then gliderPhysics.disableJumping() end')
				--vehicle:queueLuaCommand('if gliderPhysics then gliderPhysics.disableGliding() end')
			else
				vehicle:queueLuaCommand('if gliderPhysics then gliderPhysics.enableJumping() end')
				vehicle:queueLuaCommand('if gliderPhysics then gliderPhysics.enableGliding() end')
			end
		end
	end
end

local function CDStartRound()
	CDSetFreeze(0)
	TriggerServerEvent("CDSetScore", "0")
end

local function CDEndRound(removeArena)
	dump("removeArena",removeArena)
	if removeArena ~= "nil" then
		CDRemoveArena()
	end
	CDAllowedResets(blockedInputActionsOnRoundStart, true)
	CDSetTeamColor(false)
	CDSetFreeze(0)
	allPoints = {[0] = true}
	useFieldSystem = nil
end

local function CDSpawnArena(name)
	dump("CDSpawnArena")
	currentArenaName = name
	local metadata = jsonReadFile("art/" .. name .. ".metadata.json")
	trackPrefabName   = name
	if metadata.prefabLocation then
		arenaOffset = vec3(metadata.prefabLocation)
	end
	if metadata.prefabRotation then
		arenaRotOffsetEuler = vec3(metadata.prefabRotation)
		arenaRotOffsetQuat = quatFromEuler(metadata.prefabRotation.x,metadata.prefabRotation.y,metadata.prefabRotation.z)
	end

	trackPrefabObj = spawnPrefab(name, "art/" .. name .. ".prefab.json", ''..arenaOffset.x..' '..arenaOffset.y..' '..arenaOffset.z..'', ''..arenaRotOffsetEuler.x..' '..arenaRotOffsetEuler.y..' '..arenaRotOffsetEuler.z..'', '1 1 1') --the prefab is the target
	if trackPrefabObj then
		trackPrefabObj:setPosRot(arenaOffset.x,arenaOffset.y,arenaOffset.z,arenaRotOffsetQuat.x,arenaRotOffsetQuat.y,arenaRotOffsetQuat.z,arenaRotOffsetQuat.w)
	end

	if metadata.floorHeight then
		floorHeight = metadata.floorHeight
	end

	if metadata.useFieldSystem then
		CarDartpointsTracker.addTargets(name)
		useFieldSystem = true
		be:reloadStaticCollision(true)
	elseif name == "CDTarget" then
		for i=1,#metadata.spawnLocations do
			extensions['util_trackBuilder_splineTrack'].load(jsonReadFile("art/" .. name .. i .. ".json"), true, nil, nil, true, false) --calls reloadStaticCollision so should be called last.
		end
	end
	currentLoadedArenaName = name
end

local function onCDScoreTrigger(trigger)
	print(customDump(trigger))
	for ID, veh in pairs(MPVehicleGE.getOwnMap()) do
		if ID ~= trigger.subjectID then break end
		TriggerServerEvent("CDStrikePlayerOut", "nil")
		if trigger.event == "enter" then
			CDSetFreeze(1)
			allPoints[tonumber(trigger.points)] = true
		elseif trigger.event == "exit" then
			allPoints[tonumber(trigger.points)] = nil
			if #allPoints == 0 then
				CDSetFreeze(0)
			end
		end
		print("allPoints: " .. customDump(allPoints))
		TriggerServerEvent("CDSetScore", #allPoints or "0")
	end
end

local function onCDOutOfBoundsTrigger(trigger)
	print(customDump(trigger))
	if trigger.event ~= "enter" then return end

	local triggerObj = scenetree.findObject(trigger.triggerName)
	local position = triggerObj:getPosition()
	local boundingBox = triggerObj:getWorldBox():getExtents()
	local triggerRoof = position.z + (boundingBox.z/2)

	for ID, _ in pairs(MPVehicleGE.getOwnMap()) do
		if ID ~= trigger.subjectID then break end
		local veh = be:getObjectByID(ID)
		if veh then
			if  vec3(be:getObjectOOBBCenterXYZ(trigger.subjectID)).z < triggerRoof then -- TODO, make this check if center is in the trigger bounding box instead of just using altitude
				TriggerServerEvent("CDStrikePlayerOut", "nil")
				veh:queueLuaCommand("controller.setFreeze(1)")
				veh:queueLuaCommand("CarDartSpeedExplosion.explode()")
				veh:queueLuaCommand('if gliderPhysics then gliderPhysics.disableJumping() end')
				veh:queueLuaCommand('if gliderPhysics then gliderPhysics.disableGliding() end')
			end
		end
	end
end

local function CDPrepareRound(arena)
	if not currentLoadedArenaName or currentLoadedArenaName ~= arena then
		CDRemoveArena()
		CDSpawnArena(arena)
	end
	CDSetTeam()
	CDSetTeamColor(true)
	CDTeleportToStart()
	CDSetFreeze(1)
	CDAllowedResets(blockedInputActionsOnRoundStart, false)
end

local function onExtensionLoaded()
	loadDirRec("art/Shapes/CarDart")
	if MPGameNetwork then
		AddEventHandler("CDSpawnArena", CDSpawnArena)
		AddEventHandler("CDRemoveArena", CDRemoveArena)
		AddEventHandler("CDRemoveArena", CDRemoveArena)
		AddEventHandler("onCDScoreTrigger", onCDScoreTrigger)
		AddEventHandler("CDPrepareRound", CDPrepareRound)
		AddEventHandler("CDStartRound", CDStartRound)
		AddEventHandler("CDEndRound", CDEndRound)
		AddEventHandler("CDSetFreeze", CDSetFreeze)
		AddEventHandler("onCDOutOfBoundsTrigger", onCDOutOfBoundsTrigger)
	end
end

M.CDSpawnArena = CDSpawnArena
M.CDRemoveArena = CDRemoveArena
M.onCDScoreTrigger = onCDScoreTrigger
M.CDPrepareRound = CDPrepareRound
M.CDStartRound = CDStartRound
M.CDEndRound = CDEndRound
M.CDSetFreeze = CDSetFreeze
M.onCDOutOfBoundsTrigger = onCDOutOfBoundsTrigger
M.onExtensionLoaded = onExtensionLoaded --
return M --return the metatable	