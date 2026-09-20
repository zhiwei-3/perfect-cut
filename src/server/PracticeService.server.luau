-- src/server/PracticeService.server.luau
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local PracticeFolder = workspace:WaitForChild("PracticeStations")
local StationSpawn = PracticeFolder:WaitForChild("StationSpawn")
local StationTemplate = PracticeFolder:WaitForChild("StationTemplate")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CutEvent = Remotes:WaitForChild("CutEvent")
local TriggerEvent = Remotes:WaitForChild("TriggerEvent")

-- ─── BindableEvents Setup ──────────────────────────────────────────────────────
local EndPracticeEvent = ServerScriptService:FindFirstChild("EndPracticeEvent")
if not EndPracticeEvent then
	EndPracticeEvent = Instance.new("BindableEvent")
	EndPracticeEvent.Name = "EndPracticeEvent"
	EndPracticeEvent.Parent = ServerScriptService
end

local AccuracyEvent = ServerScriptService:FindFirstChild("AccuracyEvent")
if not AccuracyEvent then
	AccuracyEvent = Instance.new("BindableEvent")
	AccuracyEvent.Name = "AccuracyEvent"
	AccuracyEvent.Parent = ServerScriptService
end

local activePractice = {} -- [Player] = { spawnPart, camPart, activeObject, pad }

local function getCameraDistance(obj): number
	local size
	if obj:IsA("Model") then
		local _, objSize = obj:GetBoundingBox()
		size = math.max(objSize.X, objSize.Y, objSize.Z)
	else
		size = math.max(obj.Size.X, obj.Size.Y, obj.Size.Z)
	end
	return (size / 2) / (math.tan(math.rad(35)) * 0.3)
end

local function endPractice(plr: Player, isTransitioningToRound: boolean?)
	local data = activePractice[plr]
	if not data then
		return
	end

	if data.activeObject then
		data.activeObject:Destroy()
	end
	if data.spawnPart then
		data.spawnPart:Destroy()
	end
	if data.camPart then
		data.camPart:Destroy()
	end

	activePractice[plr] = nil

	if not isTransitioningToRound then
		Remotes.RoundEvent:FireClient(plr, "ROUND_RESET", nil)
	end
	print(string.format("[PracticeService] %s practice station destroyed", plr.Name))
end

-- ─── Spawn New Practice Object (Looping) ──────────────────────────────────────
local function spawnNewPracticeObject(plr: Player)
	local data = activePractice[plr]
	if not data then
		return
	end

	if data.activeObject and data.activeObject.Parent then
		data.activeObject:Destroy()
	end

	local cuttables = ReplicatedStorage:WaitForChild("Cuttables"):GetChildren()
	if #cuttables == 0 then
		return
	end

	local template = cuttables[math.random(1, #cuttables)]
	local obj = template:Clone()
	obj.Parent = PracticeFolder

	if obj:IsA("Model") then
		obj:PivotTo(data.spawnPart.CFrame)
		for _, part in obj:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	else
		obj.CFrame = data.spawnPart.CFrame
		obj.Anchored = true
	end

	local objCenter = obj:IsA("Model") and obj:GetPivot().Position or obj.Position
	local dist = getCameraDistance(obj)
	local camPos = objCenter + data.pad.CFrame.LookVector * dist + Vector3.new(0, 0.3, 0)

	data.camPart.CFrame = CFrame.new(camPos, objCenter + Vector3.new(0, 0.3, 0))

	obj:SetAttribute("Cuttable", true)
	obj:SetAttribute("OwnerID", plr.UserId)
	obj:SetAttribute("IsPractice", true)

	data.activeObject = obj

	CutEvent:FireClient(plr, "ASSIGN_OBJECT", obj)
	TriggerEvent:FireClient(plr, data.camPart)
	Remotes.RoundEvent:FireClient(plr, "ROUND_START", "practice")
end

-- ─── Listen for Practice Cut Accuracy to Loop Next Object ────────────────────
AccuracyEvent.Event:Connect(function(plr: Player, accuracy: number)
	local data = activePractice[plr]
	if data then
		print(
			string.format("[PracticeService] %s scored %.2f%% in practice. Respawning in 2.5s...", plr.Name, accuracy)
		)
		task.delay(2.5, function()
			if activePractice[plr] == data then
				spawnNewPracticeObject(plr)
			end
		end)
	end
end)

EndPracticeEvent.Event:Connect(function(plr: Player?, isTransitioningToRound: boolean?)
	if plr then
		endPractice(plr, isTransitioningToRound)
	else
		for practicingPlr in activePractice do
			endPractice(practicingPlr, isTransitioningToRound)
		end
	end
end)

local function startPractice(plr: Player, pad: BasePart)
	if activePractice[plr] then
		return
	end

	local cuttables = ReplicatedStorage:WaitForChild("Cuttables"):GetChildren()
	if #cuttables == 0 then
		return
	end

	local offsetY = CFrame.new(0, 7, 0)
	local spawnPart = StationTemplate.SpawnPart:Clone()
	local camPart = StationTemplate.CamPart:Clone()

	spawnPart.CFrame = pad.CFrame * offsetY
	camPart.CFrame = pad.CFrame * offsetY

	spawnPart.Parent = PracticeFolder
	camPart.Parent = PracticeFolder

	local template = cuttables[math.random(1, #cuttables)]
	local obj = template:Clone()
	obj.Parent = PracticeFolder

	if obj:IsA("Model") then
		obj:PivotTo(spawnPart.CFrame)
		for _, part in obj:GetDescendants() do
			if part:IsA("BasePart") then
				part.Anchored = true
			end
		end
	else
		obj.CFrame = spawnPart.CFrame
		obj.Anchored = true
	end

	local objCenter = obj:IsA("Model") and obj:GetPivot().Position or obj.Position
	local dist = getCameraDistance(obj)
	local camPos = objCenter + pad.CFrame.LookVector * dist + Vector3.new(0, 0.3, 0)

	camPart.CFrame = CFrame.new(camPos, objCenter + Vector3.new(0, 0.3, 0))

	obj:SetAttribute("Cuttable", true)
	obj:SetAttribute("OwnerID", plr.UserId)
	obj:SetAttribute("IsPractice", true)

	activePractice[plr] = {
		spawnPart = spawnPart,
		camPart = camPart,
		activeObject = obj,
		pad = pad,
	}

	CutEvent:FireClient(plr, "ASSIGN_OBJECT", obj)
	TriggerEvent:FireClient(plr, camPart)
	Remotes.RoundEvent:FireClient(plr, "ROUND_START", "practice")

	print(string.format("[PracticeService] %s started practice on %s", plr.Name, pad.Name))
end

for _, pad in StationSpawn:GetChildren() do
	if pad:IsA("BasePart") then
		pad.Touched:Connect(function(hit)
			local char = hit.Parent
			local plr = Players:GetPlayerFromCharacter(char)
			if plr and not activePractice[plr] then
				startPractice(plr, pad)
			end
		end)
	end
end

Players.PlayerRemoving:Connect(function(plr)
	endPractice(plr, false)
end)

Remotes.RoundEvent.OnServerEvent:Connect(function(plr, msg)
	if msg == "EXIT_PRACTICE" then
		endPractice(plr, false)
	end
end)
