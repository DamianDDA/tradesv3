local Core = exports.vorp_core:GetCore()
local storageKey = 'market_ledger_v1'
local raw = GetResourceKvpString(storageKey)
local ledger = raw and json.decode(raw) or nil
if raw and (type(ledger) ~= 'table' or ledger.version ~= 1
    or type(ledger.markets) ~= 'table' or type(ledger.pending) ~= 'table') then
    error('Market ledger could not be loaded. Restore it before starting this resource.')
end
ledger = ledger or { version = 1, nextId = 1, markets = {}, pending = {} }

local busy = false
local halted = false
local lastRequest = {}

local function persist()
    local ok, message = pcall(function()
        local encoded = json.encode(ledger)
        SetResourceKvp(storageKey, encoded)
        assert(GetResourceKvpString(storageKey) == encoded, 'Ledger write verification failed')
    end)
    if not ok then
        halted = true
        error(message)
    end
end

local function character(src)
    local user = Core.getUser(src)
    local active = user and user.getUsedCharacter
    if not active or not active.identifier or not active.charIdentifier then return end
    return active, tostring(active.identifier) .. '/' .. tostring(active.charIdentifier)
end

local function cash(active)
    local amount = active and tonumber(active.money)
    if amount then return math.floor(amount * 100 + 0.5) end
end

local function status(m)
    if m.status == 'open' and m.closes <= os.time() then return 'closed' end
    return m.status
end

local function finishCash(key, entry, applied)
    local m = assert(ledger.markets[tostring(entry.market)])
    if applied and entry.kind == 'bet' then
        local position = m.positions[key] or { 0, 0 }
        position[entry.side] = position[entry.side] + entry.amount
        m.positions[key] = position
        m.totals[entry.side] = m.totals[entry.side] + entry.amount
    elseif applied then
        m.claims[key] = nil
    end
    ledger.pending[key] = nil
    persist()
end

local function moveCash(src, key, active, entry)
    entry.before = cash(active)
    local delta = entry.kind == 'bet' and -entry.amount or entry.amount
    entry.after = entry.before + delta
    entry.time = os.time()
    entry.name = ((active.firstname or '') .. ' ' .. (active.lastname or ''))
    ledger.pending[key] = entry
    persist()

    local change = delta < 0 and active.removeCurrency or active.addCurrency
    local ok, result = pcall(change, 0, entry.amount / 100)
    local current, currentKey = character(src)
    if ok and result ~= false and currentKey == key and cash(current) == entry.after then
        finishCash(key, entry, true)
        return true
    end
    print(('[bf_markets] Cash review required for %s on market %s'):format(key, entry.market))
    return false
end

local function settle(m, winner)
    local keys = {}
    for key in pairs(m.positions) do keys[#keys + 1] = key end
    table.sort(keys)
    m.claims = {}
    local total = m.totals[1] + m.totals[2]
    local winning = winner and m.totals[winner] or 0
    local cumulative, distributed = 0, 0
    for _, key in ipairs(keys) do
        local p = m.positions[key]
        local amount = p[1] + p[2]
        if winning > 0 then
            cumulative = cumulative + p[winner]
            local target = (cumulative * total) // winning
            amount = target - distributed
            distributed = target
        end
        if amount > 0 then m.claims[key] = amount end
    end
    m.status = winning > 0 and 'settled' or 'refunded'
    m.winner = winner
    m.finished = os.time()
    persist()
end

local function prune()
    local cutoff = os.time() - Config.HistoryDays * 86400
    for id, m in pairs(ledger.markets) do
        if m.finished and m.finished < cutoff and not next(m.claims) then
            ledger.markets[id] = nil
        end
    end
end

local function snapshot(active, key, admin)
    local markets, reviews = {}, {}
    for _, m in pairs(ledger.markets) do
        local position = m.positions[key] or { 0, 0 }
        local claim = m.claims and m.claims[key] or 0
        if not m.finished or os.time() - m.finished <= Config.HistoryDays * 86400 or claim > 0 then
            markets[#markets + 1] = {
                id = m.id, title = m.title, rules = m.rules, options = m.options,
                totals = m.totals, closes = m.closes, status = status(m),
                position = position, claim = claim, winner = m.winner
            }
        end
    end
    table.sort(markets, function(a, b) return a.id > b.id end)
    if admin then
        for owner, entry in pairs(ledger.pending) do
            reviews[#reviews + 1] = {
                key = owner, name = entry.name, market = entry.market, kind = entry.kind,
                before = entry.before, after = entry.after, time = entry.time
            }
        end
    end
    return {
        admin = admin, markets = markets, reviews = reviews, balance = cash(active),
        pending = ledger.pending[key] ~= nil, min = Config.MinWager, max = Config.MaxWager
    }
end

local function clean(value, max)
    if type(value) ~= 'string' or #value > max or value:find('[%z\1-\8\11\12\14-\31]') then return end
    local trimmed = value:match('^%s*(.-)%s*$')
    if trimmed ~= '' then return trimmed end
end

local function integer(value, min, max)
    if type(value) == 'number' and value >= min and value <= max and value % 1 == 0 then return math.tointeger(value) end
end

local function act(src, data, active, key, admin)
    local action = data.action
    if action == 'view' then return end
    if halted then return 'Markets are temporarily unavailable. Contact staff.' end

    if action == 'review' then
        if not admin then return 'Staff access required.' end
        local entry = type(data.key) == 'string' and ledger.pending[data.key]
        if not entry or type(data.applied) ~= 'boolean' then return 'Review no longer available.' end
        finishCash(data.key, entry, data.applied)
        print(('[bf_markets] Staff source %s reviewed market %s for %s (applied: %s)'):format(
            src, entry.market, data.key, tostring(data.applied)))
        return nil, 'Cash review saved.'
    end

    if action == 'create' then
        if not admin then return 'Staff access required.' end
        local title, rules = clean(data.title, 120), clean(data.rules, 800)
        local first, second = clean(data.first, 40), clean(data.second, 40)
        local minutes = integer(data.minutes, 1, 43200)
        if not title or not rules or not first or not second or first:lower() == second:lower() or not minutes then
            return 'Enter a question, resolution rules, two distinct outcomes and a valid duration.'
        end
        local count = 0
        for _, m in pairs(ledger.markets) do
            if not m.finished then count = count + 1 end
        end
        if count >= Config.MaxOpenMarkets then return 'Settle or refund an existing market first.' end
        local id = ledger.nextId
        ledger.nextId = id + 1
        prune()
        ledger.markets[tostring(id)] = {
            id = id, title = title, rules = rules, options = { first, second },
            closes = os.time() + minutes * 60, status = 'open',
            totals = { 0, 0 }, positions = {}, createdBy = key
        }
        persist()
        return nil, 'Market published.'
    end

    local id = integer(data.id, 1, ledger.nextId)
    local m = id and ledger.markets[tostring(id)]
    if not m then return 'Market unavailable.' end

    if action == 'bet' or action == 'claim' then
        if ledger.pending[key] then return 'A cash movement on this character is awaiting staff review.' end
        if not cash(active) then return 'Character cash is unavailable.' end

        local entry = { kind = action, market = id }
        if action == 'bet' then
            if status(m) ~= 'open' then return 'This market is closed.' end
            local dollars = integer(data.amount, Config.MinWager, Config.MaxWager)
            local side = integer(data.side, 1, 2)
            if not dollars or not side then return 'Choose an outcome and enter a valid whole-dollar wager.' end
            entry.side, entry.amount = side, dollars * 100
            if cash(active) < entry.amount then return 'You do not have enough cash.' end
            local reserved, participants = 0, 0
            for _ in pairs(m.positions) do participants = participants + 1 end
            for owner, pending in pairs(ledger.pending) do
                if pending.market == id and pending.kind == 'bet' then
                    reserved = reserved + pending.amount
                    if not m.positions[owner] then participants = participants + 1 end
                end
            end
            if not m.positions[key] and participants >= Config.MaxParticipants then return 'This market is at capacity.' end
            if m.totals[1] + m.totals[2] + reserved + entry.amount > math.min(Config.MaxPot, 1000000) * 100 then
                return 'That wager would exceed the market pool limit.'
            end
        else
            entry.amount = m.claims and m.claims[key]
            if not entry.amount then return 'There is no cash to claim on this market.' end
        end
        if not moveCash(src, key, active, entry) then return 'Cash movement pending staff review.' end
        return nil, action == 'bet' and 'Wager placed.' or 'Cash collected.'
    end

    if not admin then return 'Staff access required.' end
    if action == 'close' and status(m) == 'open' then
        m.status = 'closed'
        persist()
        return nil, 'Wagering closed.'
    end
    if (action == 'settle' and status(m) == 'closed') or (action == 'refund' and not m.finished) then
        for _, entry in pairs(ledger.pending) do
            if entry.market == id then return 'Review the pending cash movement before settling or refunding.' end
        end
        local winner = action == 'settle' and integer(data.side, 1, 2) or nil
        if action == 'settle' and not winner then return 'Choose the winning outcome.' end
        settle(m, winner)
        return nil, m.status == 'refunded' and 'Refunds are ready to claim.' or 'Winnings are ready to claim.'
    end
    return 'That action is unavailable.'
end

RegisterNetEvent('bf_markets:request', function(data)
    local src = source
    if type(data) ~= 'table' then return end
    local now = GetGameTimer()
    if lastRequest[src] and now - lastRequest[src] >= 0 and now - lastRequest[src] < 350 then
        TriggerClientEvent('bf_markets:response', src, { error = 'Please wait a moment.' })
        return
    end
    lastRequest[src] = now
    if busy then
        TriggerClientEvent('bf_markets:response', src, { error = 'Markets are busy. Try again.' })
        return
    end

    busy = true
    local ok, response = xpcall(function()
        local active, key = character(src)
        if not active then return { error = 'Select a character first.' } end
        local admin = IsPlayerAceAllowed(src, Config.AdminAce)
        local message, notice = act(src, data, active, key, admin)
        local current, currentKey = character(src)
        if currentKey ~= key then return { error = 'Character changed. Reopen the exchange.' } end
        local state = snapshot(current, key, admin)
        state.error, state.notice = message, notice
        return state
    end, debug.traceback)
    busy = false
    if not ok then
        print(response)
        response = { error = 'Market service error. Contact staff if cash moved.' }
    end
    TriggerClientEvent('bf_markets:response', src, response)
end)

AddEventHandler('playerDropped', function() lastRequest[source] = nil end)
