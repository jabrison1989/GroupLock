-- Core addon handle (Ace/Blizz expects first vararg to be addon name)
local addonName = ...

-- Single frame listening for all events we care about
local eventFrame = CreateFrame("Frame")

-- Default per-character settings applied on first load
local DEFAULTS = {
    allowFriends = true,
    allowGuild = true,
    whitelist = {},
}

local db
local friendCache = {}
local guildCache = {}

-- UI state references (populated in CreateConfigFrame)
local configFrame
local friendsCheckbox
local guildCheckbox
local whitelistInput
local addWhitelistButton
local closeButton
local descriptionText
local whitelistBackground
local instructionsText
local whitelistScrollFrame
local whitelistScrollChild
local whitelistEmptyText

local whitelistRows = {}

-- Forward declarations so helpers can reference functions defined later
local CreateConfigFrame
local ApplyElvUISkin
local ResizeConfigFrame
local EnsureUnitPopupSetup
local EnsureItemRefButton

local WHITELIST_ROW_HEIGHT = 24
local UNIT_POPUP_OPTION = "GROUPLOCK_WHITELIST"

local popupSetupDone = false
local popupHooked = false
local itemRefAddButton
local itemRefTooltipHooked = false

local UpdateWhitelistDisplay
local AddToWhitelist
local RemoveFromWhitelist

local function Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cFF33FF99GroupLock:|r " .. msg)
end

local function CopyDefaults(src, dest)
    -- Recursively fill missing keys so upgrades keep previous choices
    for key, value in pairs(src) do
        if type(value) == "table" then
            if type(dest[key]) ~= "table" then
                dest[key] = {}
            end
            CopyDefaults(value, dest[key])
        elseif dest[key] == nil then
            dest[key] = value
        end
    end
end

local function NormalizeName(name)
    -- Strip realm suffix and lower-case for safe table lookups
    if not name then
        return nil
    end

    name = strtrim(name)
    if name == "" then
        return nil
    end

    local shortName = name:match("([^%-]+)") or name
    return shortName:lower()
end

local function PrettyName(name)
    if not name then
        return ""
    end

    local lowered = name:lower()
    return lowered:gsub("^%l", string.upper)
end

local function AcquireWhitelistRow(index)
    -- Lazily builds or reuses a row to show a stored whitelist entry
    if not whitelistScrollChild then
        return nil
    end

    local row = whitelistRows[index]
    if row then
        return row
    end

    row = CreateFrame("Frame", nil, whitelistScrollChild)
    row:SetHeight(WHITELIST_ROW_HEIGHT)

    if index == 1 then
        row:SetPoint("TOPLEFT", whitelistScrollChild, "TOPLEFT", 0, 0)
    else
        row:SetPoint("TOPLEFT", whitelistRows[index - 1], "BOTTOMLEFT", 0, 0)
    end
    row:SetPoint("RIGHT", whitelistScrollChild, "RIGHT", -4, 0)

    row.nameText = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    row.nameText:SetPoint("LEFT", 4, 0)
    row.nameText:SetPoint("RIGHT", -36, 0)
    row.nameText:SetJustifyH("LEFT")

    row.remove = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    row.remove:SetSize(24, 18)
    row.remove:SetPoint("RIGHT", -4, 0)
    row.remove:SetText("X")
    row.remove:SetScript("OnClick", function(button)
        local parent = button:GetParent()
        if parent and parent.OnRemove then
            parent:OnRemove()
        end
    end)

    whitelistRows[index] = row
    return row
end

UpdateWhitelistDisplay = function()
    -- Rebuilds scroll content, maintaining alphabetical order and skins
    if not db or not whitelistBackground or not whitelistScrollChild then
        return
    end

    local entries = {}
    for normalized, storedName in pairs(db.whitelist) do
        table.insert(entries, { normalized = normalized, display = storedName })
    end
    table.sort(entries, function(a, b)
        return a.display:lower() < b.display:lower()
    end)

    local count = #entries

    for index, entry in ipairs(entries) do
        local row = AcquireWhitelistRow(index)
        if row then
            local displayName = entry.display
            row.entryNormalized = entry.normalized
            row.entryDisplay = displayName
            row.nameText:SetText(displayName)
            row.OnRemove = function()
                local removed, result = RemoveFromWhitelist(displayName)
                if removed then
                    Print("Removed " .. result .. " from whitelist.")
                else
                    Print(result or "Unable to remove name.")
                end
            end
            row:Show()
            if row.remove then
                row.remove:Enable()
            end
        end
    end

    for index = count + 1, #whitelistRows do
        local row = whitelistRows[index]
        if row then
            row:Hide()
            row.entryNormalized = nil
            row.entryDisplay = nil
            row.OnRemove = nil
        end
    end

    local targetHeight = math.max(count * WHITELIST_ROW_HEIGHT, whitelistBackground:GetHeight() - 16)
    whitelistScrollChild:SetHeight(targetHeight)
    if whitelistScrollFrame then
        whitelistScrollChild:SetWidth(whitelistScrollFrame:GetWidth())
    end

    if whitelistEmptyText then
        if count == 0 then
            whitelistEmptyText:Show()
        else
            whitelistEmptyText:Hide()
        end
    end

    if configFrame and configFrame:IsShown() then
        ResizeConfigFrame()
        if type(ElvUI) == "table" then
            ApplyElvUISkin()
        end
    end
end

local function CommitProfile()
    -- Ensure saved variables reflect the latest in-memory settings
    if not db then
        return
    end

    if type(GroupLockDB) ~= "table" then
        GroupLockDB = {}
    end

    -- Copy scalar settings
    GroupLockDB.allowFriends = db.allowFriends and true or false
    GroupLockDB.allowGuild = db.allowGuild and true or false

    -- Preserve whitelist table reference
    GroupLockDB.whitelist = db.whitelist

    if db ~= GroupLockDB then
        -- Keep local reference aligned with the saved variable table
        db = GroupLockDB
    end
end

AddToWhitelist = function(rawName)
    -- Normalizes and persists a player name inside the profile whitelist
    if not rawName then
        return false, "Name required."
    end

    local trimmed = strtrim(rawName)
    if trimmed == "" then
        return false, "Name required."
    end

    local normalized = NormalizeName(trimmed)
    if not normalized then
        return false, "Unable to parse name."
    end

    if db.whitelist[normalized] then
        return false, PrettyName(trimmed) .. " is already whitelisted."
    end

    local displayName = PrettyName(trimmed)
    db.whitelist[normalized] = displayName
    CommitProfile()
    UpdateWhitelistDisplay()
    return true, displayName
end

RemoveFromWhitelist = function(rawName)
    -- Removes a player entry if it exists, returning the pretty string
    if not rawName then
        return false, "Name required."
    end

    local trimmed = strtrim(rawName)
    if trimmed == "" then
        return false, "Name required."
    end

    local normalized = NormalizeName(trimmed)
    if not normalized then
        return false, "Unable to parse name."
    end

    local current = db.whitelist[normalized]
    if current then
        db.whitelist[normalized] = nil
        CommitProfile()
        UpdateWhitelistDisplay()
        return true, current
    end

    return false, PrettyName(trimmed) .. " is not in the whitelist."
end

local function UpdateFriendCache()
    -- Snapshot the current WoW friends roster for quick membership checks
    wipe(friendCache)

    for i = 1, GetNumFriends() do
        local name = GetFriendInfo(i)
        if name then
            local normalized = NormalizeName(name)
            if normalized then
                friendCache[normalized] = true
            end
        end
    end
end

local function UpdateGuildCache()
    -- Snapshot guild roster so guild invites can bypass the decline
    wipe(guildCache)

    if not IsInGuild() then
        return
    end

    for i = 1, GetNumGuildMembers(true) do
        local name = GetGuildRosterInfo(i)
        if name then
            local normalized = NormalizeName(name)
            if normalized then
                guildCache[normalized] = true
            end
        end
    end
end

local function IsWhitelisted(name)
    local normalized = NormalizeName(name)
    if not normalized then
        return false
    end
    return db.whitelist[normalized] ~= nil
end

local function IsFriend(name)
    if not db.allowFriends then
        return false
    end

    local normalized = NormalizeName(name)
    if not normalized then
        return false
    end

    return friendCache[normalized] == true
end

local function IsGuildMate(name)
    if not db.allowGuild then
        return false
    end

    local normalized = NormalizeName(name)
    if not normalized then
        return false
    end

    return guildCache[normalized] == true
end

local function ShouldDecline(name)
    -- Evaluates whether an incoming invite should be auto-declined
    if not name or name == "" then
        return false
    end

    if IsWhitelisted(name) then
        return false
    end

    if IsFriend(name) then
        return false
    end

    if IsGuildMate(name) then
        return false
    end

    return true
end

local function ToggleConfigFrame()
    -- Slash command handler toggling the configuration panel
    if not configFrame then
        CreateConfigFrame()
    end

    if configFrame:IsShown() then
        configFrame:Hide()
    else
        configFrame:Show()
    end
end

local function RefreshOptionStates()
    if friendsCheckbox then
        friendsCheckbox:SetChecked(db.allowFriends)
    end
    if guildCheckbox then
        guildCheckbox:SetChecked(db.allowGuild)
    end
    UpdateWhitelistDisplay()
end

ResizeConfigFrame = function()
    -- Adjusts window size based on current contents, leaving padding
    if not configFrame or not configFrame:IsShown() then
        return
    end

    local padding = 48
    local minWidth = 460
    local minHeight = 420

    local minLeft = math.huge
    local maxRight = -math.huge
    local highest = -math.huge
    local lowest = math.huge

    local elements = {
        configFrame.TitleText,
        descriptionText,
        friendsCheckbox,
        guildCheckbox,
        whitelistBackground,
        whitelistInput,
        addWhitelistButton,
        instructionsText,
        closeButton,
    }

    for _, element in ipairs(elements) do
        if element and element:IsShown() then
            local left = element:GetLeft()
            local right = element:GetRight()
            local top = element:GetTop()
            local bottom = element:GetBottom()

            if left and right and top and bottom then
                if left < minLeft then
                    minLeft = left
                end
                if right > maxRight then
                    maxRight = right
                end
                if top > highest then
                    highest = top
                end
                if bottom < lowest then
                    lowest = bottom
                end
            end
        end
    end

    if minLeft < math.huge and maxRight > -math.huge then
        configFrame:SetWidth(math.max(minWidth, (maxRight - minLeft) + padding))
    else
        configFrame:SetWidth(minWidth)
    end

    if highest > -math.huge and lowest < math.huge then
        configFrame:SetHeight(math.max(minHeight, (highest - lowest) + padding))
    else
        configFrame:SetHeight(minHeight)
    end

    if descriptionText then
        descriptionText:SetWidth(configFrame:GetWidth() - 120)
    end

    if instructionsText then
        instructionsText:SetWidth(configFrame:GetWidth() - 80)
    end
end

ApplyElvUISkin = function()
    -- Calls into ElvUI skinning if present so our panels blend in
    if not configFrame or type(ElvUI) ~= "table" then
        return
    end

    local ok, E = pcall(function()
        return unpack(ElvUI)
    end)

    if not ok or not E or type(E.GetModule) ~= "function" then
        return
    end

    local Skins = E:GetModule("Skins", true)
    if not Skins then
        return
    end

    if Skins.HandleFrame then
        Skins:HandleFrame(configFrame, true)
    end

    if closeButton and Skins.HandleCloseButton then
        Skins:HandleCloseButton(closeButton)
        closeButton:ClearAllPoints()
        closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -4, -4)
        closeButton:SetFrameLevel(configFrame:GetFrameLevel() + 10)
    end

    if friendsCheckbox and Skins.HandleCheckBox then
        Skins:HandleCheckBox(friendsCheckbox)
    end

    if guildCheckbox and Skins.HandleCheckBox then
        Skins:HandleCheckBox(guildCheckbox)
    end

    if whitelistInput and Skins.HandleEditBox then
        Skins:HandleEditBox(whitelistInput)
    end

    if addWhitelistButton and Skins.HandleButton then
        Skins:HandleButton(addWhitelistButton)
    end

    if Skins.HandleButton then
        for _, row in ipairs(whitelistRows) do
            if row.remove then
                Skins:HandleButton(row.remove)
            end
        end
    end

    if itemRefAddButton and Skins.HandleButton then
        Skins:HandleButton(itemRefAddButton)
    end

    if closeButton then
        closeButton:SetFrameLevel(configFrame:GetFrameLevel() + 10)
        closeButton:Show()
    end

    ResizeConfigFrame()
end

local function HandleUnitPopupClick(self)
    -- Handles right-click context menu action when user selects our entry
    if self.value ~= UNIT_POPUP_OPTION then
        return
    end

    local dropdown = UIDROPDOWNMENU_INIT_MENU
    if not dropdown then
        return
    end

    local name
    if dropdown.unit and UnitExists(dropdown.unit) then
        name = GetUnitName(dropdown.unit, true)
    else
        name = dropdown.name
        local server = dropdown.server
        if name and server and server ~= "" then
            name = name .. "-" .. server
        end
    end

    if not name or name == "" then
        return
    end

    local added, result = AddToWhitelist(name)
    if added then
        Print("Added " .. (result or "") .. " to whitelist.")
    else
        Print(result or "Unable to add name.")
    end
end

EnsureUnitPopupSetup = function()
    -- Injects an "Add to GroupLock Whitelist" choice into key unit menus
    if popupSetupDone then
        return
    end

    if not UnitPopupButtons or not UnitPopupMenus then
        return
    end

    if not UnitPopupButtons[UNIT_POPUP_OPTION] then
        UnitPopupButtons[UNIT_POPUP_OPTION] = { text = "Add to GroupLock Whitelist", dist = 0 }
    end

    local menus = {
        "PLAYER",
        "PARTY",
        "FRIEND",
        "FRIEND_OFFLINE",
        "RAID_PLAYER",
        "RAID",
        "FOCUS",
        "TARGET",
        "CHAT_ROSTER",
        "CHAT_ROSTER_PLAYER",
        "GUILD",
        "ARENAENEMY",
        "BATTLEGROUND_ENEMY",
    }

    for _, menu in ipairs(menus) do
        local list = UnitPopupMenus[menu]
        if list then
            local exists = false
            for _, value in ipairs(list) do
                if value == UNIT_POPUP_OPTION then
                    exists = true
                    break
                end
            end
            if not exists then
                local insertIndex = #list + 1
                for idx, value in ipairs(list) do
                    if value == "CANCEL" then
                        insertIndex = idx
                        break
                    end
                end
                table.insert(list, insertIndex, UNIT_POPUP_OPTION)
            end
        end
    end

    if not popupHooked then
        hooksecurefunc("UnitPopup_OnClick", HandleUnitPopupClick)
        popupHooked = true
    end

    popupSetupDone = true
end

EnsureItemRefButton = function()
    -- Creates (once) the "Whitelist" button shown when clicking player links
    if itemRefAddButton then
        return itemRefAddButton
    end

    if not ItemRefTooltip then
        return nil
    end

    itemRefAddButton = CreateFrame("Button", "GroupLockItemRefButton", ItemRefTooltip, "UIPanelButtonTemplate")
    itemRefAddButton:SetSize(160, 20)
    itemRefAddButton:SetPoint("TOPLEFT", ItemRefTooltip, "BOTTOMLEFT", 0, -4)
    itemRefAddButton:SetText("Whitelist Player")
    itemRefAddButton:SetFrameStrata("TOOLTIP")
    itemRefAddButton:Hide()
    itemRefAddButton:SetScript("OnClick", function(button)
        if not button.playerName then
            return
        end
        local added, result = AddToWhitelist(button.playerName)
        if added then
            Print("Added " .. (result or "") .. " to whitelist.")
        else
            Print(result or "Unable to add name.")
        end
    end)

    if not itemRefTooltipHooked then
        ItemRefTooltip:HookScript("OnHide", function()
            if itemRefAddButton then
                itemRefAddButton:Hide()
                itemRefAddButton.playerName = nil
            end
        end)
        ItemRefTooltip:HookScript("OnShow", function(self)
            if itemRefAddButton and itemRefAddButton:IsShown() then
                itemRefAddButton:ClearAllPoints()
                itemRefAddButton:SetPoint("TOPLEFT", self, "BOTTOMLEFT", 0, -4)
                itemRefAddButton:SetWidth(math.max(160, (self:GetWidth() or 0)))
            end
        end)
        itemRefTooltipHooked = true
    end

    return itemRefAddButton
end

hooksecurefunc("SetItemRef", function(link)
    -- Chat hyperlink handler so left-clicking names quickly whitelists them
    if type(link) ~= "string" then
        return
    end

    local linkType, details = link:match("^([^:]+):(.+)")
    if linkType ~= "player" then
        if itemRefAddButton then
            itemRefAddButton:Hide()
            itemRefAddButton.playerName = nil
        end
        return
    end

    local name = details and details:match("([^:]+)")
    if not name or name == "" then
        return
    end

    local button = EnsureItemRefButton()
    if not button then
        return
    end

    button.playerName = name
    local displayName = PrettyName(name)
    button:SetText("Whitelist " .. displayName)
    button:ClearAllPoints()
    button:SetPoint("TOPLEFT", ItemRefTooltip, "BOTTOMLEFT", 0, -4)
    button:SetWidth(math.max(160, (ItemRefTooltip:GetWidth() or 0)))
    button:Show()

    if type(ElvUI) == "table" then
        ApplyElvUISkin()
    end
end)

CreateConfigFrame = function()
    -- Builds the addon configuration window, wiring all interactive controls
    if configFrame then
        RefreshOptionStates()
        return
    end

    configFrame = CreateFrame("Frame", "GroupLockConfigFrame", UIParent, "PortraitFrameTemplate")
    configFrame:SetSize(460, 440)
    configFrame:SetPoint("CENTER")
    configFrame:Hide()

    configFrame:SetMovable(true)
    configFrame:EnableMouse(true)
    configFrame:RegisterForDrag("LeftButton")
    configFrame:SetScript("OnDragStart", configFrame.StartMoving)
    configFrame:SetScript("OnDragStop", configFrame.StopMovingOrSizing)
    configFrame:SetToplevel(true)
    configFrame:SetClampedToScreen(true)

    configFrame.TitleText:SetText("Group Lock")

    if not closeButton then
        closeButton = CreateFrame("Button", "GroupLockConfigFrameCloseButton", configFrame, "UIPanelCloseButton")
        closeButton:SetScript("OnClick", function()
            PlaySound("igMainMenuClose")
            configFrame:Hide()
        end)
    else
        closeButton:SetParent(configFrame)
    end
    closeButton:ClearAllPoints()
    closeButton:SetPoint("TOPRIGHT", configFrame, "TOPRIGHT", -6, -4)
    closeButton:SetFrameLevel(configFrame:GetFrameLevel() + 10)
    closeButton:SetFrameStrata("MEDIUM")
    closeButton:SetHitRectInsets(4, 4, 4, 4)
    closeButton:Show()

    if configFrame.portrait then
        SetPortraitTexture(configFrame.portrait, "player")
    end

    descriptionText = configFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    descriptionText:SetPoint("TOPLEFT", 70, -40)
    descriptionText:SetPoint("RIGHT", -30, 0)
    descriptionText:SetJustifyH("LEFT")
    descriptionText:SetText("Automatically decline party invites unless the inviter is on your whitelist, in your friends list, or in your guild according to the options below.")

    friendsCheckbox = CreateFrame("CheckButton", "$parentAllowFriendsCheck", configFrame, "UICheckButtonTemplate")
    friendsCheckbox:SetPoint("TOPLEFT", descriptionText, "BOTTOMLEFT", -5, -20)
    friendsCheckbox.text = friendsCheckbox.text or friendsCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    friendsCheckbox.text:SetPoint("LEFT", friendsCheckbox, "RIGHT", 4, 1)
    friendsCheckbox.text:SetText("Allow invites from friends")
    friendsCheckbox:SetScript("OnClick", function(self)
        db.allowFriends = self:GetChecked()
        CommitProfile()
        if db.allowFriends then
            ShowFriends()
            UpdateFriendCache()
        end
    end)

    guildCheckbox = CreateFrame("CheckButton", "$parentAllowGuildCheck", configFrame, "UICheckButtonTemplate")
    guildCheckbox:SetPoint("TOPLEFT", friendsCheckbox, "BOTTOMLEFT", 0, -10)
    guildCheckbox.text = guildCheckbox.text or guildCheckbox:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    guildCheckbox.text:SetPoint("LEFT", guildCheckbox, "RIGHT", 4, 1)
    guildCheckbox.text:SetText("Allow invites from guild members")
    guildCheckbox:SetScript("OnClick", function(self)
        db.allowGuild = self:GetChecked()
        CommitProfile()
        if db.allowGuild then
            GuildRoster()
            UpdateGuildCache()
        end
    end)

    local whitelistLabel = configFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    whitelistLabel:SetPoint("TOPLEFT", guildCheckbox, "BOTTOMLEFT", 0, -24)
    whitelistLabel:SetText("Whitelist")

    whitelistBackground = CreateFrame("Frame", nil, configFrame)
    whitelistBackground:SetPoint("TOPLEFT", whitelistLabel, "BOTTOMLEFT", -4, -8)
    whitelistBackground:SetSize(280, 170)

    whitelistBackground:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    whitelistBackground:SetBackdropColor(0, 0, 0, 0.8)
    whitelistBackground:SetBackdropBorderColor(0.2, 0.2, 0.2, 1)

    whitelistScrollFrame = CreateFrame("ScrollFrame", "$parentWhitelistScroll", whitelistBackground, "UIPanelScrollFrameTemplate")
    whitelistScrollFrame:SetPoint("TOPLEFT", 6, -6)
    whitelistScrollFrame:SetPoint("BOTTOMRIGHT", -28, 6)

    whitelistScrollChild = CreateFrame("Frame", nil, whitelistScrollFrame)
    whitelistScrollChild:SetSize(whitelistScrollFrame:GetWidth() or 1, WHITELIST_ROW_HEIGHT)
    whitelistScrollFrame:SetScrollChild(whitelistScrollChild)

    whitelistEmptyText = whitelistScrollChild:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    whitelistEmptyText:SetPoint("TOPLEFT", 4, -4)
    whitelistEmptyText:SetJustifyH("LEFT")
    whitelistEmptyText:SetText("|cff888888None|r")

    whitelistScrollFrame:HookScript("OnSizeChanged", function(_, width)
        if whitelistScrollChild then
            whitelistScrollChild:SetWidth(width or 1)
        end
        UpdateWhitelistDisplay()
    end)

    whitelistInput = CreateFrame("EditBox", "$parentWhitelistInput", configFrame, "InputBoxTemplate")
    whitelistInput:SetSize(200, 24)
    whitelistInput:SetPoint("TOPLEFT", whitelistBackground, "BOTTOMLEFT", 4, -18)
    whitelistInput:SetAutoFocus(false)
    whitelistInput:SetMaxLetters(48)
    whitelistInput:SetScript("OnEscapePressed", function(self)
        self:ClearFocus()
    end)

    whitelistInput:SetScript("OnEnterPressed", function(self)
        local text = self:GetText()
        local added, response = AddToWhitelist(text)
        if added then
            Print("Added " .. (response or PrettyName(strtrim(text or ""))) .. " to whitelist.")
            self:SetText("")
        else
            Print(response or "Unable to add name. Please check the spelling.")
        end
        self:ClearFocus()
    end)

    addWhitelistButton = CreateFrame("Button", "$parentAddButton", configFrame, "UIPanelButtonTemplate")
    addWhitelistButton:SetSize(80, 24)
    addWhitelistButton:SetPoint("LEFT", whitelistInput, "RIGHT", 6, 0)
    addWhitelistButton:SetText("Add")
    addWhitelistButton:SetScript("OnClick", function()
        local name = whitelistInput:GetText()
        local added, response = AddToWhitelist(name)
        if added then
            Print("Added " .. (response or PrettyName(strtrim(name or ""))) .. " to whitelist.")
            whitelistInput:SetText("")
        else
            Print(response or "Unable to add name.")
        end
    end)

    instructionsText = configFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    instructionsText:SetPoint("TOPLEFT", whitelistInput, "BOTTOMLEFT", 0, -8)
    instructionsText:SetPoint("RIGHT", -30, 0)
    instructionsText:SetJustifyH("LEFT")
    instructionsText:SetText("Type a player name (without realm) and press Add to whitelist. Click the X next to a name to remove it.")

    RefreshOptionStates()
    configFrame:HookScript("OnShow", function()
        if closeButton then
            closeButton:SetFrameLevel(configFrame:GetFrameLevel() + 10)
            closeButton:SetFrameStrata("MEDIUM")
            closeButton:Show()
        end
        ResizeConfigFrame()
        ApplyElvUISkin()
        RefreshOptionStates()
    end)
    ApplyElvUISkin()
    RefreshOptionStates()
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    -- Primary event dispatcher for addon loading, rosters, and invites
    if event == "ADDON_LOADED" then
        local loadedAddon = ...
        if loadedAddon == addonName then
            if type(GroupLockDB) ~= "table" then
                GroupLockDB = {}
            end

            db = GroupLockDB
        CopyDefaults(DEFAULTS, db)

        if type(db.whitelist) ~= "table" then
            db.whitelist = {}
        end
        CommitProfile()

            CreateConfigFrame()

            SLASH_GROUPLOCK1 = "/glock"
            SlashCmdList.GROUPLOCK = function()
                ToggleConfigFrame()
            end

            self:RegisterEvent("PLAYER_LOGIN")
            self:RegisterEvent("FRIENDLIST_UPDATE")
            self:RegisterEvent("GUILD_ROSTER_UPDATE")
            self:RegisterEvent("PLAYER_GUILD_UPDATE")
            self:RegisterEvent("PARTY_INVITE_REQUEST")
            self:RegisterEvent("PLAYER_LOGOUT")
            EnsureUnitPopupSetup()
        elseif loadedAddon == "ElvUI" then
            ApplyElvUISkin()
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        ShowFriends()
        UpdateFriendCache()

        if IsInGuild() then
            GuildRoster()
        end
        UpdateGuildCache()

        RefreshOptionStates()
        EnsureUnitPopupSetup()
        ApplyElvUISkin()

    elseif event == "FRIENDLIST_UPDATE" then
        UpdateFriendCache()

    elseif event == "GUILD_ROSTER_UPDATE" then
        UpdateGuildCache()

    elseif event == "PLAYER_GUILD_UPDATE" then
        GuildRoster()

    elseif event == "PARTY_INVITE_REQUEST" then
        local inviterName = ...

        if ShouldDecline(inviterName) then
            DeclineGroup()
            StaticPopup_Hide("PARTY_INVITE")
            Print("Declined invite from " .. inviterName .. ".")
        end
    elseif event == "PLAYER_LOGOUT" then
        -- Persist any pending profile changes before logout
        CommitProfile()
    end
end)

eventFrame:RegisterEvent("ADDON_LOADED")
