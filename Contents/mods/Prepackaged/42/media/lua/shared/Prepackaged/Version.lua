-- Pack versions are MAJOR.MINOR.PATCH, each part digits without a leading zero, kept as the text written.
local Version = {}

local function parts(text)
    local list = { string.match(text, "^([0-9]+)%.([0-9]+)%.([0-9]+)$") }
    if #list ~= 3 then
        return nil
    end
    for _, part in ipairs(list) do
        if #part > 1 and string.sub(part, 1, 1) == "0" then
            return nil
        end
    end
    return list
end

function Version.valid(text)
    return parts(text) ~= nil
end

-- Below 0, 0 or above 0 as a is older than, the same as or newer than b, over the first count parts (all three by
-- default). Without leading zeros, the longer part is the bigger number, so parts of any length compare exactly.
function Version.compare(a, b, count)
    local x, y = parts(a), parts(b)
    for i = 1, count or 3 do
        if #x[i] ~= #y[i] then
            return #x[i] - #y[i]
        elseif x[i] ~= y[i] then
            return x[i] < y[i] and -1 or 1
        end
    end
    return 0
end

return Version
