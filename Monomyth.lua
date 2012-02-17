local Monomyth = CreateFrame('Frame')
Monomyth:SetScript('OnEvent', function(self, event, ...) self[event](...) end)

function Monomyth:Register(event, func)
	self:RegisterEvent(event)
	self[event] = function(...)
		if(IsShiftKeyDown()) then
			if(event == 'QUEST_DETAIL') then
				QuestFrame_OnEvent(nil, event)
			end
		else
			func(...)
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
	return not not select(index * 4, GetGossipActiveQuests())
end

local function IsGossipQuestTrivial(index)
	return not not select(index * 3, GetGossipAvailableQuests())
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

	if(available == 0 and active == 0 and GetNumGossipOptions() == 1) then
		local _, type = GetGossipOptions()
		if(type == 'gossip') then
			SelectGossipOption(1)
		end
	end
end)

QuestFrame:UnregisterEvent('QUEST_DETAIL')
Monomyth:Register('QUEST_DETAIL', function()
	if(QuestGetAutoAccept()) then
		if(GossipFrame:IsShown()) then
			HideUIPanel(GossipFrame)
		else
			CloseQuest()
		end
	else
		QuestFrame_OnEvent(nil, 'QUEST_DETAIL')
		AcceptQuest()
	end
end)

Monomyth:Register('QUEST_ACCEPT_CONFIRM', AcceptQuest)

Monomyth:Register('QUEST_PROGRESS', function()
	if(IsQuestCompletable()) then
		CompleteQuest()
	end
end)

local choiceQueue, choiceFinished
Monomyth:Register('QUEST_ITEM_UPDATE', function(...)
	if(choiceQueue) then
		Monomyth.QUEST_COMPLETE()
	end
end)

Monomyth:Register('QUEST_COMPLETE', function()
	local choices = GetNumQuestChoices()
	if(choices <= 1) then
		GetQuestReward(QuestFrameRewardPanel.itemChoice)
	elseif(choices > 1) then
		local bestValue, bestIndex = 0

		for index = 1, choices do
			local link = GetQuestItemLink('choice', index)
			if(link) then
				local _, _, _, _, _, _, _, _, _, _, value = GetItemInfo(link)
				if(value > bestValue) then
					bestValue, bestIndex = value, index
				end
			else
				choiceQueue = true
				return GetQuestItemInfo('choice', index)
			end
		end

		if(bestIndex) then
			choiceFinished = true
			_G['QuestInfoItem' .. bestIndex]:Click()
		end
	end
end)

Monomyth:Register('QUEST_FINISHED', function()
	if(choiceFinished) then
		choiceQueue = false
	end
end)

Monomyth:Register('QUEST_AUTOCOMPLETE', function(id)
	local index = GetQuestLogIndexByID(id)
	if(GetQuestLogIsAutoComplete(index)) then
		-- The quest might not be considered complete, investigate later
		ShowQuestComplete(index)
	end
end)

local atBank
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

local completedQuests, query = {}
Monomyth:Register('QUEST_QUERY_COMPLETE', function()
	if(query) then
		local bag = query
		query = nil

		GetQuestsCompleted(completedQuests)
		Monomyth.BAG_UPDATE(bag)
	end
end)

Monomyth:Register('BAG_UPDATE', function(bag)
	if(bag < 0) then return end
	if(atBank) then return end
	if(query) then return end

	for slot = 1, GetContainerNumSlots(bag) do
		local _, id, active = GetContainerItemQuestInfo(bag, slot)
		if(id and not active) then
			if(not next(completedQuests)) then
				query = bag
				QueryQuestsCompleted()
			elseif(not completedQuests[id]) then
				UseContainerItem(bag, slot)
			end
		end
	end
end)

hooksecurefunc('QuestLogTitleButton_OnClick', function(self)
	if(self.isHeader) then return end
	QuestLog_SetSelection(self:GetID())

	if(IsControlKeyDown()) then
		AbandonQuest()
	elseif(IsAltKeyDown() and GetQuestLogPushable()) then
		QuestLogPushQuest()
	end
end)

QuestInfoDescriptionText.SetAlphaGradient = function() end
