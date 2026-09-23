local ADDON_NAME = ...
local PREFIX, PROTOCOL = "CCWF3", 3
local CHUNK_SIZE, MAX_CHUNKS, MAX_PAYLOAD = 180, 160, 28000
local CC = CreateFrame("Frame")
local DB, REMOTE
local incoming, sendQueue, pendingRequests = {}, {}, {}
local nextSendAt = 0

local function Print(msg) print("|cff33ff99CraftCircle WF:|r " .. tostring(msg)) end
local function PlayerKey()
    local name, realm = UnitFullName("player")
    realm = realm or GetRealmName() or "UnknownRealm"
    return (name or "Unknown") .. "-" .. realm:gsub("%s+", "")
end
local function InitDB()
    CraftCircleWFDB = CraftCircleWFDB or {schema=3, client="WF-12.1.5", characters={}, sync={}}
    CraftCircleWFRemoteDB = CraftCircleWFRemoteDB or {schema=3, characters={}}
    CraftCircleWFDB.characters = CraftCircleWFDB.characters or {}
    CraftCircleWFDB.sync = CraftCircleWFDB.sync or {}
    CraftCircleWFRemoteDB.characters = CraftCircleWFRemoteDB.characters or {}
    DB, REMOTE = CraftCircleWFDB, CraftCircleWFRemoteDB
end

local function Esc(v)
    return tostring(v or ""):gsub("%%","%%25"):gsub("|","%%7C"):gsub("\n","%%0A"):gsub("\r","%%0D")
end
local function Unesc(v)
    return (v or ""):gsub("%%0D","\r"):gsub("%%0A","\n"):gsub("%%7C","|"):gsub("%%25","%%")
end
local function Split(s, sep)
    local out, p = {}, 1
    while true do
        local a,b = s:find(sep, p, true)
        if not a then out[#out+1]=s:sub(p); break end
        out[#out+1]=s:sub(p,a-1); p=b+1
    end
    return out
end
local function Hash(s)
    local h = 5381
    for i=1,#s do h = (h * 33 + s:byte(i)) % 4294967296 end
    return string.format("%08x", h)
end

-- Canonical, compact wire format. Reagents remain local to keep guild traffic low.
local function SerializeCharacter(key, c)
    local lines = {table.concat({"C",Esc(key),Esc(c.name),Esc(c.realm),Esc(c.class),tonumber(c.revision) or 0,tonumber(c.updated) or 0},"|")}
    local profNames = {}
    for name in pairs(c.professions or {}) do profNames[#profNames+1]=name end
    table.sort(profNames)
    for _,name in ipairs(profNames) do
        local p=c.professions[name]
        lines[#lines+1]=table.concat({"P",Esc(name),p.professionID or 0,p.skill or 0,p.maxSkill or 0,p.updated or 0},"|")
        local recipes={}
        for _,r in ipairs(p.recipes or {}) do recipes[#recipes+1]=r end
        table.sort(recipes,function(a,b) return (a.recipeID or 0)<(b.recipeID or 0) end)
        for _,r in ipairs(recipes) do
            lines[#lines+1]=table.concat({"R",r.recipeID or 0,r.itemID or 0,Esc(r.name)},"|")
        end
        local cds={}
        for _,cd in ipairs(p.cooldowns or {}) do cds[#cds+1]=cd end
        table.sort(cds,function(a,b) return (a.recipeID or 0)<(b.recipeID or 0) end)
        for _,cd in ipairs(cds) do
            lines[#lines+1]=table.concat({"D",cd.recipeID or 0,cd.readyAt or 0,cd.observedAt or 0,Esc(cd.name)},"|")
        end
    end
    return table.concat(lines,"\n")
end

local function DeserializeCharacter(payload)
    if type(payload)~="string" or #payload>MAX_PAYLOAD then return nil,"invalid size" end
    local c,key,current={professions={}}
    local recipeCount=0
    for line in payload:gmatch("[^\n]+") do
        local f=Split(line,"|")
        if f[1]=="C" then
            key=Unesc(f[2]); c.name=Unesc(f[3]); c.realm=Unesc(f[4]); c.class=Unesc(f[5])
            c.revision=tonumber(f[6]) or 0; c.updated=tonumber(f[7]) or 0
            if key=="" or #key>100 then return nil,"invalid owner" end
        elseif f[1]=="P" and key then
            local name=Unesc(f[2]); if name=="" or #name>100 then return nil,"invalid profession" end
            current={professionID=tonumber(f[3]) or 0,skill=tonumber(f[4]) or 0,maxSkill=tonumber(f[5]) or 0,updated=tonumber(f[6]) or 0,recipes={},cooldowns={}}
            c.professions[name]=current
        elseif f[1]=="R" and current then
            recipeCount=recipeCount+1; if recipeCount>5000 then return nil,"too many recipes" end
            current.recipes[#current.recipes+1]={recipeID=tonumber(f[2]) or 0,itemID=tonumber(f[3]) or nil,name=Unesc(f[4])}
        elseif f[1]=="D" and current then
            current.cooldowns[#current.cooldowns+1]={recipeID=tonumber(f[2]) or 0,readyAt=tonumber(f[3]) or 0,observedAt=tonumber(f[4]) or 0,name=Unesc(f[5])}
        else return nil,"invalid record" end
    end
    if not key then return nil,"missing header" end
    return key,c
end

local function CharacterPayload(key)
    local c=(DB.characters or {})[key] or (REMOTE.characters or {})[key]
    if not c then return nil end
    local payload=SerializeCharacter(key,c)
    return payload,Hash(payload),c.revision or 0
end
local function Queue(msg, channel, target)
    if #msg>240 then return end
    sendQueue[#sendQueue+1]={msg=msg,channel=channel or "GUILD",target=target}
end
local function PumpQueue()
    if #sendQueue==0 or GetTime()<nextSendAt then return end
    local x=table.remove(sendQueue,1)
    C_ChatInfo.SendAddonMessage(PREFIX,x.msg,x.channel,x.target)
    nextSendAt=GetTime()+0.12
end
local function Announce(key)
    if not IsInGuild() then return end
    local payload,hash,revision=CharacterPayload(key)
    if payload then Queue(table.concat({"H",PROTOCOL,Esc(key),revision,hash,#payload},"|"),"GUILD") end
end
local function AnnounceAll()
    if not IsInGuild() then return end
    for key in pairs(DB.characters or {}) do Announce(key) end
    for key in pairs(REMOTE.characters or {}) do if not DB.characters[key] then Announce(key) end end
end
local function Request(key,revision,hash)
    local token=key..":"..hash
    if pendingRequests[token] and GetTime()-pendingRequests[token]<10 then return end
    pendingRequests[token]=GetTime()
    Queue(table.concat({"Q",PROTOCOL,Esc(key),revision,hash},"|"),"GUILD")
end
local function SendRecord(key,wantedHash)
    local payload,hash,revision=CharacterPayload(key)
    if not payload or hash~=wantedHash or #payload>MAX_PAYLOAD then return end
    local total=math.ceil(#payload/CHUNK_SIZE)
    if total<1 or total>MAX_CHUNKS then return end
    local transfer=Hash(key..hash..GetTime()..PlayerKey()):sub(1,8)
    Queue(table.concat({"B",transfer,Esc(key),revision,hash,total,#payload},"|"),"GUILD")
    for i=1,total do
        local chunk=payload:sub((i-1)*CHUNK_SIZE,i*CHUNK_SIZE)
        Queue(table.concat({"X",transfer,i,total,chunk},"|"),"GUILD")
    end
    Queue("E|"..transfer,"GUILD")
end

local function GetRecipeIDs()
    if not C_TradeSkillUI then return nil,"C_TradeSkillUI unavailable" end
    if C_TradeSkillUI.GetAllRecipeIDs then return C_TradeSkillUI.GetAllRecipeIDs() end
    if C_TradeSkillUI.GetFilteredRecipeIDs then return C_TradeSkillUI.GetFilteredRecipeIDs() end
    return nil,"No supported recipe-list function"
end
local function CurrentProfession()
    local info
    if C_TradeSkillUI and C_TradeSkillUI.GetBaseProfessionInfo then local ok,v=pcall(C_TradeSkillUI.GetBaseProfessionInfo); if ok then info=v end end
    if type(info)=="table" then return info.professionName or info.name or "Profession",info.skillLevel or 0,info.maxSkillLevel or 0,info.professionID end
    return (C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName and C_TradeSkillUI.GetTradeSkillDisplayName()) or "Profession",0,0,nil
end
local function Scan()
    InitDB(); local ids,err=GetRecipeIDs(); if not ids then Print(err); return end
    local professionName,skill,maxSkill,professionID=CurrentProfession(); local recipes={}
    -- Enchants apply directly to gear and have no craftable "item" of their own; the
    -- output data some clients return for them is not a real, displayable item, so we
    -- never attach an itemID for this profession and just show the recipe name.
    local isEnchant = (professionName or ""):lower():find("enchant",1,true) ~= nil
    for _,recipeID in ipairs(ids) do
        local ok,info=pcall(C_TradeSkillUI.GetRecipeInfo,recipeID)
        if ok and type(info)=="table" and info.learned then
            local itemID
            if not isEnchant and C_TradeSkillUI.GetRecipeOutputItemData then
                local ok2,d=pcall(C_TradeSkillUI.GetRecipeOutputItemData,recipeID,nil)
                -- Validate against the client's local item DB before trusting it -- a
                -- bogus/non-item ID here would otherwise show the wrong icon/tooltip.
                if ok2 and type(d)=="table" and d.itemID and d.itemID>0 and C_Item.GetItemInfoInstant(d.itemID) then
                    itemID=d.itemID
                end
            end
            recipes[#recipes+1]={recipeID=recipeID,itemID=itemID,name=info.name or tostring(recipeID)}
        end
    end
    table.sort(recipes,function(a,b) return (a.recipeID or 0)<(b.recipeID or 0) end)
    local key=PlayerKey(); local c=DB.characters[key] or {professions={}}
    c.professions=c.professions or {}; local old=c.professions[professionName]
    local candidate={professionID=professionID,skill=skill,maxSkill=maxSkill,updated=time(),recipes=recipes,cooldowns=(old and old.cooldowns) or {}}
    c.name=UnitName("player"); c.realm=GetRealmName(); c.class=select(2,UnitClass("player")); c.updated=time(); c.professions[professionName]=candidate
    local before=c.hash
    c.revision=(c.revision or 0)+1; c.hash=nil
    local payload=SerializeCharacter(key,c); c.hash=Hash(payload); DB.characters[key]=c
    Print(string.format("saved %d learned recipes from %s.",#recipes,professionName))
    if c.hash~=before then C_Timer.After(0.5,function() Announce(key) end) end
    if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end
end

local function HandleAddon(message,sender)
    local f=Split(message,"|"); local kind=f[1]
    if kind=="H" and tonumber(f[2])==PROTOCOL then
        local key,revision,hash,size=Unesc(f[3]),tonumber(f[4]) or 0,f[5],tonumber(f[6]) or 0
        if size>MAX_PAYLOAD or key==PlayerKey() then return end
        local payload,localHash,localRev=CharacterPayload(key)
        if not payload or localHash~=hash or localRev<revision then
            C_Timer.After((Hash(PlayerKey()..key..hash):byte(1)%20)/10,function() Request(key,revision,hash) end)
        end
    elseif kind=="Q" and tonumber(f[2])==PROTOCOL then
        local key,revision,hash=Unesc(f[3]),tonumber(f[4]) or 0,f[5]
        local _,localHash,localRev=CharacterPayload(key)
        if localHash==hash and localRev>=revision then
            C_Timer.After((Hash(PlayerKey()..key):byte(1)%15)/10,function() SendRecord(key,hash) end)
        end
    elseif kind=="B" then
        local id,key,revision,hash,total,size=f[2],Unesc(f[3]),tonumber(f[4]) or 0,f[5],tonumber(f[6]) or 0,tonumber(f[7]) or 0
        if #id<=12 and total>0 and total<=MAX_CHUNKS and size<=MAX_PAYLOAD then incoming[id]={key=key,revision=revision,hash=hash,total=total,size=size,chunks={},sender=sender,started=GetTime()} end
    elseif kind=="X" then
        local id,n,total=f[2],tonumber(f[3]),tonumber(f[4]); local t=incoming[id]
        if t and sender==t.sender and total==t.total and n and n>=1 and n<=total and not t.chunks[n] then t.chunks[n]=f[5] or "" end
    elseif kind=="E" then
        local t=incoming[f[2]]; if not t or sender~=t.sender then return end
        local parts={}; for i=1,t.total do if not t.chunks[i] then incoming[f[2]]=nil; return end parts[i]=t.chunks[i] end
        local payload=table.concat(parts); incoming[f[2]]=nil
        if #payload~=t.size or Hash(payload)~=t.hash then return end
        local key,c=DeserializeCharacter(payload); if not key or key~=t.key then return end
        local _,oldHash,oldRev=CharacterPayload(key)
        if (c.revision or 0)>=(oldRev or 0) and oldHash~=t.hash then
            c.hash=t.hash; c.syncSource=sender; c.receivedAt=time(); REMOTE.characters[key]=c
            if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end
        end
    end
end

local function MergedCharacters()
    local merged={}; for k,v in pairs(REMOTE.characters or {}) do merged[k]=v end; for k,v in pairs(DB.characters or {}) do merged[k]=v end; return merged
end
local function Age(ts) if not ts then return "unknown" end local s=math.max(0,time()-ts); if s<3600 then return math.floor(s/60).."m" elseif s<86400 then return math.floor(s/3600).."h" else return math.floor(s/86400).."d" end end

-- ===== Frames: window chrome, controls row, category pane (left), results pane (right) =====
local window=CreateFrame("Frame","CraftCircleWFWindow",UIParent,"BasicFrameTemplateWithInset")
window:SetSize(940,560); window:SetPoint("CENTER"); window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton"); window:SetScript("OnDragStart",window.StartMoving); window:SetScript("OnDragStop",window.StopMovingOrSizing); window:Hide(); window.TitleText:SetText("CraftCircle WF")
local search=CreateFrame("EditBox",nil,window,"InputBoxTemplate"); search:SetSize(310,26); search:SetPoint("TOPLEFT",18,-38); search:SetAutoFocus(false)
local scan=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); scan:SetSize(145,24); scan:SetPoint("TOPRIGHT",-18,-38); scan:SetText("Scan profession"); scan:SetScript("OnClick",Scan)

-- Level requirement filter + sort mode
local lvlLabel=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); lvlLabel:SetPoint("TOPLEFT",18,-76); lvlLabel:SetText("Level req:")
local minLvlBox=CreateFrame("EditBox",nil,window,"InputBoxTemplate"); minLvlBox:SetSize(40,20); minLvlBox:SetPoint("TOPLEFT",92,-74); minLvlBox:SetAutoFocus(false); minLvlBox:SetNumeric(true); minLvlBox:SetMaxLetters(3)
local dashLabel=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); dashLabel:SetPoint("TOPLEFT",136,-76); dashLabel:SetText("-")
local maxLvlBox=CreateFrame("EditBox",nil,window,"InputBoxTemplate"); maxLvlBox:SetSize(40,20); maxLvlBox:SetPoint("TOPLEFT",148,-74); maxLvlBox:SetAutoFocus(false); maxLvlBox:SetNumeric(true); maxLvlBox:SetMaxLetters(3)
local sortOrder={"name","level_asc","level_desc"}
local sortLabels={name="Sort: Name",level_asc="Sort: Level (low>high)",level_desc="Sort: Level (high>low)"}
local sortMode="name"
local sortButton=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); sortButton:SetSize(190,22); sortButton:SetPoint("TOPLEFT",200,-74); sortButton:SetText(sortLabels[sortMode])

-- UI scale slider (50%-200%), draws its own labels rather than relying on
-- template sub-regions that may not exist under this exact name on every client.
local scaleTitleText=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); scaleTitleText:SetPoint("TOPRIGHT",-18,-70); scaleTitleText:SetText("UI Scale: 100%")
local scaleSlider=CreateFrame("Slider",nil,window,"OptionsSliderTemplate"); scaleSlider:SetPoint("TOPRIGHT",-18,-92); scaleSlider:SetSize(160,16)
scaleSlider:SetMinMaxValues(0.5,2.0); scaleSlider:SetValueStep(0.05)
if scaleSlider.SetObeyStepOnDrag then scaleSlider:SetObeyStepOnDrag(true) end
for _,region in ipairs({scaleSlider:GetRegions()}) do if region.GetObjectType and region:GetObjectType()=="FontString" then region:SetText("") end end

local catLabel=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); catLabel:SetPoint("TOPLEFT",18,-118); catLabel:SetText("Categories")
local status=window:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); status:SetPoint("TOPLEFT",254,-118); status:SetPoint("RIGHT",-18,0)
local divider=window:CreateTexture(nil,"ARTWORK"); divider:SetColorTexture(1,1,1,0.15); divider:SetPoint("TOPLEFT",240,-136); divider:SetPoint("BOTTOMLEFT",240,15); divider:SetWidth(1)
local categoryScroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate"); categoryScroll:SetPoint("TOPLEFT",14,-138); categoryScroll:SetPoint("BOTTOMLEFT",14,15); categoryScroll:SetWidth(220)
local categoryContent=CreateFrame("Frame",nil,categoryScroll); categoryContent:SetSize(210,1); categoryScroll:SetScrollChild(categoryContent)
local scroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",248,-138); scroll:SetPoint("BOTTOMRIGHT",-32,15)
local content=CreateFrame("Frame",nil,scroll); content:SetSize(636,1); scroll:SetScrollChild(content); local rows={}

scaleSlider:SetScript("OnValueChanged",function(self,value)
    value=math.floor(value*20+0.5)/20
    window:SetScale(value)
    scaleTitleText:SetText(string.format("UI Scale: %d%%",math.floor(value*100+0.5)))
    if DB then DB.uiScale=value end
end)
scaleSlider:SetValue(1.0)

-- ===== Compat + item helpers =====
-- Some clients don't expose the global GetItemInfo (this is what caused the
-- "attempt to call a nil value" error) -- fall back to C_Item.GetItemInfo.
local function GetItemInfoCompat(itemID)
    if type(GetItemInfo)=="function" then return GetItemInfo(itemID) end
    if C_Item and type(C_Item.GetItemInfo)=="function" then return C_Item.GetItemInfo(itemID) end
end
local function DisplayName(key) return key:match("^[^-]+") or key end

local requestedItems = {}
-- Returns a real, clickable item link when the item's data is cached locally;
-- otherwise falls back to the plain recipe name and quietly requests the data
-- so a later attempt (or hover) will have a link ready.
local function ItemLinkOrName(itemID, name)
    if itemID and itemID > 0 then
        local link = select(2, GetItemInfoCompat(itemID))
        if link then return link end
        if not requestedItems[itemID] then
            requestedItems[itemID] = true
            C_Item.RequestLoadItemDataByID(itemID)
        end
    end
    return name
end
local function Whisper(crafter,recipe,itemID)
    local target = crafter:match("^[^-]+") or crafter
    local linkOrName = ItemLinkOrName(itemID, recipe)
    ChatFrame_OpenChat("/w "..target.." Could you craft "..linkOrName.." for me? I can bring the materials. ")
end

-- Level ("Requires Level") cache -- populated asynchronously per item, then
-- triggers a single debounced refresh so sort/filter pick it up.
local itemLevelCache, levelRequested = {}, {}
local levelRefreshPending = false
local function ScheduleLevelRefresh()
    if levelRefreshPending then return end
    levelRefreshPending = true
    C_Timer.After(0.3, function() levelRefreshPending=false; if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end end)
end
local function EnsureLevelCached(itemID)
    if not itemID or itemID<=0 or itemLevelCache[itemID] or levelRequested[itemID] then return end
    levelRequested[itemID] = true
    local item = Item:CreateFromItemID(itemID)
    item:ContinueOnItemLoad(function()
        local minLevel = select(5, GetItemInfoCompat(itemID))
        itemLevelCache[itemID] = minLevel or 0
        ScheduleLevelRefresh()
    end)
end
local function FilterLevelOK(itemID)
    local minFilter,maxFilter = tonumber(minLvlBox:GetText()), tonumber(maxLvlBox:GetText())
    if not minFilter and not maxFilter then return true end
    if not itemID or itemID<=0 then return false end
    local lvl = itemLevelCache[itemID]
    if not lvl then return false end -- not loaded yet; reappears once cached (see ScheduleLevelRefresh)
    if minFilter and lvl<minFilter then return false end
    if maxFilter and lvl>maxFilter then return false end
    return true
end
minLvlBox:SetScript("OnTextChanged",function() if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end end)
maxLvlBox:SetScript("OnTextChanged",function() if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end end)
minLvlBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
maxLvlBox:SetScript("OnEnterPressed",function(self) self:ClearFocus() end)
sortButton:SetScript("OnClick",function()
    local idx=1; for k,v in ipairs(sortOrder) do if v==sortMode then idx=k end end
    sortMode=sortOrder[(idx % #sortOrder)+1]
    sortButton:SetText(sortLabels[sortMode])
    if CraftCircleWF_Refresh then CraftCircleWF_Refresh() end
end)
local function SortResults(results)
    if sortMode=="level_asc" or sortMode=="level_desc" then
        local desc = sortMode=="level_desc"
        table.sort(results,function(a,b)
            local la=a.r.itemID and itemLevelCache[a.r.itemID]
            local lb=b.r.itemID and itemLevelCache[b.r.itemID]
            la = la or (desc and -1 or math.huge)
            lb = lb or (desc and -1 or math.huge)
            if la~=lb then if desc then return la>lb else return la<lb end end
            return (a.r.name or "")<(b.r.name or "")
        end)
    else
        table.sort(results,function(a,b) if a.r.name==b.r.name then return a.key<b.key end return (a.r.name or "")<(b.r.name or "") end)
    end
end

-- ===== Category tree: Weapon/Armor/etc, split further by weapon type or
-- armor material + slot (e.g. Armor > Cloth · Wrist). Recipes with no real
-- item (enchants) fall under Other > <profession>. =====
local categoryIcons = {
    Armor="Interface\\Icons\\INV_Chest_Cloth_01", Weapon="Interface\\Icons\\INV_Sword_04",
    Consumable="Interface\\Icons\\INV_Potion_54", ["Trade Goods"]="Interface\\Icons\\INV_Fabric_Linen_01",
    Recipe="Interface\\Icons\\INV_Scroll_03", Gem="Interface\\Icons\\INV_Misc_Gem_01",
    Container="Interface\\Icons\\INV_Misc_Bag_08", Quest="Interface\\Icons\\INV_Misc_Note_01",
    Miscellaneous="Interface\\Icons\\INV_Misc_QuestionMark", Other="Interface\\Icons\\INV_Misc_QuestionMark",
}
local function CategoryIcon(cat) return categoryIcons[cat] or "Interface\\Icons\\INV_Misc_QuestionMark" end
local currentCategory, currentSub = nil, nil
local treeExpanded, catRows = {}, {}
local function CategoryFor(itemID, professionName)
    if itemID and itemID > 0 then
        local _,itemType,itemSubType,_,equipLoc = C_Item.GetItemInfoInstant(itemID)
        if itemType then
            if itemType=="Armor" and equipLoc and equipLoc~="" then
                local slotLabel = _G[equipLoc]
                local sub = itemSubType or "Armor"
                if slotLabel and slotLabel~="" then sub = sub.." · "..slotLabel end
                return "Armor", sub
            end
            return itemType, itemSubType or "General"
        end
    end
    return "Other", professionName or "Unknown"
end
local function BuildCategoryTree()
    local tree={}
    for _,c in pairs(MergedCharacters()) do
        for pn,p in pairs(c.professions or {}) do
            for _,r in ipairs(p.recipes or {}) do
                local cat,sub=CategoryFor(r.itemID,pn)
                local node=tree[cat]; if not node then node={count=0,subs={}}; tree[cat]=node end
                node.count=node.count+1; node.subs[sub]=(node.subs[sub] or 0)+1
            end
        end
    end
    return tree
end
local function GetOrMakeCatRow(i)
    local row=catRows[i]
    if not row then
        row=CreateFrame("Button",nil,categoryContent); row:SetSize(206,20)
        row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(16,16); row.icon:SetPoint("LEFT",2,0)
        row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.text:SetPoint("LEFT",22,0); row.text:SetPoint("RIGHT",-4,0); row.text:SetJustifyH("LEFT")
        row.bg=row:CreateTexture(nil,"BACKGROUND"); row.bg:SetAllPoints(); row.bg:SetColorTexture(1,1,1,0.08); row.bg:Hide()
        catRows[i]=row
    end
    return row
end
local function RenderCategoryTree()
    local tree=BuildCategoryTree(); local catNames={}
    for cat in pairs(tree) do catNames[#catNames+1]=cat end
    table.sort(catNames)
    for _,r in ipairs(catRows) do r:Hide() end
    local i=1
    local allRow=GetOrMakeCatRow(i); allRow:ClearAllPoints(); allRow:SetPoint("TOPLEFT",2,-((i-1)*21))
    local allSelected=currentCategory==nil
    allRow.icon:Hide()
    allRow.text:SetText(allSelected and "|cffffd200All categories|r" or "All categories")
    allRow.bg:SetShown(allSelected)
    allRow:SetScript("OnClick",function() currentCategory=nil; currentSub=nil; CraftCircleWF_Refresh() end)
    allRow:Show()
    for _,cat in ipairs(catNames) do
        local node=tree[cat]; i=i+1
        local row=GetOrMakeCatRow(i); row:ClearAllPoints(); row:SetPoint("TOPLEFT",2,-((i-1)*21))
        local isSelected=currentCategory==cat and currentSub==nil
        -- Plain ASCII expand marker -- the earlier unicode triangle glyphs
        -- render as blank boxes on the game's default fonts.
        local label=string.format("[%s] %s (%d)",(treeExpanded[cat] and "-" or "+"),cat,node.count)
        row.icon:Show(); row.icon:SetTexture(CategoryIcon(cat))
        row.text:SetText(isSelected and ("|cffffd200"..label.."|r") or label)
        row.bg:SetShown(isSelected)
        row:SetScript("OnClick",function() treeExpanded[cat]=not treeExpanded[cat]; currentCategory=cat; currentSub=nil; CraftCircleWF_Refresh() end)
        row:Show()
        if treeExpanded[cat] then
            local subNames={}; for sub in pairs(node.subs) do subNames[#subNames+1]=sub end; table.sort(subNames)
            for _,sub in ipairs(subNames) do
                i=i+1
                local subRow=GetOrMakeCatRow(i); subRow:ClearAllPoints(); subRow:SetPoint("TOPLEFT",2,-((i-1)*21))
                local subSelected=currentCategory==cat and currentSub==sub
                subRow.icon:Hide()
                local subLabel=string.format("      %s (%d)",sub,node.subs[sub])
                subRow.text:SetText(subSelected and ("|cffffd200"..subLabel.."|r") or subLabel)
                subRow.bg:SetShown(subSelected)
                subRow:SetScript("OnClick",function() currentCategory=cat; currentSub=sub; CraftCircleWF_Refresh() end)
                subRow:Show()
            end
        end
    end
    categoryContent:SetHeight(math.max(1,i*21))
end

-- ===== Result rows: icon, quality-colored + level-tagged name, hover tooltip =====
local function RowText(x,qualityHex)
    local displayName = qualityHex and (qualityHex..x.r.name.."|r") or x.r.name
    local minLevel = x.r.itemID and itemLevelCache[x.r.itemID]
    local levelBadge = (minLevel and minLevel>0) and ("  |cffffcc00Req. Lvl "..minLevel.."|r") or ""
    return string.format("%s%s  |cff999999%s · %s · %s ago|r",displayName,levelBadge,DisplayName(x.key),x.pn,Age(x.p.updated))
end
local function QualityHex(quality)
    if not quality then return nil end
    if C_Item and C_Item.GetItemQualityColor then
        local ok,info=pcall(C_Item.GetItemQualityColor,quality)
        if ok and type(info)=="table" and info.hex then return info.hex end
    end
    if ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then return ITEM_QUALITY_COLORS[quality].hex end
    return nil
end
-- Sets a row's icon/text immediately from cache, and swaps in the real icon
-- plus quality-colored name once the async item load completes. Guarded
-- against the row having been recycled for a different entry meanwhile.
local function SetRowItem(row,x)
    local itemID=x.r.itemID
    row.itemID=itemID
    row.text:SetText(RowText(x,nil))
    if itemID and itemID>0 then
        row.icon:Show()
        row.icon:SetTexture(C_Item.GetItemIconByID(itemID) or 134400)
        local item=Item:CreateFromItemID(itemID)
        item:ContinueOnItemLoad(function()
            if row.itemID~=itemID then return end
            row.icon:SetTexture(item:GetItemIcon())
            local hex=QualityHex(item:GetItemQuality())
            row.text:SetText(RowText(x,hex))
        end)
    else
        -- No real item (e.g. an enchant) -- nothing to show, not "still loading".
        row.icon:Hide()
    end
end

function CraftCircleWF_Refresh()
    InitDB(); RenderCategoryTree()
    for _,r in ipairs(rows) do r:Hide() end
    local q=(search:GetText() or ""):lower(); local results={}
    for key,c in pairs(MergedCharacters()) do
        for pn,p in pairs(c.professions or {}) do
            for _,r in ipairs(p.recipes or {}) do
                if r.itemID then EnsureLevelCached(r.itemID) end
                local cat,sub=CategoryFor(r.itemID,pn)
                if (not currentCategory or cat==currentCategory) and (not currentSub or sub==currentSub) and FilterLevelOK(r.itemID) then
                    local text=(key.." "..pn.." "..(r.name or "")):lower()
                    if q=="" or text:find(q,1,true) then results[#results+1]={key=key,pn=pn,p=p,r=r} end
                end
            end
        end
    end
    SortResults(results)
    local breadcrumb=currentCategory and (currentCategory..(currentSub and (" › "..currentSub) or "")) or "All categories"
    status:SetText(string.format("%d matching recipes · %s · guild hash sync %s",#results,breadcrumb,IsInGuild() and "on" or "off"))
    content:SetHeight(math.max(1,#results*24))
    for i,x in ipairs(results) do
        local row=rows[i]
        if not row then
            row=CreateFrame("Frame",nil,content); row:SetSize(636,22)
            row.icon=row:CreateTexture(nil,"ARTWORK"); row.icon:SetSize(20,20); row.icon:SetPoint("LEFT",2,0)
            row.text=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); row.text:SetPoint("LEFT",26,0); row.text:SetWidth(525); row.text:SetJustifyH("LEFT")
            row.button=CreateFrame("Button",nil,row,"UIPanelButtonTemplate"); row.button:SetSize(75,20); row.button:SetPoint("RIGHT",-2,0); row.button:SetText("Request")
            row:EnableMouse(true)
            row:SetScript("OnEnter",function(self)
                if self.itemID and self.itemID>0 then
                    GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
                    GameTooltip:SetItemByID(self.itemID)
                    GameTooltip:Show()
                end
            end)
            row:SetScript("OnLeave",function() GameTooltip:Hide() end)
            rows[i]=row
        end
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",2,-((i-1)*24))
        SetRowItem(row,x)
        row.button:SetScript("OnClick",function() Whisper(x.key,x.r.name,x.r.itemID) end)
        row:Show()
    end
end
search:SetScript("OnTextChanged",CraftCircleWF_Refresh); window:SetScript("OnShow",CraftCircleWF_Refresh)

-- ===== Minimap button (Atlasloot-style: drag around the minimap ring) =====
local minimapAngle = 200
local minimapButton=CreateFrame("Button","CraftCircleWFMinimapButton",Minimap)
minimapButton:SetSize(31,31); minimapButton:SetFrameStrata("MEDIUM"); minimapButton:SetFrameLevel(8)
minimapButton:RegisterForClicks("LeftButtonUp"); minimapButton:RegisterForDrag("LeftButton")
local minimapIcon=minimapButton:CreateTexture(nil,"BACKGROUND"); minimapIcon:SetSize(20,20); minimapIcon:SetPoint("CENTER"); minimapIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
local minimapBorder=minimapButton:CreateTexture(nil,"OVERLAY"); minimapBorder:SetSize(54,54); minimapBorder:SetPoint("TOPLEFT"); minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
local function UpdateMinimapButtonPosition()
    local angle=math.rad(minimapAngle); local radius=80
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER",Minimap,"CENTER",radius*math.cos(angle),radius*math.sin(angle))
end
minimapButton:SetScript("OnDragStart",function(self)
    self:SetScript("OnUpdate",function()
        local mx,my=Minimap:GetCenter(); local px,py=GetCursorPosition(); local scale=Minimap:GetEffectiveScale()
        px,py=px/scale,py/scale
        minimapAngle=math.deg(math.atan2(py-my,px-mx))
        UpdateMinimapButtonPosition()
    end)
end)
minimapButton:SetScript("OnDragStop",function(self) self:SetScript("OnUpdate",nil); if DB then DB.minimapAngle=minimapAngle end end)
minimapButton:SetScript("OnClick",function() if window:IsShown() then window:Hide() else window:Show() end end)
minimapButton:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_LEFT"); GameTooltip:SetText("CraftCircle WF"); GameTooltip:AddLine("Click to open/close · drag to move",1,1,1); GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave",function() GameTooltip:Hide() end)
UpdateMinimapButtonPosition()

SLASH_CRAFTCIRCLEWF1="/craftcircle"; SLASH_CRAFTCIRCLEWF2="/ccraft"
SlashCmdList.CRAFTCIRCLEWF=function(msg)
    msg=(msg or ""):lower():match("^%s*(.-)%s*$")
    if msg=="scan" then Scan() elseif msg=="sync" then AnnounceAll(); Print("guild hashes announced") elseif msg=="api" then Print("C_ChatInfo="..tostring(C_ChatInfo~=nil)..", C_TradeSkillUI="..tostring(C_TradeSkillUI~=nil)) else if window:IsShown() then window:Hide() else window:Show() end end
end

CC:RegisterEvent("ADDON_LOADED"); CC:RegisterEvent("PLAYER_LOGIN"); CC:RegisterEvent("PLAYER_GUILD_UPDATE"); CC:RegisterEvent("CHAT_MSG_ADDON"); CC:RegisterEvent("TRADE_SKILL_SHOW"); CC:RegisterEvent("TRADE_SKILL_LIST_UPDATE")
CC:SetScript("OnEvent",function(_,event,...)
    if event=="ADDON_LOADED" and (...)==ADDON_NAME then InitDB(); C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
    elseif event=="PLAYER_LOGIN" then
        InitDB(); C_ChatInfo.RegisterAddonMessagePrefix(PREFIX); C_Timer.After(4,AnnounceAll)
        if DB.uiScale then scaleSlider:SetValue(DB.uiScale) end
        if DB.minimapAngle then minimapAngle=DB.minimapAngle; UpdateMinimapButtonPosition() end
        Print("loaded. Guild hash sync enabled.")
    elseif event=="PLAYER_GUILD_UPDATE" then C_Timer.After(2,AnnounceAll)
    elseif event=="CHAT_MSG_ADDON" then local prefix,message,channel,sender=...; if prefix==PREFIX and channel=="GUILD" and sender~=PlayerKey() then HandleAddon(message,sender) end
    elseif event=="TRADE_SKILL_SHOW" or event=="TRADE_SKILL_LIST_UPDATE" then C_Timer.After(0.5,Scan) end
end)
CC:SetScript("OnUpdate",function() PumpQueue(); local now=GetTime(); for id,t in pairs(incoming) do if now-t.started>30 then incoming[id]=nil end end end)
