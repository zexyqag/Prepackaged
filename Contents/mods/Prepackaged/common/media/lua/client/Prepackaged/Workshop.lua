local Subscriptions = require "Prepackaged/Subscriptions"

local Workshop = {}

Workshop.PAGE = "https://steamcommunity.com/sharedfiles/filedetails/?id="

-- One page: in the Steam overlay when it is on, else its address goes on the clipboard. The https address keeps it in the
-- overlay; activateSteamOverlayToWorkshopItem's steam:// link also opens the desktop client and minimizes the game.
function Workshop.open(id)
    if isSteamOverlayEnabled() then
        activateSteamOverlayToWebPage(Workshop.PAGE .. id)
        return "overlay"
    end
    Clipboard.setClipboard(Workshop.PAGE .. id)
    return "clipboard"
end

-- The items Steam has installed, by id: read from Steam's own list, so it needs no network. Never nil while Steam mode
-- is on (LuaManager.java:8037-8057).
function Workshop.installed()
    local set = {}
    local list = getSteamWorkshopItemIDs()
    for i = 0, list:size() - 1 do
        set[list:get(i)] = true
    end
    return set
end

local function arrayList(ids)
    local list = ArrayList.new()
    for _, id in ipairs(ids) do
        list:add(id)
    end
    return list
end

local function read(info)
    local details = {}
    for i = 0, info:size() - 1 do
        local d = info:get(i)
        details[d:getIDString()] = { title = d:getTitle(), state = d:getState() }
    end
    return details
end

-- One batch at a time, each sent once the one before is answered. The answer can come during the call (an empty list,
-- or a request Steam refuses: LuaManager.java:8219-8233, 10472-10480), so the batches go out from a loop, not from
-- inside an answer, and the call stack stays flat. After stop() an answer does nothing.
function Workshop.query(ids, onBatch)
    local query = { batches = Subscriptions.batches(ids, Subscriptions.BATCH), next = 1, waiting = false, sending = false, stopped = false }
    local send
    local function answered(batch, status, info)
        if query.stopped then
            return
        end
        query.waiting = false
        onBatch(batch, status, status == "Completed" and read(info) or {})
        if not query.sending then
            send()
        end
    end
    send = function()
        query.sending = true
        while not query.waiting and query.next <= #query.batches do
            local batch = query.batches[query.next]
            query.next = query.next + 1
            query.waiting = true
            querySteamWorkshopItemDetails(arrayList(batch), answered, batch)
        end
        query.sending = false
    end
    send()
    return { stop = function() query.stopped = true end }
end

return Workshop
