local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Remotes = require(ReplicatedStorage.Shared.Remotes)

-- Menu logic kept from the old placeholder MenuButtons, minus the UI it built,
-- for the Studio-built MenuTiles to call once they're wired. Nothing here
-- creates or styles UI, and nothing calls it yet. Every decision is made
-- server-side (see src/server/Menus); this only asks and reports back.
--
--   Panels:  RegisterPanel(name, frame), Toggle(name), Close() -- one menu
--            open at a time.
--   Rebirth: RequestRebirth() -- two-step confirm (Rebirth spends Wins and
--            resets Mutation), returns a status string for the button/menu.
--   Store:   GetCatalog() -> { { Name, GamePassId, Owned } }, Purchase(id).
--   Codes:   Redeem(code) -> success, message.

local CONFIRM_WINDOW = 3 -- seconds a Rebirth confirm stays armed

export type RebirthInfo = { Cost: number, Count: number, Multiplier: number }
export type StoreItem = { Name: string, GamePassId: number, Owned: boolean }

local MenuActions = {}

-- Panels ----------------------------------------------------------------------

local panels: { [string]: GuiObject } = {}

function MenuActions.RegisterPanel(name: string, panel: GuiObject)
	panels[name] = panel
	panel.Visible = false
end

-- Opens `name` and closes every other panel; closes it if already open.
function MenuActions.Toggle(name: string)
	for panelName, panel in panels do
		panel.Visible = panelName == name and not panel.Visible
	end
end

function MenuActions.Close()
	for _, panel in panels do
		panel.Visible = false
	end
end

-- Rebirth ---------------------------------------------------------------------

local armedAt: number? = nil

function MenuActions.GetRebirthInfo(): RebirthInfo
	return Remotes.GetRemoteFunction("GetRebirthInfo"):InvokeServer()
end

-- First call arms and returns ("confirm", info); a second call within
-- CONFIRM_WINDOW performs the rebirth and returns ("success" | "failed", info).
-- "failed" means the server refused (can't afford it).
function MenuActions.RequestRebirth(): (string, RebirthInfo)
	if armedAt and os.clock() - armedAt <= CONFIRM_WINDOW then
		armedAt = nil
		local success, info = Remotes.GetRemoteFunction("RequestRebirth"):InvokeServer()
		return if success then "success" else "failed", info
	end

	armedAt = os.clock()
	return "confirm", MenuActions.GetRebirthInfo()
end

function MenuActions.CancelRebirth()
	armedAt = nil
end

-- Store -----------------------------------------------------------------------

-- Only passes that exist server-side; empty until their ids are filled in.
function MenuActions.GetCatalog(): { StoreItem }
	return Remotes.GetRemoteFunction("GetStoreCatalog"):InvokeServer()
end

function MenuActions.Purchase(gamePassId: number)
	Remotes.GetRemoteEvent("StorePurchaseRequest"):FireServer(gamePassId)
end

-- Codes -----------------------------------------------------------------------

function MenuActions.Redeem(code: string): (boolean, string)
	return Remotes.GetRemoteFunction("RedeemCode"):InvokeServer(code)
end

return MenuActions
