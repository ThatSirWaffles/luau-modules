--[[

@sirwaffles 2026
Reactive variable links
--!strict

--]]

local http = game:GetService("HttpService")
local cs = game:GetService("CollectionService")

--

type ReactiveMethods = {
	Set: (self: Reactive, value: any) -> (), 
	Get: (self: Reactive) -> (any?), 
	Subscribe: (self: Reactive, call: ((any?) -> ())) -> (),
	Bind: (self: Reactive, object: Instance, property: string, format: string?) -> (),
	BindTag: (self: Reactive, tag: string, property: string, format: string?) -> (),
}

type ReactiveData = {
	value: any?,
	name: string,
	subs: {((any?) -> ())}
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

function Methods:Set(value: any): ()
	local old = self.value
	self.value = value
	
	if value ~= old then
		for _, action in self.subs do
			action(value)
		end
	end
end

function Methods:Get(): any?
	return self.value
end

function Methods:Subscribe(action: (any?) -> ()): ()
	if type(action) == "function" then
		action(self.value)
		table.insert(self.subs, action)
	else
		warn(`Attempted to subscribe non-function to reactive variable {self.name}`)
	end
end

function Methods:Bind(object: Instance, property: string, format: string?): ()
	self:Subscribe(function(value)
		object[property] = if format then string.format(format, value) else value
	end)
end

function Methods:BindTag(tag: string, property: string, format: string?): ()
	self:Subscribe(function(value)
		for _, object in cs:GetTagged(tag) do
			object[property] = if format then string.format(format, value) else value
		end
	end)
	
	cs:GetInstanceAddedSignal(tag):Connect(function(object)
		object[property] = if format then string.format(format, self.value) else self.value
	end)
end

--

local Reactive: ModuleAPI = {} :: ModuleAPI

function Reactive.new(value: any?, name: string?)
	local self = setmetatable({} :: ReactiveData, Methods)
	self.value = value
	self.name = name or http:GenerateGUID(false)
	self.subs = {}
	return self
end

return Reactive