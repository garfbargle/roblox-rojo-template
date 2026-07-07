--!strict
--[[
	DayNightCycle

	Manages Lighting time over a configurable real-world duration and exposes a
	local BindableEvent for same-context systems to react to named times of day.
]]

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

type RuntimeConfig = {
	DayLengthInMinutes: number,
	StartTimeOfDay: number?,
	TimeEvents: { [string]: number },
	Debug: boolean,
}

export type DayNightCycleConfig = {
	DayLengthInMinutes: number?,
	StartTimeOfDay: number?,
	TimeEvents: { [string]: number }?,
	Debug: boolean?,
}

local DayNightCycle = {}

local config: RuntimeConfig = {
	DayLengthInMinutes = 15,
	StartTimeOfDay = 9.0,
	TimeEvents = {
		Dawn = 6.0,
		Sunrise = 7.0,
		Midday = 12.0,
		Sunset = 18.0,
		Dusk = 19.0,
		Midnight = 0.0,
	},
	Debug = false,
}

local connection: RBXScriptConnection?
local isRunning = false
local lastHourChecked: number? = nil
local triggeredEvents: { [string]: boolean } = {}
local timeRatio = 0
local cycleStartTime = 0

local MINUTES_IN_DAY = 1440
local HOURS_IN_DAY = 24

local function log(message: string, isWarning: boolean?)
	local formattedMessage = `[DayNightCycle] {message}`
	if isWarning then
		warn(formattedMessage)
	elseif config.Debug then
		print(formattedMessage)
	end
end

local function validateHour(label: string, hour: number)
	assert(typeof(hour) == "number" and hour >= 0 and hour < HOURS_IN_DAY, `{label} must be between 0 and 23.99`)
end

local function getOrCreateEvents(): BindableEvent
	local remotesFolder = ReplicatedStorage:FindFirstChild("Remotes")
	if remotesFolder then
		assert(remotesFolder:IsA("Folder"), "ReplicatedStorage.Remotes must be a Folder")
	else
		remotesFolder = Instance.new("Folder")
		remotesFolder.Name = "Remotes"
		remotesFolder.Parent = ReplicatedStorage
	end

	local existingEvent = remotesFolder:FindFirstChild("DayNightEvents")
	if existingEvent then
		assert(existingEvent:IsA("BindableEvent"), "ReplicatedStorage.Remotes.DayNightEvents must be a BindableEvent")
		return existingEvent
	end

	local event = Instance.new("BindableEvent")
	event.Name = "DayNightEvents"
	event.Parent = remotesFolder
	return event
end

DayNightCycle.Events = getOrCreateEvents()

local function minutesToHours(minutes: number): number
	return minutes / 60
end

local function crossedHour(previousHour: number?, currentHour: number, eventHour: number): boolean
	if previousHour == nil then
		return math.abs(currentHour - eventHour) < 0.01
	end

	if previousHour <= currentHour then
		return previousHour < eventHour and eventHour <= currentHour
	end

	return eventHour > previousHour or eventHour <= currentHour
end

local function checkTimeEvents(currentHour: number)
	if lastHourChecked ~= nil and currentHour < lastHourChecked then
		triggeredEvents = {}
		log("A new day has begun. Resetting daily time events.")
	end

	for eventName, eventHour in config.TimeEvents do
		if not triggeredEvents[eventName] and crossedHour(lastHourChecked, currentHour, eventHour) then
			triggeredEvents[eventName] = true
			DayNightCycle.Events:Fire(eventName, eventHour)
			log(`Time event triggered: '{eventName}' at {string.format("%.1f", eventHour)}h.`)
		end
	end

	lastHourChecked = currentHour
end

local function onHeartbeat()
	local elapsed = time() - cycleStartTime
	local totalMinutes = (elapsed * timeRatio) % MINUTES_IN_DAY

	Lighting:SetMinutesAfterMidnight(totalMinutes)
	checkTimeEvents(minutesToHours(totalMinutes))
end

function DayNightCycle.Configure(newConfig: DayNightCycleConfig)
	assert(not isRunning, "DayNightCycle.Configure must be called before StartCycle")

	if newConfig.DayLengthInMinutes ~= nil then
		assert(newConfig.DayLengthInMinutes > 0, "DayLengthInMinutes must be greater than 0")
		config.DayLengthInMinutes = newConfig.DayLengthInMinutes
	end

	if newConfig.StartTimeOfDay ~= nil then
		validateHour("StartTimeOfDay", newConfig.StartTimeOfDay)
		config.StartTimeOfDay = newConfig.StartTimeOfDay
	end

	if newConfig.TimeEvents ~= nil then
		for eventName, eventHour in newConfig.TimeEvents do
			validateHour(`TimeEvents.{eventName}`, eventHour)
			config.TimeEvents[eventName] = eventHour
		end
	end

	if newConfig.Debug ~= nil then
		config.Debug = newConfig.Debug
	end
end

function DayNightCycle.GetConfig(): RuntimeConfig
	local copy = table.clone(config)
	copy.TimeEvents = table.clone(config.TimeEvents)
	return copy
end

function DayNightCycle.StartCycle()
	if isRunning then
		log("StartCycle called but the cycle is already running.", true)
		return
	end

	local dayInSeconds = config.DayLengthInMinutes * 60
	timeRatio = MINUTES_IN_DAY / dayInSeconds
	cycleStartTime = time()
	triggeredEvents = {}

	if config.StartTimeOfDay then
		local startMinutes = config.StartTimeOfDay * 60
		Lighting:SetMinutesAfterMidnight(startMinutes)
		cycleStartTime -= startMinutes / timeRatio
	end

	lastHourChecked = minutesToHours(Lighting:GetMinutesAfterMidnight())
	connection = RunService.Heartbeat:Connect(onHeartbeat)
	isRunning = true

	log(`Day/night cycle started. Game day lasts {config.DayLengthInMinutes} real-world minutes.`)
end

function DayNightCycle.StopCycle()
	if not isRunning then
		return
	end

	isRunning = false
	if connection then
		connection:Disconnect()
		connection = nil
	end

	log("Day/night cycle stopped.")
end

function DayNightCycle.AddTimeEvent(eventName: string, eventHour: number)
	assert(eventName ~= "", "eventName must not be empty")
	validateHour("eventHour", eventHour)

	config.TimeEvents[eventName] = eventHour
	log(`Added time event: {eventName} at {string.format("%.1f", eventHour)}h.`)
end

function DayNightCycle.RemoveTimeEvent(eventName: string): boolean
	if config.TimeEvents[eventName] then
		config.TimeEvents[eventName] = nil
		triggeredEvents[eventName] = nil
		log(`Removed time event: '{eventName}'.`)
		return true
	end

	log(`Attempted to remove non-existent event: '{eventName}'.`, true)
	return false
end

function DayNightCycle.GetCurrentTime(): number
	return minutesToHours(Lighting:GetMinutesAfterMidnight())
end

function DayNightCycle.Start()
	DayNightCycle.StartCycle()
end

return table.freeze(DayNightCycle)
