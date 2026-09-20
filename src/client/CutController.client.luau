local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera
local sfxGroup = SoundService:WaitForChild("SFX")
local sliceSound = sfxGroup:WaitForChild("SliceSound")

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local CutEvent = Remotes:WaitForChild("CutEvent")
local TriggerEvent = Remotes:WaitForChild("TriggerEvent")
local RoundEvent = Remotes:WaitForChild("RoundEvent")
local RotateEvent = Remotes:WaitForChild("RotateEvent")
local ResetEvent = Remotes:WaitForChild("ResetEvent")

local CutUI = player:WaitForChild("PlayerGui"):WaitForChild("CutUI")
local CutControls = CutUI:WaitForChild("CutControls")
local ResetButton = CutControls:WaitForChild("ResetButton")
local CutButton = CutControls:WaitForChild("CutButton")
local ClearButton = CutControls:WaitForChild("ClearButton")
local ExitButton = CutControls:FindFirstChild("ExitButton")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CutPreview"
screenGui.ResetOnSpawn = false
screenGui.Parent = player:WaitForChild("PlayerGui")

local lineFrame = Instance.new("Frame", screenGui)
lineFrame.BackgroundColor3 = Color3.fromRGB(255, 50, 50)
lineFrame.BorderSizePixel = 0
lineFrame.AnchorPoint = Vector2.new(0.5, 0.5)
lineFrame.Visible = false

local function showLine(a: Vector2, b: Vector2)
	local diff = b - a
	lineFrame.Size = UDim2.fromOffset(diff.Magnitude, 3)
	lineFrame.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	lineFrame.Rotation = math.deg(math.atan2(diff.Y, diff.X))
	lineFrame.Visible = true
end

local function hideLine()
	lineFrame.Visible = false
end

local activeObject: BasePart? = nil
local originalCFrame: CFrame? = nil
local canDraw = false
local hasCommitted = false
local hasFiredCut = false

local isDrawing = false
local drawStart: Vector2? = nil
local drawEnd: Vector2? = nil
local lastDrawStart: Vector3? = nil
local lastDrawEnd: Vector3? = nil
local drawTouchId = nil

local isRotating = false
local rotateStart: Vector2? = nil
local rotateTouchId = nil

local CUT_THRESHOLD = 200
local CAST_DIST = 10
local ROTATE_SENSITIVITY = 0.3

local function setCameraTo(part: BasePart)
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = part.CFrame
end

local function resetCamera()
	camera.CameraType = Enum.CameraType.Custom
end

TriggerEvent.OnClientEvent:Connect(function(camPart)
	if camPart and camPart:IsA("BasePart") then
		setCameraTo(camPart)
		TriggerEvent:FireServer()
	end
end)

local function applyRotation(rot: CFrame)
	if not activeObject then
		return
	end

	local pivot = activeObject:IsA("Model") and activeObject:GetPivot().Position or activeObject.Position

	local newCF = CFrame.new(pivot) * rot * CFrame.new(-pivot)

	if activeObject:IsA("Model") then
		activeObject:PivotTo(newCF * activeObject:GetPivot())
	else
		activeObject.CFrame = newCF * activeObject.CFrame
	end
end

local function syncRotation()
	if not activeObject then
		return
	end
	local cf = activeObject:IsA("Model") and activeObject:GetPivot() or activeObject.CFrame
	RotateEvent:FireServer(activeObject, cf)
end

local highlight = Instance.new("Highlight")
highlight.FillTransparency = 1
highlight.DepthMode = Enum.HighlightDepthMode.Occluded
highlight.Parent = nil

local mouse = player:GetMouse()
local isHoveringObject = false

RunService.RenderStepped:Connect(function()
	if activeObject then
		local target = mouse.Target
		local hovering = (
			target ~= nil
			and (target == activeObject or (activeObject:IsA("Model") and target:IsDescendantOf(activeObject)))
		) or isRotating

		if hovering ~= isHoveringObject then
			isHoveringObject = hovering
			highlight.Parent = hovering and activeObject or nil
		end
	else
		isHoveringObject = false
		highlight.Parent = nil
	end
end)

local function calculateCut()
	if not drawStart or not drawEnd then
		return
	end
	if (drawEnd - drawStart).Magnitude < CUT_THRESHOLD then
		return
	end
	lastDrawStart = drawStart
	lastDrawEnd = drawEnd
end

local function fireCut()
	if not activeObject or not lastDrawStart or not lastDrawEnd or hasFiredCut then
		return
	end

	local ray1 = camera:ScreenPointToRay(lastDrawStart.X, lastDrawStart.Y)
	local ray2 = camera:ScreenPointToRay(lastDrawEnd.X, lastDrawEnd.Y)

	local w1 = ray1.Origin + ray1.Direction * CAST_DIST
	local w2 = ray2.Origin + ray2.Direction * CAST_DIST

	local lineDir = (w2 - w1)
	if lineDir.Magnitude < 0.01 then
		return
	end
	lineDir = lineDir.Unit

	local normal = lineDir:Cross(camera.CFrame.LookVector)
	if normal.Magnitude < 0.01 then
		return
	end
	normal = normal.Unit

	local origin = (w1 + w2) / 2

	hasFiredCut = true
	print("[Client] Firing CutEvent", origin, normal)
	CutEvent:FireServer(activeObject, origin, normal, camera.CFrame)
	if sliceSound then
		sliceSound:Play()
	end
end

local function isTap(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end

local function getTouchPos(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

local function isTouchOnObject(screenPos: Vector2): boolean
	if not activeObject then
		return false
	end
	local unitRay = camera:ScreenPointToRay(screenPos.X, screenPos.Y)
	local result = workspace:Raycast(unitRay.Origin, unitRay.Direction * 500)
	if not result then
		return false
	end
	local hit = result.Instance
	return hit == activeObject or (activeObject:IsA("Model") and hit:IsDescendantOf(activeObject))
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp or not isTap(input) then
		return
	end
	local pos = getTouchPos(input)

	if input.UserInputType == Enum.UserInputType.Touch then
		if isTouchOnObject(pos) and rotateTouchId == nil and activeObject then
			rotateTouchId = input
			rotateStart = pos
			isRotating = true
		elseif not isTouchOnObject(pos) and drawTouchId == nil and canDraw and not hasCommitted then
			drawTouchId = input
			isDrawing = true
			drawStart = pos
			drawEnd = pos
		end
	else
		if isTouchOnObject(pos) and activeObject then
			isRotating = true
			rotateStart = pos
		elseif canDraw and not hasCommitted then
			isDrawing = true
			drawStart = pos
			drawEnd = pos
		end
	end
end)

UserInputService.InputChanged:Connect(function(input)
	if isRotating and rotateStart and activeObject then
		local isDesktop = input.UserInputType == Enum.UserInputType.MouseMovement
		local isMobile = input.UserInputType == Enum.UserInputType.Touch and input == rotateTouchId

		if isDesktop or isMobile then
			local current = getTouchPos(input)
			local delta = current - rotateStart
			rotateStart = current

			local rot = CFrame.fromAxisAngle(camera.CFrame.UpVector, math.rad(delta.X * ROTATE_SENSITIVITY))
				* CFrame.fromAxisAngle(camera.CFrame.RightVector, math.rad(delta.Y * ROTATE_SENSITIVITY))
			applyRotation(rot)
		end
	end

	if not isDrawing then
		return
	end
	if input.UserInputType == Enum.UserInputType.Touch and input ~= drawTouchId then
		return
	end

	if not canDraw or hasCommitted then
		isDrawing = false
		drawTouchId = nil
		hideLine()
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		drawEnd = getTouchPos(input)
		showLine(drawStart, drawEnd)
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if not isTap(input) then
		return
	end

	local isRotateInput = input.UserInputType == Enum.UserInputType.Touch and input == rotateTouchId
	local isDesktopRotate = input.UserInputType == Enum.UserInputType.MouseButton1
		and isRotating
		and drawTouchId == nil
		and not isDrawing

	if isRotateInput or isDesktopRotate then
		isRotating = false
		rotateTouchId = nil
		rotateStart = nil
		syncRotation()
		return
	end

	if input.UserInputType == Enum.UserInputType.Touch and input ~= drawTouchId then
		return
	end
	if not isDrawing or not canDraw or hasCommitted then
		return
	end

	isDrawing = false
	drawTouchId = nil

	if not drawStart or not drawEnd then
		return
	end
	if (drawEnd - drawStart).Magnitude < CUT_THRESHOLD then
		hideLine()
		return
	end

	calculateCut()
end)

ResetButton.MouseButton1Click:Connect(function()
	if not activeObject or not originalCFrame or hasCommitted then
		return
	end
	if activeObject:IsA("Model") then
		activeObject:PivotTo(originalCFrame)
	else
		activeObject.CFrame = originalCFrame
	end
	ResetEvent:FireServer(activeObject, originalCFrame)
end)

ClearButton.MouseButton1Click:Connect(function()
	if hasCommitted then
		return
	end
	lastDrawStart = nil
	lastDrawEnd = nil
	hideLine()
end)

CutButton.MouseButton1Click:Connect(function()
	if not canDraw or hasCommitted then
		return
	end
	if not lastDrawStart or not lastDrawEnd then
		return
	end
	hideLine()
	fireCut()
end)

ExitButton.MouseButton1Click:Connect(function()
	RoundEvent:FireServer("EXIT_PRACTICE")
end)

CutEvent.OnClientEvent:Connect(function(msg, ...)
	if msg == "ASSIGN_OBJECT" then
		activeObject = ...
		hasCommitted = false
		hasFiredCut = false -- Reset state to allow slicing the newly spawned object
		originalCFrame = activeObject:IsA("Model") and activeObject:GetPivot() or activeObject.CFrame
	elseif msg == "CUT_RESULT" then
		local accuracy = ...
		print(string.format("Your accuracy: %.2f%%", accuracy))
		canDraw = false
		hasCommitted = true
		hideLine()
	end
end)

RoundEvent.OnClientEvent:Connect(function(msg, data)
	if msg == "ROUND_START" then
		canDraw = true
		hasCommitted = false
	elseif msg == "TIMER" then
		if data == 0 then
			canDraw = false
			if isDrawing then
				isDrawing = false
				drawTouchId = nil
				drawStart = nil
				drawEnd = nil
				hideLine()
			end

			if not hasFiredCut then
				if lastDrawStart and lastDrawEnd then
					print("[Timer] Auto-firing cut")
					hideLine()
					fireCut()
				else
					print("[Timer] No line drawn, reporting 0%")
					RoundEvent:FireServer("REPORT_ACCURACY", 0)
					hasCommitted = true
				end
			end
		end
	elseif msg == "LOCKED_IN" then
		canDraw = false
		hasCommitted = true
	elseif msg == "ROUND_RESET" then
		resetCamera()
		canDraw = false
		hasCommitted = false
		hasFiredCut = false
		activeObject = nil
		originalCFrame = nil
		lastDrawStart = nil
		lastDrawEnd = nil
		isHoveringObject = false
		highlight.Parent = nil
		isRotating = false
		rotateTouchId = nil
		drawTouchId = nil
		rotateStart = nil
		hideLine()
	end
end)
