local automaticTrackSelection = true
local track = ""
local possibleTracks = {}
local totalPlayerScore = {}
local playerScore = {}
local teamScore = {}
local teams = {}
local teamColors = {"Red","Light Blue","Green","Yellow","Purple"}
local playersThatAreOut = {}
local timeNotifyOffset = 15 --s
local roundLength = 90 --s
local time = 0 --s
local startWaitTime = 10 --s 
local roundRunning = false
local autoRounds = false
--TODO: fix countdown going slow
--TODO: fix teamScore
--TODO: fix being able to jump before start in glider mod

local function CDStartRound()
	if automaticTrackSelection then
		track = possibleTracks[math.random(#possibleTracks)]
	end
	playersThatAreOut = {}
	for k, playername in pairs(MP.GetPlayers()) do
		playerScore[playername] = 0
	end
	MP.TriggerClientEvent(-1, "CDPrepareRound", track)
	MP.TriggerClientEvent(-1, "CDSetFreeze", "1")
end

function onChatMessage(playerID, playerName, message)
	print("chatMessage: " .. message)
	if string.find(message, "/cardart ") then
		message = string.gsub(message, "/cardart ", "")
		print(message)
		if string.find(message, "start round") then
			autoRounds = false
			roundRunning = true
			CDStartRound()
		elseif string.find(message, "start auto") then
			autoRounds = true
			roundRunning = true
			CDStartRound()
		-- elseif string.find(message, "list tracks") then --TODO: add track selection stuff
		-- 	MP.SendChatMessage(playerID, "Tracks: " .. Util.JsonEncode(possibleTracks))
		elseif string.find(message, "stop") then
			MP.TriggerClientEvent(-1, "CDEndRound", "1")
			roundRunning = false
			playerScore = {}
			teams = {}
			track = ""
			time = 0
		end
		return 1
	end
end

function onPlayerJoin(playerID)
	if track ~= "" then
		MP.TriggerClientEvent(playerID, "CDSpawnTrack", track)
	end
end

function CDStrikePlayerOut(playerID)
	playersThatAreOut[MP.GetPlayerName(playerID)] = true
	print("CDStrikePlayerOut called " .. playerID .. Util.JsonEncode(playersThatAreOut)) 
end

function CDSetTeam(playerID, team)
	team = tonumber(team)
	if teams[team] == nil then
		teams[team] = {}
	end
	table.insert(teams[team], MP.GetPlayerName(playerID))
	if teamScore[team] == nil then
		teamScore[team] = {}
	end
	teamScore[team][MP.GetPlayerName(playerID)] = {}
	print("CDSetTeam called " .. playerID .. " " .. team .. " " .. Util.JsonEncode(teams) .. " " .. Util.JsonEncode(teamScore))
end

function CDSetScore(playerID, score)
	print("Player " .. playerID .. " scored " .. score .. " points")
	score = tonumber(score)
	playerScore[MP.GetPlayerName(playerID)] = score
	-- print("" .. team .. " " .. Util.JsonEncode(teamScore))
end

function CDTimer()
	if not roundRunning then return end
	if time < startWaitTime then
		MP.TriggerClientEvent(-1, "CDSetFreeze", "1") --this function relies on timing for some reason, so just spam the fucker
	end
	if time < startWaitTime and time >= startWaitTime - timeNotifyOffset then
		MP.SendChatMessage(-1, "Round starts in " .. startWaitTime - time .. "s")
	elseif time == startWaitTime then
		MP.TriggerClientEvent(-1, "CDStartRound", "nil")
		MP.SendChatMessage(-1, "Round started, hit the middle of the target! You have " .. roundLength / 60 .. " minutes before the round ends.")
	end
	if time >= startWaitTime and time < roundLength then
		-- print("Players that are out: " .. Util.JsonEncode(playersThatAreOut) .. " " .. Util.JsonEncode(playerScore))
		local amountOfPlayersThatAreOut = 0
		local amountOfPlayers = 0
		for _,_ in pairs(playersThatAreOut) do amountOfPlayersThatAreOut = amountOfPlayersThatAreOut + 1 end
		for _,_ in pairs(playerScore) do amountOfPlayers = amountOfPlayers + 1 end
		if amountOfPlayers == amountOfPlayersThatAreOut then time = roundLength end
	end
	if time >= roundLength + startWaitTime then
		MP.TriggerClientEvent(-1, "CDEndRound", "nil")
		time = 0
		if not autoRounds then
			roundRunning = false
		end
		print(Util.JsonEncode(playerScore) .. " " .. Util.JsonEncode(totalPlayerScore) .. " " .. Util.JsonEncode(teamScore))
		for name, score in pairs(playerScore) do
			if totalPlayerScore[name] ~= nil then
				totalPlayerScore[name] = totalPlayerScore[name] + score
			else
				totalPlayerScore[name] = tonumber(score)
			end
			MP.SendChatMessage(-1, "" .. name .. " scored " .. score .. " points this round!") 
		end
		MP.SendChatMessage(-1, "Bringing the total scores to: ")
		for name, score in pairs(totalPlayerScore) do
			MP.SendChatMessage(-1, "" .. name .. ": " .. score .. " points!")
		end
		print(Util.JsonEncode(teams))
		for team, players in pairs(teams) do
			print(team .. " " .. Util.JsonEncode(players))
			teamScore[team] = {}
			for playername, score in pairs(totalPlayerScore) do 
				if teamScore[team][playername] ~= nil then
					teamScore[team][playername] = teamScore[team][playername] + score
				else
					teamScore[team][playername] = score --table index is nil? TODO FIXME BUGME 
				end
			end
		end
		MP.SendChatMessage(-1, "Teamscore: ")
		print("Teamscore: " .. Util.JsonEncode(teamScore))
		for team, players in pairs(teamScore) do
			for playername, _ in pairs(totalPlayerScore) do
				if not teamScore[team].totalScore then
					teamScore[team].totalScore = teamScore[team][playername]
				else
					teamScore[team].totalScore = teamScore[team].totalScore + teamScore[team][playername]
				end
			end
			MP.SendChatMessage(-1, "" .. teamColors[team] .. ": " .. teamScore[team].totalScore)
		end
		if autoRounds then
			CDStartRound()
		end
	elseif time >= roundLength + startWaitTime - timeNotifyOffset then
		MP.SendChatMessage(-1, "Round ending in " .. roundLength + startWaitTime - time .. "s")
	end
	time = time + 1
end

function onInit() 
	MP.RegisterEvent("onChatMessage", "onChatMessage")
	MP.RegisterEvent("onPlayerJoin", "onPlayerJoin")
	MP.RegisterEvent("CDSetScore", "CDSetScore")
	MP.RegisterEvent("CDSetTeam", "CDSetTeam")
	MP.RegisterEvent("CDStrikePlayerOut","CDStrikePlayerOut")

	MP.CancelEventTimer("CDSecond")
	MP.CreateEventTimer("CDSecond",1000) 
	MP.RegisterEvent("CDSecond", "CDTimer")
	
	local file = io.open("Resources/Server/CarDart/trackNames.json", "r")
	if not file then 
		print("trackNames.json not found")
		return
	end
	possibleTracks = Util.JsonDecode(file:read("*a"))
	file:close()
	print("--------------------CarDart loaded------------------------")

end
