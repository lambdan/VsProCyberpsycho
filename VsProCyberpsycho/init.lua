local VsProCyberpsycho = {
	title = "V's Pro Cyberpsycho 2077",
	version = "2.0-dev"
}

local GameSession = require("Modules/GameSession.lua")
local GameSettings = require("Modules/GameSettings.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")
local LEX = require("Modules/LuaEX.lua")

local SETTINGS_FILE = "settings.2.0.json"

local MOD_SETTINGS = {
	points = {
		base = 100,
		police = 200,
		ganger = 200,
		cyberpsycho = 1000
	},
	timeLimit = 10,
	speedBonusWindow = 1.0,
	showDisplay = true,
	music = 0,
	soundEffects = false, -- cant really hear them during the action anyway
	showEndMessage = "always"
}

local SESSION_DATA = { -- persists
	bestPoints = 0,
	bestKills = 0,
	bestDuration = 0,
	totalKills = 0,
	totalPoints = 0,
	totalDuration = 0,
	totalKillstreaks = 0,
	victims = {}
}

local w,h = 1920, 1080
local displayW, displayH = w-300, h-500
local displayFontSize = 2

local HUDMessage_Current = ""
local HUDMessage_Last = 0
local showDisplay = true -- used for hiding when pausing game etc
local isPaused = true
local isInGame = false

local killstreak -- see function resetKillstreak()

registerHotkey("vpcs_showRecords", "Show stats", function()
	if SESSION_DATA.totalKillstreaks < 1 then -- avoid divide by 0 things
		showCustomShardPopup("V's Pro Cyberpsycho Stats", "No stats to show... yet")
	else
		local s = ""
		s = s .. "Killstreaks: " .. tostring(SESSION_DATA.totalKillstreaks) .. "\n"
		s = s .. "Kills: " .. tostring(SESSION_DATA.totalKills) .. "     " .. "(average: " .. string.format("%.1f", SESSION_DATA.totalKills/SESSION_DATA.totalKillstreaks) .. ")\n"
		s = s .. "Points: " .. tostring(SESSION_DATA.totalPoints) .. "     " .. "(average: " .. string.format("%.1f", SESSION_DATA.totalPoints/SESSION_DATA.totalKillstreaks) .. ")\n"
		s = s .. "Durations: " .. string.format("%.0f", SESSION_DATA.totalDuration) .. " secs     (average: "  .. string.format("%.1f", SESSION_DATA.totalDuration/SESSION_DATA.totalKillstreaks) .. " secs)\n"
		
		s = s .. "\nVictims:\n"
		for k,v in pairs(SESSION_DATA.victims) do
			s = s .. "- " .. v.name .. " (" .. tostring(v.killed) .. " killed)\n"
		end
		showCustomShardPopup("V's Pro Cyberpsycho Stats", s)

	end
end)


function IsPlayer(target)
	return target and target:GetEntityID().hash == Game.GetPlayer():GetEntityID().hash
end

function GetInfo(target)
	local result = "Unknown"
	local full_string = ""
	local groups = {}

	-- Reaction Group: Civilian, Ganger, Police
	if target:GetStimReactionComponent() then
		local reactionGroup = target:GetStimReactionComponent():GetReactionPreset():ReactionGroup()

		if reactionGroup then
			table.insert(groups, reactionGroup)
		end
	end

	-- Character Type: Human, Android, etc.
	table.insert(groups, target:GetRecord():CharacterType():Type().value)

	-- Tags: Cyberpsycho
	for _, tag in ipairs(target:GetRecord():Tags()) do
		table.insert(groups, Game.NameToString(tag))
	end

	-- Visual Tags: Affiliation, Role, etc.
	for _, tag in ipairs(target:GetRecord():VisualTags()) do
		table.insert(groups, Game.NameToString(tag))
	end

	for k,v in ipairs(groups) do
		--print(k,v)
		if full_string == "" then
			full_string = v
		elseif (v ~= "") then
			full_string = full_string .. " " .. (v)
		end
	end

	return full_string
end

registerForEvent('onShutdown', function()
	GameSession.TrySave()
end)

registerForEvent('onUpdate', function(delta)
	if (not isPaused) and (isInGame) and (killstreak.started) then
		killstreak.duration = killstreak.duration + delta

		if killstreak.duration >= killstreak.timeLimit then
			endKillstreak()
		end
	end
end)

registerForEvent('onInit', function()
	loadSettings()
	resetKillstreak()
	isInGame = Game.GetPlayer() and Game.GetPlayer():IsAttached() and not Game.GetSystemRequestsHandler():IsPreGame()

	GameSession.StoreInDir('Sessions')
	GameSession.Persist(SESSION_DATA)

	--originalCarVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
	--originalMusicVolume = GameSettings.Get("/audio/volume/MusicVolume")

	--if not load_settings(userSettingsFile) then
	--	TryAutoPosition()
	--end

	--ToggleMusic("stop_forced")

	Observe('PlayerPuppet', 'OnDeath', function()
  		resetKillstreak()
	end)

	
	Observe('NPCPuppet', 'SendAfterDeathOrDefeatEvent', function(self)
		-- https://github.com/psiberx/cp2077-cet-kit/blob/main/mods/GameSession-KillStats/init.lua
		if self.shouldDie and (IsPlayer(self.myKiller) or self.wasJustKilledOrDefeated) then
			local WhatWeKilled = GetInfo(self)
			print(self)
			gotKill(WhatWeKilled)
		end
	end)

	GameSession.OnStart(function()
		isInGame = true
		isPaused = false
	end)

	GameSession.OnPause(function()
		showDisplay = false
		isPaused = true
	end)

	GameSession.OnResume(function()
		isPaused = false
		showDisplay = true
		-- get resolution here in case user changed it 
		autoPosition()
	end)

	GameSession.OnEnd(function()
		isInGame = false
	end)

	GameSession.TryLoad()
end)

registerForEvent('onDraw', function()
	if (MOD_SETTINGS.showDisplay) and (killstreak.started) and (showDisplay) then
		ImGui.SetNextWindowPos(displayW, displayH)
		ImGui.Begin("Trick Display", true, ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoResize)
		ImGui.SetWindowFontScale(displayFontSize)
		ImGui.TextColored(1,1,1,1, displayText()) -- trick list
		ImGui.End()
	end
end)

function playerDied()
	print("vpcs: player died")
end

function displayText()
	local s = ""
	s = s .. "Kills: " .. tostring(killstreak.kills) .. "\n"
	s = s .. "Points: " .. tostring(killstreak.points) .. "\n"
	s = s .. string.format("%.1f", killstreak.duration) .. " / " .. tostring(killstreak.timeLimit)
	--print(s)
	return s
end

function gotKill(offer)
	print("vpcs: killed", offer)

	if not killstreak.started then -- start killstreak
		killstreak.started = os.clock()
	end

	table.insert(killstreak.offers, offer)
	killstreak.kills = killstreak.kills + 1

	-- calculate points here
	local points = MOD_SETTINGS.points.base
	
	if string.find(offer, "Ganger") then
		points = MOD_SETTINGS.points.ganger
	elseif string.find(offer, "Police") then
		points = MOD_SETTINGS.points.police
	elseif string.find(offer, "Cyberpsycho") then
		points = MOD_SETTINGS.points.cyberpsycho
	end

	if string.find(offer, "Lvl2") then
		points = points * 2
	elseif string.find(offer, "Lvl3") then
		points = points * 3
	elseif string.find(offer, "Lvl4") then
		points = points * 4
	end

	if string.find(offer,"Rare") then
		points = points * 2
	elseif string.find(offer, "Elite") then
		points = points * 3
	end

	-- speed bonus?
	if (killstreak.lastKill) and ( (killstreak.duration - killstreak.lastKill) <= MOD_SETTINGS.speedBonusWindow) then
		killstreak.points = killstreak.points + points
		playSFX("ui_hacking_access_granted")
	end
	killstreak.lastKill = killstreak.duration

	-- add extra time here?
	killstreak.timeLimit = killstreak.timeLimit + 1

	HUDMessage(offer .. "+" .. tostring(points))
	killstreak.points = killstreak.points + points
	
end

function autoPosition()
	print("vpcs: autoposition")
	w,h = GetDisplayResolution()
	displayW = w/2 - 200
	displayH = math.floor((h*0.78) + 0.5)
	displayFontSize = 2

end

function saveSettings()
	local file = io.open(SETTINGS_FILE, "w")
	local j = json.encode(MOD_SETTINGS)
	file:write(j)
	file:close()
end

function loadSettings()
	if not LEX.fileExists(SETTINGS_FILE) then
		return false
	end

	local file = io.open(SETTINGS_FILE, "r")
	local j = json.decode(file:read("*a"))
	file:close()

	MOD_SETTINGS = j

	return true
end

function resetKillstreak() 
	killstreak = {
		started = nil,
		duration = 0,
		kills = 0,
		timeLimit = MOD_SETTINGS.timeLimit,
		points = 0,
		lastKill = nil,
		offers = {}
	}
end

function endKillstreak()
	print("vpcs: ended killstreak")
	for k,v in pairs(killstreak) do
		print(k,v)
	end

	--reward here

	local s = "- Killstreak Ended -\n"
	local gotRecord = false

	s = s .. tostring(killstreak.points) .. " points"
	if killstreak.points > SESSION_DATA.bestPoints then
		SESSION_DATA.bestPoints = killstreak.points
		s = s .. " (New Record!)"
		gotRecord = true
	end
	s = s .. "\n"

	s = s .. tostring(killstreak.kills) .. " kills"
	if killstreak.kills > SESSION_DATA.bestKills then
		SESSION_DATA.bestKills = killstreak.kills
		s = s .. " (New Record!)"
		gotRecord = true
	end
	s = s .. "\n"

	s = s .. string.format("%.2f", killstreak.duration) .. " secs"
	if killstreak.duration > SESSION_DATA.bestDuration then
		SESSION_DATA.bestDuration = killstreak.duration
		s = s .. " (New Record!)"
		gotRecord = true
	end

	if MOD_SETTINGS.showEndMessage == "always" then
		GameHUD.ShowWarning(s, 5)
	elseif MOD_SETTINGS.showEndMessage == "records" and gotRecord then
		GameHUD.ShowWarning(s, 5)
	end

	SESSION_DATA.totalKills = SESSION_DATA.totalKills + killstreak.kills
	SESSION_DATA.totalDuration = SESSION_DATA.totalDuration + killstreak.duration
	SESSION_DATA.totalPoints = SESSION_DATA.totalPoints + killstreak.points
	SESSION_DATA.totalKillstreaks = SESSION_DATA.totalKillstreaks + 1

	for index,victim in pairs(killstreak.offers) do
		local victimFound = false
		for i,v in pairs(SESSION_DATA.victims) do
			if victim == v.name then
				victimFound = true
				SESSION_DATA.victims[i].killed = v.killed + 1
			end
		end
		if not victimFound then
			local new = {
				name = victim,
				killed = 1
			}
			table.insert(SESSION_DATA.victims, new)
		end
	end

	resetKillstreak()
end

function addExtraTime(t)
	killstreak.timeLimit = killstreak.timeLimit + t
end

function HUDMessage(msg)
	if os:clock() - HUDMessage_Last <= 1.5 then
		HUDMessage_Current = msg .. "\n" .. HUDMessage_Current
	else
		HUDMessage_Current = msg
	end

	GameHUD.ShowMessage(HUDMessage_Current)
	HUDMessage_Last = os:clock()
end

function playSFX(sfx)
	if MOD_SETTINGS.soundEffects then
		print("vpcs: playing", sfx)
		Game.GetAudioSystem():Play(sfx)
	end
end

function showCustomShardPopup(titel, text) -- from #cet-snippets @ discord
    shardUIevent = NotifyShardRead.new()
    shardUIevent.title = titel
    shardUIevent.text = text
    Game.GetUISystem():QueueEvent(shardUIevent)
end