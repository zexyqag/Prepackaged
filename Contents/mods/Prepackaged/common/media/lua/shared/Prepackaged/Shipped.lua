-- The key binds the game ships, as keyBinding holds them when this shared file loads: after the game's shared Lua, and
-- before the client Lua where mods add most of theirs. Copied, as a mod may change an entry later.
local Shipped = {}

for _, entry in ipairs(type(keyBinding) == "table" and keyBinding or {}) do
    if type(entry) == "table" and type(entry.value) == "string" and Shipped[entry.value] == nil then
        Shipped[entry.value] = { value = entry.value, key = entry.key, alt = entry.alt, shift = entry.shift, ctrl = entry.ctrl, altKey = entry.altKey }
    end
end

return Shipped
