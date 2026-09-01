--// ai_chasers
--// Demo: drive the AI car from Spawn to workspace.Nodes.Node1 using physics.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local AIManager = require(script.Parent:WaitForChild("ai_manager"))

local Storage_Vehicles: Folder = ReplicatedStorage:WaitForChild("Vehicles")
local Nodes: Folder = workspace:WaitForChild("Nodes")
local Spawn: BasePart = workspace:WaitForChild("Spawn")
local targetNode: BasePart = Nodes:WaitForChild("Node1") :: BasePart
local carTemplate: Model = Storage_Vehicles:WaitForChild("ai_vudor") :: Model

local MAX_SPEED = 35
local MAX_ACCELERATION = 40
local APPROACH_SPEED_SCALE = 4
local SPEED_GAIN = 2.5
local ARRIVAL_RADIUS = 8
local ARRIVAL_SPEED = 2

-- 🚧 PLACEHOLDER STEERING SYSTEM: chassis yaw torque for the first physics demo.
-- Replace this later with steerable-wheel/tire forces without changing the node logic.
local STEERING_GAIN = 40000
local YAW_DAMPING = 8000
local MAX_STEERING_TORQUE = 100000

local WHEEL_NAMES = { "FL", "FR", "RL", "RR" }

local carModel, weightPart, wheels = AIManager.InitializeCar(carTemplate, Spawn)

local DRIVE_START_DELAY = 3
local driveEnabled = false
local hasReportedArrival = false
local lastDebugTime = 0
local startTime = os.clock()

task.delay(DRIVE_START_DELAY, function()
	driveEnabled = true
	print(string.format("ai_chasers: drive enabled after %.1f seconds", DRIVE_START_DELAY))
end)

local steeringAttachment = Instance.new("Attachment")
steeringAttachment.Name = "AI_PlaceholderSteeringAttachment"
steeringAttachment.Parent = weightPart

local steeringTorque = Instance.new("Torque")
steeringTorque.Name = "AI_PlaceholderSteeringTorque"
steeringTorque.Attachment0 = steeringAttachment
steeringTorque.RelativeTo = Enum.ActuatorRelativeTo.World
steeringTorque.Torque = Vector3.zero
steeringTorque.Parent = weightPart

local driveAttachment = Instance.new("Attachment")
driveAttachment.Name = "AI_DriveAttachment"
driveAttachment.Parent = weightPart

local driveForce = Instance.new("VectorForce")
driveForce.Name = "AI_DriveForce"
driveForce.Attachment0 = driveAttachment
driveForce.RelativeTo = Enum.ActuatorRelativeTo.World
driveForce.ApplyAtCenterOfMass = true
driveForce.Force = Vector3.zero
driveForce.Parent = weightPart

print(string.format("ai_chasers: driving %s to %s", carModel.Name, targetNode:GetFullName()))

RunService.Heartbeat:Connect(function()
	if not weightPart.Parent then
		return
	end

	-- Give the spawned suspension and assembly three seconds to settle before
	-- applying propulsion or steering.
	if not driveEnabled then
		return
	end

	-- Keep navigation planar for this first ground-vehicle test.
	local offset = targetNode.Position - weightPart.Position
	local flatOffset = Vector3.new(offset.X, 0, offset.Z)
	local distance = flatOffset.Magnitude

	local forward = weightPart.CFrame.LookVector
	local right = weightPart.CFrame.RightVector
	local flatForward = Vector3.new(forward.X, 0, forward.Z)
	local flatRight = Vector3.new(right.X, 0, right.Z)

	if flatForward.Magnitude < 0.001 or flatRight.Magnitude < 0.001 then
		return
	end

	flatForward = flatForward.Unit
	flatRight = flatRight.Unit

	local targetDirection = if distance > 0.001 then flatOffset.Unit else flatForward
	local headingError = math.atan2(flatRight:Dot(targetDirection), flatForward:Dot(targetDirection))

	-- For this first navigation demo, apply force along the planar target
	-- vector. It guarantees progress while the placeholder yaw torque works
	-- on aligning the chassis. Later tire forces can replace this guidance
	-- force with longitudinal wheel-frame traction.
	local driveDirection = targetDirection
	local driveSpeed = weightPart.AssemblyLinearVelocity:Dot(driveDirection)
	local desiredSpeed = math.clamp(distance * APPROACH_SPEED_SCALE, 0, MAX_SPEED)
	if distance <= ARRIVAL_RADIUS then
		desiredSpeed = 0
	end

	-- Force-based acceleration/braking. Negative acceleration applies braking force.
	local acceleration = math.clamp(
		(desiredSpeed - driveSpeed) * SPEED_GAIN,
		-MAX_ACCELERATION,
		MAX_ACCELERATION
	)
	local totalForce = driveDirection * acceleration * weightPart:GetMass()

	-- Propulsion is applied at each physical wheel, not to a hidden motorized
	-- chassis. The wheel constraints transfer the traction into the suspension.
	driveForce.Force = Vector3.zero
	local perWheelForce = totalForce / #WHEEL_NAMES
	for _, wheelData in pairs(wheels) do
		wheelData.Propulsion.Force = perWheelForce
	end

	-- Physical yaw control. This applies torque; it never overwrites orientation.
	if distance > ARRIVAL_RADIUS then
		local yawRate = weightPart.AssemblyAngularVelocity:Dot(Vector3.yAxis)
		local requestedTorque = headingError * STEERING_GAIN - yawRate * YAW_DAMPING
		local steeringTorqueMagnitude = math.clamp(
			requestedTorque,
			-MAX_STEERING_TORQUE,
			MAX_STEERING_TORQUE
		)
		steeringTorque.Torque = Vector3.yAxis * steeringTorqueMagnitude
	else
		steeringTorque.Torque = Vector3.zero
	end

	if distance <= ARRIVAL_RADIUS and math.abs(driveSpeed) <= ARRIVAL_SPEED then
		-- Hold the vehicle stopped while allowing the physics engine to settle it.
		driveForce.Force = Vector3.zero
		for _, wheelData in pairs(wheels) do
			wheelData.Propulsion.Force = Vector3.zero
		end
		if not hasReportedArrival then
			hasReportedArrival = true
			print(string.format(
				"ai_chasers: %s reached %s after %.2f seconds (distance=%.2f, speed=%.2f)",
				carModel.Name,
				targetNode.Name,
				os.clock() - startTime,
				distance,
				driveSpeed
			))
		end
	end

	if os.clock() - lastDebugTime >= 1 then
		lastDebugTime = os.clock()
		print(string.format(
			"ai_chasers debug: distance=%.2f speed=%.2f position=(%d, %d, %d) wheelForce=%.0f torque=%.0f",
			distance,
			driveSpeed,
			math.round(weightPart.Position.X),
			math.round(weightPart.Position.Y),
			math.round(weightPart.Position.Z),
			perWheelForce.Magnitude,
			steeringTorque.Torque.Magnitude
		))
	end
end)
