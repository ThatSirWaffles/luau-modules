--[[

@sirwaffles 2026
Reactive variable links
Cleanup implemented with AI

--]]

local http = game:GetService("HttpService")
local cs = game:GetService("CollectionService")

--

type Subscription = {
	action: (any?) -> (),
}

type ReactiveMethods = {
	Destroy: (self: Reactive) -> (),
	Set: (self: Reactive, value: any) -> (),
	Get: (self: Reactive) -> (any?),
	Subscribe: (self: Reactive, call: ((any?) -> ())) -> (() -> ()),
	Bind: (self: Reactive, object: Instance, property: string, format: string?) -> (() -> ()),
	BindTag: (self: Reactive, tag: string, property: string, format: string?) -> (() -> ()),
}

type ReactiveData = {
	value: any?,
	name: string,
	subs: {Subscription},
	connections: {RBXScriptConnection},
	destroyed: boolean,
}

export type Reactive = typeof(setmetatable({} :: ReactiveData, {} :: { __index: ReactiveMethods }))

type ModuleAPI = {
	new: (value: any?, name:string?) -> Reactive,
}

--

local Methods: ReactiveMethods = {} :: ReactiveMethods
Methods.__index = Methods

function Methods:__tostring()
	return tostring(self.value)
end

local function unwrap(x)
	return getmetatable(x) == Methods and x.value or x
end

local binary = {
	__add = function(a, b) return unwrap(a) + unwrap(b) end,
	__sub = function(a, b) return unwrap(a) - unwrap(b) end,
	__mul = function(a, b) return unwrap(a) * unwrap(b) end,
	__div = function(a, b) return unwrap(a) / unwrap(b) end,
	__idiv = function(a, b) return unwrap(a) // unwrap(b) end,
	__mod = function(a, b) return unwrap(a) % unwrap(b) end,
	__pow = function(a, b) return unwrap(a) ^ unwrap(b) end,
	__eq = function(a, b) return unwrap(a) == unwrap(b) end,
	__lt = function(a, b) return unwrap(a) < unwrap(b) end,
	__le = function(a, b) return unwrap(a) <= unwrap(b) end,
	__concat = function(a, b) return unwrap(a) .. unwrap(b) end,
}

for name, operation in binary do
	Methods[name] = operation
end

Methods.__unm = function(a)
	return -unwrap(a)
end

--

function Methods:Destroy(): ()
	if self.destroyed then
		return
	end

	self.destroyed = true

	for _, connection in self.connections do
		connection:Disconnect()
	end

	table.clear(self.connections)
	table.clear(self.subs)

	self.value = nil
end

function Methods:Set(value: any): ()
	if self.destroyed then
		return
	end

	local old = self.value
	self.value = value

	if value ~= old then
		for _, subscription in self.subs do
			subscription.action(value)
		end
	end
end

function Methods:Get(): any?
	if self.destroyed then
		return nil
	end

	return self.value
end

function Methods:Subscribe(action: (any?) -> ()): () -> ()
	if self.destroyed then
		return function() end
	end

	if type(action) ~= "function" then
		warn(`Attempted to subscribe non-function to reactive variable {self.name}`)
		return function() end
	end

	local subscription: Subscription = {
		action = action,
	}

	table.insert(self.subs, subscription)

	action(self.value)

	local unsubscribed = false

	return function()
		if unsubscribed then
			return
		end

		unsubscribed = true

		local index = table.find(self.subs, subscription)

		if index then
			table.remove(self.subs, index)
		end
	end
end

function Methods:Bind(object: Instance, property: string, format: string?): ()
	local unsubscribe = self:Subscribe(function(value)
		object[property] = if format then string.format(format, value) else value
	end)

	return unsubscribe
end

function Methods:BindTag(tag: string, property: string, format: string?): ()
	local unsubscribe = self:Subscribe(function(value)
		for _, object in cs:GetTagged(tag) do
			object[property] = if format then string.format(format, value) else value
		end
	end)

	local connection = cs:GetInstanceAddedSignal(tag):Connect(function(object)
		object[property] = if format then string.format(format, self.value) else self.value
	end)

	table.insert(self.connections, connection)

	local disconnected = false

	return function()
		if disconnected then
			return
		end

		disconnected = true

		unsubscribe()
		connection:Disconnect()

		local index = table.find(self.connections, connection)

		if index then
			table.remove(self.connections, index)
		end
	end
end

--

local Reactive: ModuleAPI = {} :: ModuleAPI

function Reactive.new(value: any?, name: string?)
	local self = setmetatable({} :: ReactiveData, Methods)

	self.value = value
	self.name = name or http:GenerateGUID(false)
	self.subs = {}
	self.connections = {}
	self.destroyed = false

	return self
end

return Reactive
