local PID = {
	value = 0,
	target = 0,
	velocity = 0,
	maxSpeed = math.huge,
	maxAccel = math.huge,
	kP = 1,
	kD = 0.1,
	kI = 0,
	integral = 0
}

function PID:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self
	return o
end

function PID:update(dt)
	if dt <= 0 then return self.value end
	local error = self.target - self.value
	local proportional = error * self.kP
	local derivative = -self.velocity * self.kD
	self.integral = self.integral + error * dt
	local integral = self.integral * self.kI
	local acceleration = proportional + derivative + integral
	if math.abs(acceleration) > self.maxAccel then
		acceleration = self.maxAccel * (acceleration > 0 and 1 or -1)
	end
	self.velocity = self.velocity + acceleration * dt
	if math.abs(self.velocity) > self.maxSpeed then
		self.velocity = self.maxSpeed * (self.velocity > 0 and 1 or -1)
	end
	self.value = self.value + self.velocity * dt
	if math.abs(error) < 1e-3 and math.abs(self.velocity) < 1e-3 then
		self.value = self.target
		self.velocity = 0
	end
	return self.value
end

function PID:setTarget(target, maxval)
	local max = maxval or 20
	self.target = math.clamp(target, -max, max)
end

function PID:setValue(value)
	self.value = value
	self.velocity = 0
	self.integral = 0
end

function PID:getValue() return self.value end

function PID:getTarget() return self.target end

function PID:modifyTarget(target, maxval)
	local max = maxval or 20
	self.target = math.clamp(self:getTarget() + target, -max, max)
end

function PID:isClose(threshold)
	threshold = threshold or 1e-3
	return math.abs(self.target - self.value) < threshold
end

return PID