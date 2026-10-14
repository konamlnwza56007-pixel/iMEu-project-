--============================================================================--
--  iMEu — Phase 1: Architecture Foundation (single-file bootstrap)
--
--  วิธีใช้:
--    1. สร้าง Script ใน ServerScriptService (หรือวางใน Command Bar ของ Studio)
--    2. วางไฟล์นี้ทั้งหมด แล้ว Run / Play
--
--  สคริปต์นี้จะสร้างโครงสร้างตามแผนผัง:
--      ReplicatedStorage/iMEuPackage
--      ├── Shared    : Types, Defaults
--      ├── Utility   : Validate, SafeCall, Signal, Scope
--      ├── State     : Value
--      └── Core      : Registry
--      StarterPlayerScripts/iMEuPhase1Test (LocalScript)
--
--  และรันเทสทั้ง 8 กรณีทันที (ถ้า loadstring ใช้ได้) หรือรอรันผ่าน Play Solo
--============================================================================--

local TypesSource = [==[
--!strict

export type ChangeSource =
	"user"
	| "api"
	| "sync"
	| "load"
	| "reset"

-- Scalar models cover toggles, numeric controls, text, colors and keybinds.
-- Multi-select will use a separate immutable Selection model.
export type Scalar = boolean | number | string | Color3 | EnumItem

export type NumericSpec = {
	Min: number,
	Max: number,
	Step: number,
}

export type Settings = {
	Theme: string,
	AccentColor: Color3?,
	UIScale: number,
	AnimationSpeed: number,
	Transparency: number,
	ParticlesEnabled: boolean,
	ReducedMotion: boolean,
	GlowEnabled: boolean,
	GlowIntensity: number,
	GradientEnabled: boolean,
	LowPerformanceMode: boolean,
}

export type WindowOptions = {
	Id: string?,
	Title: string?,
	Subtitle: string?,
	Theme: string?,
	MobileButton: boolean?,
	AnimationSpeed: number?,
	Shortcut: Enum.KeyCode?,
}

return table.freeze({})
]==]

local DefaultsSource = [==[
--!strict

local Types = require(script.Parent.Types)

local settings: Types.Settings = {
	Theme = "Midnight",
	AccentColor = nil,
	UIScale = 1,
	AnimationSpeed = 1,
	Transparency = 0.12,
	ParticlesEnabled = true,
	ReducedMotion = false,
	GlowEnabled = true,
	GlowIntensity = 0.18,
	GradientEnabled = true,
	LowPerformanceMode = false,
}

local Defaults = {
	Version = "0.1.0-dev",
	DefaultWindowId = "iMEu.Main",

	Settings = table.freeze(settings),

	Window = table.freeze({
		Title = "iMEu",
		Subtitle = "Premium Interface",
		MobileButton = true,
		Shortcut = Enum.KeyCode.RightShift,
	}),

	Layout = table.freeze({
		PreferredWidth = 960,
		PreferredHeight = 620,
		MinWidth = 320,
		MinHeight = 300,

		HeaderHeight = 64,
		FooterHeight = 30,
		SidebarWidth = 192,
		MobileNavigationHeight = 56,

		MobileBreakpoint = 720,
		ViewportMargin = 12,
		TouchTarget = 48,

		CornerRadius = 12,
		Spacing = 12,
		CompactSpacing = 8,
	}),

	Limits = table.freeze({
		MinUIScale = 0.8,
		MaxUIScale = 1.35,
		MinAnimationSpeed = 0.25,
		MaxAnimationSpeed = 2,
		MaxTransparency = 0.45,
		MaxGlowIntensity = 0.4,
		MaxParticles = 18,
		LowPerformanceParticles = 6,
	}),
}

return table.freeze(Defaults)
]==]

local ValidateSource = [==[
--!strict

local Types = require(script.Parent.Parent.Shared.Types)

local Validate = {}

function Validate.IsFinite(value: any): boolean
	return typeof(value) == "number"
		and value == value
		and value > -math.huge
		and value < math.huge
end

function Validate.Number(value: any, label: string?): number
	assert(
		Validate.IsFinite(value),
		string.format("%s must be a finite number", label or "Value")
	)

	return value :: number
end

function Validate.Name(value: any, label: string?): string
	assert(
		typeof(value) == "string",
		string.format("%s must be a string", label or "Name")
	)

	local trimmed = string.match(value, "^%s*(.-)%s*$") :: string

	assert(#trimmed > 0, (label or "Name") .. " cannot be empty")
	assert(#trimmed <= 120, (label or "Name") .. " is too long")

	return trimmed
end

function Validate.NumberSpec(
	minimum: any,
	maximum: any,
	step: any
): Types.NumericSpec
	local minValue = Validate.Number(minimum, "Min")
	local maxValue = Validate.Number(maximum, "Max")
	local stepValue = Validate.Number(step, "Step")

	assert(maxValue > minValue, "Max must be greater than Min")
	assert(stepValue > 0, "Step must be greater than zero")

	local span = maxValue - minValue
	assert(Validate.IsFinite(span), "Numeric range is too large")

	local divisions = span / stepValue
	assert(
		Validate.IsFinite(divisions) and divisions <= 1e9,
		"Step is too small for this numeric range"
	)

	assert(
		minValue + stepValue > minValue,
		"Step is below numeric precision at Min"
	)

	return table.freeze({
		Min = minValue,
		Max = maxValue,
		Step = stepValue,
	})
end

function Validate.Snap(value: any, spec: Types.NumericSpec): number
	local numeric = Validate.Number(value, "Value")
	local clamped = math.clamp(numeric, spec.Min, spec.Max)

	if clamped <= spec.Min then
		return spec.Min
	end

	if clamped >= spec.Max then
		return spec.Max
	end

	local index = math.floor((clamped - spec.Min) / spec.Step)
	local lower = math.clamp(
		spec.Min + index * spec.Step,
		spec.Min,
		spec.Max
	)
	local upper = math.min(lower + spec.Step, spec.Max)

	-- Choose the nearest valid point; ties round upward.
	if clamped - lower < upper - clamped then
		return lower
	end

	return upper
end

function Validate.ParseNumber(text: any): number?
	if typeof(text) ~= "string" then
		return nil
	end

	local trimmed = string.match(text, "^%s*(.-)%s*$") :: string

	if trimmed == "" then
		return nil
	end

	-- Decimal/scientific notation only.
	-- tonumber performs the final syntax validation.
	if string.find(trimmed, "[^%d%.eE%+%-]") then
		return nil
	end

	local numeric = tonumber(trimmed)

	if not Validate.IsFinite(numeric) then
		return nil
	end

	return numeric
end

return table.freeze(Validate)
]==]

local SafeCallSource = [==[
--!strict

local SafeCall = {}

export type Callback = (...any) -> ()

local function traceback(message: any): string
	return debug.traceback(tostring(message), 2)
end

function SafeCall.Call(
	label: string,
	callback: Callback?,
	...: any
): boolean
	if callback == nil then
		return true
	end

	if typeof(callback) ~= "function" then
		warn(string.format(
			"[iMEu:%s] Callback must be a function",
			label
		))
		return false
	end

	local success, message = xpcall(callback, traceback, ...)

	if not success then
		warn(string.format(
			"[iMEu:%s]\n%s",
			label,
			tostring(message)
		))
	end

	return success
end

return table.freeze(SafeCall)
]==]

local SignalSource = [==[
--!strict

local SafeCall = require(script.Parent.SafeCall)

local Signal = {}
Signal.__index = Signal

export type Connection = {
	Connected: boolean,
	Disconnect: (self: Connection) -> (),
}

type Entry = {
	Id: number,
	Callback: SafeCall.Callback,
	Connection: Connection,
}

type Data = {
	_listeners: {[number]: Entry},
	_nextId: number,
	_destroyed: boolean,
}

export type Signal = typeof(setmetatable({} :: Data, Signal))

function Signal.new(): Signal
	return setmetatable({
		_listeners = {},
		_nextId = 0,
		_destroyed = false,
	} :: Data, Signal)
end

function Signal.Connect(
	self: Signal,
	callback: SafeCall.Callback
): Connection
	assert(not self._destroyed, "Cannot connect to a destroyed Signal")
	assert(typeof(callback) == "function", "Listener must be a function")

	self._nextId += 1
	local id = self._nextId
	local owner: Signal? = self

	local connection: Connection = {
		Connected = true,

		Disconnect = function(current: Connection)
			local target = owner

			if target == nil then
				return
			end

			-- Release the captured owner reference on disconnect.
			owner = nil
			current.Connected = false
			target._listeners[id] = nil
		end,
	}

	self._listeners[id] = {
		Id = id,
		Callback = callback,
		Connection = connection,
	}

	return connection
end

function Signal.Once(
	self: Signal,
	callback: SafeCall.Callback
): Connection
	assert(typeof(callback) == "function", "Listener must be a function")

	local connection: Connection? = nil

	connection = self:Connect(function(...: any)
		local current = connection

		-- Disconnect first so recursive Fire cannot call this twice.
		if current ~= nil then
			current:Disconnect()
		end

		callback(...)
	end)

	return connection :: Connection
end

function Signal.Fire(self: Signal, ...: any)
	if self._destroyed then
		return
	end

	local snapshot: {Entry} = {}

	for _, entry in pairs(self._listeners) do
		table.insert(snapshot, entry)
	end

	table.sort(snapshot, function(a: Entry, b: Entry): boolean
		return a.Id < b.Id
	end)

	for _, entry in ipairs(snapshot) do
		if self._destroyed then
			break
		end

		if entry.Connection.Connected then
			SafeCall.Call("Signal.Listener", entry.Callback, ...)
		end
	end
end

function Signal.Destroy(self: Signal)
	if self._destroyed then
		return
	end

	self._destroyed = true

	local listeners = self._listeners
	self._listeners = {}

	for _, entry in pairs(listeners) do
		entry.Connection:Disconnect()
	end
end

function Signal.IsDestroyed(self: Signal): boolean
	return self._destroyed
end

return Signal
]==]

local ScopeSource = [==[
--!strict

local SafeCall = require(script.Parent.SafeCall)
local Validate = require(script.Parent.Validate)

local Scope = {}
Scope.__index = Scope

type Cleanup = () -> ()

type Entry = {
	Cleanup: Cleanup,
}

type Data = {
	_entries: {[number]: Entry},
	_nextId: number,
	_cleaning: boolean,
	_destroyed: boolean,
}

export type Scope = typeof(setmetatable({} :: Data, Scope))

local function cleanupFor(resource: any, method: string?): Cleanup
	if method ~= nil then
		assert(method ~= "", "Cleanup method cannot be empty")

		local callback = resource[method]
		assert(
			typeof(callback) == "function",
			"Cleanup method must reference a function"
		)

		return function()
			callback(resource)
		end
	end

	local kind = typeof(resource)

	if kind == "RBXScriptConnection" then
		return function()
			resource:Disconnect()
		end
	end

	if kind == "Instance" then
		local instance = resource :: Instance

		if instance:IsA("TweenBase") then
			local tween = instance :: TweenBase

			return function()
				tween:Cancel()
				tween:Destroy()
			end
		end

		return function()
			instance:Destroy()
		end
	end

	if kind == "function" then
		return resource :: Cleanup
	end

	if kind == "thread" then
		local worker = resource :: thread

		return function()
			-- An executing callback cannot cancel itself safely.
			-- Suspended or queued work is cancelled here.
			if worker ~= coroutine.running()
				and coroutine.status(worker) ~= "dead"
			then
				task.cancel(worker)
			end
		end
	end

	if kind == "table" then
		if typeof(resource.Destroy) == "function" then
			return cleanupFor(resource, "Destroy")
		end

		if typeof(resource.Disconnect) == "function" then
			return cleanupFor(resource, "Disconnect")
		end
	end

	error("Unsupported Scope resource: " .. kind, 2)
end

function Scope.new(): Scope
	return setmetatable({
		_entries = {},
		_nextId = 0,
		_cleaning = false,
		_destroyed = false,
	} :: Data, Scope)
end

function Scope.Add(
	self: Scope,
	resource: any,
	method: string?
): number
	local cleanup = cleanupFor(resource, method)

	self._nextId += 1
	local id = self._nextId

	-- Late additions must not outlive an owner being destroyed.
	if self._destroyed or self._cleaning then
		SafeCall.Call("Scope.LateCleanup", cleanup)
		return id
	end

	self._entries[id] = {
		Cleanup = cleanup,
	}

	return id
end

function Scope.Remove(
	self: Scope,
	id: number,
	shouldCleanup: boolean?
): boolean
	local entry = self._entries[id]

	if entry == nil then
		return false
	end

	-- Remove before invoking cleanup to allow safe re-entry.
	self._entries[id] = nil

	if shouldCleanup ~= false then
		SafeCall.Call("Scope.Remove", entry.Cleanup)
	end

	return true
end

function Scope.Clean(self: Scope)
	if self._cleaning then
		return
	end

	self._cleaning = true

	local entries = self._entries
	self._entries = {}

	local ids: {number} = {}

	for id in pairs(entries) do
		table.insert(ids, id)
	end

	-- Reverse creation order: child resources before their owners.
	table.sort(ids, function(a: number, b: number): boolean
		return a > b
	end)

	for _, id in ipairs(ids) do
		SafeCall.Call("Scope.Clean", entries[id].Cleanup)
	end

	self._cleaning = false
end

function Scope.Destroy(self: Scope)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self:Clean()
end

function Scope.IsDestroyed(self: Scope): boolean
	return self._destroyed
end

local function schedule(
	self: Scope,
	seconds: number?,
	callback: SafeCall.Callback,
	...: any
): thread?
	assert(typeof(callback) == "function", "Task callback must be a function")

	if self._destroyed or self._cleaning then
		return nil
	end

	local arguments = table.pack(...)
	local resourceId = 0

	local worker = coroutine.create(function()
		SafeCall.Call(
			"Scope.Task",
			callback,
			table.unpack(arguments, 1, arguments.n)
		)

		-- Completed tasks no longer need to be retained.
		self:Remove(resourceId, false)
	end)

	-- Register before scheduling; the callback cannot outrun ownership.
	resourceId = self:Add(worker)

	if seconds == nil then
		task.defer(worker)
	else
		task.delay(seconds, worker)
	end

	return worker
end

function Scope.Defer(
	self: Scope,
	callback: SafeCall.Callback,
	...: any
): thread?
	return schedule(self, nil, callback, ...)
end

function Scope.Delay(
	self: Scope,
	seconds: number,
	callback: SafeCall.Callback,
	...: any
): thread?
	local duration = Validate.Number(seconds, "Delay")
	assert(duration >= 0, "Delay cannot be negative")

	return schedule(self, duration, callback, ...)
end

return Scope
]==]

local ValueSource = [==[
--!strict

local Types = require(script.Parent.Parent.Shared.Types)
local Signal = require(script.Parent.Parent.Utility.Signal)
local Validate = require(script.Parent.Parent.Utility.Validate)

local Value = {}
Value.__index = Value

export type Normalizer = (input: any) -> Types.Scalar

local sources: {[string]: boolean} = table.freeze({
	user = true,
	api = true,
	sync = true,
	load = true,
	reset = true,
})

type Data = {
	_value: Types.Scalar,
	_normalizer: Normalizer?,
	_destroyed: boolean,
	Changed: Signal.Signal,
}

export type Value = typeof(setmetatable({} :: Data, Value))

local function normalize(
	input: any,
	normalizer: Normalizer?
): Types.Scalar
	local result: any = input

	if normalizer ~= nil then
		result = normalizer(input)
	end

	local kind = typeof(result)

	assert(
		kind == "boolean"
			or kind == "number"
			or kind == "string"
			or kind == "Color3"
			or kind == "EnumItem",
		"Value requires a supported scalar type"
	)

	if kind == "number" then
		Validate.Number(result, "State value")
	end

	return result :: Types.Scalar
end

function Value.new(
	initial: any,
	normalizer: Normalizer?
): Value
	if normalizer ~= nil then
		assert(
			typeof(normalizer) == "function",
			"Normalizer must be a function"
		)
	end

	local initialValue = normalize(initial, normalizer)

	return setmetatable({
		_value = initialValue,
		_normalizer = normalizer,
		_destroyed = false,
		Changed = Signal.new(),
	} :: Data, Value)
end

function Value.GetValue(self: Value): Types.Scalar
	assert(not self._destroyed, "Cannot read a destroyed Value")
	return self._value
end

function Value.SetValue(
	self: Value,
	input: any,
	source: Types.ChangeSource?
): boolean
	assert(not self._destroyed, "Cannot change a destroyed Value")

	local origin = source or "api"
	assert(sources[origin] == true, "Unknown value change source")

	-- Normalize completely before mutating state.
	-- Invalid input therefore preserves the previous value.
	local nextValue = normalize(input, self._normalizer)
	local previous = self._value

	if nextValue == previous then
		return false
	end

	self._value = nextValue
	self.Changed:Fire(nextValue, previous, origin)

	return true
end

function Value.Destroy(self: Value)
	if self._destroyed then
		return
	end

	self._destroyed = true
	self._normalizer = nil
	self.Changed:Destroy()
end

function Value.IsDestroyed(self: Value): boolean
	return self._destroyed
end

return Value
]==]

local RegistrySource = [==[
--!strict

local Validate = require(script.Parent.Parent.Utility.Validate)

local Registry = {}
Registry.__index = Registry

export type Builder = (context: any, config: any) -> any

type Data = {
	_builders: {[string]: Builder},
	_destroyed: boolean,
}

export type Registry = typeof(setmetatable({} :: Data, Registry))

function Registry.new(): Registry
	return setmetatable({
		_builders = {},
		_destroyed = false,
	} :: Data, Registry)
end

function Registry.Register(
	self: Registry,
	name: string,
	builder: Builder
)
	assert(not self._destroyed, "Registry has been destroyed")

	local key = Validate.Name(name, "Registration name")

	assert(typeof(builder) == "function", "Builder must be a function")
	assert(
		self._builders[key] == nil,
		string.format("Builder '%s' is already registered", key)
	)

	self._builders[key] = builder
end

function Registry.Get(self: Registry, name: string): Builder
	assert(not self._destroyed, "Registry has been destroyed")

	local key = Validate.Name(name, "Registration name")
	local builder = self._builders[key]

	assert(
		builder ~= nil,
		string.format("Builder '%s' is not registered", key)
	)

	return builder
end

function Registry.Has(self: Registry, name: string): boolean
	assert(not self._destroyed, "Registry has been destroyed")

	local key = Validate.Name(name, "Registration name")
	return self._builders[key] ~= nil
end

function Registry.Unregister(self: Registry, name: string): boolean
	assert(not self._destroyed, "Registry has been destroyed")

	local key = Validate.Name(name, "Registration name")

	if self._builders[key] == nil then
		return false
	end

	self._builders[key] = nil
	return true
end

function Registry.List(self: Registry): {string}
	assert(not self._destroyed, "Registry has been destroyed")

	local names: {string} = {}

	for name in pairs(self._builders) do
		table.insert(names, name)
	end

	table.sort(names)
	return names
end

function Registry.Destroy(self: Registry)
	if self._destroyed then
		return
	end

	self._destroyed = true
	table.clear(self._builders)
end

function Registry.IsDestroyed(self: Registry): boolean
	return self._destroyed
end

return Registry
]==]

local TestSource = [==[
--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Package = ReplicatedStorage:WaitForChild("iMEuPackage")
local Utility = Package:WaitForChild("Utility")
local Shared = Package:WaitForChild("Shared")
local State = Package:WaitForChild("State")
local Core = Package:WaitForChild("Core")

local Defaults = require(Shared:WaitForChild("Defaults"))
local Validate = require(Utility:WaitForChild("Validate"))
local SafeCall = require(Utility:WaitForChild("SafeCall"))
local Signal = require(Utility:WaitForChild("Signal"))
local Scope = require(Utility:WaitForChild("Scope"))
local Value = require(State:WaitForChild("Value"))
local Registry = require(Core:WaitForChild("Registry"))

local passed = 0

local function test(name: string, callback: () -> ())
	local success, message = pcall(callback)

	assert(
		success,
		string.format("[iMEu FAIL] %s: %s", name, tostring(message))
	)

	passed += 1
	print("[iMEu PASS] " .. name)
end

test("Defaults are isolated and frozen", function()
	assert(table.isfrozen(Defaults))
	assert(table.isfrozen(Defaults.Settings))
	assert(table.isfrozen(Defaults.Layout))

	local first = table.clone(Defaults.Settings)
	local second = table.clone(Defaults.Settings)

	first.UIScale = 1.2

	assert(second.UIScale == 1)
	assert(Defaults.Settings.UIScale == 1)
	assert(SafeCall.Call("MissingCallback", nil))
end)

test("Numeric validation and snapping", function()
	local spec = Validate.NumberSpec(0, 100, 5)

	assert(Validate.Snap(52.4, spec) == 50)
	assert(Validate.Snap(53, spec) == 55)
	assert(Validate.Snap(-10, spec) == 0)
	assert(Validate.Snap(500, spec) == 100)

	local uneven = Validate.NumberSpec(0, 10, 3)
	assert(Validate.Snap(9.7, uneven) == 10)

	assert(Validate.ParseNumber(" 12.5 ") == 12.5)
	assert(Validate.ParseNumber("1e2") == 100)
	assert(Validate.ParseNumber("hello") == nil)
	assert(Validate.ParseNumber("0x10") == nil)
	assert(Validate.ParseNumber("1e999") == nil)

	assert(not Validate.IsFinite(0 / 0))
	assert(not Validate.IsFinite(math.huge))

	local accepted = pcall(function()
		Validate.NumberSpec(0, 100, 0)
	end)

	assert(not accepted)
end)

test("Signal ordering, Once and disconnect during dispatch", function()
	local signal = Signal.new()
	local calls: {string} = {}
	local secondConnection: Signal.Connection? = nil

	local firstConnection = signal:Connect(function()
		table.insert(calls, "first")

		local connection = secondConnection
		if connection ~= nil then
			connection:Disconnect()
		end
	end)

	secondConnection = signal:Connect(function()
		table.insert(calls, "second")
	end)

	signal:Once(function()
		table.insert(calls, "once")
	end)

	signal:Fire()
	signal:Fire()

	assert(table.concat(calls, ",") == "first,once,first")

	signal:Destroy()
	signal:Destroy()

	assert(not firstConnection.Connected)

	local accepted = pcall(function()
		signal:Connect(function() end)
	end)

	assert(not accepted)
end)

test("Listener errors do not stop remaining listeners", function()
	local signal = Signal.new()
	local reachedSecondListener = false

	signal:Once(function()
		error("EXPECTED TEST ERROR: callback isolation")
	end)

	signal:Connect(function()
		reachedSecondListener = true
	end)

	-- Exactly one intentional warning is expected from this test.
	signal:Fire()

	assert(reachedSecondListener)
	signal:Destroy()
end)

test("Scope cleanup, reuse and late ownership", function()
	local scope = Scope.new()
	local order: {string} = {}

	local container = Instance.new("Folder")
	local ownedInstance = Instance.new("Folder")
	ownedInstance.Parent = container
	scope:Add(ownedInstance)

	local event = Instance.new("BindableEvent")
	scope:Add(event)

	local connection = event.Event:Connect(function() end)
	scope:Add(connection)

	scope:Add(function()
		table.insert(order, "A")
	end)

	local removedId = scope:Add(function()
		table.insert(order, "B")
	end)

	assert(scope:Remove(removedId))

	scope:Add(function()
		table.insert(order, "C")
	end)

	scope:Clean()

	assert(table.concat(order, ",") == "B,C,A")
	assert(not connection.Connected)
	assert(ownedInstance.Parent == nil)
	assert(not scope:IsDestroyed())

	scope:Add(function()
		table.insert(order, "D")
	end)

	scope:Destroy()
	scope:Destroy()

	scope:Add(function()
		table.insert(order, "E")
	end)

	assert(table.concat(order, ",") == "B,C,A,D,E")
	assert(scope:IsDestroyed())

	container:Destroy()
end)

test("Owned tasks complete or cancel with their Scope", function()
	local activeScope = Scope.new()
	local completed = false

	activeScope:Defer(function()
		completed = true
	end)

	task.wait()
	assert(completed)
	activeScope:Destroy()

	local cancelledScope = Scope.new()
	local deferredRan = false
	local delayedRan = false

	cancelledScope:Defer(function()
		deferredRan = true
	end)

	cancelledScope:Delay(0.1, function()
		delayedRan = true
	end)

	cancelledScope:Destroy()
	task.wait(0.2)

	assert(not deferredRan)
	assert(not delayedRan)
end)

test("Shared numeric state and invalid input preservation", function()
	local spec = Validate.NumberSpec(0, 100, 5)
	local scope = Scope.new()

	local model = Value.new(50, function(input: any): number
		return Validate.Snap(input, spec)
	end)

	scope:Add(model)

	local sliderView = 50
	local numberInputView = 50
	local changes = 0
	local lastSource = ""

	scope:Add(model.Changed:Connect(function(
		nextValue: any,
		_previous: any,
		source: any
	)
		sliderView = nextValue
		changes += 1
		lastSource = source
	end))

	scope:Add(model.Changed:Connect(function(nextValue: any)
		numberInputView = nextValue
	end))

	assert(not model:SetValue(52.4))
	assert(changes == 0)

	assert(model:SetValue(76, "user"))
	assert(sliderView == 75)
	assert(numberInputView == 75)
	assert(changes == 1)
	assert(lastSource == "user")

	assert(model:SetValue(105))
	assert(model:GetValue() == 100)
	assert(changes == 2)

	local accepted = pcall(function()
		model:SetValue("invalid")
	end)

	assert(not accepted)
	assert(model:GetValue() == 100)
	assert(changes == 2)

	scope:Destroy()
	assert(model:IsDestroyed())

	local changedAfterDestroy = pcall(function()
		model:SetValue(20)
	end)

	assert(not changedAfterDestroy)
end)

test("Registry lookup and duplicate prevention", function()
	local registry = Registry.new()

	-- A plain builder tests the Registry independently of GUI code.
	registry:Register("CalculationProbe", function(
		context: any,
		config: any
	): any
		return context.Base + config.Amount
	end)

	assert(registry:Has("CalculationProbe"))

	local builder = registry:Get("CalculationProbe")
	assert(builder({ Base = 40 }, { Amount = 2 }) == 42)

	local duplicateAccepted = pcall(function()
		registry:Register("CalculationProbe", builder)
	end)

	assert(not duplicateAccepted)

	local names = registry:List()
	assert(#names == 1)
	assert(names[1] == "CalculationProbe")

	assert(registry:Unregister("CalculationProbe"))
	assert(not registry:Has("CalculationProbe"))
	assert(not registry:Unregister("CalculationProbe"))

	registry:Destroy()
	registry:Destroy()

	assert(registry:IsDestroyed())
end)

print(string.format(
	"[iMEu] Phase 1 foundation tests passed: %d/8",
	passed
))
]==]

--============================================================================--
--  สร้างโครงสร้าง Instance
--============================================================================--

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPlayer = game:GetService("StarterPlayer")
local StarterPlayerScripts = StarterPlayer:WaitForChild("StarterPlayerScripts")

-- ล้างของเก่าเผื่อรันซ้ำ (Command Bar)
local oldPackage = ReplicatedStorage:FindFirstChild("iMEuPackage")
if oldPackage then oldPackage:Destroy() end
local oldTest = StarterPlayerScripts:FindFirstChild("iMEuPhase1Test")
if oldTest then oldTest:Destroy() end

local function make(className: string, name: string, parent: Instance): Instance
	local inst = Instance.new(className)
	inst.Name = name
	inst.Parent = parent
	return inst
end

local package  = make("Folder", "iMEuPackage", ReplicatedStorage)
local shared   = make("Folder", "Shared", package)
local utility  = make("Folder", "Utility", package)
local state    = make("Folder", "State", package)
local core     = make("Folder", "Core", package)

local function moduleSource(name: string, parent: Instance, source: string)
	local mod = make("ModuleScript", name, parent)
	mod.Source = source
	return mod
end

moduleSource("Types",    shared,  TypesSource)
moduleSource("Defaults", shared,  DefaultsSource)
moduleSource("Validate", utility, ValidateSource)
moduleSource("SafeCall", utility, SafeCallSource)
moduleSource("Signal",   utility, SignalSource)
moduleSource("Scope",    utility, ScopeSource)
moduleSource("Value",    state,   ValueSource)
moduleSource("Registry", core,    RegistrySource)

-- LocalScript สำหรับรันจริงตอน Play Solo
local testScript = make("LocalScript", "iMEuPhase1Test", StarterPlayerScripts)
testScript.Source = TestSource

print("[iMEu] Phase 1 structure built: ReplicatedStorage.iMEuPackage")

--============================================================================--
--  รันเทสทันที (Studio/Command Bar); ถ้า loadstring ไม่ได้ให้กด Play
--============================================================================--

local chunk = loadstring(TestSource, "iMEuPhase1Test")

if chunk then
	local ok, err = pcall(chunk)
	if not ok then
		warn("[iMEu] Phase 1 test run failed: " .. tostring(err))
	end
else
	print("[iMEu] loadstring unavailable here — press Play to run iMEuPhase1Test via StarterPlayerScripts.")
end
