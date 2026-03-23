--[[
    Signal.luau
    Lightweight custom signal/event implementation.
    Used for intra-module communication without RemoteEvents.
    Pattern: observer/pub-sub within the same execution context.
]]

local Signal = {}
Signal.__index = Signal

export type Connection = {
    Disconnect: (self: Connection) -> (),
    Connected: boolean,
}

export type Signal<T...> = {
    Fire: (self: Signal<T...>, T...) -> (),
    Connect: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
    Once: (self: Signal<T...>, callback: (T...) -> ()) -> Connection,
    Wait: (self: Signal<T...>) -> T...,
    DisconnectAll: (self: Signal<T...>) -> (),
    Destroy: (self: Signal<T...>) -> (),
}

function Signal.new<T...>(): Signal<T...>
    local self = setmetatable({}, Signal)
    self._connections = {} :: { { callback: (T...) -> (), once: boolean } }
    self._waiting = {} :: { thread }
    return self :: any
end

function Signal:Connect(callback: (...any) -> ()): Connection
    local node = { callback = callback, once = false, connected = true }
    table.insert(self._connections, node)

    local connection = {
        Connected = true,
        Disconnect = function(conn)
            if not node.connected then return end
            node.connected = false
            conn.Connected = false
            for i, n in self._connections do
                if n == node then
                    table.remove(self._connections, i)
                    break
                end
            end
        end,
    }
    return connection
end

function Signal:Once(callback: (...any) -> ()): Connection
    local connection
    connection = self:Connect(function(...)
        connection:Disconnect()
        callback(...)
    end)
    return connection
end

function Signal:Fire(...)
    -- Fire to all current connections (snapshot to allow disconnect mid-fire)
    local snapshot = table.clone(self._connections)
    for _, node in snapshot do
        if node.connected then
            task.spawn(node.callback, ...)
        end
    end

    -- Resume waiting threads
    local waiting = self._waiting
    self._waiting = {}
    for _, thread in waiting do
        task.spawn(thread, ...)
    end
end

function Signal:Wait()
    local thread = coroutine.running()
    table.insert(self._waiting, thread)
    return coroutine.yield()
end

function Signal:DisconnectAll()
    for _, node in self._connections do
        node.connected = false
    end
    table.clear(self._connections)
    table.clear(self._waiting)
end

function Signal:Destroy()
    self:DisconnectAll()
    setmetatable(self, nil)
end

return Signal
