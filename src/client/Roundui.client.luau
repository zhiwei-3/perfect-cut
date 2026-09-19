local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local RoundEvent = Remotes:WaitForChild("RoundEvent")

local CutUI = player:WaitForChild("PlayerGui"):WaitForChild("CutUI")
local roundGui = player:WaitForChild("PlayerGui"):WaitForChild("RoundUI")
local revealFrame = roundGui:WaitForChild("RevealPanel")
local statusLabel = roundGui:WaitForChild("Status")
local rankingLabel = revealFrame:WaitForChild("Ranking")

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
	statusLabel.Visible = false
	revealFrame.Visible = false
	statusLabel.Text = ""
	clearRevealRows()
end

RoundEvent.OnClientEvent:Connect(function(msg, data)
	if msg == "ROUND_START" then
		resetUI()
		statusLabel.Visible = true
		statusLabel.Text = "✏️  Draw your cut line!"
		statusLabel.TextColor3 = Color3.fromRGB(255, 170, 0)
		CutUI.Enabled = true
	elseif msg == "WAIT_ROUND" then
		resetUI()
		statusLabel.Visible = true
		statusLabel.Text = "⏳  Round in progress... Waiting for next intermission"
		statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	elseif msg == "INTERMISSION" then
		statusLabel.Visible = true
		statusLabel.Text = "Next round in " .. tostring(data) .. "..."
		statusLabel.TextColor3 = Color3.new(1, 1, 1)
	elseif msg == "WAIT_PLAYER" then
		statusLabel.Visible = true
		statusLabel.Text = "Need " .. data .. " more player to start..."
		statusLabel.TextColor3 = Color3.new(1, 1, 1)
	elseif msg == "TIMER" then
		local t = data
		if t > 0 then
			statusLabel.Visible = true
			statusLabel.Text = tostring(t)
			statusLabel.TextColor3 = t <= 3 and Color3.fromRGB(255, 80, 80) or Color3.new(1, 1, 1)
		else
			statusLabel.Text = ""
		end
	elseif msg == "LOCKED_IN" then
		statusLabel.Visible = true
		statusLabel.Text = "✅  Locked in! Waiting for others..."
		statusLabel.TextColor3 = Color3.fromRGB(100, 255, 100)
	elseif msg == "REVEAL_START" then
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
		task.wait(1)
		resetUI()
	end
end)
