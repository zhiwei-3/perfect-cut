-- StarterPlayerScripts/RoundUI (LocalScript)
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundEvent = Remotes:WaitForChild("RoundEvent")
local CutEvent = Remotes:WaitForChild("CutEvent")

local CutUI = player:WaitForChild("PlayerGui"):WaitForChild("CutUI")
local CutControls = CutUI:WaitForChild("CutControls")
local roundGui = player:WaitForChild("PlayerGui"):WaitForChild("RoundUI")
local lobbyGui = player:WaitForChild("PlayerGui"):WaitForChild("LobbyUI")
local afkButton = lobbyGui:WaitForChild("LobbyPanel"):WaitForChild("AfkButton")
local joinState = afkButton:WaitForChild("State")
local revealFrame = roundGui:WaitForChild("RevealPanel")
local statusLabel = roundGui:WaitForChild("Status")
local rankingLabel = revealFrame:WaitForChild("Ranking")

-- ─── Local State Tracking ──────────────────────────────────────────────────────
local isPractice = false
local lockedIn = false
local currentAccuracy = nil

-- ─── Join / Lobby Toggle Button Setup ────────────────────────────────────────
afkButton.MouseButton1Click:Connect(function()
	local isPlaying = joinState.Value
	RoundEvent:FireServer("TOGGLE_PARTICIPATION", isPlaying)
end)

-- ─── Helpers ──────────────────────────────────────────────────────────────────
local function addRevealRow(name: string, accuracy: number, rank: number)
	local medal = rank == 1 and "🥇" or rank == 2 and "🥈" or "🥉"

	local row = rankingLabel:Clone()
	row.Visible = true
	row.Parent = revealFrame
	row.Name = tostring(rank)
	row.TextColor3 = rank == 1 and Color3.fromRGB(255, 215, 0) or Color3.new(1, 1, 1)
	row.Text = string.format("%s  %s  —  %.2f%%", medal, name, accuracy)
	row.LayoutOrder = rank
end

local function clearRevealRows()
	for _, child in revealFrame:GetChildren() do
		if child:IsA("TextLabel") and child.Name ~= "Ranking" then
			child:Destroy()
		end
	end
end

local function resetUI()
	CutUI.Enabled = false
	local exitBtn = CutControls:FindFirstChild("ExitButton")
	if exitBtn then
		exitBtn.Visible = false
	end
	statusLabel.Visible = false
	revealFrame.Visible = false
	statusLabel.Text = ""
	clearRevealRows()
end

-- ─── Accuracy & Cut Result Display ────────────────────────────────────────────
CutEvent.OnClientEvent:Connect(function(msg, ...)
	if msg == "CUT_RESULT" then
		local accuracy = ...
		currentAccuracy = accuracy
		lockedIn = true
		statusLabel.Visible = true

		if isPractice then
			statusLabel.Text = string.format("🎯  Accuracy: %.2f%%", accuracy)
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		else
			statusLabel.Text = string.format("🎯  Accuracy: %.2f%%  |  ✅  Locked in!", accuracy)
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		end
	end
end)

-- ─── Event Handling ───────────────────────────────────────────────────────────
RoundEvent.OnClientEvent:Connect(function(msg, data)
	if msg == "ROUND_START" then
		resetUI()
		lockedIn = false
		currentAccuracy = nil

		if data == "practice" then
			isPractice = true
			local exitBtn = CutControls:FindFirstChild("ExitButton")
			if exitBtn then
				exitBtn.Visible = true
			end
		else
			isPractice = false
		end

		statusLabel.Visible = true
		statusLabel.Text = "✏️  Draw your cut line!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
		CutUI.Enabled = true
	elseif msg == "WAIT_ROUND" then
		isPractice = false
		lockedIn = false
		currentAccuracy = nil
		resetUI()
		statusLabel.Visible = true
		statusLabel.Text = "⏳  Waiting in lobby for next round..."
		statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	elseif msg == "INTERMISSION" then
		-- Ignore intermission timer if player is currently in Practice Mode
		if not isPractice then
			statusLabel.Visible = true
			statusLabel.Text = "Next round in " .. tostring(data) .. "..."
			statusLabel.TextColor3 = Color3.new(1, 1, 1)
		end
	elseif msg == "WAIT_PLAYER" then
		-- Ignore waiting player text if player is currently in Practice Mode
		if not isPractice then
			statusLabel.Visible = true
			statusLabel.Text = "Need " .. data .. " more player to start..."
			statusLabel.TextColor3 = Color3.new(1, 1, 1)
		end
	elseif msg == "TIMER" then
		-- Do NOT overwrite statusLabel if player has already locked in or is practicing
		if not isPractice and not lockedIn then
			local t = data
			if t > 0 then
				statusLabel.Visible = true
				statusLabel.Text = tostring(t)
				statusLabel.TextColor3 = t <= 3 and Color3.fromRGB(255, 80, 80) or Color3.new(1, 1, 1)
			else
				statusLabel.Text = ""
			end
		end
	elseif msg == "LOCKED_IN" then
		lockedIn = true
		if not isPractice and currentAccuracy == nil then
			statusLabel.Visible = true
			statusLabel.Text = "✅  Locked in! Waiting for others..."
			statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
		end
	elseif msg == "REVEAL_START" then
		isPractice = false
		statusLabel.Visible = true
		statusLabel.Text = ""
		clearRevealRows()
	elseif msg == "REVEAL_PLAYER" then
		addRevealRow(data.name, data.accuracy, data.rank)
	elseif msg == "WINNER" then
		revealFrame.Visible = true
		statusLabel.Visible = true
		statusLabel.Text = "👑  " .. data.name .. " wins!\n" .. string.format("%.2f%% accuracy", data.accuracy)
		statusLabel.TextColor3 = Color3.fromRGB(255, 215, 0)
	elseif msg == "ROUND_RESET" then
		isPractice = false
		lockedIn = false
		currentAccuracy = nil
		resetUI()
	end
end)
