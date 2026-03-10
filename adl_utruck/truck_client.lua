local MOVEMENT = {
    { dict = "va_utillitruck", anim = "crane" },
    { dict = "v_boomtruck",    anim = "rotate_crane_base" },
}

local COLLISION = {

    {
        model = `prop_crate_06a`,
        bone = "bucket",
        position = vec3(0.0, -0.36, -0.86),
        rotation = vec3(0.0, 0.0, 90.0)
    },
    {
        model = `prop_skate_rail`,
        bone = "arm_1",
        position = vec3(0.0, 3.0, 0.06)
    },
    {
        model = `prop_skate_rail`,
        bone = "arm_2",
        position = vec3(0.0, -3.4, 0.1)
    }
}

local SOUND = {
    ambient = 'Crane',
    script = 'Container_Lifter',
    scene = 'DOCKS_HEIST_USING_CRANE',
    name = 'Move_U_D',
    ref = 'CRANE_SOUNDS',
}

local PlayEntityAnim = PlayEntityAnim
local SetEntityAnimCurrentTime = SetEntityAnimCurrentTime
local IsEntityPlayingAnim = IsEntityPlayingAnim
local DisableControlAction = DisableControlAction
local IsDisabledControlPressed = IsDisabledControlPressed
local GetEntityAnimCurrentTime = GetEntityAnimCurrentTime

---@type integer
---@diagnostic disable-next-line: assign-type-mismatch
local craneVehicle = false
local craneState = false
local switchMode = 1
local dict = MOVEMENT[switchMode].dict
local anim = MOVEMENT[switchMode].anim
local animTime = { 0.0, 0.0 }
local soundId = -1
local CONTROL_ZONE_DISTANCE = 2.2
local CRANE_SYNC_INTERVAL_MS = 100
local CRANE_SYNC_EPSILON = 0.001
local craneControlActive = false
local craneHandlerActive = false
local cranePromptActive = false
local remoteEntity = 0
local REMOTE_MODEL = `ex_prop_tv_settop_remote`
local controlRope = 0
local ROPE_LENGTH = 3.0
local ROPE_TYPE = 4

local function loadAnimationDicts()
    lib.array.forEach(MOVEMENT, function(type)
        lib.requestAnimDict(type.dict)
    end)

    RequestAmbientAudioBank(SOUND.ambient, false)
    lib.requestAudioBank(SOUND.script)
end

local function moveVertical(direction)
    if switchMode ~= 1 then
        anim = MOVEMENT[1].anim
        dict = MOVEMENT[1].dict
        switchMode = 1
        Entity(cache.ped).state:set('craneMode', switchMode, true)
    end

    if not IsEntityPlayingAnim(craneVehicle, dict, anim, 3) then
        PlayEntityAnim(craneVehicle, anim, dict, 8.0, false, true, false, 0.0, 0)
        Wait(0)
        SetEntityAnimCurrentTime(craneVehicle, dict, anim, animTime[switchMode])
    end

    SetEntityAnimSpeed(craneVehicle, dict, anim, 0.1 * direction)
end

local function moveHorizontal(direction)
    if switchMode ~= 2 then
        anim = MOVEMENT[2].anim
        dict = MOVEMENT[2].dict
        switchMode = 2
        Entity(cache.ped).state:set('craneMode', switchMode, true)
    end

    if not IsEntityPlayingAnim(craneVehicle, dict, anim, 3) then
        PlayEntityAnim(craneVehicle, anim, dict, 8.0, false, true, false, 0.0, 0)
        Wait(0)
        SetEntityAnimCurrentTime(craneVehicle, dict, anim, animTime[switchMode])
    end

    local animTime = animTime[2]

    if (direction == 1 and animTime >= 1) or (direction == -1 and animTime == 0) then
        local newTime = (direction == 1) and 0.0 or 1.0

        animTime = newTime
        SetEntityAnimCurrentTime(craneVehicle, dict, anim, newTime)
        Wait(0)
    end

    SetEntityAnimSpeed(craneVehicle, dict, anim, 0.1 * direction)
end

local function playSound()
    if not IsAudioSceneActive(SOUND.scene) then
        StartAudioScene(SOUND.scene)
    end
    soundId = GetSoundId()
    if HasSoundFinished(soundId) then
        PlaySoundFromEntity(soundId, SOUND.name, craneVehicle, SOUND.ref, false, 0)
    end
end

local function stopSound()
    if soundId == -1 then return end

    StopSound(soundId)
    ReleaseSoundId(soundId)
    soundId = -1
end

local function setCraneControlUiVisible(visible)
    SendNUIMessage({
        action = 'setVisible',
        visible = visible
    })
end

local function updateCraneControlUiState(upPressed, downPressed, westPressed, eastPressed)
    SendNUIMessage({
        action = 'setState',
        up = upPressed,
        down = downPressed,
        west = westPressed,
        east = eastPressed
    })
end

local function isCraneModeActive()
    return craneVehicle and DoesEntityExist(craneVehicle) and Entity(craneVehicle).state.crane
end

local function getControlAnchorCoords(vehicle)
    return GetOffsetFromEntityInWorldCoords(vehicle, -0.95, -3.05, 0.05)
end

local function getControlZoneDistance()
    if not craneVehicle or not DoesEntityExist(craneVehicle) then return nil end

    local playerCoords = GetEntityCoords(cache.ped)
    local controlCoords = getControlAnchorCoords(craneVehicle)

    return #(playerCoords - controlCoords)
end

local function startRemoteControlPose()
    local dict = 'amb@world_human_stand_mobile@male@text@base'
    local name = 'base'

    lib.requestAnimDict(dict)
    TaskPlayAnim(cache.ped, dict, name, 2.0, 2.0, -1, 49, 0.0, false, false, false)

    if remoteEntity ~= 0 and DoesEntityExist(remoteEntity) then return end

    lib.requestModel(REMOTE_MODEL)
    remoteEntity = CreateObjectNoOffset(REMOTE_MODEL, 0.0, 0.0, 0.0, true, false, false)
    SetModelAsNoLongerNeeded(REMOTE_MODEL)

    local bone = GetPedBoneIndex(cache.ped, 57005)
    AttachEntityToEntity(remoteEntity, cache.ped, bone, 0.11, 0.02, -0.01, -80.0, 160.0, 15.0, true, true, false, true, 1, true)

    if not RopeAreTexturesLoaded() then
        RopeLoadTextures()
        while not RopeAreTexturesLoaded() do
            Wait(0)
        end
    end

    local anchor = getControlAnchorCoords(craneVehicle)
    controlRope = AddRope(anchor.x, anchor.y, anchor.z, 0.0, 0.0, 0.0, ROPE_LENGTH, ROPE_TYPE, 8.0, 0.0, 1.0, false, false, false, 1.0, true)

    if controlRope and controlRope ~= 0 then
        local remoteCoords = GetEntityCoords(remoteEntity)
        AttachEntitiesToRope(controlRope, craneVehicle, remoteEntity, anchor.x, anchor.y, anchor.z, remoteCoords.x, remoteCoords.y, remoteCoords.z, ROPE_LENGTH, false, false, nil, nil)
    end
end

local function stopRemoteControlPose()
    local dict = 'amb@world_human_stand_mobile@male@text@base'
    local name = 'base'

    StopAnimTask(cache.ped, dict, name, 1.0)

    if controlRope and controlRope ~= 0 then
        DeleteRope(controlRope)
        controlRope = 0
    end

    if remoteEntity ~= 0 and DoesEntityExist(remoteEntity) then
        DeleteEntity(remoteEntity)
    end

    remoteEntity = 0
end

local function activateCrane()
    if craneControlActive then return end
    craneControlActive = true

    CreateThread(function()
        loadAnimationDicts()
        playSound()
        startRemoteControlPose()
        setCraneControlUiVisible(true)

        local lastCraneSync = 0
        local lastSyncedAnimTime = { animTime[1], animTime[2] }

        Entity(cache.ped).state:set('craneMode', switchMode, true)
        Entity(cache.ped).state:set('craneData', animTime, true)

        while craneControlActive and isCraneModeActive() do
            dict = MOVEMENT[switchMode].dict
            anim = MOVEMENT[switchMode].anim

            local distance = getControlZoneDistance()
            local canControl = distance and distance <= CONTROL_ZONE_DISTANCE

            if not canControl then
                break
            end

            SetEntityAnimSpeed(craneVehicle, dict, anim, 0.0)
            DisableControlAction(0, 172, true) -- Up
            DisableControlAction(0, 173, true) -- Down
            DisableControlAction(0, 174, true) -- Left
            DisableControlAction(0, 175, true) -- Right
            DisableControlAction(0, 177, true) -- Backspace

            local upPressed = IsDisabledControlPressed(0, 172)
            local downPressed = IsDisabledControlPressed(0, 173)
            local leftPressed = IsDisabledControlPressed(0, 174)
            local rightPressed = IsDisabledControlPressed(0, 175)

            updateCraneControlUiState(upPressed, downPressed, leftPressed, rightPressed)

            if upPressed then
                moveVertical(1)    -- Up
            elseif downPressed then
                moveVertical(-1)   -- Down
            elseif leftPressed then
                moveHorizontal(1)  -- Left
            elseif rightPressed then
                moveHorizontal(-1) -- Right
            elseif IsDisabledControlPressed(0, 177) then
                break
            end

            animTime[switchMode] = GetEntityAnimCurrentTime(craneVehicle, dict, anim)

            local now = GetGameTimer()
            local changed = math.abs(animTime[1] - lastSyncedAnimTime[1]) > CRANE_SYNC_EPSILON
                or math.abs(animTime[2] - lastSyncedAnimTime[2]) > CRANE_SYNC_EPSILON

            if changed and now - lastCraneSync >= CRANE_SYNC_INTERVAL_MS then
                lastCraneSync = now
                lastSyncedAnimTime[1] = animTime[1]
                lastSyncedAnimTime[2] = animTime[2]
                Entity(cache.ped).state:set('craneData', animTime, true)
            end

            Wait(0)
        end

        setCraneControlUiVisible(false)
        lib.hideTextUI()
        stopSound()
        stopRemoteControlPose()
        craneControlActive = false
    end)
end

local function startBucketPromptLoop()
    if cranePromptActive then return end
    cranePromptActive = true

    CreateThread(function()
        local showingPrompt = false

        while cranePromptActive and craneVehicle do
            local canPrompt = isCraneModeActive() and not craneControlActive
            local distance = canPrompt and getControlZoneDistance() or nil
            local closeEnough = distance and distance <= CONTROL_ZONE_DISTANCE

            if closeEnough then
                if not showingPrompt then
                    lib.showTextUI('[E] Control remoto de grúa')
                    showingPrompt = true
                end

                if IsControlJustPressed(0, 38) then
                    if isCraneModeActive() and (getControlZoneDistance() or 999.0) <= CONTROL_ZONE_DISTANCE then
                        lib.hideTextUI()
                        showingPrompt = false
                        activateCrane()
                    end
                end

                Wait(0)
            else
                if showingPrompt then
                    lib.hideTextUI()
                    showingPrompt = false
                end

                Wait(300)
            end
        end

        if showingPrompt then
            lib.hideTextUI()
        end

        cranePromptActive = false
    end)
end


local function createCollision()
    local objs = {}
    lib.array.forEach(COLLISION, function(col)
        local model = col.model
        local bone = GetEntityBoneIndexByName(craneVehicle, col.bone)
        local pos = col.position
        local rot = col.rotation or vec3(0.0, 0.0, 0.0)
        local coords = GetOffsetFromEntityInWorldCoords(craneVehicle, 0.0, 0.0, -20)

        lib.requestModel(model)
        local obj = CreateObjectNoOffset(model, coords.x, coords.y, coords.z, true, false, false)
        SetModelAsNoLongerNeeded(model)
        SetEntityVisible(obj, false, false)
        AttachEntityToEntity(obj, craneVehicle, bone, pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, true, true, 1, true)

        objs[#objs + 1] = NetworkGetNetworkIdFromEntity(obj)
    end)

    return objs
end

local function craneHandler()
    if craneHandlerActive then return end
    craneHandlerActive = true

    CreateThread(function()
        local previousLegsState = nil

        while craneVehicle do
            local currentLegsState = AreOutriggerLegsDeployed(craneVehicle)
            if currentLegsState ~= previousLegsState then
                if currentLegsState and not craneState then
                    craneState = true

                    local objects = not Entity(craneVehicle).state.hasCollision and createCollision() or false
                    TriggerServerEvent('utillitruck:deployLegs', VehToNet(craneVehicle), objects)
                    startBucketPromptLoop()
                elseif not currentLegsState and craneState then
                    craneState = false
                    craneControlActive = false
                    cranePromptActive = false
                    setCraneControlUiVisible(false)
                    stopRemoteControlPose()
                    TriggerServerEvent('utillitruck:deployLegs', VehToNet(craneVehicle))
                end

                previousLegsState = currentLegsState
            end
            Wait(500)
        end

        cranePromptActive = false
        craneControlActive = false
        setCraneControlUiVisible(false)
        stopRemoteControlPose()
        craneHandlerActive = false
    end)
end

---@diagnostic disable-next-line: param-type-mismatch
AddStateBagChangeHandler('crane', nil, function(bagName, _, value)
    if not value then return end

    local veh = GetEntityFromStateBagName(bagName)
    local ped = NetworkGetEntityFromNetworkId(value[2])

    if ped == cache.ped then return end

    CreateThread(function()
        loadAnimationDicts()

        local time = Entity(ped).state.craneData
        local newtime = time
        local mode = Entity(ped).state.craneMode
        local dict = MOVEMENT[mode].dict
        local anim = MOVEMENT[mode].anim

        while DoesEntityExist(veh) and DoesEntityExist(ped) and Entity(veh).state.crane do
            newtime = Entity(ped).state.craneData
            mode = Entity(ped).state.craneMode
            dict = MOVEMENT[mode].dict
            anim = MOVEMENT[mode].anim

            if not IsEntityPlayingAnim(veh, dict, anim, 3) then
                PlayEntityAnim(veh, anim, dict, 8.0, false, true, false, 0.0, 0)
                Wait(0)
                SetEntityAnimSpeed(veh, dict, anim, 0.0)
                Wait(0)
                SetEntityAnimCurrentTime(veh, dict, anim, newtime[mode])
            end

            if time[mode] ~= newtime[mode] then
                SetEntityAnimCurrentTime(veh, dict, anim, newtime[mode])
            end

            time = newtime
            Wait(0)
        end
    end)
end)


CreateThread(function()
    while true do
        if not craneVehicle or not DoesEntityExist(craneVehicle) then
            local playerCoords = GetEntityCoords(cache.ped)
            local nearby = GetClosestVehicle(playerCoords.x, playerCoords.y, playerCoords.z, 25.0, `utillitruck4`, 70)

            if nearby ~= 0 and DoesEntityExist(nearby) then
                local isCrane = Entity(nearby).state.crane or AreOutriggerLegsDeployed(nearby)
                if isCrane then
                    craneVehicle = nearby
                    craneHandler()
                end
            end
        end

        Wait(1000)
    end
end)

lib.onCache('vehicle', function(vehicle)
    if vehicle and GetEntityModel(vehicle) == `utillitruck4` then
        craneVehicle = vehicle
        craneHandler()
        return
    end

    if craneVehicle and DoesEntityExist(craneVehicle) then
        if Entity(craneVehicle).state.crane or AreOutriggerLegsDeployed(craneVehicle) then
            return
        end
    end

    ---@diagnostic disable-next-line: cast-local-type
    craneVehicle = false
end)
