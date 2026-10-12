-- Lobby (Server)
-- Put this Script in the LOBBY place: ServerScriptService
--
-- Shows the chapter list to the LobbyMenu script, and teleports the
-- player to the place for the chapter they picked. Every chapter goes to
-- its own place (placeId in the CHAPTERS list below), and each place
-- starts from its own beginning.
--
-- NOTE: teleports do NOT work when you press Play in Studio.
-- Publish, then test from the Roblox website / app.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local MarketplaceService = game:GetService("MarketplaceService")

-- This must run on the SERVER. If it's a LocalScript, or sitting in
-- StarterCharacterScripts / StarterPlayerScripts, stop with a clear message.
if RunService:IsClient() then
	warn("[Lobby] WRONG PLACE: this is the SERVER script. Delete it from " .. script:GetFullName()
		.. " and put it in a normal Script (not a LocalScript) inside ServerScriptService.")
	return
end

---------------------------------------------------------------------
-- SETTINGS
---------------------------------------------------------------------
-- Backup Place ID, used for any chapter below that has no placeId of its own.
-- Leave it at 0 if every chapter has its own place.
-- (Get an ID in Studio: View > Asset Manager > Places > right-click the place > Copy ID)
local GAME_PLACE_ID = 0

-- true = every player gets their own private copy of the story
-- (so nobody lands in the middle of someone else's night).
-- false = players join a normal public server of the story place.
local SOLO_SERVERS = true

local MENU_TITLE = "Choose a chapter"

-- The buttons in the menu, top to bottom.
--   id      = any unique name or number for the chapter (just used to tell them apart)
--   label   = the small text on the left of the button
--   name    = the text on the right
--   placeId = the place this chapter teleports to (0 = use GAME_PLACE_ID)
local CHAPTERS = {
	{ id = 1,          label = "Chapter 1", name = "Night 1, Tim",       placeId = 88451914043309 },
	{ id = 2,          label = "Chapter 2", name = "Night 2, Alexander", placeId = 0 },
	{ id = 3,          label = "Chapter 3", name = "Night 3 ???",        placeId = 0 },
	{ id = 4,          label = "Chapter 4", name = "Night 4 ???",        placeId = 0 },
	{ id = 5,          label = "Chapter 5", name = "there is no night",  placeId = 0 },
	{ id = "hospital", label = "Final",     name = "The Hospital",       placeId = 0 },
}

-- The gamepasses on the TV's "Support the game" screen, top to bottom.
-- Add as many as you like; if they don't fit on the screen they're split
-- into pages automatically.
--   id   = the gamepass ID (Creator Hub > your game > Monetization > Passes,
--          or the number in the gamepass's web address)
--   name = optional: a different name to show. Leave it out to use the
--          gamepass's real name from Roblox.
local GAMEPASSES = {
	{ id = 1998230556 },
	{ id = 1999394553 },
	{ id = 1998026581 },
	-- { id = 123456789, name = "Big Donation" },
}

local DEBUG = true   -- prints what the lobby is doing to Output
---------------------------------------------------------------------

local function dprint(...)
	if DEBUG then print("[Lobby]", ...) end
end

local function getRemote(className, name)
	local existing = ReplicatedStorage:FindFirstChild(name)
	if existing and existing:IsA(className) then return existing end
	local r = Instance.new(className)
	r.Name = name
	r.Parent = ReplicatedStorage
	return r
end

local listFunction = getRemote("RemoteFunction", "LobbyChapters")
local lobbyEvent = getRemote("RemoteEvent", "LobbyEvent")

-- the menu asks for the chapter list when it opens
listFunction.OnServerInvoke = function(player)
	dprint(player.Name .. " asked for the chapter list")
	-- only send what the menu needs to show
	local list = {}
	for _, ch in ipairs(CHAPTERS) do
		table.insert(list, { id = ch.id, label = ch.label, name = ch.name })
	end
	return { title = MENU_TITLE, chapters = list }
end

---------------------------------------------------------------------
-- Gamepasses
---------------------------------------------------------------------
local passFunction = getRemote("RemoteFunction", "LobbyGamepasses")
local infoCache = {}       -- gamepass details from Roblox (name, price)
local boughtHere = {}      -- [player][passId] = true for purchases made this visit

local function passInfo(id)
	if infoCache[id] then return infoCache[id] end
	local ok, result = pcall(function()
		return MarketplaceService:GetProductInfoAsync(id, Enum.InfoType.GamePass)
	end)
	if not ok then
		ok, result = pcall(function()
			return MarketplaceService:GetProductInfo(id, Enum.InfoType.GamePass)
		end)
	end
	if ok and result then
		infoCache[id] = result
		return result
	end
	warn("[Lobby] couldn't get info for gamepass " .. id .. ": " .. tostring(result))
	return nil
end

local function ownsPass(player, id)
	if boughtHere[player] and boughtHere[player][id] then return true end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(player.UserId, id)
	end)
	if not ok then
		warn("[Lobby] couldn't check if " .. player.Name .. " owns gamepass " .. id .. ": " .. tostring(result))
		return false
	end
	return result == true
end

-- the TV asks for the list when the support screen opens
passFunction.OnServerInvoke = function(player)
	local list = {}
	for _, gp in ipairs(GAMEPASSES) do
		if gp.id and gp.id ~= 0 then
			local info = passInfo(gp.id)
			local price = info and info.PriceInRobux or nil
			if info and info.IsForSale == false then price = nil end
			table.insert(list, {
				id = gp.id,
				name = gp.name or (info and info.Name) or ("Gamepass " .. gp.id),
				price = price,
				owned = ownsPass(player, gp.id),
			})
		end
	end
	dprint(player.Name .. " opened the support screen (" .. #list .. " gamepass(es))")
	return list
end

-- a purchase went through: tell the TV so it shows [OWNED] straight away
MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
	dprint(("%s %s gamepass %d"):format(player.Name, purchased and "BOUGHT" or "closed the purchase for", id))
	if purchased then
		boughtHere[player] = boughtHere[player] or {}
		boughtHere[player][id] = true
		lobbyEvent:FireClient(player, "PassOwned", id)
	end
end)

-- which place a chapter goes to
local function placeFor(chapter)
	if chapter.placeId and chapter.placeId ~= 0 then return chapter.placeId end
	return GAME_PLACE_ID
end

local function findChapter(id)
	for _, ch in ipairs(CHAPTERS) do
		if ch.id == id then return ch end
	end
	return nil
end

local function status(player, text, isError)
	if isError then warn("[Lobby] " .. player.Name .. ": " .. text) else dprint(player.Name .. ": " .. text) end
	lobbyEvent:FireClient(player, "Status", text, isError == true)
end

local teleporting = {}   -- players already on their way

lobbyEvent.OnServerEvent:Connect(function(player, action, id)
	if action ~= "Pick" then return end
	dprint(player.Name .. " picked " .. tostring(id))

	if teleporting[player] then return end

	local chapter = findChapter(id)
	if not chapter then
		status(player, "That chapter doesn't exist.", true)
		return
	end

	local placeId = placeFor(chapter)
	if placeId == 0 then
		status(player, ("%s has no placeId in the Lobby script yet."):format(chapter.label), true)
		return
	end

	if RunService:IsStudio() then
		status(player, ("Teleports don't work in Studio. In the real game this would go to place %d."):format(placeId), true)
		return
	end

	teleporting[player] = true
	status(player, "Loading " .. chapter.label .. "...", false)

	local options = Instance.new("TeleportOptions")
	options.ShouldReserveServer = SOLO_SERVERS

	-- teleports sometimes fail for no reason, so try a few times
	local ok, err
	for attempt = 1, 3 do
		ok, err = pcall(function()
			return TeleportService:TeleportAsync(placeId, { player }, options)
		end)
		if ok then break end
		warn(("[Lobby] teleport attempt %d failed: %s"):format(attempt, tostring(err)))
		task.wait(2)
	end

	if ok then
		dprint(player.Name .. " is teleporting to place " .. placeId .. " (chapter " .. tostring(chapter.id) .. ")")
	else
		teleporting[player] = nil
		status(player, "Couldn't start the chapter: " .. tostring(err), true)
	end
end)

-- the teleport can also fail after it has started
TeleportService.TeleportInitFailed:Connect(function(player, result, message)
	teleporting[player] = nil
	status(player, ("Teleport failed (%s): %s"):format(tostring(result), tostring(message)), true)
end)

Players.PlayerRemoving:Connect(function(player)
	teleporting[player] = nil
	boughtHere[player] = nil
end)

for _, ch in ipairs(CHAPTERS) do
	local id = placeFor(ch)
	if id == 0 then
		warn(("[Lobby] SETUP: %s (%s) has no placeId and there's no GAME_PLACE_ID"):format(ch.label, ch.name))
	else
		dprint(("%s -> place %d"):format(ch.label, id))
	end
end
local realPasses = 0
for _, gp in ipairs(GAMEPASSES) do
	if gp.id and gp.id ~= 0 then realPasses += 1 end
end
if realPasses < #GAMEPASSES then
	warn(("[Lobby] SETUP: %d gamepass(es) in GAMEPASSES still have id = 0 and won't show on the TV")
		:format(#GAMEPASSES - realPasses))
end
dprint("lobby ready with " .. #CHAPTERS .. " chapter(s) and " .. realPasses .. " gamepass(es)")