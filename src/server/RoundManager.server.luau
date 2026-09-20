-- src/server/RoundManager.server.luau
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local ServerScriptService = game:GetService("ServerScriptService")

local Stations = workspace:WaitForChild("Stations")
local StationSpawn = Stations:WaitForChild("StationSpawn")
local StationTemplate = Stations:WaitForChild("StationTemplate")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundEvent = Remotes:WaitForChild("RoundEvent")
local CutEvent = Remotes:WaitForChild("CutEvent")
local TriggerEvent = Remotes:WaitForChild("TriggerEvent")
local AccuracyEvent = ServerScriptService:WaitForChild("AccuracyEvent")

-- Get or create EndPracticeEvent BindableEvent
local EndPracticeEvent = ServerScriptService:FindFirstChild("EndPracticeEvent")
if not EndPracticeEvent then
	EndPracticeEvent = Instance.new("BindableEvent")
	EndPracticeEvent.Name = "EndPracticeEvent"
	EndPracticeEvent.Parent = ServerScriptService
end

local CAMERA_FOV = 70
local SCREEN_FILL = 0.3
local CAMERA_HEIGHT_OFFSET = 0.3
local CUT_TIME = 10
local MIN_PLAYERS = 1
local REVEAL_DELAY = 1
local WINNER_HOLD = 3
local INTERMISSION = 10

local roundActive = false
local roundPlayers = {}
local lateJoiners = {}
local spectators = {}
local playerStations = {}
local playerScores = {}
local playerLocked = {}
local cutConnections = {}

local function teleportToLobby(plr: Player)
	local lobbySpawn = workspace:FindFirstChild("LobbySpawn", true)
	if plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") and lobbySpawn then
		plr.Character.HumanoidRootPart.CFrame = lobbySpawn.CFrame + Vector3.new(0, 3, 0)
	end
end

RoundEvent.OnServerEvent:Connect(function(plr, msg, isPlaying)
	if msg == "TOGGLE_PARTICIPATION" then
		if isPlaying == false then
			spectators[plr] = true
			RoundEvent:FireClient(plr, "WAIT_ROUND", nil)
		else
			spectators[plr] = nil
		end
	end
end)

Players.PlayerAdded:Connect(function(plr)
	plr.CharacterAdded:Connect(function()
		task.wait(0.1)
		teleportToLobby(plr)
	end)
	if roundActive then
		lateJoiners[plr] = true
		RoundEvent:FireClient(plr, "WAIT_ROUND", nil)
	end
end)

Players.PlayerRemoving:Connect(function(plr)
	lateJoiners[plr] = nil
	spectators[plr] = nil
	playerStations[plr] = nil
	playerScores[plr] = nil
	playerLocked[plr] = nil

	for _, obj in workspace:GetChildren() do
		if obj:GetAttribute("OwnerID") == plr.UserId then
			obj:Destroy()
		end
	end

	local index = table.find(roundPlayers, plr)
	if index then
		table.remove(roundPlayers, index)
	end
end)

local function fireRound(msg, data)
	for _, plr in roundPlayers do
		RoundEvent:FireClient(plr, msg, data)
	end
end

local function fireAll(msg, data)
	for _, plr in Players:GetPlayers() do
		RoundEvent:FireClient(plr, msg, data)
	end
end

local function allPlayersLocked()
	if #roundPlayers == 0 then
		return true
	end
	for _, plr in roundPlayers do
		if not playerLocked[plr] then
			return false
		end
	end
	return true
end

local function getCameraDistance(obj): number
	local size
	if obj:IsA("Model") then
		local _, objSize = obj:GetBoundingBox()
		size = math.max(objSize.X, objSize.Y, objSize.Z)
	else
		size = math.max(obj.Size.X, obj.Size.Y, obj.Size.Z)
	end
	local halfFOV = math.rad(CAMERA_FOV / 2)
	return (size / 2) / (math.tan(halfFOV) * SCREEN_FILL)
end

local function spawnStations()
	local stationParts = StationSpawn:GetChildren()
	table.sort(stationParts, function(a, b)
		return a.Name < b.Name
	end)

	for i, plr in roundPlayers do
		local stationAnchor = stationParts[i]
		if not stationAnchor then
			warn("[RoundManager] Not enough StationSpawn parts for:", plr.Name)
			continue
		end

		local offsetY = CFrame.new(0, 7, 0)
		local spawnPart = StationTemplate.SpawnPart:Clone()
		local camPart = StationTemplate.CamPart:Clone()

		spawnPart.CFrame = stationAnchor.CFrame * offsetY
		camPart.CFrame = stationAnchor.CFrame * offsetY

		spawnPart.Parent = workspace
		camPart.Parent = workspace

		playerStations[plr] = {
			spawnPart = spawnPart,
			camPart = camPart,
			anchor = stationAnchor,
		}
	end
end

local function destroyStations()
	for plr, station in playerStations do
		if station.spawnPart then
			station.spawnPart:Destroy()
		end
		if station.camPart then
			station.camPart:Destroy()
		end
	end
	playerStations = {}
end

local function assignObjects()
	local cuttables = ReplicatedStorage:WaitForChild("Cuttables"):GetChildren()
	if #cuttables == 0 then
		warn("[RoundManager] No objects in Cuttables folder")
		return
	end

	local template = cuttables[math.random(1, #cuttables)]

	for _, plr in roundPlayers do
		local station = playerStations[plr]
		if not station then
			continue
		end

		for _, obj in workspace:GetChildren() do
			if obj:GetAttribute("OwnerID") == plr.UserId then
				obj:Destroy()
			end
		end

		local obj = template:Clone()
		obj.Parent = workspace

		if obj:IsA("Model") then
			obj:PivotTo(station.spawnPart.CFrame)
			for _, part in obj:GetDescendants() do
				if part:IsA("BasePart") then
					part.Anchored = true
				end
			end
		else
			obj.CFrame = station.spawnPart.CFrame
			obj.Anchored = true
		end

		local objCenter = obj:IsA("Model") and obj:GetPivot().Position or obj.Position
		local dist = getCameraDistance(obj)
		local anchorCF = station.anchor.CFrame
		local camPos = objCenter + anchorCF.LookVector * dist + Vector3.new(0, CAMERA_HEIGHT_OFFSET, 0)

		station.camPart.CFrame = CFrame.new(camPos, objCenter + Vector3.new(0, CAMERA_HEIGHT_OFFSET, 0))

		obj:SetAttribute("Cuttable", true)
		obj:SetAttribute("OwnerID", plr.UserId)

		CutEvent:FireClient(plr, "ASSIGN_OBJECT", obj)
		TriggerEvent:FireClient(plr, station.camPart)
	end
end

local function doReveal()
	local results = {}
	for _, plr in roundPlayers do
		table.insert(results, {
			name = plr.Name,
			accuracy = playerScores[plr] or 0,
		})
	end
	table.sort(results, function(a, b)
		return a.accuracy > b.accuracy
	end)

	for i, result in results do
		task.wait(REVEAL_DELAY)
		fireAll("REVEAL_PLAYER", {
			name = result.name,
			accuracy = result.accuracy,
			rank = i,
		})
	end

	task.wait(REVEAL_DELAY)
	local winner = results[1]
	if winner then
		fireAll("WINNER", {
			name = winner.name,
			accuracy = winner.accuracy,
		})

		local winnerPlr = Players:FindFirstChild(winner.name)
		if winnerPlr and winnerPlr.Character then
			local head = winnerPlr.Character:FindFirstChild("Head")
			if head then
				local crown = Instance.new("Part")
				crown.Name = "Crown"
				crown.Size = Vector3.new(1.5, 0.5, 1.5)
				crown.Color = Color3.fromRGB(255, 215, 0)
				crown.Material = Enum.Material.Neon
				crown.Anchored = false
				crown.CanCollide = false
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = crown
				weld.Part1 = head
				weld.Parent = crown
				crown.CFrame = head.CFrame * CFrame.new(0, 1.5, 0)
				crown.Parent = winnerPlr.Character
				game:GetService("Debris"):AddItem(crown, WINNER_HOLD + 2)
			end
		end
	end
end

local function clearRound()
	destroyStations()

	for _, obj in workspace:GetChildren() do
		if obj:GetAttribute("Cuttable") ~= nil or obj:GetAttribute("OwnerID") ~= nil then
			obj:Destroy()
		end
	end

	for _, plr in roundPlayers do
		teleportToLobby(plr)
	end

	lateJoiners = {}
	roundPlayers = {}
	playerScores = {}
	playerLocked = {}

	for _, conn in cutConnections do
		conn:Disconnect()
	end
	cutConnections = {}
	roundActive = false
end

local function startRound()
	roundActive = true
	print("[RoundManager] Starting round")

	roundPlayers = {}
	for _, plr in Players:GetPlayers() do
		if not lateJoiners[plr] and not spectators[plr] then
			table.insert(roundPlayers, plr)
		end
	end

	-- Destroy practice stations for players entering this round
	for _, plr in roundPlayers do
		EndPracticeEvent:Fire(plr, true)
	end

	if #roundPlayers == 0 then
		print("[RoundManager] Aborting round: no eligible playing players")
		clearRound()
		return
	end

	spawnStations()
	assignObjects()
	fireRound("ROUND_START", nil)

	for plr in lateJoiners do
		RoundEvent:FireClient(plr, "WAIT_ROUND", nil)
	end
	for plr in spectators do
		RoundEvent:FireClient(plr, "WAIT_ROUND", nil)
	end

	local conn1 = CutEvent.OnServerEvent:Connect(function(plr)
		if playerLocked[plr] or not roundActive then
			return
		end
		if not table.find(roundPlayers, plr) then
			return
		end
		playerLocked[plr] = true
		RoundEvent:FireClient(plr, "LOCKED_IN", nil)
	end)
	table.insert(cutConnections, conn1)

	local conn2 = AccuracyEvent.Event:Connect(function(plr, accuracy)
		if not roundActive then
			return
		end
		playerScores[plr] = accuracy
	end)
	table.insert(cutConnections, conn2)

	local conn3 = RoundEvent.OnServerEvent:Connect(function(plr, msg, accuracy)
		if msg == "REPORT_ACCURACY" and roundActive then
			playerScores[plr] = accuracy
		end
	end)
	table.insert(cutConnections, conn3)

	for t = CUT_TIME, 1, -1 do
		if not roundActive then
			return
		end
		fireRound("TIMER", t)
		task.wait(1)
		if allPlayersLocked() then
			print("[RoundManager] All active players locked in early")
			break
		end
	end

	for _, plr in roundPlayers do
		if not playerLocked[plr] then
			playerLocked[plr] = true
			RoundEvent:FireClient(plr, "LOCKED_IN", nil)
		end
	end

	fireRound("TIMER", 0)

	local waited = 0
	while waited < 15 do
		local allScored = true
		for _, plr in roundPlayers do
			if playerScores[plr] == nil then
				allScored = false
				break
			end
		end
		if allScored or #roundPlayers == 0 then
			break
		end
		task.wait(0.1)
		waited += 0.1
	end

	if #roundPlayers > 0 then
		fireAll("REVEAL_START", nil)
		doReveal()
		task.wait(WINNER_HOLD)
	end

	fireAll("ROUND_RESET", nil)
	clearRound()
end

task.spawn(function()
	while true do
		while #Players:GetPlayers() < MIN_PLAYERS do
			fireAll("WAIT_PLAYER", MIN_PLAYERS - #Players:GetPlayers())
			task.wait(1)
		end

		for t = INTERMISSION, 1, -1 do
			fireAll("INTERMISSION", t)
			task.wait(1)
		end

		startRound()
		task.wait(2)
	end
end)
