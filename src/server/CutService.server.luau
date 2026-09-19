local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GeometryService = game:GetService("GeometryService")
local ServerScriptService = game:GetService("ServerScriptService")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CutEvent = Remotes:WaitForChild("CutEvent")
local RotateEvent = Remotes:WaitForChild("RotateEvent")
local ResetEvent = Remotes:WaitForChild("ResetEvent")
local AccuracyEvent = ServerScriptService:WaitForChild("AccuracyEvent")

local EXTENT = 30

local GEO_OPTIONS = {
	CollisionFidelity = Enum.CollisionFidelity.Default,
	RenderFidelity = Enum.RenderFidelity.Automatic,
}

local function makeBox(player, cutOrigin, cutNormal, camCFrame, side)
	local right = cutNormal:Cross(camCFrame.UpVector)
	if right.Magnitude < 0.01 then
		right = cutNormal:Cross(camCFrame.RightVector)
	end
	right = right.Unit
	local up = right:Cross(cutNormal).Unit
	local rot = CFrame.fromMatrix(Vector3.zero, right, up, -cutNormal)

	local box = Instance.new("Part")
	box.Parent = workspace
	box.CFrame = CFrame.new(cutOrigin + cutNormal * side * (EXTENT / 2)) * rot
	box.Size = Vector3.new(EXTENT, EXTENT, EXTENT)
	box.Anchored = true
	box.CanCollide = false
	box.CastShadow = false
	box.Color = Color3.fromRGB(255, 255, 255)
	box.Transparency = 1
	box.Name = "negateBox"
	return box
end

RotateEvent.OnServerEvent:Connect(function(player, object, newCFrame)
	if typeof(newCFrame) ~= "CFrame" then
		return
	end
	if not object or not object:IsDescendantOf(workspace) then
		return
	end
	if object:GetAttribute("OwnerID") ~= player.UserId then
		return
	end

	if object:IsA("Model") then
		object:PivotTo(newCFrame)
	else
		object.CFrame = newCFrame
	end
end)

ResetEvent.OnServerEvent:Connect(function(player, object, originalCFrame)
	if typeof(originalCFrame) ~= "CFrame" then
		return
	end
	if not object or not object:IsDescendantOf(workspace) then
		return
	end
	if object:GetAttribute("OwnerID") ~= player.UserId then
		return
	end

	if object:IsA("Model") then
		object:PivotTo(originalCFrame)
	else
		object.CFrame = originalCFrame
	end
end)

CutEvent.OnServerEvent:Connect(function(player, object, cutOrigin, cutNormal, camCFrame)
	print("[Server] received - object:", object, "origin:", cutOrigin)

	if typeof(cutOrigin) ~= "Vector3" or typeof(cutNormal) ~= "Vector3" or typeof(camCFrame) ~= "CFrame" then
		return
	end
	if not object or not object:IsDescendantOf(workspace) or not object:GetAttribute("Cuttable") then
		return
	end

	object:SetAttribute("Cuttable", false)

	local partToCut: BasePart?
	if object:IsA("BasePart") then
		partToCut = object
	elseif object:IsA("Model") then
		partToCut = object.PrimaryPart or object:FindFirstChildWhichIsA("BasePart", true)
	end

	if not partToCut then
		warn("[CutService] No BasePart found to cut")
		AccuracyEvent:Fire(player, 0)
		CutEvent:FireClient(player, "CUT_RESULT", 0)
		return
	end

	cutNormal = cutNormal.Unit

	local box1 = makeBox(player, cutOrigin, cutNormal, camCFrame, 1)
	local box2 = makeBox(player, cutOrigin, cutNormal, camCFrame, -1)

	local clone1 = partToCut:Clone()
	local clone2 = partToCut:Clone()
	clone1.Parent = workspace
	clone2.Parent = workspace

	local half1, half2
	local ok, err = pcall(function()
		local r1 = GeometryService:SubtractAsync(clone1, { box2 }, GEO_OPTIONS)
		local r2 = GeometryService:SubtractAsync(clone2, { box1 }, GEO_OPTIONS)
		half1 = r1 and r1[1] or nil
		half2 = r2 and r2[1] or nil
	end)

	game:GetService("Debris"):AddItem(box1, 10)
	game:GetService("Debris"):AddItem(box2, 10)
	clone1:Destroy()
	clone2:Destroy()

	if not ok or not half1 or not half2 then
		warn("[CutService] Cut failed:", err)
		AccuracyEvent:Fire(player, 0)
		CutEvent:FireClient(player, "CUT_RESULT", 0)
		return
	end

	for _, half in { half1, half2 } do
		half.Color = partToCut.Color
		half.Material = partToCut.Material
		half.Anchored = false
		half.Parent = workspace
	end

	half1.AssemblyLinearVelocity = cutNormal * 3
	half2.AssemblyLinearVelocity = -cutNormal * 3

	object:Destroy()

	game:GetService("Debris"):AddItem(half1, 5)
	game:GetService("Debris"):AddItem(half2, 5)

	local m1 = half1.Mass
	local m2 = half2.Mass
	local total = m1 + m2
	local accuracy = total > 0 and math.clamp((1 - math.abs(m1 - m2) / total) * 100, 0, 100) or 0

	AccuracyEvent:Fire(player, accuracy)
	CutEvent:FireClient(player, "CUT_RESULT", accuracy)
	print(string.format("[Cut] %s -> %.2f%%", player.Name, accuracy))
end)
