local cloneref = cloneref or function(o) return o end
local Players = cloneref(game:GetService("Players"))
local HttpService = cloneref(game:GetService("HttpService"))
local RunService = cloneref(game:GetService("RunService"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local TextService = cloneref(game:GetService("TextService"))
local TeleportService = cloneref(game:GetService("TeleportService"))
local MarketplaceService = cloneref(game:GetService("MarketplaceService"))
local CoreGui = cloneref(game:GetService("CoreGui"))

local httpRequest = (syn and syn.request) or (http and http.request) or http_request or request or (fluxus and fluxus.request) or (getgenv and getgenv().request)
if not httpRequest then 
	error("Your executor does not support HTTP requests!") 
end

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera or workspace:WaitForChild("CurrentCamera")

-- Whitelist check (Multiple admins supported)
local ADMIN_WHITELIST = {
	["bs_top12345678"] = true,
	["hfalr2"] = true
}
local isAdmin = (ADMIN_WHITELIST[player.Name] == true)

local getHui = gethui or function() return CoreGui end
local targetParent = getHui()

if targetParent:FindFirstChild("DeadlyChatGui") then 
	targetParent.DeadlyChatGui:Destroy() 
end
if playerGui:FindFirstChild("DeadlyChatGui") then 
	playerGui.DeadlyChatGui:Destroy() 
end

local FIREBASE_URL = "https://test-1f23c-default-rtdb.firebaseio.com"
local gameNameCache = {}

local function getGameName(placeId)
	placeId = tonumber(placeId)
	if not placeId or placeId == 0 then return "Unknown Game" end
	if gameNameCache[placeId] then return gameNameCache[placeId] end
	local success, info = pcall(function()
		return MarketplaceService:GetProductInfo(placeId, Enum.InfoType.Asset)
	end)
	if success and info and info.Name then
		gameNameCache[placeId] = info.Name
		return info.Name
	end
	return "Place: " .. tostring(placeId)
end

local colorPalette = {
	Color3.fromRGB(255, 105, 180), Color3.fromRGB(186, 85, 211), Color3.fromRGB(100, 200, 255),
	Color3.fromRGB(255, 99, 71), Color3.fromRGB(50, 205, 50), Color3.fromRGB(255, 215, 0),
	Color3.fromRGB(255, 140, 0), Color3.fromRGB(0, 255, 255), Color3.fromRGB(255, 0, 255),
	Color3.fromRGB(173, 255, 47), Color3.fromRGB(255, 192, 203), Color3.fromRGB(147, 112, 219),
	Color3.fromRGB(0, 250, 154), Color3.fromRGB(240, 230, 140), Color3.fromRGB(255, 160, 122),
	Color3.fromRGB(127, 255, 212), Color3.fromRGB(221, 160, 221), Color3.fromRGB(176, 224, 230),
	Color3.fromRGB(250, 128, 114), Color3.fromRGB(240, 128, 128), Color3.fromRGB(154, 205, 50),
	Color3.fromRGB(64, 224, 208), Color3.fromRGB(238, 130, 238), Color3.fromRGB(255, 182, 193),
	Color3.fromRGB(135, 206, 235), Color3.fromRGB(255, 222, 173), Color3.fromRGB(152, 251, 152)
}

local function getRandomColor()
	return colorPalette[math.random(1, #colorPalette)]
end

local function makeDraggable(frame, handle)
	handle = handle or frame
	local dragging, dragStart, startPos, dragInput
	handle.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			dragStart = input.Position
			startPos = frame.Position
			input.Changed:Connect(function()
				if input.UserInputState == Enum.UserInputState.End then
					dragging = false
				end
			end)
		end
	end)
	handle.InputChanged:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			dragInput = input
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if input == dragInput and dragging then
			local delta = input.Position - dragStart
			frame.Position = UDim2.new(
				startPos.X.Scale, startPos.X.Offset + delta.X,
				startPos.Y.Scale, startPos.Y.Offset + delta.Y
			)
		end
	end)
end

----------------------------------------------------
-- TARGET STATE & ACTIONS
----------------------------------------------------
local activeWalkSpeed = nil
local activeJumpPower = nil
local isFlying = false
local currentFlySpeed = 50
local flyBV, flyBG, flyConn

local isNoclipping = false
local noclipConn = nil

local function applySpeedAndJump(hum)
	if not hum then return end
	if activeWalkSpeed then
		hum.WalkSpeed = activeWalkSpeed
	end
	if activeJumpPower then
		hum.UseJumpPower = true
		hum.JumpPower = activeJumpPower
		pcall(function() hum.JumpHeight = activeJumpPower / 2.5 end)
	end
end

local function stopNoclipping()
	isNoclipping = false
	if noclipConn then
		noclipConn:Disconnect()
		noclipConn = nil
	end
end

local function startNoclipping()
	stopNoclipping()
	isNoclipping = true
	noclipConn = RunService.Stepped:Connect(function()
		if not isNoclipping then
			stopNoclipping()
			return
		end
		local char = player.Character
		if char then
			for _, part in ipairs(char:GetDescendants()) do
				if part:IsA("BasePart") and part.CanCollide then
					part.CanCollide = false
				end
			end
		end
	end)
end

local function stopFlying()
	isFlying = false
	if flyConn then flyConn:Disconnect() flyConn = nil end
	if flyBV then flyBV:Destroy() flyBV = nil end
	if flyBG then flyBG:Destroy() flyBG = nil end
	
	local char = player.Character
	if char then
		for _, v in ipairs(char:GetDescendants()) do
			if (v:IsA("BodyVelocity") or v:IsA("BodyGyro")) and (v.Name == "TrollFlyBV" or v.Name == "TrollFlyBG") then
				v:Destroy()
			end
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.PlatformStand = false end
	end
end

local function startFlying()
	stopFlying()
	local char = player.Character
	if not char then return end
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hrp or not hum then return end
	isFlying = true
	hum.PlatformStand = true
	
	flyBG = Instance.new("BodyGyro")
	flyBG.Name = "TrollFlyBG"
	flyBG.P = 9e4
	flyBG.maxTorque = Vector3.new(9e9, 9e9, 9e9)
	flyBG.cframe = hrp.CFrame
	flyBG.Parent = hrp
	
	flyBV = Instance.new("BodyVelocity")
	flyBV.Name = "TrollFlyBV"
	flyBV.velocity = Vector3.zero
	flyBV.maxForce = Vector3.new(9e9, 9e9, 9e9)
	flyBV.Parent = hrp
	
	flyConn = RunService.RenderStepped:Connect(function()
		if not isFlying or not hrp or not hrp.Parent or not hum or not hum.Parent then
			stopFlying()
			return
		end
		flyBG.cframe = Camera.CFrame
		local moveDir = Vector3.zero
		if UserInputService:IsKeyDown(Enum.KeyCode.W) then moveDir = moveDir + Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.S) then moveDir = moveDir - Camera.CFrame.LookVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.A) then moveDir = moveDir - Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.D) then moveDir = moveDir + Camera.CFrame.RightVector end
		if UserInputService:IsKeyDown(Enum.KeyCode.Space) then moveDir = moveDir + Vector3.new(0, 1, 0) end
		if UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) then moveDir = moveDir - Vector3.new(0, 1, 0) end
		
		if moveDir.Magnitude == 0 and hum.MoveDirection.Magnitude > 0 then
			local camCFrame = Camera.CFrame
			local lookVector = camCFrame.LookVector
			local rightVector = camCFrame.RightVector
			local flatMove = hum.MoveDirection
			local dotForward = flatMove:Dot(camCFrame.LookVector * Vector3.new(1, 0, 1).Unit)
			local dotRight = flatMove:Dot(rightVector * Vector3.new(1, 0, 1).Unit)
			moveDir = (lookVector * dotForward) + (rightVector * dotRight)
		end
		if hum.Jump then
			moveDir = moveDir + Vector3.new(0, 1, 0)
		end
		if moveDir.Magnitude > 0 then
			flyBV.velocity = moveDir.Unit * currentFlySpeed
		else
			flyBV.velocity = Vector3.zero
		end
	end)
end

player.CharacterAdded:Connect(function(char)
	local hum = char:WaitForChild("Humanoid", 5)
	if hum then
		applySpeedAndJump(hum)
	end
	if isFlying then
		task.delay(0.5, startFlying)
	end
	if isNoclipping then
		task.delay(0.5, startNoclipping)
	end
end)

local function createChatBubble(senderName, messageText)
	if messageText:sub(1, 7) == "[[img]]" then messageText = "[GIF]" end
	local targetPlayer = Players:FindFirstChild(senderName)
	if not targetPlayer or not targetPlayer.Character then return end
	local head = targetPlayer.Character:FindFirstChild("Head")
	if not head then return end
	
	local oldBubble = head:FindFirstChild("DeadlyChatBubble")
	if oldBubble then oldBubble:Destroy() end
	
	local font = Enum.Font.GothamMedium
	local fontSize = 14
	local maxTextWidth = 220
	local textBounds = TextService:GetTextSize(messageText, fontSize, font, Vector2.new(maxTextWidth, 300))
	local baseWidth = math.clamp(textBounds.X + 24, 60, 250)
	local baseHeight = math.clamp(textBounds.Y + 16, 32, 120)
	
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DeadlyChatBubble"
	billboard.Size = UDim2.new(0, baseWidth, 0, baseHeight)
	billboard.StudsOffset = Vector3.new(0, 2.8, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Adornee = head
	billboard.Parent = head
	
	local bubbleFrame = Instance.new("Frame")
	bubbleFrame.Size = UDim2.new(1, 0, 1, 0)
	bubbleFrame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	bubbleFrame.BackgroundTransparency = 0.05
	bubbleFrame.BorderSizePixel = 0
	bubbleFrame.Parent = billboard
	
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bubbleFrame
	
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(210, 210, 210)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = bubbleFrame
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -12, 1, -8)
	label.Position = UDim2.new(0, 6, 0, 4)
	label.BackgroundTransparency = 1
	label.Text = messageText
	label.TextColor3 = Color3.fromRGB(30, 30, 30)
	label.TextSize = fontSize
	label.Font = font
	label.TextWrapped = true
	label.TextTruncate = Enum.TextTruncate.AtEnd
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.TextYAlignment = Enum.TextYAlignment.Center
	label.Parent = bubbleFrame
	
	local renderConnection
	renderConnection = RunService.RenderStepped:Connect(function()
		if not billboard or not billboard.Parent or not head or not head.Parent then
			if renderConnection then renderConnection:Disconnect() end
			return
		end
		local distance = (Camera.CFrame.Position - head.Position).Magnitude
		if distance > 35 then
			local shrinkFactor = math.clamp((80 - distance) / 45, 0.25, 1)
			billboard.Size = UDim2.new(0, baseWidth * shrinkFactor, 0, baseHeight * shrinkFactor)
			label.TextSize = math.clamp(fontSize * shrinkFactor, 8, fontSize)
		else
			billboard.Size = UDim2.new(0, baseWidth, 0, baseHeight)
			label.TextSize = fontSize
		end
	end)
	
	task.delay(5, function()
		if renderConnection then renderConnection:Disconnect() end
		if billboard and billboard.Parent then billboard:Destroy() end
	end)
end

-- Main UI Construction
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "DeadlyChatGui"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 9999
screenGui.Parent = targetParent

local toggleButton = Instance.new("ImageButton")
toggleButton.Name = "ToggleChatButton"
toggleButton.Size = UDim2.new(0, 36, 0, 36)
toggleButton.Position = UDim2.new(0, 10, 0, 10)
toggleButton.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
toggleButton.BackgroundTransparency = 0.3
toggleButton.Image = "rbxassetid://6023426915"
toggleButton.ZIndex = 9999
toggleButton.Parent = screenGui

local toggleCorner = Instance.new("UICorner")
toggleCorner.CornerRadius = UDim.new(1, 0)
toggleCorner.Parent = toggleButton

local unreadBadge = Instance.new("TextLabel")
unreadBadge.Name = "UnreadBadge"
unreadBadge.Size = UDim2.new(0, 18, 0, 18)
unreadBadge.Position = UDim2.new(1, -6, 0, -2)
unreadBadge.BackgroundColor3 = Color3.fromRGB(255, 60, 60)
unreadBadge.TextColor3 = Color3.fromRGB(255, 255, 255)
unreadBadge.TextSize = 11
unreadBadge.Font = Enum.Font.SourceSansBold
unreadBadge.Text = "0"
unreadBadge.Visible = false
unreadBadge.ZIndex = 10000
unreadBadge.Parent = toggleButton

local badgeCorner = Instance.new("UICorner")
badgeCorner.CornerRadius = UDim.new(1, 0)
badgeCorner.Parent = unreadBadge

local mainFrame = Instance.new("Frame")
mainFrame.Name = "MainFrame"
mainFrame.Size = UDim2.new(0, 320, 0, 215)
mainFrame.Position = UDim2.new(0, 10, 0, 55)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BackgroundTransparency = 0.3
mainFrame.BorderSizePixel = 0
mainFrame.Visible = true
mainFrame.ZIndex = 9999
mainFrame.Parent = screenGui

local uiCorner = Instance.new("UICorner")
uiCorner.CornerRadius = UDim.new(0, 6)
uiCorner.Parent = mainFrame

local topBar = Instance.new("Frame")
topBar.Name = "TopHeader"
topBar.Size = UDim2.new(1, 0, 0, 30)
topBar.BackgroundTransparency = 1
topBar.ZIndex = 9999
topBar.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(0, 120, 1, 0)
titleLabel.Position = UDim2.new(0, 8, 0, 0)
titleLabel.Text = "Deadly Chat"
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.TextSize = 14
titleLabel.Font = Enum.Font.SourceSansBold
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.BackgroundTransparency = 1
titleLabel.ZIndex = 9999
titleLabel.Parent = topBar

local onlineButton = Instance.new("TextButton")
onlineButton.Name = "OnlineButton"
onlineButton.Size = UDim2.new(0, 90, 1, 0)
onlineButton.Position = UDim2.new(1, -8, 0, 0)
onlineButton.AnchorPoint = Vector2.new(1, 0)
onlineButton.Text = "Online: 0 👥"
onlineButton.TextColor3 = Color3.fromRGB(100, 255, 100)
onlineButton.TextSize = 12
onlineButton.Font = Enum.Font.SourceSansBold
onlineButton.TextXAlignment = Enum.TextXAlignment.Right
onlineButton.BackgroundTransparency = 1
onlineButton.ZIndex = 9999
onlineButton.Parent = topBar

local usersFrame = Instance.new("Frame")
usersFrame.Name = "UsersFrame"
usersFrame.Size = UDim2.new(0, 210, 0, 215)
usersFrame.Position = UDim2.new(1, 6, 0, 0)
usersFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
usersFrame.BackgroundTransparency = 0.2
usersFrame.BorderSizePixel = 0
usersFrame.Visible = false
usersFrame.ZIndex = 10010
usersFrame.Parent = mainFrame

local usersCorner = Instance.new("UICorner")
usersCorner.CornerRadius = UDim.new(0, 6)
usersCorner.Parent = usersFrame

local usersTitle = Instance.new("TextLabel")
usersTitle.Size = UDim2.new(1, -12, 0, 28)
usersTitle.Position = UDim2.new(0, 6, 0, 2)
usersTitle.Text = "Online Users"
usersTitle.TextColor3 = Color3.fromRGB(255, 255, 255)
usersTitle.TextSize = 13
usersTitle.Font = Enum.Font.SourceSansBold
usersTitle.TextXAlignment = Enum.TextXAlignment.Left
usersTitle.BackgroundTransparency = 1
usersTitle.ZIndex = 10011
usersTitle.Parent = usersFrame

local usersScroll = Instance.new("ScrollingFrame")
usersScroll.Size = UDim2.new(1, -12, 1, -34)
usersScroll.Position = UDim2.new(0, 6, 0, 30)
usersScroll.BackgroundTransparency = 1
usersScroll.BorderSizePixel = 0
usersScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
usersScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
usersScroll.ScrollBarThickness = 3
usersScroll.ZIndex = 10011
usersScroll.Parent = usersFrame

local usersListLayout = Instance.new("UIListLayout")
usersListLayout.SortOrder = Enum.SortOrder.LayoutOrder
usersListLayout.Padding = UDim.new(0, 4)
usersListLayout.Parent = usersScroll

----------------------------------------------------
-- ADMIN PANEL IMPLEMENTATION
----------------------------------------------------
local adminButton, adminFrame, adminScroll, targetSelectedLabel
local selectedTarget = nil
local isSpectating = false
local flyingTargets = {}
local noclippingTargets = {}

local speedPresets = {16, 50, 100, 200}
local currentSpeedIdx = 1
local jumpPresets = {50, 100, 200}
local currentJumpIdx = 1
local flySpeedPresets = {50, 100, 200}
local currentFlySpeedIdx = 1

local function sendAdminCommand(action, value, extraData)
	if not selectedTarget then return end
	task.spawn(function()
		pcall(function()
			local body = { Action = action, Value = value }
			if extraData then
				for k, v in pairs(extraData) do body[k] = v end
			end
			httpRequest({
				Url = FIREBASE_URL .. "/commands/" .. selectedTarget.UserId .. ".json",
				Method = "PUT",
				Headers = {["Content-Type"] = "application/json"},
				Body = HttpService:JSONEncode(body)
			})
		end)
	end)
end

-- Persistent spectate camera handler (fixes camera resetting on target rejoin/respawn)
RunService.RenderStepped:Connect(function()
	if isSpectating and selectedTarget then
		local targetPlr = Players:FindFirstChild(selectedTarget.Name)
		if targetPlr and targetPlr.Character then
			local hum = targetPlr.Character:FindFirstChildOfClass("Humanoid")
			if hum and Camera.CameraSubject ~= hum then
				Camera.CameraSubject = hum
			end
		end
	end
end)

if isAdmin then
	adminButton = Instance.new("TextButton")
	adminButton.Name = "AdminButton"
	adminButton.Size = UDim2.new(0, 65, 1, 0)
	adminButton.Position = UDim2.new(1, -105, 0, 0)
	adminButton.AnchorPoint = Vector2.new(1, 0)
	adminButton.Text = "⚙️ Admin"
	adminButton.TextColor3 = Color3.fromRGB(255, 215, 0)
	adminButton.TextSize = 12
	adminButton.Font = Enum.Font.SourceSansBold
	adminButton.BackgroundTransparency = 1
	adminButton.ZIndex = 9999
	adminButton.Parent = topBar

	adminFrame = Instance.new("Frame")
	adminFrame.Name = "AdminFrame"
	adminFrame.Size = UDim2.new(0, 220, 0, 215)
	adminFrame.Position = UDim2.new(1, 6, 0, 0)
	adminFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
	adminFrame.BackgroundTransparency = 0.15
	adminFrame.BorderSizePixel = 0
	adminFrame.Visible = false
	adminFrame.ZIndex = 10020
	adminFrame.Parent = mainFrame

	local adminCorner = Instance.new("UICorner")
	adminCorner.CornerRadius = UDim.new(0, 6)
	adminCorner.Parent = adminFrame

	local adminTitle = Instance.new("TextLabel")
	adminTitle.Size = UDim2.new(1, -12, 0, 22)
	adminTitle.Position = UDim2.new(0, 6, 0, 2)
	adminTitle.Text = "Admin Control Panel"
	adminTitle.TextColor3 = Color3.fromRGB(255, 215, 0)
	adminTitle.TextSize = 13
	adminTitle.Font = Enum.Font.SourceSansBold
	adminTitle.TextXAlignment = Enum.TextXAlignment.Left
	adminTitle.BackgroundTransparency = 1
	adminTitle.ZIndex = 10021
	adminTitle.Parent = adminFrame

	targetSelectedLabel = Instance.new("TextLabel")
	targetSelectedLabel.Size = UDim2.new(1, -12, 0, 16)
	targetSelectedLabel.Position = UDim2.new(0, 6, 0, 22)
	targetSelectedLabel.Text = "Target: None"
	targetSelectedLabel.TextColor3 = Color3.fromRGB(180, 180, 180)
	targetSelectedLabel.TextSize = 11
	targetSelectedLabel.Font = Enum.Font.SourceSansItalic
	targetSelectedLabel.TextXAlignment = Enum.TextXAlignment.Left
	targetSelectedLabel.BackgroundTransparency = 1
	targetSelectedLabel.ZIndex = 10021
	targetSelectedLabel.Parent = adminFrame

	local actionsContainer = Instance.new("Frame")
	actionsContainer.Size = UDim2.new(1, -12, 0, 80)
	actionsContainer.Position = UDim2.new(0, 6, 0, 40)
	actionsContainer.BackgroundTransparency = 1
	actionsContainer.ZIndex = 10021
	actionsContainer.Parent = adminFrame

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0, 64, 0, 22)
	gridLayout.CellPadding = UDim2.new(0, 4, 0, 4)
	gridLayout.Parent = actionsContainer

	local function makeAdminBtn(text, color, onClick)
		local btn = Instance.new("TextButton")
		btn.Text = text
		btn.BackgroundColor3 = color
		btn.TextColor3 = Color3.fromRGB(255, 255, 255)
		btn.TextSize = 10
		btn.Font = Enum.Font.SourceSansBold
		btn.BorderSizePixel = 0
		btn.ZIndex = 10022
		btn.Parent = actionsContainer

		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 3)
		corner.Parent = btn

		btn.MouseButton1Click:Connect(onClick)
		return btn
	end

	makeAdminBtn("TP To", Color3.fromRGB(0, 150, 255), function()
		if not selectedTarget then return end
		local targetPlr = Players:FindFirstChild(selectedTarget.Name)
		if targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChild("HumanoidRootPart") and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
			player.Character.HumanoidRootPart.CFrame = targetPlr.Character.HumanoidRootPart.CFrame * CFrame.new(2, 0, 2)
		end
	end)

	local specBtn
	specBtn = makeAdminBtn("Spec", Color3.fromRGB(120, 80, 220), function()
		if not selectedTarget then return end
		local targetPlr = Players:FindFirstChild(selectedTarget.Name)
		if isSpectating then
			isSpectating = false
			specBtn.Text = "Spec"
			if player.Character and player.Character:FindFirstChildOfClass("Humanoid") then
				Camera.CameraSubject = player.Character:FindFirstChildOfClass("Humanoid")
			end
		else
			if targetPlr and targetPlr.Character and targetPlr.Character:FindFirstChildOfClass("Humanoid") then
				isSpectating = true
				specBtn.Text = "Unspec"
				Camera.CameraSubject = targetPlr.Character:FindFirstChildOfClass("Humanoid")
			end
		end
	end)

	makeAdminBtn("Bring", Color3.fromRGB(220, 100, 0), function()
		if not selectedTarget or not player.Character or not player.Character:FindFirstChild("HumanoidRootPart") then return end
		local myCFrame = player.Character.HumanoidRootPart.CFrame
		sendAdminCommand("bring", nil, { CFrame = {myCFrame:GetComponents()} })
	end)

	local flyBtn
	flyBtn = makeAdminBtn("Fly", Color3.fromRGB(200, 50, 100), function()
		if not selectedTarget then return end
		local isTargetFlying = not flyingTargets[selectedTarget.UserId]
		flyingTargets[selectedTarget.UserId] = isTargetFlying
		flyBtn.Text = isTargetFlying and "Unfly" or "Fly"
		sendAdminCommand(isTargetFlying and "fly" or "unfly")
	end)

	local noclipBtn
	noclipBtn = makeAdminBtn("Noclip", Color3.fromRGB(140, 60, 200), function()
		if not selectedTarget then return end
		local isTargetNoclip = not noclippingTargets[selectedTarget.UserId]
		noclippingTargets[selectedTarget.UserId] = isTargetNoclip
		noclipBtn.Text = isTargetNoclip and "UnNoclip" or "Noclip"
		sendAdminCommand(isTargetNoclip and "noclip" or "unnoclip")
	end)

	local speedBtn
	speedBtn = makeAdminBtn("Speed", Color3.fromRGB(50, 180, 100), function()
		if not selectedTarget then return end
		currentSpeedIdx = (currentSpeedIdx % #speedPresets) + 1
		local val = speedPresets[currentSpeedIdx]
		speedBtn.Text = (val == 16) and "Speed (Norm)" or ("Speed (" .. val .. ")")
		sendAdminCommand("walkspeed", val)
	end)

	local jumpBtn
	jumpBtn = makeAdminBtn("Jump", Color3.fromRGB(220, 150, 0), function()
		if not selectedTarget then return end
		currentJumpIdx = (currentJumpIdx % #jumpPresets) + 1
		local val = jumpPresets[currentJumpIdx]
		jumpBtn.Text = (val == 50) and "Jump (Norm)" or ("Jump (" .. val .. ")")
		sendAdminCommand("jumppower", val)
	end)

	local flySpdBtn
	flySpdBtn = makeAdminBtn("FlySpd", Color3.fromRGB(180, 50, 200), function()
		if not selectedTarget then return end
		currentFlySpeedIdx = (currentFlySpeedIdx % #flySpeedPresets) + 1
		local val = flySpeedPresets[currentFlySpeedIdx]
		flySpdBtn.Text = "FlySpd (" .. val .. ")"
		sendAdminCommand("flyspeed", val)
	end)

	adminScroll = Instance.new("ScrollingFrame")
	adminScroll.Size = UDim2.new(1, -12, 1, -130)
	adminScroll.Position = UDim2.new(0, 6, 0, 126)
	adminScroll.BackgroundTransparency = 1
	adminScroll.BorderSizePixel = 0
	adminScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	adminScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	adminScroll.ScrollBarThickness = 3
	adminScroll.ZIndex = 10021
	adminScroll.Parent = adminFrame

	local adminListLayout = Instance.new("UIListLayout")
	adminListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	adminListLayout.Padding = UDim.new(0, 3)
	adminListLayout.Parent = adminScroll

	adminButton.MouseButton1Click:Connect(function()
		adminFrame.Visible = not adminFrame.Visible
		if adminFrame.Visible then usersFrame.Visible = false end
	end)
end

onlineButton.MouseButton1Click:Connect(function()
	usersFrame.Visible = not usersFrame.Visible
	if usersFrame.Visible and adminFrame then adminFrame.Visible = false end
end)

makeDraggable(mainFrame, topBar)

local unreadCount = 0
toggleButton.MouseButton1Click:Connect(function()
	mainFrame.Visible = not mainFrame.Visible
	if mainFrame.Visible then
		unreadCount = 0
		unreadBadge.Visible = false
		unreadBadge.Text = "0"
	end
end)

local scrollFrame = Instance.new("ScrollingFrame")
scrollFrame.Size = UDim2.new(1, -16, 1, -82)
scrollFrame.Position = UDim2.new(0, 8, 0, 32)
scrollFrame.BackgroundTransparency = 1
scrollFrame.BorderSizePixel = 0
scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
scrollFrame.ScrollingDirection = Enum.ScrollingDirection.Y
scrollFrame.ScrollBarThickness = 4
scrollFrame.ZIndex = 10000
scrollFrame.Parent = mainFrame

local scrollPadding = Instance.new("UIPadding")
scrollPadding.PaddingBottom = UDim.new(0, 4)
scrollPadding.Parent = scrollFrame

local uiList = Instance.new("UIListLayout")
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Padding = UDim.new(0, 2)
uiList.Parent = scrollFrame

local typingLabel = Instance.new("TextLabel")
typingLabel.Name = "TypingLabel"
typingLabel.Size = UDim2.new(1, -16, 0, 14)
typingLabel.Position = UDim2.new(0, 8, 1, -48)
typingLabel.BackgroundTransparency = 1
typingLabel.Text = ""
typingLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
typingLabel.TextSize = 12
typingLabel.Font = Enum.Font.SourceSansItalic
typingLabel.TextXAlignment = Enum.TextXAlignment.Left
typingLabel.ZIndex = 10005
typingLabel.Visible = false
typingLabel.Parent = mainFrame

local textBox = Instance.new("TextBox")
textBox.Size = UDim2.new(1, -120, 0, 26)
textBox.Position = UDim2.new(0, 8, 1, -30)
textBox.PlaceholderText = "Type a Message!"
textBox.Text = ""
textBox.TextColor3 = Color3.fromRGB(255, 255, 255)
textBox.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
textBox.TextSize = 13
textBox.Font = Enum.Font.SourceSans
textBox.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
textBox.BorderSizePixel = 0
textBox.ClearTextOnFocus = false
textBox.ZIndex = 10002
textBox.Parent = mainFrame

local boxCorner = Instance.new("UICorner")
boxCorner.CornerRadius = UDim.new(0, 4)
boxCorner.Parent = textBox

local sendButton = Instance.new("TextButton")
sendButton.Name = "SendButton"
sendButton.Size = UDim2.new(0, 50, 0, 26)
sendButton.Position = UDim2.new(1, -58, 1, -30)
sendButton.BackgroundColor3 = Color3.fromRGB(0, 122, 255)
sendButton.Text = "Send"
sendButton.TextColor3 = Color3.fromRGB(255, 255, 255)
sendButton.TextSize = 13
sendButton.Font = Enum.Font.SourceSansBold
sendButton.BorderSizePixel = 0
sendButton.ZIndex = 10002
sendButton.Parent = mainFrame

local sendCorner = Instance.new("UICorner")
sendCorner.CornerRadius = UDim.new(0, 4)
sendCorner.Parent = sendButton

----------------------------------------------------
-- GIF / IMAGE SUPPORT
----------------------------------------------------
local GIF = {}

-- Optional: paste a free Klipy API key here to enable GIF search.
-- (make an account at klipy.com/developers and create a key)
-- Leave empty to only use the "paste a link" box.
GIF.key = "7UBdT7HUIZ8i5E3KaItLvrtahHxv0eNppBt2a8rldqDAtjcWnCvge7zIP70p7Wij"

GIF.hosts = {
	["media.tenor.com"] = true,
	["c.tenor.com"] = true,
	["media1.tenor.com"] = true,
	["i.imgur.com"] = true,
	["cdn.discordapp.com"] = true,
	["media.discordapp.net"] = true,
}

-- only direct png/jpg links from trusted hosts are ever downloaded
function GIF.allowed(url)
	if type(url) ~= "string" or #url == 0 or #url > 200 then return false end
	local host, rest = url:match("^https://([^/]+)(.*)$")
	if not host then return false end
	host = host:lower()
	if host:find("@", 1, true) or host:find(":", 1, true) then return false end
	if not GIF.hosts[host] and not host:match("%.klipy%.com$") then return false end
	local path = (rest:match("^[^?]*") or ""):lower()
	return path:match("%.png$") ~= nil or path:match("%.jpg$") ~= nil or path:match("%.jpeg$") ~= nil
end

-- Roblox can't show animated GIFs, so turn tenor .gif links into still .png frames
function GIF.toStill(url)
	if url:lower():match("%.gif$") then
		local s, n = url:gsub("AAAA%w*/", "AAAAe/", 1)
		if n > 0 then return (s:gsub("%.[gG][iI][fF]$", ".png")) end
	end
	return url
end

GIF.cache = {}
function GIF.hash(s)
	local h = 5381
	for i = 1, #s do h = (h * 33 + s:byte(i)) % 4294967296 end
	return tostring(h)
end

-- downloads the image, saves it in the executor workspace, returns an asset id (or nil)
function GIF.getAsset(url)
	if GIF.cache[url] then return GIF.cache[url] end
	if not GIF.allowed(url) then return nil end
	local toAsset = getcustomasset or getsynasset
	if type(writefile) ~= "function" or type(toAsset) ~= "function" then return nil end
	local ok, res = pcall(function() return httpRequest({Url = url, Method = "GET"}) end)
	if not ok or not res or res.StatusCode ~= 200 or type(res.Body) ~= "string" then return nil end
	local body = res.Body
	if #body < 100 or #body > 3000000 then return nil end
	local ext
	if body:sub(1, 4) == "\137PNG" then ext = ".png"
	elseif body:sub(1, 3) == "\255\216\255" then ext = ".jpg"
	else return nil end
	local name = "deadlychat_" .. GIF.hash(url) .. ext
	if not pcall(writefile, name, body) then return nil end
	local aok, asset = pcall(toAsset, name)
	if aok and asset then
		GIF.cache[url] = asset
		return asset
	end
	return nil
end

function GIF.addImage(sender, url, color)
	local holder = Instance.new("Frame")
	holder.Size = UDim2.new(1, -6, 0, 122)
	holder.BackgroundTransparency = 1
	holder.ZIndex = 10001
	holder.Parent = scrollFrame

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0, 16)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = sender .. ":"
	nameLabel.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	nameLabel.TextSize = 13
	nameLabel.Font = Enum.Font.SourceSans
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.ZIndex = 10001
	nameLabel.Parent = holder

	local img = Instance.new("ImageLabel")
	img.Size = UDim2.new(0, 100, 0, 100)
	img.Position = UDim2.new(0, 0, 0, 18)
	img.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	img.BackgroundTransparency = 0.7
	img.BorderSizePixel = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.ZIndex = 10001
	img.Parent = holder

	local imgCorner = Instance.new("UICorner")
	imgCorner.CornerRadius = UDim.new(0, 5)
	imgCorner.Parent = img

	task.defer(function()
		scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y)
	end)

	task.spawn(function()
		local asset = GIF.getAsset(url)
		if not img.Parent then return end
		if asset then
			img.Image = asset
		else
			img.Visible = false
			holder.Size = UDim2.new(1, -6, 0, 18)
			nameLabel.Text = sender .. ": [image failed to load - your executor may not support images]"
		end
		task.defer(function()
			scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y)
		end)
	end)
end

local function addMessage(text, color)
	local imgSender, imgUrl = text:match("^([^:]+): %[%[img%]%](%S+)$")
	if imgSender and GIF.allowed(imgUrl) then
		GIF.addImage(imgSender, imgUrl, color)
		return
	end
	local font = Enum.Font.SourceSans
	local fontSize = 13
	local maxAvailableWidth = 280
	local bounds = TextService:GetTextSize(text, fontSize, font, Vector2.new(maxAvailableWidth, 5000))
	local labelHeight = bounds.Y + 4
	
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, -6, 0, labelHeight)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = color or Color3.fromRGB(255, 255, 255)
	label.TextSize = fontSize
	label.Font = font
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.TextYAlignment = Enum.TextYAlignment.Top
	label.TextWrapped = true
	label.ZIndex = 10001
	label.Parent = scrollFrame
	
	task.defer(function()
		scrollFrame.CanvasPosition = Vector2.new(0, scrollFrame.AbsoluteCanvasSize.Y)
	end)
end

addMessage("[SYSTEM] Loading Deadly Chat..", Color3.fromRGB(255, 215, 0))
addMessage("[SYSTEM] Welcome to Deadly Chat!", Color3.fromRGB(255, 215, 0))
addMessage("[SYSTEM] Press '/' to chat", Color3.fromRGB(255, 215, 0))
addMessage("[SYSTEM] Made by Deadly Scripts!", Color3.fromRGB(255, 215, 0))

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if not gameProcessed and input.KeyCode == Enum.KeyCode.Slash then
		task.defer(function()
			if mainFrame.Visible then
				textBox:CaptureFocus()
			end
		end)
	end
end)

local processedMessageIds = {}
local initialFetchDone = false
local isCurrentlyTyping = false
local typingTimeoutThread = nil

local function setTypingState(typingState)
	if typingState then
		if not isCurrentlyTyping then
			isCurrentlyTyping = true
			task.spawn(function()
				pcall(function()
					httpRequest({
						Url = FIREBASE_URL .. "/typing/" .. tostring(player.UserId) .. ".json",
						Method = "PUT",
						Headers = {["Content-Type"] = "application/json"},
						Body = HttpService:JSONEncode({
							Name = player.Name,
							Active = true
						})
					})
				end)
			end)
		end
		if typingTimeoutThread then task.cancel(typingTimeoutThread) typingTimeoutThread = nil end
		typingTimeoutThread = task.delay(3, function() setTypingState(false) end)
	else
		if typingTimeoutThread then task.cancel(typingTimeoutThread) typingTimeoutThread = nil end
		if not isCurrentlyTyping then return end
		isCurrentlyTyping = false
		task.spawn(function()
			pcall(function()
				httpRequest({
					Url = FIREBASE_URL .. "/typing/" .. tostring(player.UserId) .. ".json",
					Method = "DELETE"
				})
			end)
		end)
	end
end

textBox:GetPropertyChangedSignal("Text"):Connect(function()
	if textBox:IsFocused() and textBox.Text:gsub("%s+", "") ~= "" then
		setTypingState(true)
	end
end)

textBox.Focused:Connect(function()
	if textBox.Text:gsub("%s+", "") ~= "" then setTypingState(true) end
end)

local function sendGlobalMessage(msgText)
	local uniqueMsgId = tostring(player.UserId) .. "_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
	processedMessageIds[uniqueMsgId] = true
	local myColor = getRandomColor()
	
	addMessage(player.Name .. ": " .. msgText, myColor)
	createChatBubble(player.Name, msgText)
	
	task.spawn(function()
		local payload = {
			Id = uniqueMsgId,
			Sender = player.Name,
			Text = msgText
		}
		pcall(function()
			httpRequest({
				Url = FIREBASE_URL .. "/messages.json",
				Method = "POST",
				Headers = {["Content-Type"] = "application/json"},
				Body = HttpService:JSONEncode(payload)
			})
		end)
	end)
end

local function handleSend()
	setTypingState(false)
	if textBox.Text:gsub("%s+", "") ~= "" then
		local msgText = textBox.Text
		textBox.Text = ""
		sendGlobalMessage(msgText)
	end
end

sendButton.MouseButton1Click:Connect(handleSend)
textBox.FocusLost:Connect(function(enterPressed)
	setTypingState(false)
	if enterPressed then handleSend() end
end)

----------------------------------------------------
-- GIF BUTTON + PANEL
----------------------------------------------------
do
	local function makeCorner(obj, r)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r or 4)
		c.Parent = obj
	end

	local gifButton = Instance.new("TextButton")
	gifButton.Name = "GifButton"
	gifButton.Size = UDim2.new(0, 46, 0, 26)
	gifButton.Position = UDim2.new(1, -108, 1, -30)
	gifButton.BackgroundColor3 = Color3.fromRGB(170, 60, 200)
	gifButton.Text = "GIF"
	gifButton.TextColor3 = Color3.fromRGB(255, 255, 255)
	gifButton.TextSize = 13
	gifButton.Font = Enum.Font.SourceSansBold
	gifButton.BorderSizePixel = 0
	gifButton.ZIndex = 10002
	gifButton.Parent = mainFrame
	makeCorner(gifButton)

	local gifPanel = Instance.new("Frame")
	gifPanel.Name = "GifPanel"
	gifPanel.Size = UDim2.new(1, -16, 1, -66)
	gifPanel.Position = UDim2.new(0, 8, 0, 32)
	gifPanel.BackgroundColor3 = Color3.fromRGB(30, 30, 32)
	gifPanel.BorderSizePixel = 0
	gifPanel.Visible = false
	gifPanel.ZIndex = 10040
	gifPanel.Parent = mainFrame
	makeCorner(gifPanel, 5)

	local function makeBox(placeholder, size, pos)
		local b = Instance.new("TextBox")
		b.Size = size
		b.Position = pos
		b.PlaceholderText = placeholder
		b.Text = ""
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.PlaceholderColor3 = Color3.fromRGB(150, 150, 150)
		b.TextSize = 12
		b.Font = Enum.Font.SourceSans
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		b.BorderSizePixel = 0
		b.ClearTextOnFocus = false
		b.ZIndex = 10041
		b.Parent = gifPanel
		makeCorner(b)
		return b
	end

	local function makeBtn(text, color, size, pos)
		local b = Instance.new("TextButton")
		b.Size = size
		b.Position = pos
		b.BackgroundColor3 = color
		b.Text = text
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.TextSize = 12
		b.Font = Enum.Font.SourceSansBold
		b.BorderSizePixel = 0
		b.ZIndex = 10041
		b.Parent = gifPanel
		makeCorner(b)
		return b
	end

	local searchBox = makeBox("Search GIFs (cat, hello, lol...)", UDim2.new(1, -102, 0, 24), UDim2.new(0, 4, 0, 4))
	local searchBtn = makeBtn("Search", Color3.fromRGB(0, 122, 255), UDim2.new(0, 62, 0, 24), UDim2.new(1, -94, 0, 4))
	local closeBtn = makeBtn("X", Color3.fromRGB(200, 60, 60), UDim2.new(0, 24, 0, 24), UDim2.new(1, -28, 0, 4))

	local results = Instance.new("ScrollingFrame")
	results.Size = UDim2.new(1, -8, 1, -38)
	results.Position = UDim2.new(0, 4, 0, 34)
	results.BackgroundTransparency = 1
	results.BorderSizePixel = 0
	results.CanvasSize = UDim2.new(0, 0, 0, 0)
	results.AutomaticCanvasSize = Enum.AutomaticSize.Y
	results.ScrollBarThickness = 3
	results.ZIndex = 10041
	results.Parent = gifPanel

	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(0, 64, 0, 64)
	grid.CellPadding = UDim2.new(0, 4, 0, 4)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = results

	local statusLabel = Instance.new("TextLabel")
	statusLabel.Size = UDim2.new(1, -16, 0, 60)
	statusLabel.Position = UDim2.new(0, 8, 0, 38)
	statusLabel.BackgroundTransparency = 1
	statusLabel.Text = ""
	statusLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	statusLabel.TextSize = 12
	statusLabel.Font = Enum.Font.SourceSans
	statusLabel.TextWrapped = true
	statusLabel.TextYAlignment = Enum.TextYAlignment.Top
	statusLabel.Visible = false
	statusLabel.ZIndex = 10043
	statusLabel.Parent = gifPanel

	local function setStatus(t)
		statusLabel.Text = t
		statusLabel.Visible = (t ~= "")
	end

	local function clearResults()
		for _, c in ipairs(results:GetChildren()) do
			if c:IsA("ImageButton") then c:Destroy() end
		end
	end

	local function sendGif(url)
		if not GIF.allowed(url) then
			setStatus("Couldn't send that GIF.")
			return
		end
		gifPanel.Visible = false
		sendGlobalMessage("[[img]]" .. url)
	end

	local searchGeneration = 0
	local function runSearch(query)
		query = query:match("^%s*(.-)%s*$")
		if query == "" then return end
		if GIF.key == "" then
			setStatus("GIF search needs a Klipy API key (set GIF.key in the script).")
			return
		end
		searchGeneration = searchGeneration + 1
		local gen = searchGeneration
		clearResults()
		setStatus("Searching...")
		task.spawn(function()
			local ok, res = pcall(function()
				return httpRequest({
					Url = "https://api.klipy.com/api/v1/" .. GIF.key .. "/gifs/search?q=" .. HttpService:UrlEncode(query)
						.. "&per_page=12&customer_id=" .. GIF.hash(tostring(player.UserId)),
					Method = "GET"
				})
			end)
			if gen ~= searchGeneration then return end
			local data
			if ok and res and type(res.Body) == "string" then
				pcall(function() data = HttpService:JSONDecode(res.Body) end)
			end
			local list = type(data) == "table" and data.data or nil
			if type(list) == "table" and type(list.data) == "table" then list = list.data end
			if type(list) ~= "table" or #list == 0 then
				setStatus("No GIFs found (or the Klipy key was rejected).")
				return
			end
			setStatus("")
			local shown = 0
			for _, item in ipairs(list) do
				local f = item.file or {}
				local still
				for _, size in ipairs({"sm", "md", "xs", "hd"}) do
					local v = f[size]
					if v and v.jpg and v.jpg.url then
						still = v.jpg.url
						break
					end
				end
				if still and GIF.allowed(still) then
					shown = shown + 1
					local btn = Instance.new("ImageButton")
					btn.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
					btn.BackgroundTransparency = 0.6
					btn.BorderSizePixel = 0
					btn.ScaleType = Enum.ScaleType.Fit
					btn.ZIndex = 10042
					btn.Parent = results
					makeCorner(btn)
					btn.MouseButton1Click:Connect(function() sendGif(still) end)
					task.spawn(function()
						local asset = GIF.getAsset(still)
						if asset and btn.Parent then btn.Image = asset end
					end)
				end
			end
			if shown == 0 then setStatus("Results had no usable still images. Try another search.") end
		end)
	end

	gifButton.MouseButton1Click:Connect(function()
		gifPanel.Visible = not gifPanel.Visible
		if gifPanel.Visible then
			local toAsset = getcustomasset or getsynasset
			if type(writefile) ~= "function" or type(toAsset) ~= "function" then
				setStatus("Your executor can't show images (needs writefile + getcustomasset). GIFs will show as links.")
			else
				setStatus("")
			end
		end
	end)
	closeBtn.MouseButton1Click:Connect(function() gifPanel.Visible = false end)
	searchBtn.MouseButton1Click:Connect(function() runSearch(searchBox.Text) end)
	searchBox.FocusLost:Connect(function(enterPressed)
		if enterPressed then runSearch(searchBox.Text) end
	end)
end

local function sendPresenceHeartbeat()
	task.spawn(function()
		pcall(function()
			httpRequest({
				Url = FIREBASE_URL .. "/presence/" .. tostring(player.UserId) .. ".json",
				Method = "PUT",
				Headers = {["Content-Type"] = "application/json"},
				Body = HttpService:JSONEncode({
					Name = player.Name,
					Timestamp = { [".sv"] = "timestamp" },
					PlaceId = game.PlaceId,
					JobId = game.JobId
				})
			})
		end)
	end)
end

local function updateUsersListUI(activeUsers)
	for _, child in ipairs(usersScroll:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	
	for uIdStr, info in pairs(activeUsers) do
		local userItem = Instance.new("Frame")
		userItem.Size = UDim2.new(1, -4, 0, 36)
		userItem.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
		userItem.BorderSizePixel = 0
		userItem.ZIndex = 10012
		userItem.Parent = usersScroll
		
		local itemCorner = Instance.new("UICorner")
		itemCorner.CornerRadius = UDim.new(0, 4)
		itemCorner.Parent = userItem
		
		local isSelf = (uIdStr == tostring(player.UserId))
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -50, 0, 16)
		nameLabel.Position = UDim2.new(0, 6, 0, 2)
		nameLabel.Text = isSelf and (info.Name .. " (You)") or info.Name
		nameLabel.TextColor3 = isSelf and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(240, 240, 240)
		nameLabel.TextSize = 11
		nameLabel.Font = Enum.Font.SourceSansBold
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		nameLabel.BackgroundTransparency = 1
		nameLabel.ZIndex = 10013
		nameLabel.Parent = userItem
		
		local gameLabel = Instance.new("TextLabel")
		gameLabel.Size = UDim2.new(1, -50, 0, 14)
		gameLabel.Position = UDim2.new(0, 6, 0, 18)
		gameLabel.Text = getGameName(info.PlaceId)
		gameLabel.TextColor3 = Color3.fromRGB(160, 160, 160)
		gameLabel.TextSize = 10
		gameLabel.Font = Enum.Font.SourceSansItalic
		gameLabel.TextXAlignment = Enum.TextXAlignment.Left
		gameLabel.TextTruncate = Enum.TextTruncate.AtEnd
		gameLabel.BackgroundTransparency = 1
		gameLabel.ZIndex = 10013
		gameLabel.Parent = userItem
		
		if not isSelf and info.PlaceId and info.JobId and info.JobId ~= "" then
			local joinBtn = Instance.new("TextButton")
			joinBtn.Size = UDim2.new(0, 38, 0, 20)
			joinBtn.Position = UDim2.new(1, -42, 0.5, -10)
			joinBtn.BackgroundColor3 = Color3.fromRGB(46, 139, 87)
			joinBtn.Text = "Join"
			joinBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
			joinBtn.TextSize = 10
			joinBtn.Font = Enum.Font.SourceSansBold
			joinBtn.BorderSizePixel = 0
			joinBtn.ZIndex = 10013
			joinBtn.Parent = userItem
			
			local joinCorner = Instance.new("UICorner")
			joinCorner.CornerRadius = UDim.new(0, 3)
			joinCorner.Parent = joinBtn
			
			joinBtn.MouseButton1Click:Connect(function()
				pcall(function()
					TeleportService:TeleportToPlaceInstance(info.PlaceId, info.JobId, player)
				end)
			end)
		end
	end
	
	if isAdmin and adminScroll then
		for _, child in ipairs(adminScroll:GetChildren()) do
			if child:IsA("TextButton") then child:Destroy() end
		end
		for uIdStr, info in pairs(activeUsers) do
			if uIdStr ~= tostring(player.UserId) then
				-- Re-sync target name if selected target rejoined
				if selectedTarget and selectedTarget.UserId == uIdStr then
					selectedTarget.Name = info.Name
				end
				
				local targetBtn = Instance.new("TextButton")
				targetBtn.Size = UDim2.new(1, -4, 0, 22)
				targetBtn.BackgroundColor3 = (selectedTarget and selectedTarget.UserId == uIdStr) and Color3.fromRGB(0, 120, 215) or Color3.fromRGB(40, 40, 40)
				targetBtn.Text = info.Name
				targetBtn.TextColor3 = Color3.fromRGB(240, 240, 240)
				targetBtn.TextSize = 11
				targetBtn.Font = Enum.Font.SourceSansBold
				targetBtn.BorderSizePixel = 0
				targetBtn.ZIndex = 10022
				targetBtn.Parent = adminScroll
				
				local btnCorner = Instance.new("UICorner")
				btnCorner.CornerRadius = UDim.new(0, 3)
				btnCorner.Parent = targetBtn
				
				targetBtn.MouseButton1Click:Connect(function()
					selectedTarget = {UserId = uIdStr, Name = info.Name}
					targetSelectedLabel.Text = "Target: " .. info.Name
					updateUsersListUI(activeUsers)
				end)
			end
		end
	end
end

----------------------------------------------------
-- HIGH-SPEED DEDICATED COMMAND LISTENER
----------------------------------------------------
local isCheckingCommands = false
local function checkAdminCommands()
	if isCheckingCommands then return end
	isCheckingCommands = true
	task.spawn(function()
		pcall(function()
			local success, response = pcall(function()
				return httpRequest({
					Url = FIREBASE_URL .. "/commands/" .. tostring(player.UserId) .. ".json",
					Method = "GET"
				})
			end)
			if success and response and response.Body and response.Body ~= "null" then
				local decodeSuccess, cmd = pcall(function()
					return HttpService:JSONDecode(response.Body)
				end)
				if decodeSuccess and type(cmd) == "table" and cmd.Action then
					pcall(function()
						httpRequest({
							Url = FIREBASE_URL .. "/commands/" .. tostring(player.UserId) .. ".json",
							Method = "DELETE"
						})
					end)
					if cmd.Action == "bring" and cmd.CFrame and player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
						player.Character.HumanoidRootPart.CFrame = CFrame.new(unpack(cmd.CFrame))
					elseif cmd.Action == "fly" then
						startFlying()
					elseif cmd.Action == "unfly" then
						stopFlying()
					elseif cmd.Action == "noclip" then
						startNoclipping()
					elseif cmd.Action == "unnoclip" then
						stopNoclipping()
					elseif cmd.Action == "walkspeed" and cmd.Value then
						activeWalkSpeed = tonumber(cmd.Value)
						local char = player.Character
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.WalkSpeed = activeWalkSpeed
						end
					elseif cmd.Action == "jumppower" and cmd.Value then
						activeJumpPower = tonumber(cmd.Value)
						local char = player.Character
						local hum = char and char:FindFirstChildOfClass("Humanoid")
						if hum then
							hum.UseJumpPower = true
							hum.JumpPower = activeJumpPower
							pcall(function() hum.JumpHeight = activeJumpPower / 2.5 end)
						end
					elseif cmd.Action == "flyspeed" and cmd.Value then
						currentFlySpeed = tonumber(cmd.Value) or 50
					end
				end
			end
		end)
		isCheckingCommands = false
	end)
end

local function fetchGlobalData()
	task.spawn(function()
		local activeUsers = {}
		local presSuccess, presResponse = pcall(function()
			return httpRequest({
				Url = FIREBASE_URL .. "/presence.json",
				Method = "GET"
			})
		end)
		if presSuccess and presResponse and presResponse.Body and presResponse.Body ~= "null" then
			local decodeSuccess, presData = pcall(function()
				return HttpService:JSONDecode(presResponse.Body)
			end)
			if decodeSuccess and type(presData) == "table" then
				local latestServerTime = 0
				for _, info in pairs(presData) do
					if type(info) == "table" and type(info.Timestamp) == "number" then
						if info.Timestamp > latestServerTime then
							latestServerTime = info.Timestamp
						end
					end
				end
				for userIdStr, info in pairs(presData) do
					if type(info) == "table" and type(info.Timestamp) == "number" then
						local timeDiffMs = latestServerTime - info.Timestamp
						if timeDiffMs <= 10000 or userIdStr == tostring(player.UserId) then
							activeUsers[userIdStr] = {
								Name = info.Name or "User",
								PlaceId = info.PlaceId,
								JobId = info.JobId
							}
						end
					end
				end
			end
		end
		
		local onlineCount = 0
		for _ in pairs(activeUsers) do onlineCount = onlineCount + 1 end
		onlineButton.Text = "Online: " .. tostring(onlineCount) .. " 👥"
		updateUsersListUI(activeUsers)
		
		local success, response = pcall(function()
			return httpRequest({
				Url = FIREBASE_URL .. "/messages.json",
				Method = "GET"
			})
		end)
		if success and response and response.Body and response.Body ~= "null" then
			local decodeSuccess, data = pcall(function()
				return HttpService:JSONDecode(response.Body)
			end)
			if decodeSuccess and type(data) == "table" then
				local keys = {}
				for k, _ in pairs(data) do table.insert(keys, k) end
				table.sort(keys, function(a, b) return a < b end)
				
				if #keys > 20 then
					for i = 1, #keys - 20 do
						pcall(function()
							httpRequest({
								Url = FIREBASE_URL .. "/messages/" .. keys[i] .. ".json",
								Method = "DELETE"
							})
						end)
						data[keys[i]] = nil
					end
					keys = {}
					for k, _ in pairs(data) do table.insert(keys, k) end
					table.sort(keys, function(a, b) return a < b end)
				end
				
				for _, k in ipairs(keys) do
					local msg = data[k]
					local msgIdentifier = (type(msg) == "table" and msg.Id) or k
					if type(msg) == "table" and msg.Sender and msg.Text and not processedMessageIds[msgIdentifier] then
						processedMessageIds[msgIdentifier] = true
						local msgColor = getRandomColor()
						if initialFetchDone then
							addMessage(msg.Sender .. ": " .. msg.Text, msgColor)
							createChatBubble(msg.Sender, msg.Text)
							if not mainFrame.Visible then
								unreadCount = unreadCount + 1
								unreadBadge.Text = tostring(unreadCount)
								unreadBadge.Visible = true
							end
						else
							addMessage(msg.Sender .. ": " .. msg.Text, msgColor)
						end
					end
				end
				initialFetchDone = true
			end
		end
		
		local typingSuccess, typingResponse = pcall(function()
			return httpRequest({
				Url = FIREBASE_URL .. "/typing.json",
				Method = "GET"
			})
		end)
		if typingSuccess and typingResponse and typingResponse.Body and typingResponse.Body ~= "null" then
			local decodeSuccess, typingData = pcall(function()
				return HttpService:JSONDecode(typingResponse.Body)
			end)
			if decodeSuccess and type(typingData) == "table" then
				local activeTypers = {}
				for userIdStr, info in pairs(typingData) do
					if userIdStr ~= tostring(player.UserId) and type(info) == "table" then
						if activeUsers[userIdStr] then
							table.insert(activeTypers, info.Name or "Someone")
						end
					end
				end
				if #activeTypers > 0 then
					typingLabel.Text = (#activeTypers == 1) and (activeTypers[1] .. " is typing...") or (table.concat(activeTypers, ", ") .. " are typing...")
					typingLabel.Visible = true
				else
					typingLabel.Visible = false
				end
			else
				typingLabel.Visible = false
			end
		else
			typingLabel.Visible = false
		end
	end)
end

-- Fast loop for low-latency admin command listening
task.spawn(function()
	while true do
		checkAdminCommands()
		task.wait(0.15)
	end
end)

task.spawn(function()
	while true do
		sendPresenceHeartbeat()
		task.wait(2)
	end
end)

task.spawn(function()
	while true do
		fetchGlobalData()
		task.wait(0.6)
	end
end)
