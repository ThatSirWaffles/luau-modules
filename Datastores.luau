--[[

@sirwaffles 2026
Schema-based datastore module
Caching implemented with AI

The Pelagorine schema was left as an example

--]]

local datastores = {}

--

local ds = game:GetService("DataStoreService")
local ps = game:GetService("Players")

local cache = {} -- cache[datastoreName][key] = data
local dirty = {} -- dirty[datastoreName][key] = true when cache has unsaved changes

local schemas = {
	players = {		-- keys are userid as number
		position = {
			inWorld = nil :: string, 	-- serialised Vector2
			inIsland = nil :: string, 	-- serialised Vector3
			rotation = nil :: number 	-- degrees, y rotation
		},
		config = {
			graphics = {
				noMaterials = false
			}
		},
		faction = nil :: string		-- faction id
	},
	
	islands = {		-- keys are serialised Vector2
		worldGenVersion = "1", 		-- keep updated to latest worldgen version
		owner = nil :: string, 		-- faction id
	},
	
	factions = {	-- keys are UUIDs
		owner = nil :: number, 					-- userid
		members = {} :: {[number]: string}, 	-- k: userid,  v: role id
		roles = {} :: Role
	}
}

export type Player = typeof(schemas.players)
export type Island = typeof(schemas.islands)
export type Faction = typeof(schemas.factions)

export type Role = {
	[string]: {	-- role id
		rank: number,
		title: string,
		permissions: {string}
	}
}

--

local function syncTableFromSchema(data: {any}, schema: {any}) -- this affects entry variables, be careful using it
	local modified = false
	
	for k, v in pairs(schema) do
		if typeof(v) == "table" then
			data[k] = data[k] or {}
			_, modified = syncTableFromSchema(data[k], v)
		else
			if data[k] == nil then
				modified = true
				data[k] = v
			end
		end
	end

	return data, modified
end

local function replaceData(originalData: {any}, changes: {any}, increment: boolean?) -- this also affects entry variables, be careful using it
	for k, v in pairs(changes) do
		if typeof(v) == "table" then
			if type(originalData[k]) ~= "table" then
				originalData[k] = {}
			end
			
			replaceData(originalData[k], v, increment)
		else
			if increment and type(originalData[k]) == "number" and type(v) == "number" then
				originalData[k] += v
			else
				originalData[k] = v
			end
		end
	end

	return originalData
end

--local function safeJSONDecode(str:string?) -- decodes supposedly json strings to lua tables
--	if str then
--		return http:JSONDecode(str)
--	else
--		return {}
--	end
--end

function datastores:InitialiseSchema(datastoreName: string, key: any, relevantPlayers:{number}): boolean?
	if schemas[datastoreName] then
		local datastore = ds:GetDataStore(datastoreName)
		
		if datastore:GetAsync(key) then
			warn("Attempted to initialise a key that already exists: "..key)
			return nil
		else
			datastore:SetAsync(key, schemas[datastoreName], relevantPlayers)
			cache[datastoreName] = cache[datastoreName] or {}
			cache[datastoreName][key] = schemas[datastoreName]
			return true
		end
	else
		warn("Attempted to initialise schema in unregistered datastore: "..datastoreName)
		return nil
	end
end

function datastores:SaveData(datastoreName: string, key: any, changes: {any}, relevantPlayers: {number}?): any? -- applies changes to cache and marks dirty; call FlushData to persist
	if schemas[datastoreName] then
		cache[datastoreName] = cache[datastoreName] or {}
		dirty[datastoreName] = dirty[datastoreName] or {}

		local current = cache[datastoreName][key]
		if not current then
			current = ds:GetDataStore(datastoreName):GetAsync(key) or {}
			syncTableFromSchema(current, schemas[datastoreName])
		end

		local updated = replaceData(current, changes)
		cache[datastoreName][key] = updated
		dirty[datastoreName][key] = relevantPlayers or true

		return updated
	else
		warn("Attempted to save data to unregistered datastore: "..datastoreName)
		return nil
	end
end

function datastores:UpdateData(datastoreName: string, key: any, modFunc: ({any}) -> ({any}), relevantPlayers: {number}?): any?
	datastores:SaveData(datastoreName, key, modFunc(datastores:GetData(datastoreName, key)), relevantPlayers)
end

function datastores:FlushData(datastoreName: string, key: any): boolean -- persists a single dirty entry to the datastore
	if not (dirty[datastoreName] and dirty[datastoreName][key]) then
		return true
	end

	local data = cache[datastoreName][key]
	local relevantPlayers = dirty[datastoreName][key]
	local datastore = ds:GetDataStore(datastoreName)

	local success = pcall(function()
		if typeof(relevantPlayers) == "table" then
			datastore:SetAsync(key, data, relevantPlayers)
		else
			datastore:SetAsync(key, data)
		end
	end)

	if success then
		dirty[datastoreName][key] = nil
	end

	return success
end

function datastores:FlushAll(): {string} -- flushes all dirty entries; returns list of failed keys
	local failed = {}

	for datastoreName, keys in pairs(dirty) do
		for key in pairs(keys) do
			if not datastores:FlushData(datastoreName, key) then
				table.insert(failed, datastoreName..":"..tostring(key))
			end
		end
	end

	return failed
end

function datastores:GetData(datastoreName: string, key: any): any?
	if schemas[datastoreName] then
		if cache[datastoreName] and cache[datastoreName][key] then
			return cache[datastoreName][key]
		end
		
		local data = ds:GetDataStore(datastoreName):GetAsync(key) or {}
		
		local _, modified = syncTableFromSchema(data, schemas[datastoreName])
		
		if modified then
			datastores:SaveData(datastoreName, key, data)
		end
		
		cache[datastoreName] = cache[datastoreName] or {}
		cache[datastoreName][key] = data
		
		return data
	else
		warn("Attempted to access unregistered datastore: "..datastoreName)
		return nil
	end
end

function datastores:InvalidateCache(datastoreName: string, key: any)
	if cache[datastoreName] then
		if key then
			cache[datastoreName][key] = nil
			if dirty[datastoreName] then
				dirty[datastoreName][key] = nil
			end
		else
			cache[datastoreName] = nil
			dirty[datastoreName] = nil
		end
	end
end

--

game:BindToClose(function()
	print("Saving all data...")
	datastores:FlushAll()
end)

ps.PlayerRemoving:Connect(function(plr)
	print(`Saving {plr.Name}...`)
	datastores:FlushData("players", plr.UserId)
end)

task.spawn(function()
	while true do
		print("Autosaving...")
		datastores:FlushAll()
		
		task.wait(60 * 2)
	end
end)

--

return datastores
