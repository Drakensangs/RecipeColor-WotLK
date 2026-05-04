-- Compatibility

local IsKnownRecipe
local GetFromLink
local HookGlobal
local IsRecipeItem

local isBagnon          = false
local isBagnonGuildBank = false
local isOneBag    = false
local isSUCCbag   = false
local isAdiBags      = false
local isArkInventory = false
local isBaggins      = false
local isExtVendor = false
local isElvUI     = false
local isGudaBags  = false
local isDragonUICombuctor = false

function RecipeColor.InitCompat(isKnownRecipeFn, getFromLinkFn, hookGlobalFn, isRecipeItemFn)
	IsKnownRecipe = isKnownRecipeFn
	GetFromLink   = getFromLinkFn
	HookGlobal    = hookGlobalFn
	IsRecipeItem  = isRecipeItemFn

	isBagnon     = IsAddOnLoaded("Bagnon")
	isOneBag     = (OneCore ~= nil) or IsAddOnLoaded("OneBag3")
	isAdiBags      = IsAddOnLoaded("AdiBags")
	isArkInventory = IsAddOnLoaded("ArkInventory")
	isBaggins      = IsAddOnLoaded("Baggins")
	isExtVendor  = IsAddOnLoaded("ExtVendor")
	isElvUI      = IsAddOnLoaded("ElvUI")
	isGudaBags   = IsAddOnLoaded("GudaBags")
	isDragonUICombuctor = IsAddOnLoaded("DragonUI")

	-- ElvUI
	if isElvUI then
		local elvUIHookTicker = CreateFrame("Frame")
		elvUIHookTicker:SetScript("OnUpdate", function(self)
			local E = ElvUI and ElvUI[1]
			local B = E and E:GetModule("Bags")
			if not (B and B.Initialized) then return end

			self:SetScript("OnUpdate", nil)

			if B.UpdateSlot then
				local origUpdateSlot = B.UpdateSlot
				B.UpdateSlot = function(bself, frame, bagID, slotID)
					origUpdateSlot(bself, frame, bagID, slotID)
					local slot = frame and frame.Bags
						and frame.Bags[bagID]
						and frame.Bags[bagID][slotID]
					if not slot then return end

					local key = bagID .. ":" .. slotID
					local link = GetContainerItemLink(bagID, slotID)

					if not slot.hasItem or not link or not IsRecipeItem(link) then
						if slot.rcKnownRecipe ~= nil or slot.rcLink ~= nil then
							slot.rcKnownRecipe = nil
							slot.rcLink = nil
							if RecipeColor.knownRecipeSlots
									and RecipeColor.knownRecipeSlots[key] then
								RecipeColor.knownRecipeSlots[key] = nil
								RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
							end
						end
						return
					end

					if link == slot.rcLink then
						if slot.rcKnownRecipe then
							local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
							if not (duration > 0 and enable == 0) then
								SetItemButtonTextureVertexColor(slot, 0, 1, 0)
							end
						end
						return
					end

					slot.rcLink = link
					local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
					if duration > 0 and enable == 0 then
						slot.rcKnownRecipe = nil
						return
					end

					if IsKnownRecipe(bagID, slotID) then
						slot.rcKnownRecipe = true
						SetItemButtonTextureVertexColor(slot, 0, 1, 0)
						if RecipeColor.knownRecipeSlots
								and not RecipeColor.knownRecipeSlots[key] then
							RecipeColor.knownRecipeSlots[key] = true
							RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount + 1
						end
					else
						slot.rcKnownRecipe = nil
						if RecipeColor.knownRecipeSlots
								and RecipeColor.knownRecipeSlots[key] then
							RecipeColor.knownRecipeSlots[key] = nil
							RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
						end
					end
				end
			end

			if B.UpdateItemLock then
				local origUpdateItemLock = B.UpdateItemLock
				B.UpdateItemLock = function(bself, frame, bagID, slotID)
					origUpdateItemLock(bself, frame, bagID, slotID)
					local slot = frame and frame.Bags
						and frame.Bags[bagID]
						and frame.Bags[bagID][slotID]
					if not slot or not slot.rcKnownRecipe then return end
					local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
					if not (duration > 0 and enable == 0) then
						SetItemButtonTextureVertexColor(slot, 0, 1, 0)
					end
				end
			end

			if B.SetSearch then
				local origSetSearch = B.SetSearch
				B.SetSearch = function(bself, query)
					origSetSearch(bself, query)
					for _, bagFrame in pairs(B.BagFrames) do
						if bagFrame:IsShown() then
							for _, bagID in ipairs(bagFrame.BagIDs) do
								for slotID = 1, GetContainerNumSlots(bagID) do
									local slot = bagFrame.Bags[bagID]
										and bagFrame.Bags[bagID][slotID]
									if slot and slot.hasItem then
										local link = GetContainerItemLink(bagID, slotID)
										if link and IsRecipeItem(link)
												and IsKnownRecipe(bagID, slotID) then
											SetItemButtonTextureVertexColor(slot, 0, 1, 0)
										end
									end
								end
							end
						end
					end
				end
			end

			local learnTicker = RecipeColor.learnTicker
			if learnTicker then
				local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
				learnTicker:SetScript("OnUpdate", function(self)
					if origLearnOnUpdate then origLearnOnUpdate(self) end
					for _, bagFrame in pairs(B.BagFrames) do
						if bagFrame:IsShown() then
							if RecipeColor.knownRecipeSlots then
								for key in pairs(RecipeColor.knownRecipeSlots) do
									local bagID, slotID = key:match("^(-?%d+):(%d+)$")
									bagID, slotID = tonumber(bagID), tonumber(slotID)
									local slot = bagID and slotID
										and bagFrame.Bags
										and bagFrame.Bags[bagID]
										and bagFrame.Bags[bagID][slotID]
									if slot then slot.rcLink = nil end
								end
							end
							B:UpdateAllSlots(bagFrame)
						end
					end
				end)
			end

			local M = E:GetModule("Misc")
			if M then
				-- Custom ElvUI loot frame path.
				local origLootOpened = M.LOOT_OPENED
				M.LOOT_OPENED = function(mself, ...)
					origLootOpened(mself, ...)
					local elvLootFrame = _G["ElvLootFrame"]
					if not (elvLootFrame and elvLootFrame:IsShown()) then return end
					for _, slot in pairs(elvLootFrame.slots) do
						if slot:IsShown() then
							local lootSlot = slot:GetID()
							if LootSlotIsItem(lootSlot) then
								local link = GetLootSlotLink(lootSlot)
								if link and IsRecipeItem(link) then
									RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
									RecipeColor_ScanTooltip:ClearLines()
									RecipeColor_ScanTooltip:SetLootItem(lootSlot)
									for j = 1, RecipeColor_ScanTooltip:NumLines() do
										local line = _G["RecipeColor_ScanTooltipTextLeft" .. j]
										local text = line and line:GetText()
										if text and string.find(text, "Already known") then
											slot.icon:SetVertexColor(0, 1, 0)
											break
										end
									end
								end
							end
						end
					end
				end

				if _G["LootFrame_UpdateButton"] then
					local origUpdateButton = LootFrame_UpdateButton
					HookGlobal("LootFrame_UpdateButton", function(index)
						origUpdateButton(index)
						if E.private.general.loot then return end
						local numLootToShow = LOOTFRAME_NUMBUTTONS
						if LootFrame.numLootItems
								and LootFrame.numLootItems > LOOTFRAME_NUMBUTTONS then
							numLootToShow = numLootToShow - 1
						end
						local lootSlot = (numLootToShow * ((LootFrame.page or 1) - 1)) + index
						if lootSlot > (LootFrame.numLootItems or 0) then return end
						if not LootSlotIsItem(lootSlot) then return end
						local link = GetLootSlotLink(lootSlot)
						if not link or not IsRecipeItem(link) then return end
						local button = _G["LootButton" .. index]
						if not button then return end
						RecipeColor_ScanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
						RecipeColor_ScanTooltip:ClearLines()
						RecipeColor_ScanTooltip:SetLootItem(lootSlot)
						for j = 1, RecipeColor_ScanTooltip:NumLines() do
							local line = _G["RecipeColor_ScanTooltipTextLeft" .. j]
							local text = line and line:GetText()
							if text and string.find(text, "Already known") then
								SetItemButtonTextureVertexColor(button, 0, 1, 0)
								break
							end
						end
					end)
				end
			end

		end)
	end

	-- Bagnon
	if isBagnon then
		local bagnonHookTicker = CreateFrame("Frame")
		bagnonHookTicker:SetScript("OnUpdate", function(self)
			self:SetScript("OnUpdate", nil)

			local ItemSlot = Bagnon and Bagnon.ItemSlot
			if not (ItemSlot and ItemSlot.Update) then return end

			local origUpdate = ItemSlot.Update
			ItemSlot.Update = function(slot)
				origUpdate(slot)
				if slot:IsCached() then return end
				local bagID  = slot:GetBag()
				local slotID = slot:GetID()
				if not bagID or not slotID then return end
				local link = GetContainerItemLink(bagID, slotID)
				if not link or not IsRecipeItem(link) then
					-- Clear stale tracking entry if present.
					local key = bagID .. ":" .. slotID
					if RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = nil
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
					end
					return
				end
				local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
				if duration > 0 and enable == 0 then return end
				local key = bagID .. ":" .. slotID
				if IsKnownRecipe(bagID, slotID) then
					SetItemButtonTextureVertexColor(slot, 0, 1, 0)
					if RecipeColor.knownRecipeSlots and not RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = true
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount + 1
					end
				else
					if RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = nil
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
					end
				end
			end


			local origUpdateLocked = ItemSlot.UpdateLocked
			ItemSlot.UpdateLocked = function(slot)
				origUpdateLocked(slot)
				if slot:IsCached() then return end
				local bagID  = slot:GetBag()
				local slotID = slot:GetID()
				if not bagID or not slotID then return end
				local key = bagID .. ":" .. slotID
				if RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
					SetItemButtonTextureVertexColor(slot, 0, 1, 0)
				end
			end

			local learnTicker = RecipeColor.learnTicker
			if learnTicker then
				local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
				learnTicker:SetScript("OnUpdate", function(self)
					if origLearnOnUpdate then origLearnOnUpdate(self) end
					local invFrame = Bagnon and Bagnon.GetFrame and Bagnon:GetFrame("inventory")
					if not (invFrame and invFrame:IsVisible()) then return end
					local itemFrame = invFrame:GetItemFrame()
					if not itemFrame then return end
					for bag = 0, NUM_BAG_SLOTS do
						itemFrame:UpdateAllItemSlotsForBag(bag)
					end
				end)
			end


		end)
		bagnonHookTicker:Show()
		RecipeColor.BagnonTicker = bagnonHookTicker
	end

	-- OneBag
	if isOneBag then
		local aceAddon = LibStub and LibStub("AceAddon-3.0", true)
		local addons = {}
		if aceAddon then
			local ob = aceAddon:GetAddon("OneBag3", true)
			local obk = aceAddon:GetAddon("OneBank3", true)
			if ob  then addons[#addons+1] = ob  end
			if obk then addons[#addons+1] = obk end
		end

		local function ApplyGreenToSlot(slot, bagID, slotID)
			if not slot.rcIcon then
				slot.rcIcon = _G[slot:GetName() .. "IconTexture"]
			end
			local link = GetContainerItemLink(bagID, slotID)
			if not link or not IsRecipeItem(link) then
				slot.rcKnownRecipe = nil
				slot.rcLink = nil
				return
			end
			if link == slot.rcLink then
				-- Item unchanged: re-apply cached result without tooltip scan.
				if slot.rcKnownRecipe and slot.rcIcon then
					slot.rcIcon:SetVertexColor(0, 1, 0)
				end
				return
			end
			slot.rcLink = link
			if IsKnownRecipe(bagID, slotID) then
				slot.rcKnownRecipe = true
				if slot.rcIcon then slot.rcIcon:SetVertexColor(0, 1, 0) end
			else
				slot.rcKnownRecipe = nil
			end
		end

		for _, addon in ipairs(addons) do
			local origUpdateBag = addon.UpdateBag
			addon.UpdateBag = function(self, bag)
				origUpdateBag(self, bag)
				if not self.frame or not self.frame.slots then return end
				for key, slot in pairs(self.frame.slots) do
					local b, s = key:match("^(-?%d+):(%d+)$")
					if b and tonumber(b) == bag and slot:IsVisible() then
						ApplyGreenToSlot(slot, bag, tonumber(s))
					end
				end
			end

			-- Hook UpdateItemLock: called per-slot on ITEM_LOCK_CHANGED.
			-- SetItemButtonDesaturated resets vertex color; re-apply from cache.
			local origUpdateItemLock = addon.UpdateItemLock
			addon.UpdateItemLock = function(self, event, bagid, slotid)
				origUpdateItemLock(self, event, bagid, slotid)
				if not self.frame or not self.frame.slots then return end
				local slot = self:GetSlot(bagid, slotid)
				if slot and slot.rcKnownRecipe and slot.rcIcon then
					slot.rcIcon:SetVertexColor(0, 1, 0)
				end
			end
		end

		-- learnTicker: invalidate all slot link caches so the next UpdateBag
		-- re-runs IsKnownRecipe (known status changed), then repaint all bags.
		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
			learnTicker:SetScript("OnUpdate", function(self)
				if origLearnOnUpdate then origLearnOnUpdate(self) end
				for _, addon in ipairs(addons) do
					if addon.frame and addon.frame.slots then
						for _, slot in pairs(addon.frame.slots) do
							slot.rcLink = nil
						end
						addon:UpdateFrame()
					end
				end
			end)
		end
	end

	-- AdiBags
	if isAdiBags then
		local adiBagsAddon = LibStub and LibStub('AceAddon-3.0', true)
		adiBagsAddon = adiBagsAddon and adiBagsAddon:GetAddon('AdiBags', true)
		local class = adiBagsAddon and adiBagsAddon:GetClass("ItemButton")
		local proto = class and class.prototype
		if proto and proto.Update then
			local origUpdate = proto.Update
			proto.Update = function(self)
				origUpdate(self)
				if not self.hasItem then
					self.rcKnownRecipe = nil
					return
				end
				local bag, slot = self.bag, self.slot
				if bag == nil or slot == nil then return end
				local link = GetContainerItemLink(bag, slot)
				if not link or not IsRecipeItem(link) then
					self.rcKnownRecipe = nil
					return
				end
				if IsKnownRecipe(bag, slot) then
					self.rcKnownRecipe = true
					self.IconTexture:SetVertexColor(0, 1, 0)
				else
					self.rcKnownRecipe = nil
				end
			end

			-- Hook UpdateLock: ITEM_LOCK_CHANGED fires on every visible button.
			-- Re-apply green from the cache set by our Update hook — no tooltip
			-- scan, just a flag check.
			local origUpdateLock = proto.UpdateLock
			proto.UpdateLock = function(self)
				origUpdateLock(self)
				if self.rcKnownRecipe then
					self.IconTexture:SetVertexColor(0, 1, 0)
				end
			end

			-- Extend learnTicker: broadcast AdiBags_UpdateAllButtons so every
			-- visible AdiBags button re-runs our hooked Update() after a recipe
			-- is learned, refreshing the cache and color.
			local learnTicker = RecipeColor.learnTicker
			if learnTicker then
				local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
				learnTicker:SetScript("OnUpdate", function(self)
					if origLearnOnUpdate then origLearnOnUpdate(self) end
					adiBagsAddon:SendMessage("AdiBags_UpdateAllButtons")
				end)
			end
		end
	end

	-- ArkInventory
	if isArkInventory and ArkInventory then
		local VAULT = ArkInventory.Const.Location.Vault
		local BAG   = ArkInventory.Const.Location.Bag
		local BANK  = ArkInventory.Const.Location.Bank

		local origUpdateTexture = ArkInventory.Frame_Item_Update_Texture
		ArkInventory.Frame_Item_Update_Texture = function(frame)
			origUpdateTexture(frame)
			if not frame or not frame.hasItem then
				if frame then frame.rcKnownRecipe = nil end
				return
			end
			local ark = frame.ARK_Data
			if not ark then return end
			local loc_id = ark.loc_id
			if loc_id ~= BAG and loc_id ~= BANK and loc_id ~= VAULT then
				frame.rcKnownRecipe = nil
				return
			end
			local i = ArkInventory.Frame_Item_GetDB(frame)
			if not i or not i.h then
				frame.rcKnownRecipe = nil
				return
			end
			if not IsRecipeItem(i.h) then
				frame.rcKnownRecipe = nil
				return
			end
			local known
			if loc_id == VAULT then
				known = IsKnownRecipe("GuildBank", {i.bag_id, i.slot_id})
			else
				local blizzard_id = ArkInventory.BagID_Blizzard(loc_id, i.bag_id)
				known = IsKnownRecipe(blizzard_id, i.slot_id)
			end
			if known then
				frame.rcKnownRecipe = true
				local icon = _G[frame:GetName() .. "IconTexture"]
				if icon then icon:SetVertexColor(0, 1, 0) end
			else
				frame.rcKnownRecipe = nil
			end
		end

		-- Hook Frame_Item_Update_Lock: called directly on ITEM_LOCK_CHANGED and
		-- GUILDBANK_ITEM_LOCK_CHANGED per slot. SetItemButtonDesaturate resets
		-- vertex color. Re-apply green from cache — no API calls.
		local origUpdateLock = ArkInventory.Frame_Item_Update_Lock
		ArkInventory.Frame_Item_Update_Lock = function(frame)
			origUpdateLock(frame)
			if frame and frame.rcKnownRecipe then
				local icon = _G[frame:GetName() .. "IconTexture"]
				if icon then icon:SetVertexColor(0, 1, 0) end
			end
		end

		-- learnTicker: re-run Frame_Item_Update_Texture on all visible Bag/Bank/
		-- Vault item frames so the cache and color refresh after a recipe is learned.
		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
			learnTicker:SetScript("OnUpdate", function(self)
				if origLearnOnUpdate then origLearnOnUpdate(self) end
				local locs = ArkInventory.Global and ArkInventory.Global.Location
				if not locs then return end
				for _, loc_id in ipairs({BAG, BANK, VAULT}) do
					local loc = locs[loc_id]
					if loc and loc.maxSlot then
						for bag_id in pairs(loc.Bags) do
							for slot_id = 1, loc.maxSlot[bag_id] or 0 do
								local frame = _G[ArkInventory.ContainerItemNameGet(loc_id, bag_id, slot_id)]
								if frame and frame:IsVisible() then
									ArkInventory.Frame_Item_Update_Texture(frame)
								end
							end
						end
					end
				end
			end)
		end
	end


	-- Baggins
	if isBaggins and Baggins then
		local origUpdateItemButton = Baggins.UpdateItemButton
		Baggins.UpdateItemButton = function(self, bagframe, button, bag, slot)
			origUpdateItemButton(self, bagframe, button, bag, slot)
			-- Cache icon reference once per button lifetime.
			if not button.rcIcon then
				button.rcIcon = _G[button:GetName() .. "IconTexture"]
			end
			if not button.hasItem then
				button.rcKnownRecipe = nil
				button.rcLink = nil
				return
			end
			local link = GetContainerItemLink(bag, slot)
			if not link or not IsRecipeItem(link) then
				button.rcKnownRecipe = nil
				button.rcLink = nil
				return
			end
			-- Skip the expensive tooltip scan if the item hasn't changed.
			-- ReallyUpdateBags calls UpdateItemButton on every slot on every
			-- BAG_UPDATE, so this avoids redundant scans on unmoved slots.
			if link == button.rcLink then
				if button.rcKnownRecipe and button.rcIcon then
					button.rcIcon:SetVertexColor(0, 1, 0)
				end
				return
			end
			button.rcLink = link
			if IsKnownRecipe(bag, slot) then
				button.rcKnownRecipe = true
				if button.rcIcon then button.rcIcon:SetVertexColor(0, 1, 0) end
			else
				button.rcKnownRecipe = nil
			end
		end

		local origUpdateItemButtonLocks = Baggins.UpdateItemButtonLocks
		Baggins.UpdateItemButtonLocks = function(self)
			origUpdateItemButtonLocks(self)
			for _, bag in ipairs(self.bagframes) do
				for _, section in ipairs(bag.sections) do
					for _, button in ipairs(section.items) do
						if button:IsVisible() and button.rcKnownRecipe and button.rcIcon then
							button.rcIcon:SetVertexColor(0, 1, 0)
						end
					end
				end
			end
		end

		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
			learnTicker:SetScript("OnUpdate", function(self)
				if origLearnOnUpdate then origLearnOnUpdate(self) end
				for _, bag in ipairs(Baggins.bagframes) do
					for _, section in ipairs(bag.sections) do
						for _, button in ipairs(section.items) do
							button.rcLink = nil
						end
					end
				end
				Baggins:UpdateItemButtons()
			end)
		end
	end


	-- Extended Vendor UI
	if isExtVendor then
		if _G["ExtVendor_UpdateMerchantInfo"] then
			local origExtVendorMerchant = ExtVendor_UpdateMerchantInfo
			HookGlobal("ExtVendor_UpdateMerchantInfo", function()
				origExtVendorMerchant()
				if MerchantFrame:IsVisible() and MerchantFrame.selectedTab ~= 2 then
					RecipeColor:ColorKnownRecipesAtMerchant()
					RecipeColor:ColorKnownRecipesInBuybackSlot()
				end
			end)
		end

		if _G["ExtVendor_UpdateBuybackInfo"] then
			local origExtVendorBuyback = ExtVendor_UpdateBuybackInfo
			HookGlobal("ExtVendor_UpdateBuybackInfo", function()
				origExtVendorBuyback()
				if MerchantFrame:IsVisible() and MerchantFrame.selectedTab == 2 then
					RecipeColor:ColorKnownRecipesInBuybackTab()
				end
			end)
		end

		MerchantFrame:HookScript("OnShow", function()
			local extVendorShowTicker = CreateFrame("Frame")
			extVendorShowTicker:SetScript("OnUpdate", function(self)
				self:SetScript("OnUpdate", nil)
				self:Hide()
				if not MerchantFrame:IsVisible() then return end
				if MerchantFrame.selectedTab == 2 then
					RecipeColor:ColorKnownRecipesInBuybackTab()
				else
					RecipeColor:ColorKnownRecipesAtMerchant()
					RecipeColor:ColorKnownRecipesInBuybackSlot()
				end
			end)
			extVendorShowTicker:Show()
		end)
	end

	-- GudaBags
	if isGudaBags and _G["Guda_ItemButton_SetItem"] then
		local origGuda = Guda_ItemButton_SetItem
		HookGlobal("Guda_ItemButton_SetItem", function(button, bagID, slotID, itemData, isBank, otherCharName, matchesFilter, isReadOnly)
			local itemclass = itemData and itemData.class
			if not itemclass and itemData and itemData.link then
				local itemid = GetFromLink(itemData.link)
				if itemid ~= -1 then
					local _, _, _, _, _, cls = GetItemInfo(itemid)
					itemclass = cls
				end
			end

			origGuda(button, bagID, slotID, itemData, isBank, otherCharName, matchesFilter, isReadOnly)

			-- Only process live (player) recipe slots.
			if not (button.hasItem and not button.isReadOnly and not button.otherChar) then
				-- Slot is empty, read-only, or another character — clear cache.
				if button.rcKnownRecipe ~= nil or button.rcLink ~= nil then
					local key = button.bagID and button.slotID
						and (button.bagID .. ":" .. button.slotID)
					if key and RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = nil
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
					end
					button.rcKnownRecipe = nil
					button.rcLink = nil
				end
				return
			end

			if itemclass ~= "Recipe" then
				-- Not a recipe — clear any stale tracking entry.
				if button.rcKnownRecipe ~= nil or button.rcLink ~= nil then
					local key = button.bagID and button.slotID
						and (button.bagID .. ":" .. button.slotID)
					if key and RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = nil
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
					end
					button.rcKnownRecipe = nil
					button.rcLink = nil
				end
				return
			end

			-- It is a live recipe slot.
			local resolvedBag  = button.bagID  or bagID
			local resolvedSlot = button.slotID or slotID
			local link = GetContainerItemLink(resolvedBag, resolvedSlot)
			local key  = resolvedBag and resolvedSlot and (resolvedBag .. ":" .. resolvedSlot)

			if not link then
				-- Slot is empty despite hasItem being set — clear cache defensively.
				if key and RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
					RecipeColor.knownRecipeSlots[key] = nil
					RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
				end
				button.rcKnownRecipe = nil
				button.rcLink = nil
				return
			end

			if link == button.rcLink then
				if button.rcKnownRecipe then
					if button.unusableOverlay and button.unusableOverlay:IsShown() then
						button.unusableOverlay:SetVertexColor(0, 1, 0, button.unusableOverlay:GetAlpha())
					elseif button.unusableOverlay then
						button.unusableOverlay:SetVertexColor(0, 1, 0, 0.45)
						button.unusableOverlay:Show()
					end
				end
				return
			end

			button.rcLink = link

			if not button.unusableOverlay then
				local icon = _G[button:GetName() and button:GetName() .. "IconTexture"]
					or _G[button:GetName() and button:GetName() .. "Icon"]
				local overlay = (icon and icon:GetParent() or button):CreateTexture(nil, "OVERLAY")
				overlay:SetAllPoints(icon or button)
				overlay:SetTexture("Interface\\ChatFrame\\ChatFrameBackground")
				overlay:Hide()
				button.unusableOverlay = overlay
			end

			if IsKnownRecipe(resolvedBag, resolvedSlot) then
				button.rcKnownRecipe = true
				if button.unusableOverlay:IsShown() then
					-- GudaBags already showed a red unusable overlay; recolor it green.
					button.unusableOverlay:SetVertexColor(0, 1, 0, button.unusableOverlay:GetAlpha())
				else
					button.unusableOverlay:SetVertexColor(0, 1, 0, 0.45)
					button.unusableOverlay:Show()
				end
				-- Maintain tracking tables so the UNIT_SPELLCAST_SUCCEEDED gate works.
				if key and RecipeColor.knownRecipeSlots and not RecipeColor.knownRecipeSlots[key] then
					RecipeColor.knownRecipeSlots[key] = true
					RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount + 1
				end
			else
				button.rcKnownRecipe = nil
				-- Clear stale tracking entry if the item used to be a known recipe.
				if key and RecipeColor.knownRecipeSlots and RecipeColor.knownRecipeSlots[key] then
					RecipeColor.knownRecipeSlots[key] = nil
					RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
				end
			end
		end)

		if _G["Guda_UpdateLockStates"] then
			local origUpdateLockStates = Guda_UpdateLockStates
			HookGlobal("Guda_UpdateLockStates", function(parentsTable)
				origUpdateLockStates(parentsTable)
				if not parentsTable then return end
				for _, parent in pairs(parentsTable) do
					if parent and parent.itemButtons then
						for button in pairs(parent.itemButtons) do
							if button.rcKnownRecipe and button.hasItem
									and button:IsShown()
									and button.unusableOverlay then
								if button.unusableOverlay:IsShown() then
									button.unusableOverlay:SetVertexColor(0, 1, 0, button.unusableOverlay:GetAlpha())
								else
									button.unusableOverlay:SetVertexColor(0, 1, 0, 0.45)
									button.unusableOverlay:Show()
								end
							end
						end
					end
				end
			end)
		end

		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
			learnTicker:SetScript("OnUpdate", function(self)
				if origLearnOnUpdate then origLearnOnUpdate(self) end
				local Guda = _G["Guda"]
				local BF   = Guda and Guda.Modules and Guda.Modules.BagFrame
				local BKF  = Guda and Guda.Modules and Guda.Modules.BankFrame
				local n = 1
				while true do
					local btn = _G["Guda_ItemButton" .. n]
					if not btn then break end
					btn.rcLink = nil
					n = n + 1
				end
				local GudaBagFrame  = _G["Guda_BagFrame"]
				local GudaBankFrame = _G["Guda_BankFrame"]
				if GudaBagFrame and GudaBagFrame:IsShown() then
					if BF and BF.Update then BF:Update() end
				end
				if GudaBankFrame and GudaBankFrame:IsShown() then
					if BKF and BKF.Update then BKF:Update() end
				end
			end)
		end
	end

	-- DragonUI
	if isDragonUICombuctor then
		local combuctorHookTicker = CreateFrame("Frame")
		combuctorHookTicker:SetScript("OnUpdate", function(self)
			local firstItem = _G["DragonUI_CombuctorItem1"]
			if not firstItem then return end

			local proto = getmetatable(firstItem) and getmetatable(firstItem).__index
			if not (proto and proto.Update and proto.UpdateLocked and proto.UpdateCooldown) then
				return
			end

			self:SetScript("OnUpdate", nil)

			local origUpdate = proto.Update
			proto.Update = function(slot)
				origUpdate(slot)
				if not slot:IsVisible() then return end

				local bagID  = slot:GetBag()
				local slotID = slot:GetID()
				if not bagID then return end

				local link = GetContainerItemLink(bagID, slotID)

				if not slot.hasItem or not link or not IsRecipeItem(link) then
					if slot.rcKnownRecipe ~= nil or slot.rcLink ~= nil then
						local key = bagID .. ":" .. slotID
						if RecipeColor.knownRecipeSlots
								and RecipeColor.knownRecipeSlots[key] then
							RecipeColor.knownRecipeSlots[key] = nil
							RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
						end
						slot.rcKnownRecipe = nil
						slot.rcLink = nil
					end
					return
				end

				if link == slot.rcLink then
					if slot.rcKnownRecipe then
						local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
						if not (duration > 0 and enable == 0) then
							SetItemButtonTextureVertexColor(slot, 0, 1, 0)
						end
					end
					return
				end

				slot.rcLink = link
				local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
				if duration > 0 and enable == 0 then
					-- On cooldown — grey tint takes priority; clear recipe cache.
					slot.rcKnownRecipe = nil
					return
				end

				local key = bagID .. ":" .. slotID
				if IsKnownRecipe(bagID, slotID) then
					slot.rcKnownRecipe = true
					SetItemButtonTextureVertexColor(slot, 0, 1, 0)
					if RecipeColor.knownRecipeSlots
							and not RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = true
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount + 1
					end
				else
					slot.rcKnownRecipe = nil
					if RecipeColor.knownRecipeSlots
							and RecipeColor.knownRecipeSlots[key] then
						RecipeColor.knownRecipeSlots[key] = nil
						RecipeColor.knownRecipeCount = RecipeColor.knownRecipeCount - 1
					end
				end
			end

			local origUpdateLocked = proto.UpdateLocked
			proto.UpdateLocked = function(slot)
				origUpdateLocked(slot)
				if slot.rcKnownRecipe and slot.hasItem then
					local bagID  = slot:GetBag()
					local slotID = slot:GetID()
					if not bagID then return end
					local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
					if not (duration > 0 and enable == 0) then
						SetItemButtonTextureVertexColor(slot, 0, 1, 0)
					end
				end
			end

			local origUpdateCooldown = proto.UpdateCooldown
			proto.UpdateCooldown = function(slot)
				origUpdateCooldown(slot)
				if slot.rcKnownRecipe and slot.hasItem then
					local bagID  = slot:GetBag()
					local slotID = slot:GetID()
					if not bagID then return end
					local start, duration, enable = GetContainerItemCooldown(bagID, slotID)
					if not (duration > 0 and enable == 0) then
						SetItemButtonTextureVertexColor(slot, 0, 1, 0)
					end
				end
			end

			local learnTicker = RecipeColor.learnTicker
			if learnTicker then
				local origLearnOnUpdate = learnTicker:GetScript("OnUpdate")
				learnTicker:SetScript("OnUpdate", function(self)
					if origLearnOnUpdate then origLearnOnUpdate(self) end
					local n = 1
					while true do
						local btn = _G["DragonUI_CombuctorItem" .. n]
						if not btn then break end
						btn.rcLink = nil
						n = n + 1
					end
					local frameIdx = 1
					while true do
						local frame = _G["DragonUI_CombuctorFrame" .. frameIdx]
						if not frame then break end
						if frame:IsShown() and frame.itemFrame then
							frame.itemFrame:Regenerate()
						end
						frameIdx = frameIdx + 1
					end
				end)
			end
		end)
		combuctorHookTicker:Show()
		RecipeColor.DragonUICombuctorTicker = combuctorHookTicker
	end
end

-- Deferred event handler for compat addons. Called from RecipeColor_OnEvent.
function RecipeColor.OnCompatEvent(rcFrame, event, arg1)
	-- SUCC-bag
	if event == "ADDON_LOADED" and arg1 == "SUCC-bag" then
		isSUCCbag = true

		-- Helper: iterate all slots in one SUCC-bag frame and apply/clear green,
		-- using the cache when the item link has not changed.
		local function ColorSUCCFrame(frame)
			if not frame or not frame:IsShown() or not frame.size or frame.size == 0 then
				return
			end
			local frameName = frame:GetName()
			for s = 1, frame.size do
				local button = _G[frameName .. "Item" .. s]
				if button then
					if not button.hasItem then
						button.rcKnownRecipe = nil
						button.rcLink = nil
					else
						local bagID  = button:GetParent():GetID()
						local slotID = button:GetID()
						local link   = GetContainerItemLink(bagID, slotID)
						if not link or not IsRecipeItem(link) then
							button.rcKnownRecipe = nil
							button.rcLink = nil
						elseif link == button.rcLink then
							-- Same item as last paint — re-apply cached result, no tooltip scan.
							if button.rcKnownRecipe then
								SetItemButtonTextureVertexColor(button, 0, 1, 0)
							end
						else
							-- Item changed — run tooltip scan and update cache.
							button.rcLink = link
							if IsKnownRecipe(bagID, slotID) then
								button.rcKnownRecipe = true
								SetItemButtonTextureVertexColor(button, 0, 1, 0)
							else
								button.rcKnownRecipe = nil
							end
						end
					end
				end
			end
		end

		local function RestoreSUCCFrameFromCache(frame)
			if not frame or not frame:IsShown() or not frame.size or frame.size == 0 then
				return
			end
			local frameName = frame:GetName()
			for s = 1, frame.size do
				local button = _G[frameName .. "Item" .. s]
				if button and button.rcKnownRecipe then
					SetItemButtonTextureVertexColor(button, 0, 1, 0)
				end
			end
		end

		local succUpdateTicker = CreateFrame("Frame")
		succUpdateTicker:Hide()
		succUpdateTicker:SetScript("OnUpdate", function(self)
			self:Hide()
			local frames = {SUCC_bag, SUCC_bag.bank}
			for _, frame in ipairs(frames) do
				ColorSUCCFrame(frame)
			end
		end)

		local succLockTicker = CreateFrame("Frame")
		succLockTicker:Hide()
		succLockTicker:SetScript("OnUpdate", function(self)
			self:Hide()
			local frames = {SUCC_bag, SUCC_bag.bank}
			for _, frame in ipairs(frames) do
				RestoreSUCCFrameFromCache(frame)
			end
		end)

		if _G["SBFrameOpen"] then
			local origOpen = SBFrameOpen
			HookGlobal("SBFrameOpen", function(frame, automatic)
				origOpen(frame, automatic)
				ColorSUCCFrame(frame)
			end)
		end

		RecipeColor.SUCCUpdateTicker = succUpdateTicker
		RecipeColor.SUCCLockTicker   = succLockTicker
	end

	if isSUCCbag then
		if event == "BAG_UPDATE" or event == "BAG_UPDATE_COOLDOWN"
				or event == "UPDATE_INVENTORY_ALERTS"
				or event == "PLAYERBANKSLOTS_CHANGED" or event == "BANKFRAME_OPENED" then
			if RecipeColor.SUCCUpdateTicker then
				RecipeColor.SUCCUpdateTicker:Show()
			end
		end
		if event == "ITEM_LOCK_CHANGED" then
			if RecipeColor.SUCCLockTicker then
				RecipeColor.SUCCLockTicker:Show()
			end
		end
		if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" then
			if RecipeColor.SUCCUpdateTicker then
				local frames = {SUCC_bag, SUCC_bag.bank}
				for _, frame in ipairs(frames) do
					if frame and frame:IsShown() and frame.size and frame.size > 0 then
						local frameName = frame:GetName()
						for s = 1, frame.size do
							local button = _G[frameName .. "Item" .. s]
							if button then button.rcLink = nil end
						end
					end
				end
				RecipeColor.SUCCUpdateTicker:Show()
			end
		end
	end

	-- Bagnon
	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and isBagnon then
		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			local invFrame = Bagnon and Bagnon.GetFrame and Bagnon:GetFrame("inventory")
			if invFrame and invFrame:IsVisible() then
				learnTicker:Show()
			end
		end
	end

	-- Bagnon_GuildBank
	if event == "ADDON_LOADED" and arg1 == "Bagnon_GuildBank" and isBagnon then
		isBagnonGuildBank = true

		local GuildItemSlot = Bagnon and Bagnon.GuildItemSlot
		if GuildItemSlot and GuildItemSlot.Update then

			local origGuildUpdate = GuildItemSlot.Update
			GuildItemSlot.Update = function(slot)
				origGuildUpdate(slot)
				if not slot.hasItem then return end
				local tab, slotID = slot:GetSlot()
				if not tab or not slotID then return end
				local link = GetGuildBankItemLink(tab, slotID)
				if not link or not IsRecipeItem(link) then return end
				if IsKnownRecipe("GuildBank", {tab, slotID}) then
					SetItemButtonTextureVertexColor(slot, 0, 1, 0)
				end
			end

			local origGuildUpdateLocked = GuildItemSlot.UpdateLocked
			GuildItemSlot.UpdateLocked = function(slot)
				origGuildUpdateLocked(slot)
				if not slot.hasItem then return end
				local tab, slotID = slot:GetSlot()
				if not tab or not slotID then return end
				local link = GetGuildBankItemLink(tab, slotID)
				if not link or not IsRecipeItem(link) then return end
				if IsKnownRecipe("GuildBank", {tab, slotID}) then
					SetItemButtonTextureVertexColor(slot, 0, 1, 0)
				end
			end

		end
	end

	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and isBagnonGuildBank then
		local guildFrame = _G["BagnonFrameguildbank"]
		if guildFrame and guildFrame:IsVisible() then
			local itemFrame = guildFrame:GetItemFrame()
			if itemFrame then
				for _, itemSlot in itemFrame:GetAllItemSlots() do
					itemSlot:Update()
				end
			end
		end
	end

	-- AdiBags/ArkInventory/Baggins/OneBag
	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player"
			and (isAdiBags or isArkInventory or isBaggins or isOneBag) then
		local learnTicker = RecipeColor.learnTicker
		if learnTicker then
			learnTicker:Show()
		end
	end

	-- ElvUI
	if event == "UNIT_SPELLCAST_SUCCEEDED" and isElvUI then
		local learnTicker = RecipeColor.learnTicker
		if learnTicker and RecipeColor.knownRecipeCount > 0 then
			local E = ElvUI and ElvUI[1]
			local B = E and E:GetModule("Bags")
			if B and B.BagFrame and B.BagFrame:IsShown() then
				learnTicker:Show()
			end
		end
	end

	-- GudaBags
	if event == "UNIT_SPELLCAST_SUCCEEDED" and isGudaBags then
		local learnTicker = RecipeColor.learnTicker
		if learnTicker and RecipeColor.knownRecipeCount > 0 then
			local GudaBagFrame = _G["Guda_BagFrame"]
			if GudaBagFrame and GudaBagFrame:IsShown() then
				learnTicker:Show()
			end
		end
	end

	-- DragonUI
	if event == "UNIT_SPELLCAST_SUCCEEDED" and arg1 == "player" and isDragonUICombuctor then
		local learnTicker = RecipeColor.learnTicker
		if learnTicker and RecipeColor.knownRecipeCount > 0 then
			local frameIdx = 1
			while true do
				local frame = _G["DragonUI_CombuctorFrame" .. frameIdx]
				if not frame then break end
				if frame:IsShown() then
					learnTicker:Show()
					break
				end
				frameIdx = frameIdx + 1
			end
		end
	end
end