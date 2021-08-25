local VsProCyberpsycho = {
	title = "V's Pro Cyberpsycho 2077",
	version = "1.1"
}

-- configurable:
local musicEnabled = false
local earnMoney = true
local resetTimer = 15.0
local points_civ = 50
local points_ganger = 200
local points_police = 400
local points_cyberpsycho = 9000
local conversion_rate = 10
local ShouldShowTrickDisplay = false
local ShouldShowRewardDisplay = false
local UseGameHUDMessages = true
local ShouldShowRewardNotification = true
local UseGameHUDWarning = false
local TrickDisplayMaxLines = 3
local TrickDisplayMaxLineLength = 60
local TrickDisplay_FontScale = 1
local TrickDisplay_PosW = 700
local TrickDisplay_PosH = 700
local SpeedBonus_Enabled = true
local SpeedBonus_TimeLimit = 2.5
local SpeedBonus_AddMultiplier = 0.2
local PayoutThreshold = 5000
--------------------------------------

local GameSession = require("Modules/GameSession.lua")
local GameSettings = require("Modules/GameSettings.lua")
local GameUI = require("Modules/GameUI.lua")
local GameHUD = require("Modules/GameHUD.lua")

local userSettingsFile = "settings.v2.json"

local showSettings = false
local showPopup1 = false
local showPopup2_startedAt = 0

local tricks = {}
local trick_string = ""
local duration = 0
local killStreak = 0
local killstreak_started = 0
local timeLastKill = 0
local time_remaining = 0
local current_points = 0
local multiplier = 0

local popup2_msg1 = "1234567890"
local popup2_msg2 = "1234567 x 89"
local popup2_msg3 = "$999"

local originalCarVolume = 0
local originalMusicVolume = 0

local CurrentMessage = ""
local LastMessage = 0

local PayoutAmountDue = 0

local points_other = (points_civ + points_ganger + points_police + points_cyberpsycho) / 4

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

registerForEvent("onOverlayOpen", function()
	showSettings = true
end)

registerForEvent("onOverlayClose", function()
	showSettings = false
end)


registerForEvent('onInit', function()
	originalCarVolume = GameSettings.Get("/audio/volume/CarRadioVolume")
	originalMusicVolume = GameSettings.Get("/audio/volume/MusicVolume")

	if not load_settings(userSettingsFile) then
		TryAutoPosition()
	end

	ToggleMusic("stop_forced")

	GameSession.OnLoad(function()
		playerDied() -- lazy reuse
	end)

	Observe('PlayerPuppet', 'OnDeath', function()
  		playerDied()
	end)

	
	Observe('NPCPuppet', 'SendAfterDeathOrDefeatEvent', function(self)
		-- https://github.com/psiberx/cp2077-cet-kit/blob/main/mods/GameSession-KillStats/init.lua
		if self.shouldDie and (IsPlayer(self.myKiller) or self.wasJustKilledOrDefeated) then
			local WhatWeKilled = GetInfo(self)
			gotKill(WhatWeKilled)
		end
	end)
end)

registerForEvent('onDraw', function()

	if killStreak > 0 then
		time_remaining = resetTimer - (os:clock() - timeLastKill)
		--duration = os:clock() - killstreak_started

		if time_remaining <= 0 then
			endKillStreak()
		end
	end

	if (showPopup1 and ShouldShowTrickDisplay) or (showSettings and ShouldShowTrickDisplay) then

		if (showSettings) then
			fake_tricks_added = 0
			fake_tricks = {}
			while fake_tricks_added < 100 do
				table.insert(fake_tricks, "Preview " .. tostring(fake_tricks_added))
				fake_tricks_added = fake_tricks_added + 1
			end
			message = tricksToDisplayString(fake_tricks, TrickDisplayMaxLines, TrickDisplayMaxLineLength)
			message2 = "999999 x 99.9"
			message3 = string.format("%.1f", 99.9)
		else
			message = trick_string
			message2 = tostring(current_points) .. " x " .. string.format("%.1f",multiplier)
			message3 = string.format("%.1f", time_remaining)
		end
		
		ImGui.SetNextWindowPos(TrickDisplay_PosW, TrickDisplay_PosH)
		ImGui.Begin("Trick Display", true, ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoResize)

		ImGui.SetWindowFontScale(round(TrickDisplay_FontScale))
		ImGui.TextColored(1,1,1,1, message) -- trick list
		
		-- score x multiplier
		ImGui.TextColored(1, 1, 0, 1, message2 .. "\t")
		ImGui.SameLine()
		
		if os:clock() - timeLastKill <= SpeedBonus_TimeLimit then
			-- blue timer if in speedbonus window
			ImGui.TextColored((80/255), (137/255), (216/255),1, message3)
		elseif time_remaining <= 3 then
			-- red timer when almost out
			ImGui.TextColored(1,0,0,1, message3)
		else
			ImGui.TextColored(1,1,1,1, message3)
		end
		
		ImGui.End()
	end

	if ShouldShowRewardDisplay and showPopup2_startedAt + 5 >= os:clock() or showSettings and ShouldShowRewardDisplay then
		ImGui.SetNextWindowPos(1.5*TrickDisplay_PosW, TrickDisplay_PosH)
		ImGui.Begin("Trick Reward", true, ImGuiWindowFlags.NoBackground + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoMove + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.AlwaysAutoResize + ImGuiWindowFlags.NoResize)
		
		ImGui.SetWindowFontScale( round(TrickDisplay_FontScale*2) )
		ImGui.TextColored((81/255), (150/255), (235/255),1, popup2_msg1) -- big total score

		ImGui.SetWindowFontScale( round(TrickDisplay_FontScale*1.3) )
		ImGui.TextColored(1,1,1,1, popup2_msg2) -- score x multiplier
		ImGui.TextColored((117/255), (252/255), (84/255) ,1, popup2_msg3) -- money

		ImGui.End()		
	end


	if (showSettings) then
		ImGui.Begin(VsProCyberpsycho.title)
		
		ImGui.Text("Killstreak Time Limit:")
		resetTimer = ImGui.InputFloat("Time Limit", resetTimer, 5.0)
		ImGui.Separator()

		ImGui.Text("Game HUD:")
		if ImGui.Button("Use Notifications for Kills") then
			UseGameHUDMessages = not UseGameHUDMessages
		end
		ImGui.SameLine()
		ImGui.Text(tostring(UseGameHUDMessages))
		if ImGui.Button("Show Killstreak Finished Notification") then
			ShouldShowRewardNotification = not ShouldShowRewardNotification
		end
		ImGui.SameLine()
		ImGui.Text(tostring(ShouldShowRewardNotification))

		if ImGui.Button("Use Relic Warning for Killstreak Finished instead") then
			UseGameHUDWarning = not UseGameHUDWarning
		end
		ImGui.SameLine()
		ImGui.Text(tostring(UseGameHUDWarning))
		ImGui.Separator()

		ImGui.Text("THPS-Style Trick Display:")
		if ImGui.Button("Enabled") then
			ShouldShowTrickDisplay = not ShouldShowTrickDisplay
		end
		ImGui.SameLine()
		ImGui.Text(tostring(ShouldShowTrickDisplay))
		if ImGui.Button("Ugly reward display") then
			ShouldShowRewardDisplay = not ShouldShowRewardDisplay
		end
		ImGui.SameLine()
		ImGui.Text(tostring(ShouldShowRewardDisplay))
		TrickDisplay_PosW = ImGui.InputInt("Horizontal Pos.", TrickDisplay_PosW, 10)
		TrickDisplay_PosH = ImGui.InputInt("Vertical Pos.", TrickDisplay_PosH, 10)
		TrickDisplay_FontScale = ImGui.InputInt("Font Scale", TrickDisplay_FontScale, 1)
		if ImGui.Button("Try to Auto Position") then
			TryAutoPosition()
		end
		TrickDisplayMaxLines = ImGui.InputInt("Lines", TrickDisplayMaxLines, 1)
		TrickDisplayMaxLineLength = ImGui.InputInt("Line length", TrickDisplayMaxLineLength, 10)
		ImGui.Separator()

		ImGui.Text("Points:")
		points_civ = ImGui.InputInt("Civilian", points_civ, 100)
		points_ganger = ImGui.InputInt("Gang", points_ganger, 100)
		points_police = ImGui.InputInt("Police", points_police, 100)
		points_cyberpsycho = ImGui.InputInt("Cyberpsycho", points_cyberpsycho, 100)
		ImGui.Separator()

		ImGui.Text("Money:")
		if ImGui.Button("Earn Money") then
			earnMoney = not earnMoney
		end
		ImGui.SameLine()
		ImGui.Text(tostring(earnMoney))
		conversion_rate = ImGui.InputFloat("Conversion Rate", conversion_rate, 1.0)
		ImGui.Text("1000 points = $" .. tostring(PointsToMoney(1000)))
		PayoutThreshold = ImGui.InputInt("Payout Threshold", PayoutThreshold, 1000)
		ImGui.Text("(current due: " .. tostring(PayoutAmountDue) .. ")")
		ImGui.Separator()

		ImGui.Text("Speed Bonus:")
		if ImGui.Button("Speed Bonus Enabled") then
			SpeedBonus_Enabled = not SpeedBonus_Enabled
		end
		ImGui.SameLine()
		ImGui.Text(tostring(SpeedBonus_Enabled))
		SpeedBonus_TimeLimit = ImGui.InputFloat("Speed Bonus Time Window", SpeedBonus_TimeLimit, 0.5)
		SpeedBonus_AddMultiplier = ImGui.InputFloat("Multiplier Add", SpeedBonus_AddMultiplier, 0.1)
		ImGui.Separator()

		ImGui.Text("Play Music:")
		if ImGui.Button("Music enabled") then
			musicEnabled = not musicEnabled
			if killStreak > 0 and musicEnabled then
				ToggleMusic("start")
			elseif not musicEnabled then
				ToggleMusic("stop_forced")
			end
		end
		ImGui.SameLine()
		ImGui.Text(tostring(musicEnabled))
		ImGui.Text("(requires external tool)")
		ImGui.Separator()

		if ImGui.Button("Save settings") then
			save_settings(userSettingsFile)
		end
		ImGui.SameLine()
		if ImGui.Button("Load settings") then
			load_settings(userSettingsFile)
		end

		if ImGui.Button("Load defaults") then
			load_settings("defaults.json")
			ToggleMusic("stop_forced")
			TryAutoPosition()
		end

		ImGui.End()

	end

end)

function playerDied()
	ToggleMusic("stop")

	tricks = {}
	trick_string = ""
	killStreak = 0
	killstreak_started = 0
	duration = 0
	timeLastKill = 0
	current_points = 0
	multiplier = 0
	duration = 0
	time_remaining = 0

	showPopup1 = false
end

function endKillStreak()
	ToggleMusic("stop")

	duration = os:clock() - killstreak_started

	local total_score = round(current_points*multiplier)
	popup2_msg1 = tostring(total_score)
	popup2_msg2 = tostring(current_points) .. " x " .. string.format("%.1f",multiplier)
	
	if earnMoney then
		PayoutAmountDue = PayoutAmountDue + PointsToMoney(total_score)
		--Game.AddToInventory("Items.money", PointsToMoney(total_score))
		popup2_msg3 = "+ $" .. tostring(PointsToMoney(total_score))
	else
		popup2_msg3 = ""
	end

	if PayoutAmountDue >= PayoutThreshold then
		Game.AddToInventory("Items.money", PointsToMoney(PayoutAmountDue))
		PayoutAmountDue = 0
	end

	if ShouldShowRewardNotification then
		-- generate hud message
		local hud_msg = "KILLSTREAK FINISHED: " .. tostring(killStreak) .. " KILLS\n"
		hud_msg = hud_msg .. tostring(current_points) .. " X " .. string.format("%.1f",multiplier) .. " = " .. tostring(total_score) .. "\n"
		--hud_msg = hud_msg .. "DURATION: " .. string.format("%.1f",duration) .. " SECONDS"
		--if earnMoney then -- seems redundant since game's Transfer popup comes up anyway
		--	hud_msg = hud_msg .. "\n+ $" .. tostring(PointsToMoney(total_score))
		--end

		if UseGameHUDWarning and ShouldShowRewardNotification then
			HUDWarning(hud_msg, 5.0)
		elseif UseGameHUDMessages and ShouldShowRewardNotification then
			HUDNotification(hud_msg)
		end

		
	end
	
	tricks = {}
	trick_string = ""
	killStreak = 0
	killstreak_started = 0
	duration = 0
	timeLastKill = 0
	current_points = 0
	multiplier = 0
	duration = 0
	time_remaining = 0

	showPopup1 = false
	showPopup2_startedAt = os:clock()
end

function gotKill(offer)
	killStreak = killStreak + 1

	table.insert(tricks, offer)

	trick_string = tricksToDisplayString(tricks, TrickDisplayMaxLines, TrickDisplayMaxLineLength)

	if string.find(offer, "Civilian") or string.find(offer, "Driver") then
		points_worth = points_civ
	elseif string.find(offer, "Ganger") then
		points_worth = points_ganger
	elseif string.find(offer, "Police") then
		points_worth = points_police
	elseif string.find(offer, "Cyberpsycho") then
		points_worth = points_cyberpsycho
	else
		points_worth = points_other
	end

	---- do some multiplication if fancier enemies
	---- TODO more: TraumaTeam etc.
	---- TODO make these settings

	-- check level if any
	if string.find(offer, "Lvl2") then
		points_worth = points_worth * 2
	elseif string.find(offer, "Lvl3") then
		points_worth = points_worth * 3
	elseif string.find(offer, "Lvl4") then
		points_worth = points_worth * 4
	end

	-- if rare
	if string.find(offer,"Rare") then
		points_worth = points_worth * 2
	elseif string.find(offer, "Elite") then
		points_worth = points_worth * 3
	end

	-- if driver
	if string.find(offer,"Driver") then
		points_worth = points_worth * 1.5
	end

	-- if drone
	if string.find(offer, "Drone") then
		points_worth = points_worth * 2
	end

	if string.find(offer, "Big") or string.find(offer, "Strong") then
		points_worth = points_worth * 2
	end
	-----------------------------------------
	print("Killed:", offer, "(" .. tostring(points_worth) .. ")")
	
	-- if speed bonus
	if SpeedBonus_Enabled and os:clock() - timeLastKill <= SpeedBonus_TimeLimit then
		multiplier = multiplier + SpeedBonus_AddMultiplier
		HUDNotification("SPEED BONUS +" .. string.format("%.1f", SpeedBonus_AddMultiplier) .. "X (" .. string.format("%.1f", multiplier) .. "X)")
	end
	multiplier = multiplier + 1 -- add 1 kill

	points_to_add = points_worth
	current_points = current_points + points_to_add

	HUDNotification(offer .. " +" .. tostring(points_to_add))

	if killStreak == 1 then
		killstreak_started = os:clock()
		ToggleMusic("start")
		showPopup1 = true
	end

	timeLastKill = os:clock()
end

function PointsToMoney(pts)
	return math.floor(pts/conversion_rate)
end

function tricksToDisplayString(T, MaxLines, MaxLineLength)
    reversed = {}
    
    -- newest tricks are at the end of array, so reverse it
    for i = #T, 1, -1 do 
        table.insert(reversed, T[i])
    end

    -- now make a string
    result = ""
    for k,v in pairs(reversed) do -- v = trick name
        if result == "" then
            result = v
        else
            result = result .. " + " .. v
        end
        
        
    end

    a = MaxLineLength
    while a < string.len(result) do
    	result = result:gsub('()',{[a]='\n'})
    	a = a + MaxLineLength
    end

   	if string.len(result) > (MaxLines*MaxLineLength) then
   		result = string.sub(result,1,(MaxLineLength*MaxLines)-4) .. "..."
   	end



    return result
end

function save_settings(filename)
	data = {
		musicEnabled = musicEnabled,
		earnMoney = earnMoney,
		resetTimer = resetTimer,
		points_civ = points_civ,
		points_ganger = points_ganger,
		points_police = points_police,
		points_cyberpsycho = points_cyberpsycho,
		conversion_rate = conversion_rate,
		ShouldShowTrickDisplay = ShouldShowTrickDisplay,
		TrickDisplayMaxLines = TrickDisplayMaxLines,
		TrickDisplayMaxLineLength = TrickDisplayMaxLineLength,
		TrickDisplay_FontScale = TrickDisplay_FontScale,
		TrickDisplay_PosW = TrickDisplay_PosW,
		TrickDisplay_PosH = TrickDisplay_PosH,
		SpeedBonus_Enabled = SpeedBonus_Enabled,
		SpeedBonus_TimeLimit = SpeedBonus_TimeLimit,
		SpeedBonus_AddMultiplier = SpeedBonus_AddMultiplier,
		ShouldShowRewardDisplay = ShouldShowRewardDisplay,
		UseGameHUDMessages = UseGameHUDMessages,
		UseGameHUDWarning = UseGameHUDWarning,
		ShouldShowRewardNotification = ShouldShowRewardNotification,
		PayoutThreshold = PayoutThreshold
	}
	local file = io.open(filename, "w")
	local j = json.encode(data)
	file:write(j)
	file:close()
	print("Vs Pro Cyberpsycho: settings saved to " .. filename)
	return true
end

function load_settings(filename)
	if not file_exists(filename) then
		print("Vs Pro Cyberpsycho: loading settings from " .. filename .. " failed, file didnt exist?")
		return false
	end

	local file = io.open(filename,"r")
	local j = json.decode(file:read("*a"))
	file:close()

	musicEnabled = j["musicEnabled"]
	earnMoney = j["earnMoney"]
	resetTimer = j["resetTimer"]
	points_civ = j["points_civ"]
	points_ganger = j["points_ganger"]
	points_police = j["points_police"]
	points_cyberpsycho = j["points_cyberpsycho"]
	conversion_rate = j["conversion_rate"]
	ShouldShowTrickDisplay = j["ShouldShowTrickDisplay"]
	ShouldShowRewardDisplay = j["ShouldShowRewardDisplay"]
	TrickDisplayMaxLines = j["TrickDisplayMaxLines"]
	TrickDisplayMaxLineLength = j["TrickDisplayMaxLineLength"]
	TrickDisplay_FontScale = j["TrickDisplay_FontScale"]
	TrickDisplay_PosW = j["TrickDisplay_PosW"]
	TrickDisplay_PosH = j["TrickDisplay_PosH"]
	SpeedBonus_Enabled = j["SpeedBonus_Enabled"]
	SpeedBonus_TimeLimit = j["SpeedBonus_TimeLimit"]
	SpeedBonus_AddMultiplier = j["SpeedBonus_AddMultiplier"]
	UseGameHUDMessages = j["UseGameHUDMessages"]
	UseGameHUDWarning = j["UseGameHUDWarning"]
	ShouldShowRewardNotification = j["ShouldShowRewardNotification"]
	PayoutThreshold = j["PayoutThreshold"]


	print("Vs Pro Cyberpsycho: loaded settings from " .. filename)
	return true
end

function file_exists(filename) -- https://stackoverflow.com/a/4991602
    local f=io.open(filename,"r")
    if f~=nil then io.close(f) return true else return false end
end

function TryAutoPosition()
	w,h = GetDisplayResolution()

	-- theres probably some better math you can do here if you're smart
	TrickDisplay_FontScale = round(h/540)
	TrickDisplay_PosW = round(w/3.5)
	TrickDisplay_PosH = round(h*0.78)

	TrickDisplayMaxLines = 3
	TrickDisplayMaxLineLength = 60
end

function ToggleMusic(action)
	if not musicEnabled and (action ~= "stop_forced") then
		return
	end

	if string.find(action, "start") then
		GameSettings.Set("/audio/volume/CarRadioVolume", 0)
		GameSettings.Set("/audio/volume/MusicVolume", 0)
	else
		GameSettings.Set("/audio/volume/CarRadioVolume", originalCarVolume)
		GameSettings.Set("/audio/volume/MusicVolume",originalMusicVolume)
	end
	GameSettings.Save()


	--print("toggle music:", action)

	local file = io.open("music_state.txt","w")
	file:write(action)
	file:close()
end

function round(n)
	return math.floor(n + 0.5)
end

function HUDNotification(msg)
	if not UseGameHUDMessages then
		return
	end

	if os:clock() - LastMessage <= 1 then
		CurrentMessage = msg .. "\n" .. CurrentMessage
	else
		CurrentMessage = msg
	end

	GameHUD.ShowMessage(CurrentMessage)
	LastMessage = os:clock()
end

function HUDWarning(msg, length)
	if not UseGameHUDMessages then
		return
	end

	GameHUD.ShowWarning(msg, length)
end