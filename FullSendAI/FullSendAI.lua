local CSPConfig = "/full_send_ai.ini"
if io.move(ac.getFolder(ac.FolderID.ScriptOrigin) .. CSPConfig, ac.getFolder(ac.FolderID.ExtCfgSys) .. CSPConfig, true) then
	ac.log"(FULL SEND) Found config ini in script folder and moved it to CSP Extension config succesfully."
end
-- Loads the CFG overrides from CSP.
MySettings = ac.INIConfig.load(ac.getFolder(ac.FolderID.Cfg) .. "/extension/full_send_ai.ini")
PID = require"PID"
GForces = require"GForces"
ProgressToMeters = 0
DEBUG_MODE = MySettings:get("MISC", "DEBUG_MODE", false)
SectionSize = MySettings:get("GENERAL", "SECTION_SIZE", 50)
Racers = {}

function IndexRacers()
	ProgressToMeters = (ac.trackProgressToWorldCoordinate(0.02, false) - ac.trackProgressToWorldCoordinate(0.01, false)):length() * 100
	local currentIndex = 0
	repeat
		local Car = ac.getCar(currentIndex)
		Racers[currentIndex + 1] = {
			Personality = {
				StrengthVanilla = Car.aiLevel > -1 and Car.aiLevel or 1,
				AggressionVanilla = Car.aiAggression > -1 and Car.aiAggression or 1,
				SpaceLeft = 1
			},
			Gs = GForces:new(),
			ProbablyTypicalGs = 1,
			CurrentConfidence = 1,
			index = currentIndex,
			folderName = ac.getCarID(currentIndex),
			humanName = ac.getCarName(currentIndex, false) or "Unnamed",
			isOffTrack = false,
			ThrottleLimiter = 1,
			SmoothThrottleRampUp = 1,
			Dimensions = {
				Width = (Car.wheels[0].position - Car.wheels[1].position):length() + 1,
				Length = (Car.wheels[0].position - Car.wheels[2].position):length() + 1
			},
			-- Dimensions = { Width = Car.aabbSize.x, Length = Car.aabbSize.z }, --The bounding box size the game reports. Inconsistent, or incompetence from me.
			-- Index of the racer close ahead, if any
			ChasingTarget = -1,
			-- Gets filled with base cornering and braking risks right below
			TurnConfidence = {},
			SplineFollower = PID:new{
				value = 0,
				kP = 2,
				kD = 3,
				kI = 0
			},
			Spline = {
				DistToLeft = 0,
				DistToRight = 0,
				Progress = 0,
				OffsetFromSplineCenter = 0,
				TrackWidth = 0
			}
		}
		-- Initial confidences from settings, fills the track sections.
		local CornR = MySettings:get("SPEED", "SPD_CONFIDENCE", 90) / 100
		local BrakeR = MySettings:get("AGRESSION", "BRK_CONFIDENCE", 80) / 100
		for i = 0, ProgressToMeters / SectionSize do
			Racers[currentIndex + 1].TurnConfidence[i] = { Cornering = CornR, Braking = BrakeR }
		end
		currentIndex = currentIndex + 1
		Racers[currentIndex].Personality.SpaceLeft = 2
		-- Try and disable as much stuff as possible and set some defaults.
		physics.setAILookaheadBase(currentIndex, 20)
		physics.setAILookaheadGasBrake(currentIndex, 40)
		physics.setAISteerMultiplier(currentIndex, 0.9)
		physics.setAIAeroHint(currentIndex, 0.8)
		physics.setAITyresHint(currentIndex, 1.01)
		physics.setExtraAIGrip(currentIndex, 1.01)
		physics.setAIBrakeHint(currentIndex, 0.8)
		physics.setAIAggression(currentIndex, 0)
		physics.setAICaution(currentIndex, 0)
		physics.setAILevel(currentIndex, 1)
	until not ac.getCarID(currentIndex)
	UpdateRacersInfo()
end

-- This is what actually has the car move left or right of the ideal line.
function ApplySplineOffset()
	for i = 1, #Racers do
		local carIndex = Racers[i].index
		local val = Racers[i].SplineFollower:getValue()
		physics.setAISplineAbsoluteOffset(carIndex, val + 0.05, true)
	end
end

function UpdateConfidences()
	local baseChangeRate = MySettings:get("GENERAL", "ADJUST_SPEED", 0.1) / 10
	for i = 1, #Racers do
		local Car = ac.getCar(Racers[i].index)
		local progressToId = math.round(Racers[i].Spline.Progress * (ProgressToMeters / SectionSize), 0)
		-- Speed factor, full effect at 28m/s or 100kph or 60mph
		local changeRate = baseChangeRate * (Car.velocity:length() / 28)
		if WithinRange(progressToId, 2, ProgressToMeters / SectionSize) and Car.velocity:length() > 5 then
			local upcomingTurnDist = ac.getTrackUpcomingTurn(Racers[i].index).x
			local slipTarget = MySettings:get("SPEED", "SLIP_TARGET", 8) * map(Racers[i].Personality.StrengthVanilla, 0.7, 1, 0.5, 1)
			if Racers[i].ChasingTarget > -1 then slipTarget = slipTarget * 1.2 end
			-- Translates aggression to the target brakeinput the AI aims to be at when reaching a corner.
			local brakeAggroTime = map(Racers[i].Personality.AggressionVanilla, 0, 1, 0.9, 0.1)
			if Racers[i].ChasingTarget > -1 then brakeAggroTime = math.clamp(brakeAggroTime - 0.1, 0.1, 0.9) end
			local slipAngleFront = Car.wheels[1].slipAngle
			local understeerCounterStart = MySettings:get("SPEED", "UNDERSTEER_TARGET", 8)
			local undValue = 0
			-- Speed confidence (wait for braking to be sorted out first))
			if Car.brake < 0.5 then
				if math.abs(slipAngleFront) > slipTarget then
					Racers[i].TurnConfidence[progressToId].Cornering = math.max(Racers[i].TurnConfidence[progressToId].Cornering - changeRate * 3, 0.5)
					Racers[i].TurnConfidence[progressToId - 1].Cornering = math.max(Racers[i].TurnConfidence[progressToId - 1].Cornering - changeRate * 2, 0.5)
				elseif WithinRange(Car.gas, 0.01, 0.99) and math.abs(slipAngleFront) > 2 then
					Racers[i].TurnConfidence[progressToId].Cornering = math.min(Racers[i].TurnConfidence[progressToId].Cornering + changeRate, 2)
					Racers[i].TurnConfidence[progressToId - 1].Cornering = math.min(Racers[i].TurnConfidence[progressToId - 1].Cornering + changeRate, 2)
				end
			end
			-- Understeer counteractor (only if we aren't urgently avoiding anyone, kP < 4)
			if math.abs(slipAngleFront) > understeerCounterStart then
				local understeerCorrection = math.abs(Car.wheels[1].slipAngle) * (MySettings:get("SPEED", "UNDERSTEER_COUNTER", 50) * 0.01)
				if Racers[i].SplineFollower.kP < 4 then
					if Car.wheels[1].slipAngle > 0 then undValue = understeerCorrection
					else undValue = -understeerCorrection end
				end
				-- Because we reuse the spline follower target we want to modify it, not set it again. 
				-- Setting it would undo the avoidance done at UpdateIntendedSplineOffsets
				Racers[i].SplineFollower:modifyTarget(undValue, Racers[i].Spline.TrackWidth)
			end
			-- Time to reach corner is 0 if we are inside the corner already
			local timeToReach = upcomingTurnDist / Car.velocity:length()
			if upcomingTurnDist == 0 then timeToReach = 0 end
			-- Brake Confidence --
			-- If we are understeering while braking, we should be braking earlier.
			-- Reduce earlier sections too in case they are at fault
			if WithinRange(timeToReach, 0, brakeAggroTime) and Car.brake > 0.5 then
				if math.abs(slipAngleFront) > slipTarget / 2 then
					Racers[i].TurnConfidence[progressToId].Braking = Racers[i].TurnConfidence[progressToId].Braking - changeRate
					Racers[i].TurnConfidence[progressToId - 1].Braking = Racers[i].TurnConfidence[progressToId - 1].Braking - changeRate
					Racers[i].TurnConfidence[progressToId - 2].Braking = Racers[i].TurnConfidence[progressToId - 2].Braking - changeRate
				else
					local r = changeRate / 2
					Racers[i].TurnConfidence[progressToId].Braking = Racers[i].TurnConfidence[progressToId].Braking + r
					Racers[i].TurnConfidence[progressToId - 1].Braking = Racers[i].TurnConfidence[progressToId - 1].Braking + r
					Racers[i].TurnConfidence[progressToId - 2].Braking = Racers[i].TurnConfidence[progressToId - 2].Braking + r
				end
			end
			-- if we are entering a turn and braking sofly, we need to brake later.
			-- Raise earlier sections too in case they are at fault
			if Car.brake < 0.5 and Car.gas < 0.9 then
				if WithinRange(timeToReach, brakeAggroTime, 1) then
					Racers[i].TurnConfidence[progressToId].Braking = Racers[i].TurnConfidence[progressToId].Braking + changeRate * 2
					Racers[i].TurnConfidence[progressToId - 1].Braking = Racers[i].TurnConfidence[progressToId - 1].Braking + changeRate * 2
					Racers[i].TurnConfidence[progressToId - 2].Braking = Racers[i].TurnConfidence[progressToId - 2].Braking + changeRate * 2
				end
			end			
			-- Apply results to the tyre and brake hint system
			if Racers[i].TurnConfidence[progressToId].Cornering then
				local change = (Racers[i].TurnConfidence[progressToId].Cornering - Racers[i].CurrentConfidence) / 2
				Racers[i].CurrentConfidence = Racers[i].CurrentConfidence + change
				physics.setAITyresHint(Racers[i].index, Racers[i].CurrentConfidence)
				physics.setAIBrakeHint(Racers[i].index, Racers[i].TurnConfidence[progressToId].Braking)
				if DEBUG_MODE then
					ac.debug("Car Index nº" .. Racers[i].index, "SPD: x" .. math.round(Racers[i].CurrentConfidence, 1) .. " | BRK: x" .. math.round(Racers[i].TurnConfidence[progressToId].Braking, 2) .. " | UND: " .. math.round(undValue, 1) .. "º | SLP: " .. math.round(math.abs(slipAngleFront), 1) .. "º | LKA x" .. math.round(math.clamp(2 - Racers[i].ProbablyTypicalGs, 0.5, 2), 2))
				end
			end
		end
	end
end

local TenthSec = 0
local HalfSec = 0

function script.update(dt)
	if MySettings:get("BASIC", "ENABLED", true) == false then return end
	for i = 1, #Racers do
		Racers[i].SplineFollower:update(dt)
		local Car = ac.getCar(Racers[i].index)
		Racers[i].Gs:Update(Car.velocity, Car.look, Car.up, dt)
		if Racers[i].SmoothThrottleRampUp < 1 then
			Racers[i].SmoothThrottleRampUp = Racers[i].SmoothThrottleRampUp + dt / MySettings:get("MISC", "FIX_BLIPPING", 1)
		end
	end
	TenthSec = TenthSec + dt
	if TenthSec > 0.1 then
		UpdateRacersInfo()
		UpdateIntendedSplineOffsets()
		UpdateConfidences()
		ApplySplineOffset()
		TenthSec = 0
	end
	HalfSec = HalfSec + dt
	if HalfSec > 0.5 then
		for i = 1, #Racers do

			-- Basegame implementation of this is a set distance. I make it a factor of their speed, accounts better for high speed exits.
			local factor = MySettings:get("MISC", "GAS_LOOKAHEAD_FACTOR", 0.2)
			physics.setAILookaheadGasBrake(Racers[i].index, Racers[i].Spline.TrackWidth + math.clamp(ac.getCar(Racers[i].index).velocity:length() * factor, 5, 500))

			-- This constantly checks the car's peak lateral grip to adjust lookahead line following. 
			-- Helps high-grip cars not cut corners and low grip cars adhere closer to the racing line.
			-- Default is 20m for 1G
			if WithinRange(Racers[i].Gs.Gs.x, -0.5, 0) and math.abs(Racers[i].Gs.Gs.y) > 0.5 then
				local mult = math.clamp(2 - Racers[i].ProbablyTypicalGs, 0.5, 2)
				physics.setAILookaheadBase(Racers[i].index, 20 * mult)
				Racers[i].ProbablyTypicalGs = Racers[i].ProbablyTypicalGs + (math.abs(Racers[i].Gs.Gs.y) - Racers[i].ProbablyTypicalGs) / 10
			end
		end
		HalfSec = 0
	end
end
-- Figure out their offset from the spline (ideal line) and some context stuff.
function UpdateRacersInfo()
	for i = 1, #Racers do
		local Car = ac.getCar(Racers[i].index)
		Racers[i].Spline.Progress = ac.worldCoordinateToTrackProgress(Car.position)
		local Left = ac.getTrackAISplineSides(Racers[i].Spline.Progress).x
		local Right = ac.getTrackAISplineSides(Racers[i].Spline.Progress).y
		Racers[i].Spline.TrackWidth = (Left + Right) / 2
		Racers[i].Spline.DistToLeft = Left
		Racers[i].Spline.DistToRight = Right
		local offset = ac.worldCoordinateToTrack(Car.position).x
		if offset < 0 then Racers[i].Spline.OffsetFromSplineCenter = offset * Left
		else Racers[i].Spline.OffsetFromSplineCenter = offset * Right end
		if offset < -1 or offset > 1 then Racers[i].isOffTrack = true
		else Racers[i].isOffTrack = false end
		if MySettings:get("MISC", "FIX_BLIPPING", 1) > 0 and Car.gas < 0.1 and Car.brake > 0 then Racers[i].SmoothThrottleRampUp = 0.5 end
	end
end

-- Avoid other cars by stepping off the racing line.
function UpdateIntendedSplineOffsets()
	for i = 1, #Racers do
		local currentIndex = Racers[i].index
		local rivalWeWereAlreadyAvoiding = -1
		local newSplineOffset = 0
		local thisCar = ac.getCar(currentIndex)
		Racers[i].ThrottleLimiter = 1
		Racers[i].SplineFollower.kP = 2
		Racers[i].ChasingTarget = -1
		if thisCar.velocity:length() > 1 then
			for z = 1, #Racers do
				local carIndex = Racers[z].index
				if math.abs(currentIndex - carIndex) > 0 and not Racers[z].isOffTrack then
					local targetCar = ac.getCar(carIndex)
					if rivalWeWereAlreadyAvoiding == -1 or math.abs(Racers[i].Spline.Progress - Racers[z].Spline.Progress) < math.abs(Racers[i].Spline.Progress - Racers[rivalWeWereAlreadyAvoiding].Spline.Progress) then
						local distBehindTarget = (Racers[z].Spline.Progress - Racers[i].Spline.Progress) * ProgressToMeters
						if WithinRange(distBehindTarget, 0, 100) then Racers[i].ChasingTarget = Racers[z].index end
						-- If the car ahead is REALLY slow, we assume its having trouble and
						local assumeCarVelocity = targetCar.velocity
						if targetCar.velocity:length() < thisCar.velocity:length() / 2 then assumeCarVelocity = thisCar.velocity end
						local angleTreshold = math.round(angleBetweenVectorsWithMagnitudes(thisCar.velocity, assumeCarVelocity) * (180 / math.pi), 1)
						local distBetweenCars = (targetCar.position - thisCar.position):length()
						local latDiffBetweenCars = Racers[z].Spline.DistToLeft + Racers[z].Spline.OffsetFromSplineCenter - (Racers[i].Spline.DistToLeft + Racers[i].Spline.OffsetFromSplineCenter)
						local spdDifference = thisCar.velocity:length() - targetCar.velocity:length()
						local sToReach = distBetweenCars / spdDifference
						if spdDifference <= 0 then sToReach = math.huge end
						local almostSameLane = math.abs(latDiffBetweenCars) < Racers[i].Dimensions.Width + Racers[i].Personality.SpaceLeft
						local atSameLane = math.abs(latDiffBetweenCars) < Racers[i].Dimensions.Width
						local atSameLevel = math.abs(distBehindTarget) < Racers[i].Dimensions.Length + 1
						local almostSameLevel = math.abs(distBehindTarget) < Racers[i].Dimensions.Length + 1 + MySettings:get("AGRESSION", "MIN_DISTANCE", 2)
						local imBehind = distBehindTarget > 0
						-- Too close, lift
						if imBehind and almostSameLevel and atSameLane then Racers[i].ThrottleLimiter = 0 end
						-- Closing in too fast, lift
						if sToReach < 5 and imBehind then
							if atSameLane then
								Racers[i].ThrottleLimiter = math.clamp(map(sToReach, 3, 1, 1, 0.05), 0.05, 1)
							elseif almostSameLane then
								Racers[i].ThrottleLimiter = math.clamp(map(spdDifference, 15, 30, 1, 0.01), 0.01, 1)
							end
						end
						if almostSameLane and (imBehind or atSameLevel) then
							local tooFarToPass = (Racers[i].Dimensions.Length + spdDifference * 2.5) * map(math.abs(angleTreshold), 0, 30, 1, 0)
							if ac.getTrackUpcomingTurn(Racers[i].index).x / thisCar.velocity:length() < 3 then
								tooFarToPass = (Racers[i].Dimensions.Length + spdDifference * 5) * map(math.abs(angleTreshold), 0, 15, 1, 0)
							end
							local closeEnoughToPass = distBehindTarget < tooFarToPass
							if closeEnoughToPass or atSameLevel then
								local targetsLane = Racers[z].Spline.OffsetFromSplineCenter
								local offsetSize = Racers[i].Dimensions.Width + Racers[i].Personality.SpaceLeft
								local newLane = targetsLane
								if latDiffBetweenCars < 0 then
									newLane = newLane + offsetSize
									if not atSameLevel then
										if Racers[z].Spline.DistToRight < Racers[i].Dimensions.Width * 3 then newLane = newLane - offsetSize end
									end
								else
									newLane = newLane - offsetSize
									if not atSameLevel then
										if Racers[z].Spline.DistToLeft < Racers[i].Dimensions.Width * 3 then newLane = newLane + offsetSize end
									end
								end
								if newLane == targetsLane then 
								else
									newSplineOffset = newLane
									rivalWeWereAlreadyAvoiding = z
									if distBehindTarget > 0 then Racers[i].SplineFollower.kP = 4 end
									-- only aggresively avoid if you are the one behind.
								end
							end
						end
					end
				end
			end
		end
		Racers[i].SplineFollower:setTarget(newSplineOffset, Racers[i].Spline.TrackWidth * 2)
		-- If the race is starting, keep them on their starting lane for the first few seconds.
		if thisCar.lapCount < 1 and thisCar.lapTimeMs < 2e3 + thisCar.racePosition * 500 then
			Racers[i].SplineFollower:setTarget(Racers[i].Spline.OffsetFromSplineCenter)
		end
		Racers[i].ThrottleLimiter = math.clamp(Racers[i].ThrottleLimiter, 0, Racers[i].SmoothThrottleRampUp)
		physics.setAIThrottleLimit(Racers[i].index, Racers[i].ThrottleLimiter)
	end
end

function angleBetweenVectorsWithMagnitudes(v1, v2)
	local dot = v1.x * v2.x + v1.y * v2.y + v1.z * v2.z
	local mag1 = math.sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z)
	local mag2 = math.sqrt(v2.x * v2.x + v2.y * v2.y + v2.z * v2.z)
	if mag1 == 0 or mag2 == 0 then
		return 0
		-- At least one vector is zero
	end
	local cosAngle = dot / (mag1 * mag2)
	cosAngle = math.max(-1, math.min(1, cosAngle))
	-- Clamp
	return math.acos(cosAngle)
end

-- Map a value from one range to another
function map(value, in_min, in_max, out_min, out_max)
	-- First, normalize the input to a 0-1 range
	local normalized = (value - in_min) / (in_max - in_min)
	-- Then map to the output range
	return out_min + normalized * (out_max - out_min)
end

function WithinRange(val, min, max) return val >= min and val <= max end

if MySettings:get("BASIC", "ENABLED", true) then
	IndexRacers()

	-- - UPDATER
	function UpdatePullFromGitHub()
		web.loadRemoteAssets("https://github.com/Eddlm/Full-Send-AI/releases/latest/download/FullSendAI.zip", function(err, folder)
			if err then ac.log(err) end
			got_folder = folder
			io.scanDir(folder, "*", function(file, attributes, data)
				ac.log("Checking: " .. file)
				if file == "full_send_ai.ini" then
					io.move(folder .. "/" .. file, ac.getFolder(ac.FolderID.ExtCfgSys) .. "/" .. file, true)
					ac.log("Updated " .. file)
				else
					io.move(folder .. "/" .. file, ac.getFolder(ac.FolderID.ScriptOrigin) .. "/" .. file, true)
					ac.log("Updated " .. file)
				end
			end)
			io.deleteDir(folder)
		end)
	end

	if MySettings:get("MISC", "UPDATE_FREQUENCY", 1) > 0 then
		local dice = 0 + (os.time() - io.getAttributes(ac.getFolder(ac.FolderID.ScriptOrigin) .. "/FullSendAI.lua").creationTime) / 60 / 24
		if dice > MySettings:get("MISC", "UPDATE_FREQUENCY", 1) then
			if DEBUG_MODE then ac.log"Attempting to update FullSend AI..." end
			UpdatePullFromGitHub()
		else if DEBUG_MODE then ac.log"Not updating yet." end end
	else if DEBUG_MODE then ac.log"Updating disabled by user." end end
end