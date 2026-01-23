local GForceCalculator = {}
GForceCalculator.__index = GForceCalculator

function GForceCalculator.new()
	local self = setmetatable({}, GForceCalculator)
	self.prevVelocity = vec3(0, 0, 0)
	self.Gs = vec3(0, 0, 0)
	return self
end

function GForceCalculator:Update(velocity, forward, up, dt)
	if dt <= 0 then return vec3(0, 0, 0) end
	local acceleration = { x = (velocity.x - self.prevVelocity.x) / dt, y = (velocity.y - self.prevVelocity.y) / dt, z = (velocity.z - self.prevVelocity.z) / dt }
	local right = { x = forward.y * up.z - forward.z * up.y, y = forward.z * up.x - forward.x * up.z, z = forward.x * up.y - forward.y * up.x }
	local forwardDot = forward.x * acceleration.x + forward.y * acceleration.y + forward.z * acceleration.z
	local rightDot = right.x * acceleration.x + right.y * acceleration.y + right.z * acceleration.z
	local upDot = up.x * acceleration.x + up.y * acceleration.y + up.z * acceleration.z
	local gForce = 9.80665
	local longitudinal = forwardDot / gForce
	local lateral = rightDot / gForce
	local vertical = upDot / gForce
	self.prevVelocity = { x = velocity.x, y = velocity.y, z = velocity.z }
	self.Gs = vec3(math.round(longitudinal, 2), math.round(lateral, 2), math.round(vertical, 2))
	return self.Gs
end

return GForceCalculator