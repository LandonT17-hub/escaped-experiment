local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- PLACEHOLDER UI: plain left-side buttons (Rebirth, Store, Codes) and bare
-- panels, only so the server menus can be tested. Replace with the real
-- designed icons/menus -- keep the same remote calls:
--   GetRebirthInfo()            -> { Cost, Count, Multiplier }
--   RequestRebirth()            -> success, { Cost, Count, Multiplier }
--   GetStoreCatalog()           -> { { Name, GamePassId, Owned } }
--   StorePurchaseRequest:FireServer(gamePassId)
--   RedeemCode(code)            -> success, message
-- Everything is decided server-side; this only asks and displays.

local CONFIRM_WINDOW = 3 -- seconds a Rebirth confirm click stays armed

local MenuButtons = {}

local function button(parent: Instance, text: string, size: UDim2, position: UDim2): TextButton
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = Color3.fromRGB(40, 40, 45)
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Font = Enum.Font.GothamBold
	b.TextScaled = true
	b.Text = text
	b.Parent = parent
	return b
end

local function panel(parent: Instance, name: string): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = UDim2.fromOffset(300, 260)
	f.Position = UDim2.new(0, 130, 0.5, -130)
	f.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
	f.Visible = false
	f.Parent = parent
	return f
end

local function label(parent: Instance, text: string, size: UDim2, position: UDim2): TextLabel
	local l = Instance.new("TextLabel")
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.TextColor3 = Color3.new(1, 1, 1)
	l.Font = Enum.Font.Gotham
	l.TextScaled = true
	l.Text = text
	l.Parent = parent
	return l
end

function MenuButtons.Init()
	local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "MenuButtons"
	screenGui.ResetOnSpawn = false
	screenGui.Parent = playerGui

	local buttonSize = UDim2.fromOffset(100, 44)
	local rebirthButton = button(screenGui, "Rebirth", buttonSize, UDim2.new(0, 16, 0.5, -74))
	local storeButton = button(screenGui, "Store", buttonSize, UDim2.new(0, 16, 0.5, -22))
	local codesButton = button(screenGui, "Codes", buttonSize, UDim2.new(0, 16, 0.5, 30))

	local storePanel = panel(screenGui, "StorePanel")
	local codesPanel = panel(screenGui, "CodesPanel")

	local function toggle(target: Frame)
		for _, p in { storePanel, codesPanel } do
			p.Visible = p == target and not p.Visible
		end
	end

	-- Rebirth: first click shows the cost and arms; a second click within
	-- CONFIRM_WINDOW rebirths (it spends Wins and resets Mutation).
	local getRebirthInfo = Remotes.GetRemoteFunction("GetRebirthInfo")
	local requestRebirth = Remotes.GetRemoteFunction("RequestRebirth")
	local armedAt: number? = nil

	rebirthButton.Activated:Connect(function()
		if armedAt and os.clock() - armedAt <= CONFIRM_WINDOW then
			armedAt = nil
			local success, info = requestRebirth:InvokeServer()
			rebirthButton.Text = if success
				then `Rebirthed! x{string.format("%.2f", info.Multiplier)}`
				else `Need {info.Cost} Wins`
			task.delay(2, function()
				rebirthButton.Text = "Rebirth"
			end)
			return
		end

		local info = getRebirthInfo:InvokeServer()
		armedAt = os.clock()
		rebirthButton.Text = `Confirm? {info.Cost} Wins`
		task.delay(CONFIRM_WINDOW, function()
			if armedAt and os.clock() - armedAt >= CONFIRM_WINDOW then
				armedAt = nil
				rebirthButton.Text = "Rebirth"
			end
		end)
	end)

	-- Store: lists whatever passes the server says exist.
	local getStoreCatalog = Remotes.GetRemoteFunction("GetStoreCatalog")
	local storePurchaseRequest = Remotes.GetRemoteEvent("StorePurchaseRequest")

	storeButton.Activated:Connect(function()
		toggle(storePanel)
		if not storePanel.Visible then
			return
		end

		storePanel:ClearAllChildren()
		local catalog = getStoreCatalog:InvokeServer()
		if #catalog == 0 then
			label(storePanel, "Coming soon", UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, 10))
			return
		end

		for i, item in catalog do
			local y = 10 + (i - 1) * 48
			local text = if item.Owned then `{item.Name} (Owned)` else `Buy {item.Name}`
			local itemButton = button(storePanel, text, UDim2.new(1, -20, 0, 40), UDim2.fromOffset(10, y))
			if not item.Owned then
				itemButton.Activated:Connect(function()
					storePurchaseRequest:FireServer(item.GamePassId)
				end)
			end
		end
	end)

	-- Codes: text box + redeem, shows the server's message.
	local redeemCode = Remotes.GetRemoteFunction("RedeemCode")

	local codeBox = Instance.new("TextBox")
	codeBox.Size = UDim2.new(1, -20, 0, 44)
	codeBox.Position = UDim2.fromOffset(10, 10)
	codeBox.PlaceholderText = "Enter code"
	codeBox.Text = ""
	codeBox.ClearTextOnFocus = false
	codeBox.TextScaled = true
	codeBox.Font = Enum.Font.Gotham
	codeBox.Parent = codesPanel

	local redeemButton = button(codesPanel, "Redeem", UDim2.new(1, -20, 0, 44), UDim2.fromOffset(10, 64))
	local resultLabel = label(codesPanel, "", UDim2.new(1, -20, 0, 36), UDim2.fromOffset(10, 118))

	redeemButton.Activated:Connect(function()
		local _, message = redeemCode:InvokeServer(codeBox.Text)
		resultLabel.Text = message
	end)

	codesButton.Activated:Connect(function()
		toggle(codesPanel)
	end)
end

return MenuButtons
