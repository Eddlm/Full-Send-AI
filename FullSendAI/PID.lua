-- PID-inspired Inertial Value Controller
local PID = {
	value = 0,
	-- current value
	target = 0,
	-- target value
	velocity = 0,
	-- rate of change (inertia/speed)
	maxSpeed = math.huge,
	-- maximum change per second
	maxAccel = math.huge,
	-- maximum acceleration
	kP = 1,
	-- proportional gain (spring force)
	kD = 0.1,
	-- derivative gain (damping)
	kI = 0,
	-- integral gain (optional, for offset correction)
	integral = 0
	-- integral accumulator
}

-- Initialize a new inertial value controller
function PID:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

-- Update the current value (call this every frame with deltaTime)
function PID:update(dt)
	if dt <= 0 then return self.value end
	-- Calculate error
	local error = self.target - self.value
	-- PID terms
	local proportional = error * self.kP
	local derivative = -self.velocity * self.kD
	self.integral = self.integral + error * dt
	local integral = self.integral * self.kI
	-- Calculate desired acceleration
	local acceleration = proportional + derivative + integral
	-- Apply acceleration limits
	if math.abs(acceleration) > self.maxAccel then
		acceleration = self.maxAccel * (acceleration > 0 and 1 or -1)
	end
	-- Update velocity
	self.velocity = self.velocity + acceleration * dt
	-- Apply speed limits
	if math.abs(self.velocity) > self.maxSpeed then
		self.velocity = self.maxSpeed * (self.velocity > 0 and 1 or -1)
	end
	-- Update value
	self.value = self.value + self.velocity * dt
	-- Optional: small threshold to prevent oscillation
	if math.abs(error) < 1e-3 and math.abs(self.velocity) < 1e-3 then
		self.value = self.target
		self.velocity = 0
	end
	return self.value
end

-- Set the target value
function PID:setTarget(target, maxval)
	local max = maxval or 20
	self.target = math.clamp(target, -max, max)
end

-- Set the current value immediately (bypassing inertia)
function PID:setValue(value)
	self.value = value
	self.velocity = 0
	self.integral = 0
end

-- Get the current value
function PID:getValue() return self.value end

-- Get the current target
function PID:getTarget() return self.target end

-- Modify the target value
function PID:modifyTarget(target, maxval)
	local max = maxval or 20
	self.target = math.clamp(self:getTarget() + target, -max, max)
end

-- Get whether the value is close to the target (within threshold)
function PID:isClose(threshold)
	threshold = threshold or 1e-3
	return math.abs(self.target - self.value) < threshold
end

return PID