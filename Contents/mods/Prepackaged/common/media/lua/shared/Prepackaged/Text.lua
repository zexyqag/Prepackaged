local Text = {}

-- Linear: patterns like "^%s*(.-)%s*$" backtrack over every run of spaces, which is quadratic in Kahlua.
function Text.trim(text)
    local first = string.find(text, "[^ \t]")
    if first == nil then
        return ""
    end
    local _, last = string.find(text, "^.*[^ \t]")
    return string.sub(text, first, last)
end

function Text.split(text, separator)
    local parts, from = {}, 1
    while true do
        local i = string.find(text, separator, from, true)
        if i == nil then
            parts[#parts + 1] = string.sub(text, from)
            return parts
        end
        parts[#parts + 1] = string.sub(text, from, i - 1)
        from = i + 1
    end
end

-- The last field may itself hold |.
function Text.after(line, count)
    local from = 1
    for _ = 1, count do
        from = string.find(line, "|", from, true) + 1
    end
    return string.sub(line, from)
end

function Text.same(a, b)
    if #a ~= #b then
        return false
    end
    for i = 1, #a do
        if a[i] ~= b[i] then
            return false
        end
    end
    return true
end

function Text.copy(list)
    local result = {}
    for i, value in ipairs(list) do
        result[i] = value
    end
    return result
end

return Text
