--// ai_manager
--// Shared AI vehicle initialization commands.

local RunService = game:GetService("RunService")

local AIManager = {}

local Vehicles: Folder? = workspace:FindFirstChild("Vehicles") :: Folder?
if not Vehicles then
	Vehicles = Instance.new("Folder")
	Vehicles.Name = "Vehicles"
	Vehicles.Parent = workspace
end

--// Suspension tuning
local DESIRED_SAG = 0.5
local DAMPING_RATIO = 0.75
local WHEEL_TARGET_MASS = 40
local SUSPENSION_TRAVEL_UP = 0.6
local SUSPENSION_TRAVEL_DOWN = 0.3
local SPRING_CROSSING_MARGIN = 0.25
local INSTALLED_SPRING_LENGTH = SUSPENSION_TRAVEL_UP + SPRING_CROSSING_MARGIN
local SPRING_MAX_FORCE_MULTIPLIER = 10
local WEIGHT_PART_TRANSPARENCY = 0.5
local SPAWN_CLEARANCE = 3

local WHEEL_NAMES = { "FL", "FR", "RL", "RR" }

local function setWheelMass(wheel: BasePart, targetMass: number)
	wheel.CustomPhysicalProperties = PhysicalProperties.new(1, 0.3, 0.5)

	local massAtDensity1 = wheel:GetMass()
	assert(massAtDensity1 > 0, string.format("%s has zero measurable mass", wheel:GetFullName()))

	local targetDensity = targetMass / massAtDensity1
	wheel.CustomPhysicalProperties = PhysicalProperties.new(targetDensity, 0.3, 0.5)
end

function AIManager.InitializeCar(template: Model, spawnPart: BasePart)
	assert(template and template:IsA("Model"), "AIManager.InitializeCar: template must be a Model")
	assert(spawnPart and spawnPart:IsA("BasePart"), "AIManager.InitializeCar: spawnPart must be a BasePart")

	local carModel = template:Clone()
	carModel.Parent = Vehicles

	local body = carModel:WaitForChild("Body") :: Model
	local boundsCFrame, boundsSize = body:GetBoundingBox()

	local weightPart = Instance.new("Part")
	weightPart.Name = "AI_Weight"
	weightPart.Size = boundsSize
	weightPart.CFrame = boundsCFrame
	weightPart.Anchored = false
	weightPart.CanCollide = false
	weightPart.CanQuery = false
	weightPart.CanTouch = false
	weightPart.Massless = false
	weightPart.Transparency = WEIGHT_PART_TRANSPARENCY
	weightPart.Parent = carModel

	carModel.PrimaryPart = weightPart

	for _, part in ipairs(body:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = weightPart
			weld.Part1 = part
			weld.Parent = part
		end
	end

	local chassisMass = weightPart:GetMass()
	local quarterChassisMass = chassisMass / #WHEEL_NAMES
	local weightPerCorner = quarterChassisMass * workspace.Gravity
	local springFreeLength = INSTALLED_SPRING_LENGTH + DESIRED_SAG
	local springStiffness = weightPerCorner / DESIRED_SAG
	local effectiveMass = (quarterChassisMass * WHEEL_TARGET_MASS)
		/ (quarterChassisMass + WHEEL_TARGET_MASS)
	local criticalDamping = 2 * math.sqrt(springStiffness * effectiveMass)
	local springDamping = DAMPING_RATIO * criticalDamping
	local springMaxForce = weightPerCorner * SPRING_MAX_FORCE_MULTIPLIER

	print(string.format(
		"ai_manager: chassisMass=%.2f quarterMass=%.2f wheelMass=%.1f installedLength=%.3f freeLength=%.3f stiffness=%.1f damping=%.1f maxForce=%.1f",
		chassisMass, quarterChassisMass, WHEEL_TARGET_MASS, INSTALLED_SPRING_LENGTH,
		springFreeLength, springStiffness, springDamping, springMaxForce
	))

	local wheels = {}
	local suspensionAxisRotation = CFrame.Angles(0, 0, math.rad(-90))

	for _, wheelName in ipairs(WHEEL_NAMES) do
		local wheel = carModel:WaitForChild(wheelName) :: BasePart
		wheel.Anchored = false
		wheel.CanCollide = true
		wheel.Massless = false
		setWheelMass(wheel, WHEEL_TARGET_MASS)

		local visualParts = wheel:FindFirstChild("Parts")
		if visualParts then
			for _, visual in ipairs(visualParts:GetDescendants()) do
				if visual:IsA("BasePart") then
					visual.Anchored = false
					visual.CanCollide = false
					visual.CanQuery = false
					visual.CanTouch = false
					visual.Massless = true

					local visualWeld = Instance.new("WeldConstraint")
					visualWeld.Part0 = wheel
					visualWeld.Part1 = visual
					visualWeld.Parent = visual
				end
			end
		else
			warn(string.format("ai_manager: %s has no 'Parts' container; visuals will not follow the wheel", wheelName))
		end

		local authoredWheelOffset = weightPart.CFrame:ToObjectSpace(wheel.CFrame)

		-- The carrier separates suspension travel from wheel axle rotation.
		-- A HingeConstraint directly between chassis and wheel would prohibit
		-- the vertical translation needed by the suspension.
		local carrier = Instance.new("Part")
		carrier.Name = wheelName .. "_SuspensionCarrier"
		carrier.Size = Vector3.new(0.4, 0.4, 0.4)
		carrier.CFrame = wheel.CFrame
		carrier.Anchored = false
		carrier.CanCollide = false
		carrier.CanQuery = false
		carrier.CanTouch = false
		carrier.Massless = true
		carrier.Transparency = 1
		carrier.Parent = carModel

		local bodyAttach = Instance.new("Attachment")
		bodyAttach.Name = wheelName .. "_SuspensionTop"
		bodyAttach.CFrame = CFrame.new(authoredWheelOffset.Position + Vector3.yAxis * INSTALLED_SPRING_LENGTH)
			* suspensionAxisRotation
		bodyAttach.Parent = weightPart

		local carrierAttach = Instance.new("Attachment")
		carrierAttach.Name = wheelName .. "_SuspensionBottom"
		carrierAttach.CFrame = suspensionAxisRotation
		carrierAttach.Parent = carrier

		local prismatic = Instance.new("PrismaticConstraint")
		prismatic.Name = wheelName .. "_SuspensionGuide"
		prismatic.Attachment0 = bodyAttach
		prismatic.Attachment1 = carrierAttach
		prismatic.ActuatorType = Enum.ActuatorType.None
		prismatic.LimitsEnabled = true
		prismatic.LowerLimit = INSTALLED_SPRING_LENGTH - SUSPENSION_TRAVEL_UP
		prismatic.UpperLimit = INSTALLED_SPRING_LENGTH + SUSPENSION_TRAVEL_DOWN
		prismatic.Restitution = 0
		prismatic.Parent = weightPart

		local wheelAttach = carrierAttach
		local spring = Instance.new("SpringConstraint")
		spring.Name = wheelName .. "_Spring"
		spring.Attachment0 = bodyAttach
		spring.Attachment1 = carrierAttach
		spring.FreeLength = springFreeLength
		spring.Stiffness = springStiffness
		spring.Damping = springDamping
		spring.MaxForce = springMaxForce
		spring.LimitsEnabled = false
		spring.Parent = weightPart

		-- The carrier-to-wheel hinge allows rolling while the carrier handles
		-- suspension motion. The wheel's thin local X axis is its axle.
		local axleCarrierAttach = Instance.new("Attachment")
		axleCarrierAttach.Name = wheelName .. "_AxleTop"
		axleCarrierAttach.CFrame = CFrame.new()
		axleCarrierAttach.Parent = carrier

		local axleWheelAttach = Instance.new("Attachment")
		axleWheelAttach.Name = wheelName .. "_Axle"
		axleWheelAttach.CFrame = CFrame.new()
		axleWheelAttach.Parent = wheel

		local hinge = Instance.new("HingeConstraint")
		hinge.Name = wheelName .. "_AxleRotation"
		hinge.Attachment0 = axleCarrierAttach
		hinge.Attachment1 = axleWheelAttach
		hinge.LimitsEnabled = false
		hinge.Parent = carrier

		local propulsion = Instance.new("VectorForce")
		propulsion.Name = "Propulsion"
		propulsion.Attachment0 = wheelAttach
		propulsion.RelativeTo = Enum.ActuatorRelativeTo.World
		propulsion.ApplyAtCenterOfMass = false
		propulsion.Force = Vector3.zero
		propulsion.Parent = wheel

		wheels[wheelName] = {
			Part = wheel,
			Propulsion = propulsion,
			Spring = spring,
			Suspension = prismatic,
			Axle = hinge,
		}
	end

	carModel:PivotTo(spawnPart.CFrame + Vector3.new(0, SPAWN_CLEARANCE, 0))
	weightPart:SetNetworkOwner(nil)

	task.defer(function()
		RunService.Heartbeat:Wait()
		for wheelName, wheelData in pairs(wheels) do
			print(string.format(
				"ai_manager %s: springLength=%.3f suspensionPosition=%.3f expected=%.3f",
				wheelName, wheelData.Spring.CurrentLength, wheelData.Suspension.CurrentPosition,
				INSTALLED_SPRING_LENGTH
			))
		end
	end)

	return carModel, weightPart, wheels
end

return AIManager
