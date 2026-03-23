--[[
    TableUtil.luau
    Pure-function table helpers used across server and client.
]]

local TableUtil = {}

--- Deep-copy a table (handles nested tables, not metatables/userdata).
function TableUtil.deepCopy<T>(original: T): T
    if type(original) ~= "table" then
        return original
    end
    local copy = {}
    for k, v in original :: any do
        copy[TableUtil.deepCopy(k)] = TableUtil.deepCopy(v)
    end
    return copy :: any
end

--- Shallow merge b into a (b wins on conflicts). Returns a new table.
function TableUtil.merge(a: { [any]: any }, b: { [any]: any }): { [any]: any }
    local result = table.clone(a)
    for k, v in b do
        result[k] = v
    end
    return result
end

--- Deep merge b into a recursively. Returns a new table.
function TableUtil.deepMerge(a: { [any]: any }, b: { [any]: any }): { [any]: any }
    local result = TableUtil.deepCopy(a)
    for k, v in b do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = TableUtil.deepMerge(result[k], v)
        else
            result[k] = TableUtil.deepCopy(v)
        end
    end
    return result
end

--- Fisher-Yates shuffle in place. Returns same table.
function TableUtil.shuffle<T>(t: { T }): { T }
    for i = #t, 2, -1 do
        local j = math.random(1, i)
        t[i], t[j] = t[j], t[i]
    end
    return t
end

--- Pick a random element from an array.
function TableUtil.randomPick<T>(t: { T }): T?
    if #t == 0 then return nil end
    return t[math.random(1, #t)]
end

--- Weighted random selection. weights is parallel array of numbers.
function TableUtil.weightedPick<T>(items: { T }, weights: { number }): T?
    local total = 0
    for _, w in weights do total += w end
    if total <= 0 then return nil end

    local roll = math.random() * total
    local cumulative = 0
    for i, w in weights do
        cumulative += w
        if roll <= cumulative then
            return items[i]
        end
    end
    return items[#items]
end

--- Filter an array, returning elements where predicate is true.
function TableUtil.filter<T>(t: { T }, predicate: (T, number) -> boolean): { T }
    local result = {}
    for i, v in t do
        if predicate(v, i) then
            table.insert(result, v)
        end
    end
    return result
end

--- Map an array to a new array.
function TableUtil.map<T, U>(t: { T }, transform: (T, number) -> U): { U }
    local result = {}
    for i, v in t do
        result[i] = transform(v, i)
    end
    return result
end

--- Find first element matching predicate.
function TableUtil.find<T>(t: { T }, predicate: (T) -> boolean): T?
    for _, v in t do
        if predicate(v) then return v end
    end
    return nil
end

return TableUtil
