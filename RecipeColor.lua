RecipeColor = {}

-- Returns the numeric item ID from a hyperlink string, or -1 if not found.
local function GetFromLink(link)
	if link ~= nil then
		local _, _, id = string.find(link, "|c%x+|Hitem:(%d+):")
		if id ~= nil then return id end
	end
	return -1
end

local ScanTooltipLines

local function IsKnownRecipeByLink(link)
	if not link then return false end
	RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	RecipeColor_ScanTooltip:ClearLines()
	RecipeColor_ScanTooltip:SetHyperlink(link)
	local numLines = RecipeColor_ScanTooltip:NumLines()
	for i = 1, numLines do
		local line = ScanTooltipLines[i]
		local text = line and line:GetText()
		if text and string.find(text, "Already known") then
			return true
		end
	end
	return false
end

-- Checks if an item is an already-known recipe via a hidden tooltip scan.
-- SetOwner is called before every scan because other addons can steal ownership.
local function IsKnownRecipe(bag, slot)
	RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
	RecipeColor_ScanTooltip:ClearLines()
	if bag == BANK_CONTAINER then
		RecipeColor_ScanTooltip:SetInventoryItem("player", BankButtonIDToInvSlotID(slot))
	elseif bag == "MailBox" then
		RecipeColor_ScanTooltip:SetInboxItem(slot[1], slot[2])
	elseif bag == "MailBoxOpen" then
		local mailID = InboxFrame.openMailID
		if not mailID or mailID == 0 then return false end
		RecipeColor_ScanTooltip:SetInboxItem(mailID, slot)
	elseif bag == "Merchant" then
		RecipeColor_ScanTooltip:SetMerchantItem(slot)
	elseif bag == "Buyback" then
		RecipeColor_ScanTooltip:SetBuybackItem(slot)
	elseif bag == "GuildBank" then
		RecipeColor_ScanTooltip:SetGuildBankItem(slot[1], slot[2])
	else
		RecipeColor_ScanTooltip:SetBagItem(bag, slot)
	end
	local numLines = RecipeColor_ScanTooltip:NumLines()
	for i = 1, numLines do
		local line = ScanTooltipLines[i]
		local text = line and line:GetText()
		if text and string.find(text, "Already known") then
			return true
		end
	end
	return false
end

-- Returns true if the link belongs to the "Recipe" item class.
-- GetItemInfo index 6 = itemType (localized string, "Recipe" in English).
local function IsRecipeItem(link)
	if not link then return false end
	local itemid = GetFromLink(link)
	if itemid == -1 then return false end
	local _, _, _, _, _, itemtype = GetItemInfo(itemid)
	return itemtype == "Recipe"
end

-- Colors one container slot button green if it holds a known recipe.
local function ColorContainerSlot(bag, slot, itemButton)
	if not itemButton then return end
	local key = bag .. ":" .. slot
	local link = GetContainerItemLink(bag, slot)
	if not IsRecipeItem(link) then
		if RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
			RecipeColor.knownRecipeSlots[key] = nil
			RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
		end
		return
	end
	local start, duration, enable = GetContainerItemCooldown(bag, slot)
	if duration > 0 and enable == 0 then return end  -- on cooldown → leave grey
	if IsKnownRecipe(bag, slot) then
		SetItemButtonTextureVertexColor(itemButton, 0, 1, 0)
		if RecipeColor.knownRecipeSlots and not RecipeColor.knownRecipeSlots[key] then
			RecipeColor.knownRecipeSlots[key] = true
			RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount + 1
		end
	end
end

-- Hook helpers
local globalHooks = {}

local function HookGlobal(funcName, newFunc)
	globalHooks[funcName] = _G[funcName]
	_G[funcName] = newFunc
end

-- Bag

local function ColorFrameRecipes(frame)
	local size = frame.size
	if not size or size == 0 then return end
	local bag  = frame:GetID()
	local name = frame:GetName()
	for i = 1, size do
		local itemButton = _G[name .. "Item" .. i]
		if itemButton then
			ColorContainerSlot(bag, itemButton:GetID(), itemButton)
		end
	end
end

-- Bank

local function ColorBankSlot(button)
	if not button or button.isBag then return end
	local slot = button:GetID()
	ColorContainerSlot(BANK_CONTAINER, slot, button)
end

function RecipeColor:ColorKnownRecipesInBank()
	for slot = 1, NUM_BANKGENERIC_SLOTS do
		local button = _G["BankFrameItem" .. slot]
		ColorBankSlot(button)
	end
end

-- Guild bank

local function ColorGuildBankSlots()
	local tab = GetCurrentGuildBankTab()
	for col = 1, NUM_GUILDBANK_COLUMNS do
		for row = 1, NUM_SLOTS_PER_GUILDBANK_GROUP do
			local button = _G["GuildBankColumn" .. col .. "Button" .. row]
			if button and button:IsShown() then
				local slot = button:GetID()
				local link = GetGuildBankItemLink(tab, slot)
				if IsRecipeItem(link) then
					if IsKnownRecipe("GuildBank", {tab, slot}) then
						SetItemButtonTextureVertexColor(button, 0, 1, 0)
					end
				end
			end
		end
	end
end

local guildBankHooked = false
local function HookGuildBankFrame()
	if guildBankHooked then return end
	if not GuildBankFrame_Update then return end
	guildBankHooked = true
	local origGuildBankUpdate = GuildBankFrame_Update
	HookGlobal("GuildBankFrame_Update", function()
		origGuildBankUpdate()
		if GuildBankFrame and GuildBankFrame:IsShown()
				and GuildBankFrame.mode == "bank" then
			ColorGuildBankSlots()
		end
	end)
end

function RecipeColor:ColorKnownRecipesInMail()
	if not MailFrame:IsVisible() then return end
	local numItems = GetInboxNumItems()
	local pageNum  = InboxFrame.pageNum or 1
	local startIdx = (pageNum - 1) * INBOXITEMS_TO_DISPLAY + 1

	for frameSlot = 1, INBOXITEMS_TO_DISPLAY do
		local mailIndex = startIdx + (frameSlot - 1)
		if mailIndex > numItems then break end

		local _, _, _, _, _, _, _, itemCount, wasRead = GetInboxHeaderInfo(mailIndex)
		local icon = _G["MailItem" .. frameSlot .. "ButtonIcon"]
		if not icon then break end

		local isKnown = false
		if itemCount and itemCount > 0 then
			for attachIndex = 1, ATTACHMENTS_MAX_RECEIVE do
				local link = GetInboxItemLink(mailIndex, attachIndex)
				if link and IsRecipeItem(link) and IsKnownRecipeByLink(link) then
					isKnown = true
					break
				end
			end
		end

		if isKnown then
			SetDesaturation(icon, nil)
			icon:SetVertexColor(0, 1, 0)
		else
			icon:SetVertexColor(1, 1, 1)
			SetDesaturation(icon, wasRead and 1 or nil)
		end
	end
end

function RecipeColor:ColorKnownRecipesInOpenMail()
	if not OpenMailFrame:IsVisible() then return end
	local mailID = InboxFrame.openMailID
	if not mailID or mailID == 0 then return end

	for attachIndex = 1, ATTACHMENTS_MAX_RECEIVE do
		local link = GetInboxItemLink(mailID, attachIndex)
		if link then
			local btn = _G["OpenMailAttachmentButton" .. attachIndex]
			if btn and btn:IsShown() then
				if IsKnownRecipeByLink(link) then
					SetItemButtonTextureVertexColor(btn, 0, 1, 0)
					if attachIndex == 1 then
						SetItemButtonTextureVertexColor(OpenMailPackageButton, 0, 1, 0)
					end
				end
			end
		end
	end
end

-- Loot

function RecipeColor:ColorKnownRecipesInLoot()
	if not LootFrame:IsVisible() then return end
	for i = 1, LOOTFRAME_NUMBUTTONS do
		local button = _G["LootButton" .. i]
		if button then SetItemButtonTextureVertexColor(button, 1, 1, 1) end
	end
	for i = 1, LOOTFRAME_NUMBUTTONS do
		local button = _G["LootButton" .. i]
		if button and button:IsVisible() and button.slot then
			if LootSlotIsItem(button.slot) then
				local link = GetLootSlotLink(button.slot)
				if link and IsRecipeItem(link) then
					RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
					RecipeColor_ScanTooltip:ClearLines()
					RecipeColor_ScanTooltip:SetLootItem(button.slot)
					for j = 1, RecipeColor_ScanTooltip:NumLines() do
						local line = ScanTooltipLines[j]
						local text = line and line:GetText()
						if text and string.find(text, "Already known") then
							SetItemButtonTextureVertexColor(button, 0, 1, 0)
							break
						end
					end
				end
			end
		end
	end
end

-- Trade

function RecipeColor:ColorKnownRecipesInTrade()
	if not TradeFrame:IsVisible() then return end
	for id = 1, MAX_TRADE_ITEMS do
		local pb = _G["TradePlayerItem" .. id .. "ItemButton"]
		if pb then SetItemButtonTextureVertexColor(pb, 1, 1, 1) end
		local rb = _G["TradeRecipientItem" .. id .. "ItemButton"]
		if rb then SetItemButtonTextureVertexColor(rb, 1, 1, 1) end
	end
	for id = 1, MAX_TRADE_ITEMS do
		local pb = _G["TradePlayerItem" .. id .. "ItemButton"]
		if pb and pb.hasItem then
			RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
			RecipeColor_ScanTooltip:ClearLines()
			RecipeColor_ScanTooltip:SetTradePlayerItem(id)
			for i = 1, RecipeColor_ScanTooltip:NumLines() do
				local line = ScanTooltipLines[i]
				local text = line and line:GetText()
				if text and string.find(text, "Already known") then
					SetItemButtonTextureVertexColor(pb, 0, 1, 0)
					break
				end
			end
		end
		local rb = _G["TradeRecipientItem" .. id .. "ItemButton"]
		if rb and GetTradeTargetItemInfo(id) then
			RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
			RecipeColor_ScanTooltip:ClearLines()
			RecipeColor_ScanTooltip:SetTradeTargetItem(id)
			for i = 1, RecipeColor_ScanTooltip:NumLines() do
				local line = ScanTooltipLines[i]
				local text = line and line:GetText()
				if text and string.find(text, "Already known") then
					SetItemButtonTextureVertexColor(rb, 0, 1, 0)
					break
				end
			end
		end
	end
end

-- Merchant & buyback

function RecipeColor:ColorKnownRecipesAtMerchant()
	if not MerchantFrame:IsVisible() then return end
	local numMerchantItems = GetMerchantNumItems()
	for i = 1, MERCHANT_ITEMS_PER_PAGE do
		local index = ((MerchantFrame.page - 1) * MERCHANT_ITEMS_PER_PAGE) + i
		if index <= numMerchantItems then
			if IsKnownRecipe("Merchant", index) then
				local itemButton     = _G["MerchantItem" .. i .. "ItemButton"]
				local merchantButton = _G["MerchantItem" .. i]
				SetItemButtonNameFrameVertexColor(merchantButton, 0, 1, 0)
				SetItemButtonSlotVertexColor(merchantButton, 0, 1, 0)
				SetItemButtonTextureVertexColor(itemButton, 0, 1, 0)
				SetItemButtonNormalTextureVertexColor(itemButton, 0, 1, 0)
			end
		end
	end
end

local BUYBACK_ITEMS_PER_PAGE_RC = 12
local rcGreenBuybackButtons = {}
local rcGreenBuybackSlot    = false

function RecipeColor:ColorKnownRecipesInBuybackTab()
	if not MerchantFrame:IsVisible() then return end
	for btn in pairs(rcGreenBuybackButtons) do
		SetItemButtonTextureVertexColor(btn, 1, 1, 1)
	end
	rcGreenBuybackButtons = {}
	local numBuyback = GetNumBuybackItems()
	for i = 1, BUYBACK_ITEMS_PER_PAGE_RC do
		local itemButton     = _G["MerchantItem" .. i .. "ItemButton"]
		local merchantButton = _G["MerchantItem" .. i]
		if itemButton and i <= numBuyback and GetBuybackItemInfo(i) and IsKnownRecipe("Buyback", i) then
			SetItemButtonNameFrameVertexColor(merchantButton, 0, 1, 0)
			SetItemButtonSlotVertexColor(merchantButton, 0, 1, 0)
			SetItemButtonTextureVertexColor(itemButton, 0, 1, 0)
			SetItemButtonNormalTextureVertexColor(itemButton, 0, 1, 0)
			rcGreenBuybackButtons[itemButton] = true
		end
	end
end

function RecipeColor:ColorKnownRecipesInBuybackSlot()
	if not MerchantFrame:IsVisible() then return end
	local bbButton = _G["MerchantBuyBackItemItemButton"]
	if not bbButton then return end
	if rcGreenBuybackSlot then
		SetItemButtonTextureVertexColor(bbButton, 1, 1, 1)
		rcGreenBuybackSlot = false
	end
	local bbIndex = GetNumBuybackItems()
	if bbIndex > 0 and GetBuybackItemInfo(bbIndex) and IsKnownRecipe("Buyback", bbIndex) then
		SetItemButtonTextureVertexColor(bbButton, 0, 1, 0)
		rcGreenBuybackSlot = true
	end
end

-- Initialization

local function RecipeColor_Initialize()
	-- Cache tooltip line frames once.
	ScanTooltipLines = {}
	for i = 1, 30 do
		local line = _G["RecipeColor_ScanTooltipTextLeft" .. i]
		if line then
			ScanTooltipLines[i] = line
		else
			break
		end
	end

	-- CORE BAG HOOKS

	local origContainerUpdate = ContainerFrame_Update
	HookGlobal("ContainerFrame_Update", function(frame)
		origContainerUpdate(frame)
		if frame and frame:IsShown() then
			ColorFrameRecipes(frame)
		end
	end)

	local origUpdateLocked = ContainerFrame_UpdateLockedItem
	HookGlobal("ContainerFrame_UpdateLockedItem", function(frame, slot)
		origUpdateLocked(frame, slot)
		if frame and frame:IsShown() then
			local size = frame.size
			if not size or size == 0 then return end
			local buttonIndex = size + 1 - slot
			local itemButton  = _G[frame:GetName() .. "Item" .. buttonIndex]
			if itemButton and RecipeColor.knownRecipeSlots and
					RecipeColor.knownRecipeSlots[frame:GetID() .. ":" .. slot] then
				SetItemButtonTextureVertexColor(itemButton, 0, 1, 0)
			end
		end
	end)

	local origUpdateCooldown = ContainerFrame_UpdateCooldown
	HookGlobal("ContainerFrame_UpdateCooldown", function(container, button)
		origUpdateCooldown(container, button)
		local slot = button:GetID()
		local key = container .. ":" .. slot
		if RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
			local start, duration, enable = GetContainerItemCooldown(container, slot)
			if not (duration > 0 and enable == 0) then
				SetItemButtonTextureVertexColor(button, 0, 1, 0)
			end
		end
	end)

	-- BANK HOOKS
	local origBankItemUpdate = BankFrameItemButton_Update
	HookGlobal("BankFrameItemButton_Update", function(button)
		origBankItemUpdate(button)
		ColorBankSlot(button)
	end)

	local origBankUpdateLocked = BankFrameItemButton_UpdateLocked
	HookGlobal("BankFrameItemButton_UpdateLocked", function(button)
		origBankUpdateLocked(button)
		ColorBankSlot(button)
	end)

	-- GUILD BANK HOOK
	HookGuildBankFrame()

	-- MERCHANT HOOKS
	local origMerchantUpdate = MerchantFrame_Update
	HookGlobal("MerchantFrame_Update", function()
		origMerchantUpdate()
		if MerchantFrame.selectedTab == 2 then
			RecipeColor:ColorKnownRecipesInBuybackTab()
		else
			RecipeColor:ColorKnownRecipesAtMerchant()
			RecipeColor:ColorKnownRecipesInBuybackSlot()
		end
	end)

	-- RECIPE LEARN DETECTION

	RecipeColor.knownRecipeSlots = {}
	RecipeColor.knownRecipeCount = 0

	local learnTicker = CreateFrame("Frame")
	learnTicker:Hide()
	learnTicker:SetScript("OnUpdate", function(self)
		self:Hide()
		for i = 1, NUM_CONTAINER_FRAMES do
			local f = _G["ContainerFrame" .. i]
			if f and f:IsShown() then
				ColorFrameRecipes(f)
			end
		end
	end)
	RecipeColor.learnTicker = learnTicker

	-- MAIL HOOKS
	local origInbox = InboxFrame_Update
	HookGlobal("InboxFrame_Update", function()
		origInbox()
		RecipeColor:ColorKnownRecipesInMail()
		RecipeColor:ColorKnownRecipesInOpenMail()
	end)

	local origOpenMail = OpenMail_Update
	HookGlobal("OpenMail_Update", function()
		origOpenMail()
		SetItemButtonTextureVertexColor(OpenMailPackageButton, 1, 1, 1)
		for j = 1, ATTACHMENTS_MAX_RECEIVE do
			local btn = _G["OpenMailAttachmentButton" .. j]
			if btn then SetItemButtonTextureVertexColor(btn, 1, 1, 1) end
		end
		RecipeColor:ColorKnownRecipesInOpenMail()
	end)

	-- TRADE HOOKS
	local origTrade = TradeFrame_Update
	HookGlobal("TradeFrame_Update", function()
		origTrade()
		RecipeColor:ColorKnownRecipesInTrade()
	end)

	local origTradePlayer = TradeFrame_UpdatePlayerItem
	HookGlobal("TradeFrame_UpdatePlayerItem", function(id)
		origTradePlayer(id)
		RecipeColor:ColorKnownRecipesInTrade()
	end)

	local origTradeTarget = TradeFrame_UpdateTargetItem
	HookGlobal("TradeFrame_UpdateTargetItem", function(id)
		origTradeTarget(id)
		RecipeColor:ColorKnownRecipesInTrade()
	end)

	-- LOOT HOOK
	local origLoot = LootFrame_Update
	HookGlobal("LootFrame_Update", function()
		origLoot()
		RecipeColor:ColorKnownRecipesInLoot()
	end)

	-- Compatibility
	if RecipeColor.InitCompat then
		RecipeColor.InitCompat(IsKnownRecipe, GetFromLink, HookGlobal, IsRecipeItem)
	end
end

-- Event handler

function RecipeColor_OnEvent(self, event, arg1)
	if event == "ADDON_LOADED" and arg1 == "RecipeColor" and not RecipeColor._initialized then
		RecipeColor._initialized = true
		RecipeColor_Initialize()
	end

	if event == "ADDON_LOADED" and arg1 == "Blizzard_GuildBankUI" then
		HookGuildBankFrame()
	end

	if RecipeColor.OnCompatEvent then
		RecipeColor.OnCompatEvent(self, event, arg1)
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
		if RecipeColor.learnTicker and RecipeColor.knownRecipeCount > 0 then
			for i = 1, NUM_CONTAINER_FRAMES do
				if _G["ContainerFrame" .. i]:IsShown() then
					RecipeColor.learnTicker:Show()
					break
				end
			end
		end
	end

	if event == "BANKFRAME_OPENED" or event == "PLAYERBANKSLOTS_CHANGED" then
		if RecipeColor.PfUIBankTicker then
			RecipeColor.PfUIBankTicker:Show()
		end
	end

	-- Notify compat tickers (Bagnon, OneBag3, etc.) on bag change events so they
	-- can schedule their own deferred recolor pass.
	if event == "BAG_UPDATE" or event == "ITEM_LOCK_CHANGED"
			or event == "BAG_UPDATE_COOLDOWN" or event == "UPDATE_INVENTORY_ALERTS" then
		if RecipeColor.OneBagTicker then
			RecipeColor.OneBagTicker:Show()
		end
		if RecipeColor.BagnonTicker then
			RecipeColor.BagnonTicker:Show()
		end
	end


end

function RecipeColor_OnLoad(self)
	self:RegisterEvent("ADDON_LOADED")
	self:RegisterEvent("BAG_UPDATE")
	self:RegisterEvent("ITEM_LOCK_CHANGED")
	self:RegisterEvent("BAG_UPDATE_COOLDOWN")
	self:RegisterEvent("UPDATE_INVENTORY_ALERTS")
	self:RegisterEvent("BANKFRAME_OPENED")
	self:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
	self:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end