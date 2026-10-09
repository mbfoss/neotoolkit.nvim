---@class neotoolkit.LRU.Opts
---@field on_evict   fun(key:any, value:any)?  called only when capacity is exceeded
---@field on_removed fun(key:any, value:any)?  called for every removal (evict, delete, clear)

---@private
---@class neotoolkit.LRU.Node
---@field key any
---@field value any
---@field prev neotoolkit.LRU.Node?
---@field next neotoolkit.LRU.Node?

--- A bounded cache with least-recently-used eviction, for anything expensive
--- to recompute per item — file stats, rendered lines, parsed output. The
--- eviction hooks make it usable for values that own a resource, such as a
--- buffer to wipe or a handle to close.
---@class neotoolkit.LRU
---@field _capacity integer
---@field _count integer
---@field _map table<any, neotoolkit.LRU.Node>
---@field _head neotoolkit.LRU.Node?
---@field _tail neotoolkit.LRU.Node?
---@field _on_evict fun(key:any, value:any)? Called ONLY when _capacity is exceeded.
---@field _on_removed fun(key:any, value:any)? Called for EVERY removal (eviction, delete, clear).
local LRU = {}
LRU.__index = LRU

--- Create a cache holding at most `capacity` entries.
---@param capacity integer
---@param opts neotoolkit.LRU.Opts?
---@return neotoolkit.LRU
function LRU:new(capacity, opts)
    local obj = setmetatable({}, self)
    if obj.init then obj:init(capacity, opts) end
    return obj
end

---@private
---@param capacity integer
---@param opts neotoolkit.LRU.Opts?
function LRU:init(capacity, opts)
    assert(type(capacity) == "number" and capacity > 0, "LRU capacity must be a positive integer")
    opts = opts or {}

    self._capacity = capacity
    self._count = 0
    self._map = {}
    self._head = nil
    self._tail = nil
    self._on_evict = opts.on_evict
    self._on_removed = opts.on_removed
end

---@private
function LRU:_remove_links(node)
    if node.prev then node.prev.next = node.next else self._head = node.next end
    if node.next then node.next.prev = node.prev else self._tail = node.prev end
    node.prev = nil
    node.next = nil
end

---@private
function LRU:_insert_front(node)
    node.next = self._head
    node.prev = nil
    if self._head then self._head.prev = node else self._tail = node end
    self._head = node
end

---@private
function LRU:_delete_node(node, is_eviction)
    self:_remove_links(node)
    self._map[node.key] = nil
    self._count = self._count - 1
    if is_eviction and self._on_evict then
        self._on_evict(node.key, node.value)
    end
    if self._on_removed then
        self._on_removed(node.key, node.value)
    end
end

--- Look up `key` and promote it to most-recent.
---@param key any
---@return any? value
function LRU:get(key)
    local node = self._map[key]
    if not node then return nil end

    self:_remove_links(node)
    self:_insert_front(node)
    return node.value
end

--- Look up `key` without promoting it.
---@param key any
---@return any? value
function LRU:peek(key)
    local node = self._map[key]
    return node and node.value or nil
end

--- Insert or update `key`, evicting the least-recent entry at capacity.
---@param key any
---@param value any
function LRU:put(key, value)
    local node = self._map[key]

    if node then
        node.value = value
        self:_remove_links(node)
        self:_insert_front(node)
        return
    end

    if self._count >= self._capacity then
        local lru_node = self._tail
        if lru_node then
            self:_delete_node(lru_node, true)
        end
    end

    node = { key = key, value = value }
    self._map[key] = node
    self:_insert_front(node)
    self._count = self._count + 1
end

--- Move an existing `key` to most-recent without reading its value.
---@param key any
function LRU:promote(key)
    local node = self._map[key]
    if not node then return end
    self:_remove_links(node)
    self:_insert_front(node)
end

--- Remove `key` if it is present.
---@param key any
function LRU:delete(key)
    local node = self._map[key]
    if node then
        self:_delete_node(node, false)
    end
end

--- Whether `key` is in the cache, without promoting it.
---@param key any
---@return boolean
function LRU:has(key)
    return self._map[key] ~= nil
end

--- Remove every entry.
function LRU:clear()
    if self._on_removed or self._on_evict then
        while self._head do
            self:_delete_node(self._head, false)
        end
    else
        self._map = {}
        self._count = 0
        self._head = nil
        self._tail = nil
    end
end

--- Number of entries held.
---@return integer
function LRU:size()
    return self._count
end

--- Every key in the cache.
---@return any[] -- most-recent first
function LRU:keys()
    local keys = {}
    local current = self._head
    local i = 1

    while current do
        keys[i] = current.key
        current = current.next
        i = i + 1
    end

    return keys
end

--- Iterate `key, value` pairs.
---@return fun(): (any, any) -- iterator yielding (key, value), most-recent first
function LRU:iter_items()
    local current = self._head
    return function()
        if not current then return nil end
        local key, value = current.key, current.value
        current = current.next
        return key, value
    end
end

return LRU
