local Monomyth = CreateFrame('Frame')
Monomyth:SetScript('OnEvent', function(self, event, ...) self[event](...) end)

local DelayHandler
do
	local currentInfo = {}

	local Delayer = Monomyth:CreateAnimationGroup()
	Delayer:CreateAnimation():SetDuration(1)
	Delayer:SetLooping('NONE')
	Delayer:SetScript('OnFinished', function()
		DelayHandler(unpack(currentInfo))
	end)

	local delayed = true
	function DelayHandler(func, ...)
		if(delayed) then
			delayed = false

			table.wipe(currentInfo)
			table.insert(currentInfo, func)

			for index = 1, select('#', ...) do
				local argument = select(index, ...)
				table.insert(currentInfo, argument)
			end

			Delayer:Play()
		else
			delayed = true
			func(...)
		end
	end
end

local atBank, atMail, atMerchant

local delayEvent = {
	GOSSIP_SHOW = true,
	GOSSIP_CONFIRM = true,
	QUEST_GREETING = true,
	QUEST_DETAIL = true,
	QUEST_ACCEPT_CONFIRM = true,
	QUEST_PROGRESS = true,
	QUEST_AUTOCOMPLETE = true,	
}

local modifier = false
function Monomyth:Register(event, func, override)
	self:RegisterEvent(event)
	self[event] = function(...)
		if(override or MonomythDB.toggle and MonomythDB.reverse == modifier) then
			if(MonomythDB.delay and delayEvent[event]) then
				DelayHandler(func, ...)
			else
				func(...)
			end
		end
	end
end

local function IsTrackingTrivial()
	for index = 1, GetNumTrackingTypes() do
		local name, _, active = GetTrackingInfo(index)
		if(name == MINIMAP_TRACKING_TRIVIAL_QUESTS) then
			return active
		end
	end
end

Monomyth:Register('QUEST_GREETING', function()
	local active = GetNumActiveQuests()
	if(active > 0) then
		for index = 1, active do
			local _, complete = GetActiveTitle(index)
			if(complete) then
				SelectActiveQuest(index)
			end
		end
	end

	local available = GetNumAvailableQuests()
	if(available > 0) then
		for index = 1, available do
			if(not IsAvailableQuestTrivial(index) or IsTrackingTrivial()) then
				SelectAvailableQuest(index)
			end
		end
	end
end)

-- This should be part of the API, really
local function IsGossipQuestCompleted(index)
	return not not select(((index * 5) - 5) + 4, GetGossipActiveQuests())
end

local function IsGossipQuestTrivial(index)
	return not not select(((index * 6) - 6) + 3, GetGossipAvailableQuests())
end

local function GetCreatureID()
	return tonumber(string.sub(UnitGUID('npc') or '', -12, -9), 16)
end

Monomyth:Register('GOSSIP_SHOW', function()
	local active = GetNumGossipActiveQuests()
	if(active > 0) then
		for index = 1, active do
			if(IsGossipQuestCompleted(index)) then
				SelectGossipActiveQuest(index)
			end
		end
	end

	local available = GetNumGossipAvailableQuests()
	if(available > 0) then
		for index = 1, available do
			if(not IsGossipQuestTrivial(index) or IsTrackingTrivial()) then
				SelectGossipAvailableQuest(index)
			end
		end
	end

	if(MonomythDB.gossip) then
		if(available == 0 and active == 0 and GetNumGossipOptions() == 1) then
			local _, instance = GetInstanceInfo()
			if(not (MonomythDB.gossipraid and instance == 'raid')) then
				local _, type = GetGossipOptions()
				if(type == 'gossip') then
					SelectGossipOption(1)
					return
				end
			end
		end
	end

	if(MonomythDB.faireport) then
		local creatureID = GetCreatureID()
		if(creatureID and creatureID == 57850) then
			-- See if 1 is the right option
			SelectGossipOption(1)
		end
	end
end)

local darkmoonNPC = {
	[57850] = true, -- Teleportologist Fozlebub
	[55382] = true, -- Darkmoon Faire Mystic Mage (Horde)
	[54334] = true, -- Darkmoon Faire Mystic Mage (Alliance)
}

Monomyth:Register('GOSSIP_CONFIRM', function(index)
	if(not MonomythDB.faireport) then return end

	local creatureID = GetCreatureID()
	if(creatureID and darkmoonNPC[creatureID]) then
		SelectGossipOption(index, '', true)
		StaticPopup_Hide('GOSSIP_CONFIRM')
	end
end)

Monomyth:Register('QUEST_DETAIL', function()
	if(not QuestGetAutoAccept() and not QuestIsFromAreaTrigger()) then
		AcceptQuest()
	end
end)

Monomyth:Register('QUEST_ACCEPT_CONFIRM', AcceptQuest)

Monomyth:Register('QUEST_ACCEPTED', function(id)
	if(QuestFrame:IsShown() and QuestGetAutoAccept()) then
		CloseQuest()
	end
end)

local choiceQueue
Monomyth:Register('QUEST_ITEM_UPDATE', function()
	if(choiceQueue and Monomyth[choiceQueue]) then
		Monomyth[choiceQueue]()
	end
end)

Monomyth:Register('QUEST_PROGRESS', function()
	if(IsQuestCompletable()) then
		local requiredItems = GetNumQuestItems()
		if(requiredItems > 0) then
			for index = 1, requiredItems do
				local link = GetQuestItemLink('required', index)
				if(link) then
					local id = tonumber(string.match(link, 'item:(%d+)'))
					for _, itemID in pairs(MonomythDB.ignoredQuests) do
						if(itemID == id) then
							return
						end
					end
				else
					choiceQueue = 'QUEST_PROGRESS'
					return
				end
			end
		end

		CompleteQuest()
	end
end)

Monomyth:Register('QUEST_COMPLETE', function()
	local choices = GetNumQuestChoices()
	if(choices <= 1) then
		GetQuestReward(1)
	elseif(choices > 1) then
		local bestValue, bestIndex = 0

		for index = 1, choices do
			local link = GetQuestItemLink('choice', index)
			if(link) then
				local _, _, _, _, _, _, _, _, _, _, value = GetItemInfo(link)

				if(string.match(link, 'item:45724:')) then
					-- Champion's Purse, contains 10 gold
					value = 1e5
				end

				if(value > bestValue) then
					bestValue, bestIndex = value, index
				end
			else
				choiceQueue = 'QUEST_COMPLETE'
				return GetQuestItemInfo('choice', index)
			end
		end

		if(bestIndex) then
			_G['QuestInfoItem' .. bestIndex]:Click()
		end
	end
end)

Monomyth:Register('QUEST_FINISHED', function()
	choiceQueue = nil
end)

Monomyth:Register('QUEST_AUTOCOMPLETE', function(id)
	local index = GetQuestLogIndexByID(id)
	if(GetQuestLogIsAutoComplete(index)) then
		-- The quest might not be considered complete, investigate later
		ShowQuestComplete(index)
	end
end)

Monomyth:Register('BANKFRAME_OPENED', function()
	atBank = true
end)

Monomyth:Register('BANKFRAME_CLOSED', function()
	atBank = false
end)

Monomyth:Register('GUILDBANKFRAME_OPENED', function()
	atBank = true
end)

Monomyth:Register('GUILDBANKFRAME_CLOSED', function()
	atBank = false
end)

Monomyth:Register('MAIL_SHOW', function()
	atMail = true
end)

Monomyth:Register('MAIL_CLOSED', function()
	atMail = false
end)

Monomyth:Register('MERCHANT_SHOW', function()
	atMerchant = true
end)

Monomyth:Register('MERCHANT_CLOSED', function()
	atMerchant = false
end)

local sub = string.sub
Monomyth:Register('MODIFIER_STATE_CHANGED', function(key, state)
	if(sub(key, 2) == MonomythDB.modifier) then
		modifier = state == 1
	end
end, true)

local questTip = CreateFrame('GameTooltip', 'MonomythTip', UIParent)
local questLevel = string.gsub(ITEM_MIN_LEVEL, '%%d', '(%%d+)')

local function GetQuestItemLevel()
	for index = 1, questTip:NumLines() do
		local level = string.match(_G['MonomythTipTextLeft' .. index]:GetText(), questLevel)
		if(level and tonumber(level)) then
			return tonumber(level)
		end
	end
end

local function BagUpdate(bag)
	if(not MonomythDB.items) then return end
	if(atBank or atMail or atMerchant) then return end

	for slot = 1, GetContainerNumSlots(bag) do
		local _, id, active = GetContainerItemQuestInfo(bag, slot)
		if(id and not active and not IsQuestFlaggedCompleted(id) and not MonomythDB.ignoredQuests[id]) then
			questTip:SetBagItem(bag, slot)
			questTip:Show()

			local level = GetQuestItemLevel()
			if(not level or level >= UnitLevel('player')) then
				UseContainerItem(bag, slot)
			end
		end
	end
end

Monomyth:Register('PLAYER_LOGIN', function()
	Monomyth:Register('BAG_UPDATE', BagUpdate)
end)

local errors = {
	[ERR_QUEST_ALREADY_DONE] = true,
	[ERR_QUEST_FAILED_LOW_LEVEL] = true,
	[ERR_QUEST_NEED_PREREQS] = true,
}	

ChatFrame_AddMessageEventFilter('CHAT_MSG_SYSTEM', function(self, event, message)
	return errors[message]
end)

QuestInfoDescriptionText.SetAlphaGradient = function() end
