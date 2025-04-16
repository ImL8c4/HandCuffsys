-- Configurazione del sistema wanted
local WantedSystem = {
    -- Items illegali
    IllegalItems = {
        "Pistola", "Coltello", "Droga", "Soldi_Falsi", "Grimaldello" -- aggiungi gli item che vuoi rendere illegali
    },
    
    -- Azioni che incrementano il livello di ricercato
    WantedActions = {
        Rapina = 0.5,
        Aggressione = 0.25,
        Evasione = 1.0,
        FurtoDiVeicoli = 0.75
    },
    
    -- Impostazioni generali
    MaxWantedLevel = 5,              -- Livello massimo di ricercato
    WantedDecayTime = 60,            -- Tempo in secondi per diminuire di 0.5 stellette
    NoItemsDecayMultiplier = 1,      -- Moltiplicatore di decay quando non ha oggetti illegali
    IllegalItemsDecayMultiplier = 0, -- Moltiplicatore di decay quando ha oggetti illegali (0 = nessun decay)
    
    -- Tempi di carcere (in secondi) basati sul livello di ricercato
    JailTimes = {
        [0.5] = 30,   -- 0.5 stellette = 30 secondi
        [1.0] = 60,   -- 1 stelletta = 1 minuto
        [1.5] = 90,   -- 1.5 stellette = 1 minuto e mezzo
        [2.0] = 120,  -- 2 stellette = 2 minuti
        [2.5] = 150,  -- 2.5 stellette = 2 minuti e mezzo
        [3.0] = 180,  -- 3 stellette = 3 minuti
        [3.5] = 210,  -- 3.5 stellette = 3 minuti e mezzo
        [4.0] = 240,  -- 4 stellette = 4 minuti
        [4.5] = 270,  -- 4.5 stellette = 4 minuti e mezzo
        [5.0] = 300   -- 5 stellette = 5 minuti
    }
}

-- Tabella per tenere traccia dei giocatori ricercati
local WantedPlayers = {}

-- Tabella per tenere traccia dei timer di decay per ogni giocatore
local DecayTimers = {}

-- Funzione per controllare se un oggetto è illegale
local function isItemIllegal(itemName)
    for _, illegalItem in ipairs(WantedSystem.IllegalItems) do
        if itemName == illegalItem then
            return true
        end
    end
    return false
end

-- Funzione per controllare se un giocatore possiede oggetti illegali
local function hasIllegalItems(player)
    -- Controlla sia l'inventario che il backpack
    local itemsToCheck = {}
    
    -- Aggiungi tutti gli strumenti dal character
    if player.Character then
        for _, tool in pairs(player.Character:GetChildren()) do
            if tool:IsA("Tool") then
                table.insert(itemsToCheck, tool)
            end
        end
    end
    
    -- Aggiungi tutti gli strumenti dal backpack
    for _, tool in pairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            table.insert(itemsToCheck, tool)
        end
    end
    
    -- Controlla se qualsiasi item è illegale
    for _, tool in ipairs(itemsToCheck) do
        if isItemIllegal(tool.Name) then
            return true
        end
    end
    
    return false
end

-- Funzione per impostare un giocatore come ricercato o aggiornare il suo livello
local function setPlayerWanted(player, reason, addLevel)
    -- Crea o aggiorna lo stato di ricercato del giocatore
    if not WantedPlayers[player.Name] then
        WantedPlayers[player.Name] = {
            level = 0,
            reason = {},
            lastUpdateTime = os.time()
        }
    end
    
    -- Aggiungi la nuova ragione all'elenco
    if reason then
        table.insert(WantedPlayers[player.Name].reason, reason)
    end
    
    -- Aggiorna il livello di ricercato, assicurandosi che rimanga tra 0 e MaxWantedLevel
    if addLevel then
        WantedPlayers[player.Name].level = math.min(
            WantedSystem.MaxWantedLevel,
            WantedPlayers[player.Name].level + addLevel
        )
    end
    
    -- Aggiorna il timestamp dell'ultimo aggiornamento
    WantedPlayers[player.Name].lastUpdateTime = os.time()
    
    -- Aggiorna lo stato visuale del giocatore (UI, effetti, ecc.)
    updatePlayerWantedUI(player)
    
    -- Avvia o resetta il timer di decay
    startDecayTimer(player)
    
    -- Notifica al giocatore il suo nuovo stato di ricercato
    GlobalEvents.RemoteEvent:FireClient(player, "Notification", "Sei ricercato con un livello " .. tostring(WantedPlayers[player.Name].level) .. " stelle!")
    
    -- Notifica anche ai poliziotti
    notifyPoliceAboutWanted(player)
    
    return WantedPlayers[player.Name].level
end

-- Aggiorna l'UI del giocatore per mostrare il suo stato di ricercato
local function updatePlayerWantedUI(player)
    if WantedPlayers[player.Name] then
        -- Invia l'informazione sul livello di ricercato al client
        GlobalEvents.RemoteEvent:FireClient(player, "UpdateWantedLevel", WantedPlayers[player.Name].level)
        
        -- Qui puoi anche aggiungere un effetto visivo sopra il giocatore
        -- Ad esempio, un billboard gui con stelle, o un particella, ecc.
    else
        -- Rimuovi qualsiasi indicazione di ricercato
        GlobalEvents.RemoteEvent:FireClient(player, "UpdateWantedLevel", 0)
    end
end

-- Notifica i poliziotti riguardo un nuovo giocatore ricercato
local function notifyPoliceAboutWanted(criminal)
    for _, player in pairs(game.Players:GetPlayers()) do
        for i, v in pairs(Settings.CanHandcuffPlayers) do
            if i == player.Team then
                -- Questo è un poliziotto, notificalo
                GlobalEvents.RemoteEvent:FireClient(player, "WantedPlayerAlert", criminal.Name, WantedPlayers[criminal.Name].level)
                break
            end
        end
    end
end

-- Funzione per avviare o resettare il timer di decay per un giocatore
local function startDecayTimer(player)
    -- Ferma il timer precedente se esiste
    if DecayTimers[player.Name] then
        task.cancel(DecayTimers[player.Name])
    end
    
    -- Avvia un nuovo timer
    DecayTimers[player.Name] = task.spawn(function()
        while true do
            task.wait(WantedSystem.WantedDecayTime)
            
            if WantedPlayers[player.Name] and WantedPlayers[player.Name].level > 0 then
                -- Controlla se il giocatore ha oggetti illegali
                local decayMultiplier = hasIllegalItems(player) 
                    and WantedSystem.IllegalItemsDecayMultiplier 
                    or WantedSystem.NoItemsDecayMultiplier
                
                -- Se il moltiplicatore è 0, non fare nulla
                if decayMultiplier > 0 then
                    -- Riduci il livello di ricercato
                    WantedPlayers[player.Name].level = math.max(
                        0,
                        WantedPlayers[player.Name].level - (0.5 * decayMultiplier)
                    )
                    
                    -- Aggiorna l'UI
                    updatePlayerWantedUI(player)
                    
                    -- Se il livello è sceso a 0, rimuovi lo stato di ricercato
                    if WantedPlayers[player.Name].level == 0 then
                        WantedPlayers[player.Name] = nil
                        task.cancel(DecayTimers[player.Name])
                        DecayTimers[player.Name] = nil
                        
                        -- Notifica il giocatore
                        GlobalEvents.RemoteEvent:FireClient(player, "Notification", "Non sei più ricercato!")
                        break
                    end
                end
            else
                -- Il giocatore non è più ricercato, pulisci
                task.cancel(DecayTimers[player.Name])
                DecayTimers[player.Name] = nil
                break
            end
        end
    end)
end

-- Funzione per ottenere il tempo di carcere in base al livello di ricercato
local function getJailTimeFromWantedLevel(level)
    local roundedLevel = math.floor(level * 2) / 2  -- Arrotonda a 0.5 più vicino
    return WantedSystem.JailTimes[roundedLevel] or 30  -- Default a 30 secondi se non trovato
end

-- Controllo degli oggetti illegali all'aggiunta di strumenti all'inventario
local function checkPlayerTools(player, tool)
    if isItemIllegal(tool.Name) then
        -- Il giocatore ha ottenuto un oggetto illegale, impostalo come ricercato
        setPlayerWanted(
            player, 
            "Possesso di " .. tool.Name .. " (oggetto illegale)",
            0.5  -- Aggiungi 0.5 al livello di ricercato
        )
    end
end

-- Funzione per controllare se un giocatore è ricercato
local function isPlayerWanted(player)
    return WantedPlayers[player.Name] ~= nil
end

-- Funzione per ottenere il livello di ricercato di un giocatore
local function getPlayerWantedLevel(player)
    if WantedPlayers[player.Name] then
        return WantedPlayers[player.Name].level
    end
    return 0
end

-- Funzione per registrare un'azione che aumenta il livello di ricercato
local function recordWantedAction(player, actionType, customReason)
    local actionValue = WantedSystem.WantedActions[actionType]
    
    if actionValue then
        local reason = customReason or "Ha commesso un'azione di tipo: " .. actionType
        setPlayerWanted(player, reason, actionValue)
    end
end

-- Modifiche al sistema di arresto esistente

-- Modificare la funzione di arresto esistente per utilizzare il wanted level
local function modifyArrestFunction()
    -- Questo sovrascriverà l'evento "Arrest" nel tuo codice originale
    -- Aggiungi questo all'interno del tuo handler degli eventi RemoteEvent
    
    -- Nell'evento "Arrest", aggiungi:
    if EventType == "Arrest" then
        if checkPlayer(player.Character.TargetObject.Value) then
            local criminal = player.Character.TargetObject.Value
            
            -- Controlla se il criminale è ricercato
            local wantedLevel = getPlayerWantedLevel(criminal)
            local isWanted = wantedLevel > 0
            
            -- Determina il tempo di arresto in base al livello di ricercato
            local arrestTime = isWanted 
                ? getJailTimeFromWantedLevel(wantedLevel) 
                : (Value1 or DEFAULT_ARREST_TIME)
            
            -- Determina la ragione dell'arresto
            local arrestReason
            if isWanted and WantedPlayers[criminal.Name] and #WantedPlayers[criminal.Name].reason > 0 then
                arrestReason = table.concat(WantedPlayers[criminal.Name].reason, ", ")
            else
                arrestReason = Value3 or DEFAULT_ARREST_REASON
            end
            
            -- Procedi con l'arresto usando il nuovo tempo e motivo
            -- (Il resto del codice di arresto rimane uguale)
            
            -- Dopo l'arresto, rimuovi lo stato di ricercato
            if isWanted then
                WantedPlayers[criminal.Name] = nil
                if DecayTimers[criminal.Name] then
                    task.cancel(DecayTimers[criminal.Name])
                    DecayTimers[criminal.Name] = nil
                end
                updatePlayerWantedUI(criminal)
            end
        end
    end
end

-- Aggiungi eventi per le azioni criminali
local function addCriminalActionEvents()
    -- Questo può essere integrato nel tuo sistema di eventi esistente
    
    -- Esempio: Aggiungi un nuovo tipo di evento per le rapine
    if EventType == "Robbery" then
        -- Registra l'azione di rapina per il giocatore
        recordWantedAction(player, "Rapina", "Ha rapinato " .. Value1)
    elseif EventType == "VehicleTheft" then
        -- Registra il furto di veicoli
        recordWantedAction(player, "FurtoDiVeicoli", "Ha rubato un veicolo")
    elseif EventType == "PlayerAssault" then
        -- Registra un'aggressione ad un altro giocatore
        recordWantedAction(player, "Aggressione", "Ha aggredito " .. Value1.Name)
    elseif EventType == "JailEscape" then
        -- Registra un'evasione dal carcere
        recordWantedAction(player, "Evasione", "È evaso dal carcere")
    end
end

-- Inizializzazione per ogni giocatore
local function initializePlayerWantedSystem(player)
    -- Controlla gli strumenti all'inizio
    if player.Character then
        for _, tool in pairs(player.Character:GetChildren()) do
            if tool:IsA("Tool") then
                checkPlayerTools(player, tool)
            end
        end
    end
    
    for _, tool in pairs(player.Backpack:GetChildren()) do
        if tool:IsA("Tool") then
            checkPlayerTools(player, tool)
        end
    end
    
    -- Monitora nuovi strumenti aggiunti al backpack
    player.Backpack.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            checkPlayerTools(player, child)
        end
    end)
    
    -- Monitora nuovi strumenti equipaggiati
    player.CharacterAdded:Connect(function(character)
        character.ChildAdded:Connect(function(child)
            if child:IsA("Tool") then
                checkPlayerTools(player, child)
            end
        end)
    end)
}

-- Cleanup quando un giocatore esce
Players.PlayerRemoving:Connect(function(player)
    -- Pulisci i dati e i timer per questo giocatore
    if WantedPlayers[player.Name] then
        WantedPlayers[player.Name] = nil
    end
    
    if DecayTimers[player.Name] then
        task.cancel(DecayTimers[player.Name])
        DecayTimers[player.Name] = nil
    end
end)

-- Inizializza il sistema per tutti i giocatori esistenti
for _, player in pairs(Players:GetPlayers()) do
    initializePlayerWantedSystem(player)
end

-- Connessione per i nuovi giocatori
Players.PlayerAdded:Connect(initializePlayerWantedSystem)

-- Funzioni per l'interfaccia utente lato client
-- Queste funzioni dovrebbero essere chiamate dal client tramite script locali

-- GUI per mostrare le stellette di ricercato
local function createWantedGUI()
    -- Questo sarebbe un GUI lato client che mostra il livello di ricercato
    -- del giocatore con stelle o un altro indicatore visivo.
    
    -- Esempio di come potrebbe apparire lo script locale:
    [[
    local player = game.Players.LocalPlayer
    local wantedFrame = script.Parent
    
    -- Crea stelle per indicare il livello di ricercato
    local stars = {}
    for i = 1, 5 do
        local star = Instance.new("ImageLabel")
        star.Size = UDim2.new(0, 20, 0, 20)
        star.Position = UDim2.new(0, (i-1) * 22, 0, 0)
        star.Image = "rbxassetid://wantedStarImage" -- Sostituisci con l'ID della tua immagine
        star.Parent = wantedFrame
        star.Visible = false
        stars[i] = star
    end
    
    -- Funzione per aggiornare la visualizzazione delle stelle
    local function updateStars(level)
        local fullStars = math.floor(level)
        local hasHalfStar = (level - fullStars) >= 0.5
        
        for i = 1, 5 do
            if i <= fullStars then
                stars[i].Visible = true
                stars[i].Image = "rbxassetid://fullStarImage" -- Stella piena
            elseif i == fullStars + 1 and hasHalfStar then
                stars[i].Visible = true
                stars[i].Image = "rbxassetid://halfStarImage" -- Mezza stella
            else
                stars[i].Visible = false
            end
        end
    end
    
    -- Ascolta eventi dal server per aggiornare il livello di ricercato
    game.ReplicatedStorage.GlobalEvents.RemoteEvent.OnClientEvent:Connect(function(eventType, ...)
        if eventType == "UpdateWantedLevel" then
            local level = ...
            updateStars(level)
            wantedFrame.Visible = level > 0
        end
    end)
    ]]
end

-- Integrazione con il sistema di arresti esistente
-- Modificare l'evento "RemoteEvent" OnServerEvent:Connect per includere le azioni legate al sistema wanted
uxpRP.GlobalEvents.RemoteEvent.OnServerEvent:Connect(function(player, EventType, Value1, Value2, Value3)
    -- Qui andrebbero le gestioni di eventi esistenti
    
    -- Aggiungi nuovi tipi di eventi per il sistema wanted
    if EventType == "Robbery" then
        recordWantedAction(player, "Rapina", "Ha rapinato " .. tostring(Value1))
    elseif EventType == "VehicleTheft" then
        recordWantedAction(player, "FurtoDiVeicoli", "Ha rubato un veicolo")
    elseif EventType == "PlayerAssault" then
        local targetPlayer = (typeof(Value1) == "Instance" and Value1:IsA("Player")) and Value1 or Players:FindFirstChild(tostring(Value1))
        if targetPlayer then
            recordWantedAction(player, "Aggressione", "Ha aggredito " .. targetPlayer.Name)
        end
    elseif EventType == "JailEscape" then
        recordWantedAction(player, "Evasione", "È evaso dal carcere")
    end
    
    -- Gestione dell'arresto con sistema wanted
    if EventType == "Arrest" then
        if checkPlayer(player.Character.TargetObject.Value) then
            local criminal = player.Character.TargetObject.Value
            
            -- Verifica se il criminale è ricercato
            local wantedLevel = getPlayerWantedLevel(criminal)
            
            -- Determina il tempo di arresto in base al livello di ricercato
            local arrestTime
            if wantedLevel > 0 then
                arrestTime = getJailTimeFromWantedLevel(wantedLevel)
            else
                arrestTime = Value1 or DEFAULT_ARREST_TIME
            end
            
            -- Imposta Value1 con il nuovo tempo di arresto
            Value1 = arrestTime
            
            -- Imposta una ragione personalizzata se il giocatore è ricercato
            if wantedLevel > 0 and WantedPlayers[criminal.Name] and #WantedPlayers[criminal.Name].reason > 0 then
                Value3 = "Ricercato (Stellette: " .. wantedLevel .. "): " .. table.concat(WantedPlayers[criminal.Name].reason, ", ")
            end
            
            -- Dopo l'arresto, rimuovi lo stato di ricercato
            if wantedLevel > 0 then
                WantedPlayers[criminal.Name] = nil
                if DecayTimers[criminal.Name] then
                    task.cancel(DecayTimers[criminal.Name])
                    DecayTimers[criminal.Name] = nil
                end
                updatePlayerWantedUI(criminal)
            end
        end
    end
    
    -- Qui continuerebbe il codice originale per gestire gli altri tipi di evento
end)

-- Esportazione delle funzioni pubbliche
return {
    isPlayerWanted = isPlayerWanted,
    getPlayerWantedLevel = getPlayerWantedLevel,
    recordWantedAction = recordWantedAction,
    setPlayerWanted = setPlayerWanted,
    hasIllegalItems = hasIllegalItems
}