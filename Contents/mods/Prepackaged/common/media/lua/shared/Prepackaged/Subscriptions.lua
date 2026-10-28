-- The tree comes from the pack's @collections: Steam returns no children for a collection to Lua (getNumChildren is 0),
-- so the live one can't be walked from here.
local Subscriptions = {}

-- Steam returns at most 50 results per UGC query (kNumUGCResultsPerPage). The game's Java sends any number in one
-- request (LuaManager.java:10459-10472) and shows no limit, so 50 is the size that can't be cut short.
Subscriptions.BATCH = 50

-- What SteamUGCDetails.getState returns (SteamUGCDetails.java:65-77).
local STATES = { NotSubscribed = true, Downloading = true, NeedsUpdate = true, Installed = true, Error = true }
local COUNTED = { NotSubscribed = true, Downloading = true, NeedsUpdate = true, Installed = true }
-- Not installed and not on its way: these get an Open.
local ACTION = { NotSubscribed = true, Error = true, NoDetails = true, NoAnswer = true, Unknown = true }

function Subscriptions.needsAction(state)
    return ACTION[state] == true
end

-- One line per collection, depth first from the pack's top collections, then any other listed collection. A collection
-- seen again is not walked again. Iterative: Kahlua's call stack ends at about 100 frames.
function Subscriptions.tree(pack)
    local byId, isCollection = {}, {}
    for _, entry in ipairs(pack.collections) do
        byId[entry.id] = entry
        isCollection[entry.id] = true
    end
    for _, id in ipairs(pack.collection) do
        isCollection[id] = true
    end
    local tree = { lines = {}, loose = {}, ids = {}, listed = #pack.collections > 0 }
    local seen, inCollection, asked = {}, {}, {}
    local function ask(id)
        if not asked[id] then
            asked[id] = true
            tree.ids[#tree.ids + 1] = id
        end
    end
    local function walk(root)
        local stack = { { id = root, depth = 0 } }
        while #stack > 0 do
            local top = table.remove(stack)
            if not seen[top.id] then
                seen[top.id] = true
                local entry = byId[top.id]
                tree.lines[#tree.lines + 1] = { id = top.id, depth = top.depth, entry = entry }
                if entry ~= nil then
                    for _, item in ipairs(entry.items) do
                        inCollection[item] = true
                        ask(item)
                    end
                    for i = #entry.children, 1, -1 do
                        stack[#stack + 1] = { id = entry.children[i], depth = top.depth + 1 }
                    end
                end
            end
        end
    end
    for _, id in ipairs(pack.collection) do
        walk(id)
    end
    for _, entry in ipairs(pack.collections) do
        walk(entry.id)
    end
    for _, id in ipairs(pack.workshopItems) do
        if not inCollection[id] and not isCollection[id] then
            tree.loose[#tree.loose + 1] = id
            ask(id)
        end
    end
    return tree
end

function Subscriptions.batches(ids, size)
    local list = {}
    for first = 1, #ids, size do
        local batch = {}
        for i = first, math.min(first + size - 1, #ids) do
            batch[#batch + 1] = ids[i]
        end
        list[#list + 1] = batch
    end
    return list
end

-- Every item starts as being asked about, or as unknown without Steam.
function Subscriptions.start(tree, steam)
    local result = { states = {}, titles = {}, asked = #tree.ids, answered = 0, unanswered = 0, steam = steam }
    for _, id in ipairs(tree.ids) do
        result.states[id] = steam and "Asking" or "Unknown"
    end
    return result
end

-- details: what Steam returned, by id, as { title, state }. installed: the ids of installed items, which Steam knows
-- without the network, for the items it said nothing about.
function Subscriptions.answer(result, batch, status, details, installed)
    for _, id in ipairs(batch) do
        local found = details[id]
        if found ~= nil then
            result.states[id] = STATES[found.state] and found.state or "Error"
            if found.title ~= nil and found.title ~= "" then
                result.titles[id] = found.title
            end
        elseif installed[id] then
            result.states[id] = "Installed"
        else
            result.states[id] = status == "Completed" and "NoDetails" or "NoAnswer"
        end
    end
    result.answered = result.answered + #batch
    if status ~= "Completed" then
        result.unanswered = result.unanswered + #batch
    end
end

-- Error, NoDetails and NoAnswer are all not installed, whatever the reason.
function Subscriptions.count(items, states)
    local count = { total = #items, NotSubscribed = 0, Downloading = 0, NeedsUpdate = 0, Installed = 0, missing = 0, unknown = 0, asking = 0, action = false }
    for _, id in ipairs(items) do
        local state = states[id]
        if state == "Asking" then
            count.asking = count.asking + 1
        elseif state == "Unknown" then
            count.unknown = count.unknown + 1
        elseif COUNTED[state] then
            count[state] = count[state] + 1
        else
            count.missing = count.missing + 1
        end
        count.action = count.action or ACTION[state] == true
    end
    return count
end

function Subscriptions.status(result)
    if not result.steam then
        return { key = "UI_Prepackaged_SubsStatusNoSteam", args = {} }
    elseif result.answered < result.asked then
        return { key = "UI_Prepackaged_SubsStatusAsking", args = { result.asked, result.answered } }
    elseif result.unanswered > 0 then
        return { key = "UI_Prepackaged_SubsStatusPartly", args = { result.unanswered, result.asked } }
    end
    return { key = "UI_Prepackaged_SubsStatusDone", args = { result.asked } }
end

return Subscriptions
