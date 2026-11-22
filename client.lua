local visible = false

local function close()
    visible = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

local function open(admin)
    visible = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', admin = admin, brand = Config.Brand })
end

RegisterCommand(Config.Command, function() open(false) end, false)
RegisterCommand(Config.AdminCommand, function() open(true) end, false)

RegisterNUICallback('close', function(_, cb)
    close()
    cb({})
end)

RegisterNUICallback('request', function(data, cb)
    if visible then TriggerServerEvent('bf_markets:request', data) end
    cb({})
end)

RegisterNetEvent('bf_markets:response', function(data)
    if not visible then return end
    data.type = 'response'
    SendNUIMessage(data)
end)

AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() and visible then
        SetNuiFocus(false, false)
    end
end)
