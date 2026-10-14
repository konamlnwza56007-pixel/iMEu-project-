--============================================================================--
--  iMEu — Phase 1: Foundation (Single-file Table Module)
--
--  รวมร่างจาก 8 ModuleScript + เทส เป็นสคริปต์เดียว
--  ไม่สร้าง Instance / ไม่ใช้ ReplicatedStorage / ไม่มี require / ไม่มี loadstring
--  ใช้ได้ทั้ง Executor มือถือ และ Studio (Script / Command Bar)
--
--  วิธีใช้: วางทั้งไฟล์รันเลย ผลเทสจะ print ออกมาทันที
--============================================================================--

local Types = (function()
type ChangeSource =
	"user"
	| "api"
	| "sync"
	| "load"
	| "reset"

-- Scalar models cover toggles, numeric controls, text, colors and keybinds.
-- Multi-select will use a separate immutable Selection model.
type Scalar = boolean | number | string | Color3 | EnumItem

type NumericSpec = {
	Min: number,
	Max: number,
	Step: number,
}

type Settings = {
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

type WindowOptions = {
	Id: string?,
	Title: string?,
	Subtitle: string?,
	Theme: string?,
	MobileButton: boolean?,
	AnimationSpeed: number?,
	Shortcut: Enum.KeyCode?,
}

return table.freeze({})
end)()

local Defaults = (function()
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
end)()

local Validate = (function()
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
end)()

local SafeCall = (function()
local SafeCall = {}

type Callback = (...any) -> ()

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
end)()

local Signal = (function()
local Signal = {}
Signal.__index = Signal

type Connection = {
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

type Signal = typeof(setmetatable({} :: Data, Signal))

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
end)()

local Scope = (function()
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

type Scope = typeof(setmetatable({} :: Data, Scope))

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
end)()

local Value = (function()
local Value = {}
Value.__index = Value

type Normalizer = (input: any) -> Types.Scalar

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

type Value = typeof(setmetatable({} :: Data, Value))

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
end)()

local Registry = (function()
local Registry = {}
Registry.__index = Registry

type Builder = (context: any, config: any) -> any

type Data = {
	_builders: {[string]: Builder},
	_destroyed: boolean,
}

type Registry = typeof(setmetatable({} :: Data, Registry))

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
end)()

--============================================================================--
--  Phase 1 Test
--============================================================================--

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

--============================================================================--
-- iMEu — Phase 2: UI + Movement Sandbox
-- Place this complete file as a LocalScript in StarterPlayerScripts
-- Intended for your own Roblox experience / Studio testing.
--============================================================================--

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local localPlayer = Players.LocalPlayer
if not localPlayer then
	warn("[iMEu] Run this as a LocalScript.")
	return
end

local playerGui = localPlayer:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild("iMEu_Interface")
if oldGui then oldGui:Destroy() end

local COLORS = {
	Background = Color3.fromRGB(13, 16, 27),
	Panel = Color3.fromRGB(21, 25, 40),
	Panel2 = Color3.fromRGB(29, 34, 52),
	Accent = Color3.fromRGB(117, 93, 255),
	Accent2 = Color3.fromRGB(64, 211, 255),
	Text = Color3.fromRGB(242, 244, 255),
	Muted = Color3.fromRGB(151, 160, 185),
	Good = Color3.fromRGB(82, 220, 157),
	Red = Color3.fromRGB(255, 105, 125),
}

local function make(className, props, parent)
	local object = Instance.new(className)
	for key, value in pairs(props or {}) do
		object[key] = value
	end
	object.Parent = parent
	return object
end

local function corner(parent, radius)
	return make("UICorner", {CornerRadius = UDim.new(0, radius or 10)}, parent)
end

local function stroke(parent, color, transparency, thickness)
	return make("UIStroke", {
		Color = color or COLORS.Accent,
		Transparency = transparency or 0.5,
		Thickness = thickness or 1,
	}, parent)
end

local function tween(object, duration, props)
	local info = TweenInfo.new(duration, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
	local result = TweenService:Create(object, info, props)
	result:Play()
	return result
end

local gui = make("ScreenGui", {
	Name = "iMEu_Interface",
	ResetOnSpawn = false,
	IgnoreGuiInset = false,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, playerGui)

local root = make("Frame", {
	Name = "Main",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(590, 410),
	BackgroundColor3 = COLORS.Background,
	BorderSizePixel = 0,
}, gui)
corner(root, 16)
stroke(root, COLORS.Accent, 0.28, 1.4)
make("UISizeConstraint", {
	MinSize = Vector2.new(320, 300),
	MaxSize = Vector2.new(720, 560),
}, root)

local scale = make("UIScale", {Scale = 1}, root)
local function updateScale()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local viewport = camera.ViewportSize
	if viewport.X < 620 then
		scale.Scale = math.clamp((viewport.X - 24) / 590, 0.55, 1)
	else
		scale.Scale = math.clamp(viewport.X / 1200, 0.85, 1)
	end
end
updateScale()
if workspace.CurrentCamera then
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(updateScale)
end

local top = make("Frame", {
	Name = "TopBar",
	Size = UDim2.new(1, 0, 0, 62),
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
}, root)
corner(top, 16)
make("Frame", {
	Position = UDim2.new(0, 0, 1, -16),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
}, top)

local logo = make("Frame", {
	Position = UDim2.fromOffset(16, 13),
	Size = UDim2.fromOffset(36, 36),
	BackgroundColor3 = COLORS.Accent,
	BorderSizePixel = 0,
}, top)
corner(logo, 11)
make("TextLabel", {
	BackgroundTransparency = 1,
	Size = UDim2.fromScale(1, 1),
	Text = "iM",
	Font = Enum.Font.GothamBlack,
	TextSize = 15,
	TextColor3 = COLORS.Text,
}, logo)

make("TextLabel", {
	Position = UDim2.fromOffset(62, 10),
	Size = UDim2.new(1, -150, 0, 25),
	BackgroundTransparency = 1,
	Text = "iMEu",
	TextColor3 = COLORS.Text,
	TextSize = 20,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, top)
make("TextLabel", {
	Position = UDim2.fromOffset(63, 34),
	Size = UDim2.new(1, -150, 0, 16),
	BackgroundTransparency = 1,
	Text = "MOVEMENT SANDBOX  •  PHASE 02",
	TextColor3 = COLORS.Muted,
	TextSize = 9,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
}, top)

local close = make("TextButton", {
	Position = UDim2.new(1, -43, 0, 14),
	Size = UDim2.fromOffset(29, 29),
	BackgroundColor3 = COLORS.Panel2,
	Text = "×",
	TextColor3 = COLORS.Text,
	TextSize = 23,
	Font = Enum.Font.GothamMedium,
	AutoButtonColor = false,
}, top)
corner(close, 9)
close.MouseButton1Click:Connect(function()
	root.Visible = false
end)

-- Drag support works with mouse and touch.
do
	local dragging = false
	local dragStart, startPosition
	top.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPosition = root.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			local delta = input.Position - dragStart
			root.Position = UDim2.new(
				startPosition.X.Scale, startPosition.X.Offset + delta.X,
				startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
			)
		end
	end)
end

local sidebar = make("Frame", {
	Position = UDim2.fromOffset(12, 74),
	Size = UDim2.new(0, 145, 1, -88),
	BackgroundColor3 = COLORS.Panel,
	BorderSizePixel = 0,
}, root)
corner(sidebar, 12)
make("UIPadding", {
	PaddingTop = UDim.new(0, 12),
	PaddingLeft = UDim.new(0, 9),
	PaddingRight = UDim.new(0, 9),
}, sidebar)
make("UIListLayout", {
	Padding = UDim.new(0, 7),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, sidebar)

local content = make("Frame", {
	Position = UDim2.fromOffset(169, 74),
	Size = UDim2.new(1, -181, 1, -88),
	BackgroundTransparency = 1,
}, root)

local pageTitle = make("TextLabel", {
	Size = UDim2.new(1, 0, 0, 30),
	BackgroundTransparency = 1,
	Text = "Movement",
	TextColor3 = COLORS.Text,
	TextSize = 19,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Left,
}, content)

local pageSubtitle = make("TextLabel", {
	Position = UDim2.fromOffset(0, 29),
	Size = UDim2.new(1, 0, 0, 19),
	BackgroundTransparency = 1,
	Text = "Tune your character controls",
	TextColor3 = COLORS.Muted,
	TextSize = 11,
	Font = Enum.Font.Gotham,
	TextXAlignment = Enum.TextXAlignment.Left,
}, content)

local pageBody = make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 55),
	Size = UDim2.new(1, 0, 1, -55),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = COLORS.Accent,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
}, content)
make("UIListLayout", {
	Padding = UDim.new(0, 9),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, pageBody)

local statusLabel = make("TextLabel", {
	Position = UDim2.new(0, 12, 1, -20),
	Size = UDim2.new(1, -24, 0, 13),
	BackgroundTransparency = 1,
	Text = "● READY  |  Local character settings",
	TextColor3 = COLORS.Good,
	TextSize = 9,
	Font = Enum.Font.GothamMedium,
	TextXAlignment = Enum.TextXAlignment.Left,
}, root)

local function setStatus(message, good)
	statusLabel.Text = "● " .. string.upper(message)
	statusLabel.TextColor3 = good == false and COLORS.Red or COLORS.Good
end

local function getCharacter()
	local character = localPlayer.Character
	if not character then return nil, nil end
	return character, character:FindFirstChildOfClass("Humanoid")
end

local function makeCard(height)
	local card = make("Frame", {
		Size = UDim2.new(1, -2, 0, height),
		BackgroundColor3 = COLORS.Panel,
		BorderSizePixel = 0,
	}, pageBody)
	corner(card, 11)
	stroke(card, Color3.fromRGB(63, 72, 103), 0.72, 1)
	return card
end

local function makeToggle(title, description, initial, callback)
	local card = makeCard(66)
	make("TextLabel", {
		Position = UDim2.fromOffset(12, 9),
		Size = UDim2.new(1, -78, 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = COLORS.Text,
		TextSize = 12,
		Font = Enum.Font.GothamSemibold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	make("TextLabel", {
		Position = UDim2.fromOffset(12, 31),
		Size = UDim2.new(1, -78, 0, 18),
		BackgroundTransparency = 1,
		Text = description,
		TextColor3 = COLORS.Muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	local button = make("TextButton", {
		Position = UDim2.new(1, -57, 0.5, -13),
		Size = UDim2.fromOffset(44, 26),
		BackgroundColor3 = initial and COLORS.Accent or COLORS.Panel2,
		Text = "",
		AutoButtonColor = false,
	}, card)
	corner(button, 13)
	local knob = make("Frame", {
		Position = initial and UDim2.new(1, -22, 0, 4) or UDim2.fromOffset(4, 4),
		Size = UDim2.fromOffset(18, 18),
		BackgroundColor3 = COLORS.Text,
		BorderSizePixel = 0,
	}, button)
	corner(knob, 9)
	local enabled = initial
	local function render()
		tween(button, 0.16, {BackgroundColor3 = enabled and COLORS.Accent or COLORS.Panel2})
		tween(knob, 0.16, {Position = enabled and UDim2.new(1, -22, 0, 4) or UDim2.fromOffset(4, 4)})
		callback(enabled)
	end
	button.MouseButton1Click:Connect(function()
		enabled = not enabled
		render()
	end)
	render()
	return function(value)
		enabled = value
		render()
	end
end

local function makeSlider(title, minimum, maximum, initial, suffix, callback)
	local card = makeCard(78)
	make("TextLabel", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -90, 0, 19),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = COLORS.Text,
		TextSize = 12,
		Font = Enum.Font.GothamSemibold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	local valueLabel = make("TextLabel", {
		Position = UDim2.new(1, -75, 0, 8),
		Size = UDim2.fromOffset(63, 19),
		BackgroundTransparency = 1,
		TextColor3 = COLORS.Accent2,
		Text = tostring(initial) .. suffix,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextXAlignment = Enum.TextXAlignment.Right,
	}, card)
	local track = make("TextButton", {
		Position = UDim2.fromOffset(12, 43),
		Size = UDim2.new(1, -24, 0, 8),
		BackgroundColor3 = COLORS.Panel2,
		Text = "",
		AutoButtonColor = false,
	}, card)
	corner(track, 5)
	local fill = make("Frame", {
		Size = UDim2.new((initial - minimum) / (maximum - minimum), 0, 1, 0),
		BackgroundColor3 = COLORS.Accent,
		BorderSizePixel = 0,
	}, track)
	corner(fill, 5)
	local knob = make("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new((initial - minimum) / (maximum - minimum), 0, 0.5, 0),
		Size = UDim2.fromOffset(15, 15),
		BackgroundColor3 = COLORS.Text,
		BorderSizePixel = 0,
	}, track)
	corner(knob, 8)
	local dragging = false
	local value = initial
	local function setFromX(x)
		local width = math.max(track.AbsoluteSize.X, 1)
		local alpha = math.clamp((x - track.AbsolutePosition.X) / width, 0, 1)
		value = math.floor((minimum + (maximum - minimum) * alpha) * 10 + 0.5) / 10
		fill.Size = UDim2.new(alpha, 0, 1, 0)
		knob.Position = UDim2.new(alpha, 0, 0.5, 0)
		valueLabel.Text = tostring(value) .. suffix
		callback(value)
	end
	track.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement
			or input.UserInputType == Enum.UserInputType.Touch) then
			setFromX(input.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
		end
	end)
end

local function makeAction(title, description, buttonText, callback, color)
	local card = makeCard(62)
	make("TextLabel", {
		Position = UDim2.fromOffset(12, 8),
		Size = UDim2.new(1, -100, 0, 20),
		BackgroundTransparency = 1,
		Text = title,
		TextColor3 = COLORS.Text,
		TextSize = 12,
		Font = Enum.Font.GothamSemibold,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	make("TextLabel", {
		Position = UDim2.fromOffset(12, 30),
		Size = UDim2.new(1, -100, 0, 17),
		BackgroundTransparency = 1,
		Text = description,
		TextColor3 = COLORS.Muted,
		TextSize = 9,
		Font = Enum.Font.Gotham,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, card)
	local button = make("TextButton", {
		Position = UDim2.new(1, -83, 0.5, -15),
		Size = UDim2.fromOffset(72, 30),
		BackgroundColor3 = color or COLORS.Accent,
		Text = buttonText,
		TextColor3 = COLORS.Text,
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		AutoButtonColor = false,
	}, card)
	corner(button, 8)
	button.MouseButton1Click:Connect(callback)
end

local function clearPage()
	for _, child in ipairs(pageBody:GetChildren()) do
		if child:IsA("GuiObject") and not child:IsA("UIListLayout") then
			child:Destroy()
		end
	end
end

local selectedTab = "Movement"
local tabs = {}
local function switchTab(name)
	selectedTab = name
	for tabName, button in pairs(tabs) do
		button.BackgroundColor3 = tabName == name and COLORS.Accent or COLORS.Panel
		button.TextColor3 = tabName == name and COLORS.Text or COLORS.Muted
	end
	clearPage()
	pageTitle.Text = name
	pageSubtitle.Text = ({
		Movement = "Tune your character controls",
		Visuals = "Camera and display options",
		Settings = "Convenience and safety controls",
	})[name] or "iMEu"
	if name == "Movement" then
		makeSlider("Walk speed", 8, 40, 16, " spd", function(value)
			local _, humanoid = getCharacter()
			if humanoid then humanoid.WalkSpeed = value end
			setStatus("WalkSpeed set to " .. tostring(value), true)
		end)
		makeSlider("Jump power", 25, 100, 50, " jp", function(value)
			local _, humanoid = getCharacter()
			if humanoid then
				humanoid.UseJumpPower = true
				humanoid.JumpPower = value
			end
			setStatus("JumpPower set to " .. tostring(value), true)
		end)
		makeToggle("Sprint boost", "Hold no key; toggle 28 speed", false, function(enabled)
			local _, humanoid = getCharacter()
			if humanoid then humanoid.WalkSpeed = enabled and 28 or 16 end
			setStatus(enabled and "Sprint boost enabled" or "Sprint boost disabled", true)
		end)
		makeToggle("High jump", "Temporarily set jump power to 85", false, function(enabled)
			local _, humanoid = getCharacter()
			if humanoid then
				humanoid.UseJumpPower = true
				humanoid.JumpPower = enabled and 85 or 50
			end
			setStatus(enabled and "High jump enabled" or "High jump disabled", true)
		end)
		makeAction("Reset movement", "Restore default character movement", "RESET", function()
			local _, humanoid = getCharacter()
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.UseJumpPower = true
				humanoid.JumpPower = 50
			end
			setStatus("Movement reset to defaults", true)
		end, COLORS.Red)
	elseif name == "Visuals" then
		makeSlider("Camera FOV", 50, 100, 70, "°", function(value)
			local camera = workspace.CurrentCamera
			if camera then camera.FieldOfView = value end
			setStatus("Camera FOV set to " .. tostring(value), true)
		end)
		makeToggle("Hide other UI", "Toggle CoreGui is not changed; hide this panel", false, function(enabled)
			root.Visible = not enabled
			if enabled then
				task.delay(0.25, function()
					if gui.Parent then
						local reopen = gui:FindFirstChild("ReopenButton")
						if reopen then reopen.Visible = true end
					end
				end)
			end
		end)
		makeAction("Reset camera", "Restore the default camera field of view", "RESET", function()
			local camera = workspace.CurrentCamera
			if camera then camera.FieldOfView = 70 end
			setStatus("Camera FOV reset", true)
		end)
	elseif name == "Settings" then
		makeToggle("Show accent glow", "Subtle highlight around the window", true, function(enabled)
			local outline = root:FindFirstChildOfClass("UIStroke")
			if outline then outline.Transparency = enabled and 0.28 or 1 end
		end)
		makeAction("Recenter window", "Move the UI back to screen center", "CENTER", function()
			root.Position = UDim2.fromScale(0.5, 0.5)
			setStatus("Window recentered", true)
		end)
		makeAction("Restore defaults", "Reset speed, jump, and camera FOV", "RESTORE", function()
			local _, humanoid = getCharacter()
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.UseJumpPower = true
				humanoid.JumpPower = 50
			end
			local camera = workspace.CurrentCamera
			if camera then camera.FieldOfView = 70 end
			setStatus("Default settings restored", true)
		end, COLORS.Red)
	end
end

for index, tabName in ipairs({"Movement", "Visuals", "Settings"}) do
	local button = make("TextButton", {
		LayoutOrder = index,
		Size = UDim2.new(1, 0, 0, 39),
		BackgroundColor3 = COLORS.Panel,
		Text = tabName,
		TextColor3 = COLORS.Muted,
		TextSize = 11,
		Font = Enum.Font.GothamSemibold,
		AutoButtonColor = false,
	}, sidebar)
	corner(button, 9)
	button.MouseButton1Click:Connect(function()
		switchTab(tabName)
	end)
	tabs[tabName] = button
end

local reopen = make("TextButton", {
	Name = "ReopenButton",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(54, 48),
	BackgroundColor3 = COLORS.Accent,
	Text = "iMEu",
	TextColor3 = COLORS.Text,
	TextSize = 13,
	Font = Enum.Font.GothamBlack,
	Visible = false,
	AutoButtonColor = false,
}, gui)
corner(reopen, 14)
stroke(reopen, COLORS.Accent2, 0.25, 1)
reopen.MouseButton1Click:Connect(function()
	root.Visible = true
	reopen.Visible = false
end)
close.MouseButton1Click:Connect(function()
	root.Visible = false
	reopen.Visible = true
end)

-- Keyboard shortcut is optional; mobile users can use the floating reopen button.
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		root.Visible = not root.Visible
		reopen.Visible = not root.Visible
	end
end)

localPlayer.CharacterAdded:Connect(function(character)
	local humanoid = character:WaitForChild("Humanoid", 8)
	if humanoid then
		humanoid.WalkSpeed = 16
		humanoid.UseJumpPower = true
		humanoid.JumpPower = 50
	end
end)

switchTab("Movement")
print("[iMEu] Phase 2 UI loaded. Use in your own Roblox experience / Studio.")
