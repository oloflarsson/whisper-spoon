----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > BEGIN (Version 0.0.1)
----------------------------------------------------------------------------------------------------

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > UTILS
----------------------------------------------------------------------------------------------------

local function whisperSpoonShowAlert(message, duration)
    duration = duration or 5
    hs.alert.show(message, duration)
end

local function whisperSpoonEnsureDirectoryExists(dir)
    os.execute('mkdir -p "' .. dir .. '"')
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > PID UTILS
----------------------------------------------------------------------------------------------------

local function whisperSpoonPidFileWrite(pidFile, pid)
    local f = io.open(pidFile, "w")
    f:write(tostring(pid))
    f:close()
end

local function whisperSpoonPidFileRead(pidFile)
    local f = io.open(pidFile, "r")
    if not f then return nil end
    local content = f:read("*all")
    f:close()
    return content:gsub("^%s*(.-)%s*$", "%1") -- Trim whitespace
end

local function whisperSpoonPidFileDelete(pidFile)
    os.remove(pidFile)
end

local function whisperSpoonPidFileRunning(pidFile)
    local pid = whisperSpoonPidFileRead(pidFile)
    if not pid or not tonumber(pid) then return false end
    local output, _, _, rc = hs.execute("ps -p " .. pid .. " -o pid=")
    return (rc == 0 and output and output:match("%d+"))
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > FILES
----------------------------------------------------------------------------------------------------

local whisperSpoonFileDir = os.getenv("HOME") .. "/.whisperspoon"
local whisperSpoonFilePidSetup = whisperSpoonFileDir .. "/pidsetup.txt"
local whisperSpoonFilePidRecord = whisperSpoonFileDir .. "/pidrecord.txt"
local whisperSpoonFilePidTranscribe = whisperSpoonFileDir .. "/pidtranscribe.txt"
local whisperSpoonFileAudio = whisperSpoonFileDir .. "/audio.wav"
local whisperSpoonFileConfig = whisperSpoonFileDir .. "/config.json"

whisperSpoonEnsureDirectoryExists(whisperSpoonFileDir)

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > SETUP & DEPENDENCIES
----------------------------------------------------------------------------------------------------

local function whisperSpoonIsHomebrewInstalled()
    return hs.fs.attributes("/opt/homebrew/bin/brew") ~= nil
end

local function whisperSpoonIsSoxInstalled()
    return hs.fs.attributes("/opt/homebrew/bin/rec") ~= nil
end

local function whisperSpoonIsSwitchAudioInstalled()
    return hs.fs.attributes("/opt/homebrew/bin/SwitchAudioSource") ~= nil
end

local function whisperSpoonAreAllDependenciesInstalled()
    return whisperSpoonIsHomebrewInstalled() and 
           whisperSpoonIsSoxInstalled() and 
           whisperSpoonIsSwitchAudioInstalled()
end

local function whisperSpoonInstallBrewPackages()
    if not whisperSpoonIsHomebrewInstalled() then
        whisperSpoonShowAlert("Please install Homebrew first", 3)
        return false
    end
    
    if whisperSpoonPidFileRunning(whisperSpoonFilePidSetup) then
        whisperSpoonShowAlert("⏳ Installation already in progress...", 2)
        return false
    end

    whisperSpoonShowAlert("⏳ Installing Packages...", 5)
    
    local task = hs.task.new("/opt/homebrew/bin/brew", function(exitCode, stdOut, stdErr)
        whisperSpoonPidFileDelete(whisperSpoonFilePidSetup)
        whisperSpoonMenubarRebuild()
        
        if exitCode ~= 0 then
            whisperSpoonShowAlert("❌ Installation failed:\n" .. stdErr, 5)
        else
            whisperSpoonShowAlert("✅ Packages installed successfully", 2)
        end
    end, {"install", "sox", "switchaudio-osx"})
    
    local success = task:start()
    if success then
        whisperSpoonPidFileWrite(whisperSpoonFilePidSetup, task:pid())
        whisperSpoonMenubarRebuild()
        return true
    else
        whisperSpoonShowAlert("Failed to start installation", 3)
        return false
    end
end

local function whisperSpoonOpenHomebrewWebsite()
    hs.execute("/usr/bin/open https://brew.sh")
    whisperSpoonShowAlert("Opening Homebrew website...", 2)
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > CONFIG
----------------------------------------------------------------------------------------------------

local function whisperSpoonConfigRead()
    local defaultConfig = {history = {}, apiKey = "", language = ""}
    
    local f = io.open(whisperSpoonFileConfig, "r")
    if not f then 
        return defaultConfig
    end

    local content = f:read("*all")
    f:close()

    if content == nil or content:match("^%s*$") then
        return defaultConfig
    end
    
    local success, config = pcall(hs.json.decode, content)
    if not success or type(config) ~= "table" then
        return defaultConfig
    end
    
    if not config.history then
        config.history = {}
    end
    
    if not config.apiKey then
        config.apiKey = ""
    end
    
    if not config.language then
        config.language = ""
    end
    
    return config
end

local function whisperSpoonConfigWrite(config)
    local f = io.open(whisperSpoonFileConfig, "w")
    f:write(hs.json.encode(config, true))
    f:close()
end

local function whisperSpoonConfigSetApiKey(apiKey)
    local config = whisperSpoonConfigRead()
    config.apiKey = apiKey
    whisperSpoonConfigWrite(config)
end

local function whisperSpoonConfigSetLanguage(language)
    local config = whisperSpoonConfigRead()
    config.language = language
    whisperSpoonConfigWrite(config)
end

local function whisperSpoonConfigHistoryAdd(text)
    if not text or text == "" then return end
    
    local config = whisperSpoonConfigRead()
    
    -- Add new item at the beginning (most recent first)
    table.insert(config.history, 1, text)
    
    -- Trim history to max length
    while #config.history > 10 do
        table.remove(config.history)
    end
    
    whisperSpoonConfigWrite(config)
end

local function whisperSpoonConfigHistoryClear()
    local config = whisperSpoonConfigRead()
    
    config.history = {}
    
    whisperSpoonConfigWrite(config)
end

-- Language data structure with display names and codes
local whisperSpoonLanguages = {
    { code = "", name = "👂 Auto Detect" },
    
    -- Major Global Languages
    { code = "en", name = "🇬🇧 English" },
    { code = "es", name = "🇪🇸 Spanish" },
    { code = "fr", name = "🇫🇷 French" },
    { code = "zh", name = "🇨🇳 Chinese" },
    { code = "ar", name = "🇸🇦 Arabic" },
    { code = "ru", name = "🇷🇺 Russian" },
    
    -- European Languages
    { code = "de", name = "🇩🇪 German" },
    { code = "it", name = "🇮🇹 Italian" },
    { code = "nl", name = "🇳🇱 Dutch" },
    { code = "pt", name = "🇵🇹 Portuguese" },
    { code = "sv", name = "🇸🇪 Swedish" },
    { code = "da", name = "🇩🇰 Danish" },
    { code = "no", name = "🇳🇴 Norwegian" },
    { code = "fi", name = "🇫🇮 Finnish" },
    { code = "pl", name = "🇵🇱 Polish" },
    { code = "uk", name = "🇺🇦 Ukrainian" },
    { code = "cs", name = "🇨🇿 Czech" },
    { code = "el", name = "🇬🇷 Greek" },
    { code = "hu", name = "🇭🇺 Hungarian" },
    { code = "ro", name = "🇷🇴 Romanian" },
    { code = "sk", name = "🇸🇰 Slovak" },
    { code = "bg", name = "🇧🇬 Bulgarian" },
    { code = "ca", name = "🏴 Catalan" },
    
    -- East Asian Languages
    { code = "ja", name = "🇯🇵 Japanese" },
    { code = "ko", name = "🇰🇷 Korean" },
    
    -- South Asian Languages
    { code = "hi", name = "🇮🇳 Hindi" },
    { code = "bn", name = "🇧🇩 Bengali" },
    { code = "ta", name = "🇱🇰 Tamil" },
    { code = "te", name = "🇮🇳 Telugu" },
    { code = "ur", name = "🇵🇰 Urdu" },
    
    -- Southeast Asian Languages
    { code = "id", name = "🇮🇩 Indonesian" },
    { code = "ms", name = "🇲🇾 Malay" },
    { code = "th", name = "🇹🇭 Thai" },
    { code = "vi", name = "🇻🇳 Vietnamese" },
    { code = "tl", name = "🇵🇭 Tagalog" },
    
    -- Middle Eastern Languages
    { code = "tr", name = "🇹🇷 Turkish" },
    { code = "he", name = "🇮🇱 Hebrew" },
    { code = "fa", name = "🇮🇷 Persian" },
    
    -- African Languages
    { code = "sw", name = "🇰🇪 Swahili" },
    { code = "am", name = "🇪🇹 Amharic" },
}

-- Replace the whisperSpoonGetLanguageDisplayName function with this improved version
local function whisperSpoonGetLanguageDisplayName(code)
    for _, lang in ipairs(whisperSpoonLanguages) do
        if lang.code == code then
            return lang.name
        end
    end
    
    -- If we don't find the language in our list, just return the code
    return code
end

local function whisperSpoonSetLanguageAndAlert(languageCode)
    whisperSpoonConfigSetLanguage(languageCode)
    local languageDisplayName = whisperSpoonGetLanguageDisplayName(languageCode)
    whisperSpoonShowAlert("Language set to: " .. languageDisplayName, 2)
    whisperSpoonMenubarRebuild()
end

local function whisperSpoonShowCustomLanguageDialog()
    local buttonPressed, languageCode = hs.dialog.textPrompt(
        "Custom Language", 
        "Enter language code (e.g., fr, de, es, ja):",
        "", 
        "Save", 
        "Cancel"
    )
    
    if buttonPressed == "Save" and languageCode ~= "" then
        whisperSpoonSetLanguageAndAlert(languageCode)
    end
end

local function whisperSpoonGetApiConfig(suppressAlert)
    local config = whisperSpoonConfigRead()
    local apiKey = config.apiKey

    if not apiKey or apiKey == "" then
        local error = "API key is not set"
        if not suppressAlert then
            whisperSpoonShowAlert("API configuration error: " .. error)
        end
        return nil, error
    end

    local apiConfig = {
        apiKey = apiKey,
    }

    if apiKey:match("^sk_") then
        apiConfig.provider = "ElevenLabs"
        apiConfig.apiUrl = "https://api.elevenlabs.io/v1/speech-to-text"
        apiConfig.headers = {
            ["xi-api-key"] = apiKey
        }
        apiConfig.formParams = {
            ["model_id"] = "scribe_v1"
        }
    elseif apiKey:match("^gsk") then
        apiConfig.apiUrl = "https://api.groq.com/openai/v1/audio/transcriptions"
        apiConfig.provider = "Groq"
        apiConfig.headers = {
            ["Authorization"] = "Bearer " .. apiKey
        }
        apiConfig.formParams = {
            ["model"] = "whisper-large-v3",
            ["response_format"] = "json"
        }
    elseif apiKey:match("^sk%-") then
        apiConfig.provider = "OpenAI"
        apiConfig.apiUrl = "https://api.openai.com/v1/audio/transcriptions"
        apiConfig.headers = {
            ["Authorization"] = "Bearer " .. apiKey
        }
        apiConfig.formParams = {
            ["model"] = "whisper-1",
            ["response_format"] = "json"
        }
    else
        local error = "Invalid API key format"
        if not suppressAlert then
            whisperSpoonShowAlert("API configuration error: " .. error)
        end
        return nil, error
    end

    if config.language and config.language ~= "" then
        apiConfig.formParams["language"] = config.language
    end

    return apiConfig
end

local function whisperSpoonShowApiKeyDialog()
    local config = whisperSpoonConfigRead()
    local currentKey = config.apiKey

    local buttonPressed, newKey = hs.dialog.textPrompt("Voicetype API Key", 
        "Supported API Providers:\n\nhttps://elevenlabs.io\n(free for low volumes)\n\nhttps://console.groq.com\n(fast and cheap)\n\nhttps://platform.openai.com\n(well known company)",   
        currentKey, "Save", "Cancel")
    
    if buttonPressed == "Save" then
        whisperSpoonConfigSetApiKey(newKey)
        
        -- Validate the API key after saving
        local apiConfig, error = whisperSpoonGetApiConfig(true)
        if apiConfig then
            whisperSpoonShowAlert("API key updated (" .. apiConfig.provider .. ")", 2)
        else
            whisperSpoonShowAlert("Warning: " .. error, 3)
        end
        
        whisperSpoonMenubarRebuild()
    end
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > TRANSCRIBE
----------------------------------------------------------------------------------------------------

local function whisperSpoonTranscribe(callback)
    local apiConfig, error = whisperSpoonGetApiConfig()
    if not apiConfig then
        callback(nil, error)
        return false
    end
    
    local curlArgs = {
        "-s",
        "-X", "POST",
        "-H", "Content-Type: multipart/form-data"
    }
    
    for key, value in pairs(apiConfig.headers) do
        table.insert(curlArgs, "-H")
        table.insert(curlArgs, key .. ": " .. value)
    end
    
    table.insert(curlArgs, "-F")
    table.insert(curlArgs, "file=@" .. whisperSpoonFileAudio)
    
    for key, value in pairs(apiConfig.formParams) do
        table.insert(curlArgs, "-F")
        table.insert(curlArgs, key .. "=" .. value)
    end
    
    table.insert(curlArgs, apiConfig.apiUrl)
    
    local task = hs.task.new("/usr/bin/curl", function(exitCode, stdOut, stdErr)
        whisperSpoonPidFileDelete(whisperSpoonFilePidTranscribe)
        whisperSpoonMenubarRebuild()
        
        if exitCode ~= 0 then
            callback(nil, "API error: " .. stdErr)
            return
        end
        
        -- Process the response
        local success, decodedResponse = pcall(hs.json.decode, stdOut)
        if success and decodedResponse.text then
            local text = decodedResponse.text:gsub("^%s+", ""):gsub("%s+$", "")
            callback(text, nil)
        else
            callback(nil, "API error: " .. stdOut)
        end
    end, curlArgs)
    
    local success = task:start()
    if success then
        whisperSpoonPidFileWrite(whisperSpoonFilePidTranscribe, task:pid())
        whisperSpoonMenubarRebuild()
        return true
    end
    return false
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > RECORDING
----------------------------------------------------------------------------------------------------

local function whisperSpoonRecordingStart()
    -- Check API configuration first - passing true to suppress alert since we'll handle it here
    local apiConfig, error = whisperSpoonGetApiConfig(true)
    if not apiConfig then
        whisperSpoonShowAlert("API configuration error:\n" .. error, 5)
        return false
    end
    
    local recPath = "/opt/homebrew/bin/rec"
    
    if not hs.fs.attributes(recPath) then
        whisperSpoonShowAlert("Missing rec command!\nInstall with:\n$ brew install sox", 7)
        return false
    end

    local task = hs.task.new(recPath, function() whisperSpoonPidFileDelete(whisperSpoonFilePidRecord) end, {"-c", "1", "-r", "16000", "-b", "16", whisperSpoonFileAudio})

    local success = task:start()
    if success then
        whisperSpoonPidFileWrite(whisperSpoonFilePidRecord, task:pid())
        whisperSpoonMenubarRebuild()
        return true
    end
    return false
end

local function whisperSpoonRecordingStop()
    local pid = whisperSpoonPidFileRead(whisperSpoonFilePidRecord)
    if pid and tonumber(pid) then
        return os.execute("kill -15 " .. pid)
    end
end

local function whisperSpoonRecordingToggle()
    -- Check if transcription is in progress
    if whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) then
        whisperSpoonShowAlert("📝 Transcription in progress, please wait...", 2)
        return
    end

    if not whisperSpoonPidFileRunning(whisperSpoonFilePidRecord) then
        hs.sound.getByName("Morse"):play()
        whisperSpoonRecordingStart()
    else
        hs.sound.getByName("Pop"):play()
        whisperSpoonRecordingStop()
        
        hs.timer.doAfter(0.1, function()
            whisperSpoonTranscribe(function(text, error)
                if error then
                    hs.sound.getByName("Basso"):play()
                    whisperSpoonShowAlert("Transcription error: " .. error, 5)
                else
                    hs.sound.getByName("Purr"):play()
                    if text and text ~= "" then
                        hs.pasteboard.setContents(text)
                        hs.eventtap.keyStroke({"cmd"}, "v")
                        whisperSpoonConfigHistoryAdd(text)
                    end
                end
                whisperSpoonMenubarRebuild()
            end)
        end)
    end
end

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > SHORTCUT
----------------------------------------------------------------------------------------------------

hs.hotkey.bind({"alt"}, "space", whisperSpoonRecordingToggle)

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > MENUBAR
----------------------------------------------------------------------------------------------------

-- Main function to build menus from a declarative structure
local function whisperSpoonMenubarBuildFromStructure(menuStructure)
    local menuItems = {}
    
    for _, item in ipairs(menuStructure) do
        -- Skip items with a condition that evaluates to false
        if item.condition == nil or item.condition() then
            local menuItem = {}
            
            -- Handle title (string or function)
            if type(item.title) == "function" then
                menuItem.title = item.title()
            else
                menuItem.title = item.title
            end
            
            -- Handle disabled state (boolean or function)
            if type(item.disabled) == "function" then
                menuItem.disabled = item.disabled()
            else
                menuItem.disabled = item.disabled
            end
            
            -- Handle function callback
            menuItem.fn = item.fn
            
            -- Handle checked state (boolean or function)
            if item.checked ~= nil then
                if type(item.checked) == "function" then
                    menuItem.checked = item.checked()
                else
                    menuItem.checked = item.checked
                end
            end
            
            -- Handle submenu (array or function returning data structure)
            if item.submenu ~= nil then
                if type(item.submenu) == "function" then
                    -- The function now returns a data structure, not menu items
                    menuItem.menu = whisperSpoonMenubarBuildFromStructure(item.submenu())
                else
                    menuItem.menu = whisperSpoonMenubarBuildFromStructure(item.submenu)
                end
            end
            
            -- Handle tooltip
            if item.tooltip ~= nil then
                menuItem.tooltip = item.tooltip
            end
            
            table.insert(menuItems, menuItem)
        end
    end
    
    return menuItems
end

-- Define the declarative menu structure
local whisperSpoonMenuStructure = {
    -- For setup mode
    setup = {
        { 
            title = "Installation Steps:",
            disabled = true
        },
        { title = "-" },
        {
            title = function() 
                return (whisperSpoonIsHomebrewInstalled() and "✅ " or "") .. "Install Homebrew"
            end,
            disabled = function() return whisperSpoonIsHomebrewInstalled() end,
            fn = function() 
                if not whisperSpoonIsHomebrewInstalled() then 
                    whisperSpoonOpenHomebrewWebsite() 
                end
            end
        },
        {
            title = function()
                local packagesInstalled = whisperSpoonIsSoxInstalled() and whisperSpoonIsSwitchAudioInstalled()
                local installInProgress = whisperSpoonPidFileRunning(whisperSpoonFilePidSetup)
                
                local packageTitle = "Install Packages"
                if packagesInstalled then
                    packageTitle = "✅ " .. packageTitle
                elseif installInProgress then
                    packageTitle = "⏳ Installing Packages..."
                elseif whisperSpoonIsHomebrewInstalled() then
                    packageTitle = "➡️ " .. packageTitle
                end
                
                return packageTitle
            end,
            disabled = function()
                local packagesInstalled = whisperSpoonIsSoxInstalled() and whisperSpoonIsSwitchAudioInstalled()
                local installInProgress = whisperSpoonPidFileRunning(whisperSpoonFilePidSetup)
                return not whisperSpoonIsHomebrewInstalled() or packagesInstalled or installInProgress
            end,
            fn = function()
                local packagesInstalled = whisperSpoonIsSoxInstalled() and whisperSpoonIsSwitchAudioInstalled()
                local installInProgress = whisperSpoonPidFileRunning(whisperSpoonFilePidSetup)
                
                if not whisperSpoonIsHomebrewInstalled() or packagesInstalled or installInProgress then
                    return
                end
                
                whisperSpoonInstallBrewPackages()
            end
        }
    },
    
    -- For normal mode
    normal = {
        {
            title = function()
                if whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) then
                    return "📝 Transcription in progress..."
                elseif whisperSpoonPidFileRunning(whisperSpoonFilePidRecord) then
                    return "Stop Recording (⌥ + Space)"
                else
                    return "Start Recording (⌥ + Space)"
                end
            end,
            disabled = function()
                return whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe)
            end,
            fn = function()
                if not whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) then
                    whisperSpoonRecordingToggle()
                end
            end,
            condition = function()
                return whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) or
                       whisperSpoonPidFileRunning(whisperSpoonFilePidRecord) or
                       whisperSpoonGetApiConfig(true) ~= nil
            end
        },
        {
            title = function()
                local _, error = whisperSpoonGetApiConfig(true)
                return "⚠️ " .. error
            end,
            disabled = true,
            condition = function()
                return whisperSpoonGetApiConfig(true) == nil
            end
        },
        {
            title = function()
                local apiConfig, _ = whisperSpoonGetApiConfig(true)
                local apiKeyText = "Configure API Key"
                if apiConfig then
                    apiKeyText = apiKeyText .. " (" .. apiConfig.provider .. ")"
                end
                return apiKeyText
            end,
            fn = whisperSpoonShowApiKeyDialog
        },
        {
            title = function()
                local currentMicrophone = hs.audiodevice.defaultInputDevice()
                local currentMicrophoneName = currentMicrophone and currentMicrophone:name() or "Unknown"
                return "Microphone (" .. currentMicrophoneName .. ")"
            end,
            submenu = function()
                local submenuStructure = {}
                local inputDevices = hs.audiodevice.allInputDevices()
                local currentDevice = hs.audiodevice.defaultInputDevice()
                
                if #inputDevices == 0 then
                    table.insert(submenuStructure, {
                        title = "No microphone found",
                        disabled = true
                    })
                else
                    for _, device in ipairs(inputDevices) do
                        local deviceName = device:name()
                        local isDefault = (currentDevice and device:uid() == currentDevice:uid())
                        table.insert(submenuStructure, {
                            title = deviceName,
                            checked = isDefault,
                            fn = function()
                                local success = hs.execute("/opt/homebrew/bin/SwitchAudioSource -t input -s \"" .. deviceName .. "\"")
                                if success then
                                    whisperSpoonShowAlert("🎤 " .. deviceName, 3)
                                    whisperSpoonMenubarRebuild()
                                else
                                    whisperSpoonShowAlert("❌ Failed to select: " .. deviceName, 3)
                                end
                            end
                        })
                    end
                end
                
                return submenuStructure
            end
        },
        {
            title = function()
                local config = whisperSpoonConfigRead()
                local currentLanguage = config.language or ""
                local languageDisplayName = whisperSpoonGetLanguageDisplayName(currentLanguage)
                return "Language (" .. languageDisplayName .. ")"
            end,
            submenu = function()
                local config = whisperSpoonConfigRead()
                local currentLanguage = config.language or ""
                
                -- Return a data structure instead of menu items
                local submenuStructure = {}
                
                -- Add language items
                for _, lang in ipairs(whisperSpoonLanguages) do
                    local langCode = lang.code
                    local langName = lang.name
                    table.insert(submenuStructure, {
                        title = function()
                            local displayText = langName
                            if langCode ~= "" then
                                displayText = displayText .. " (" .. langCode .. ")"
                            end
                            return displayText
                        end,
                        checked = function() return currentLanguage == langCode end,
                        fn = function() whisperSpoonSetLanguageAndAlert(langCode) end
                    })
                end
                
                -- Add separator and "Other..." option
                table.insert(submenuStructure, {title = "-"})
                table.insert(submenuStructure, {
                    title = "Other...",
                    fn = whisperSpoonShowCustomLanguageDialog
                })
                
                return submenuStructure
            end
        },
        {
            title = "History",
            submenu = function()
                local config = whisperSpoonConfigRead()
                local submenuStructure = {}
                
                if #config.history > 0 then
                    for i, text in ipairs(config.history) do
                        local historyText = text -- Capture in local variable for closure
                        local displayText = historyText
                        if #displayText > 50 then
                            displayText = displayText:sub(1, 47) .. "..."
                        end
                        
                        table.insert(submenuStructure, {
                            title = displayText,
                            fn = function() 
                                hs.pasteboard.setContents(historyText)
                                whisperSpoonShowAlert("📋 Copied to clipboard", 2)
                            end,
                            tooltip = historyText
                        })
                    end
                    
                    table.insert(submenuStructure, {title = "-"})
                    table.insert(submenuStructure, {
                        title = "Clear History",
                        fn = function()
                            whisperSpoonConfigHistoryClear()
                            whisperSpoonMenubarRebuild()
                            whisperSpoonShowAlert("🗑️ History cleared", 2)
                        end
                    })
                else
                    table.insert(submenuStructure, {
                        title = "No previous transcripts",
                        disabled = true
                    })
                end
                
                return submenuStructure
            end
        }
    }
}

-- Simplified menu creation function that uses the declarative structure
function whisperSpoonMenubarCreateMenuItems()
    if not whisperSpoonAreAllDependenciesInstalled() then
        return whisperSpoonMenubarBuildFromStructure(whisperSpoonMenuStructure.setup)
    else
        return whisperSpoonMenubarBuildFromStructure(whisperSpoonMenuStructure.normal)
    end
end

local whisperSpoonMenubar = hs.menubar.new()
function whisperSpoonMenubarRebuild()
    if whisperSpoonPidFileRunning(whisperSpoonFilePidRecord) then
        whisperSpoonMenubar:setTitle("🔴")
        whisperSpoonMenubar:setIcon(nil)
    elseif whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) then
        whisperSpoonMenubar:setTitle("📝")
        whisperSpoonMenubar:setIcon(nil)
    else
        whisperSpoonMenubar:setTitle(nil)
        whisperSpoonMenubar:setIcon(hs.image.imageFromName("NSAudioInputTemplate"))
    end

    whisperSpoonMenubar:setMenu(whisperSpoonMenubarCreateMenuItems())
end
whisperSpoonMenubarRebuild()

function whisperSpoonMenubarRebuildWatcherCallback(event)
    if event == "dev#" then
        hs.timer.doAfter(2.0, whisperSpoonMenubarRebuild)
    end

    if event == "dIn " or event == "sIn " then
        whisperSpoonMenubarRebuild()
    end
end

hs.audiodevice.watcher.setCallback(whisperSpoonMenubarRebuildWatcherCallback)
hs.audiodevice.watcher.start()

----------------------------------------------------------------------------------------------------
-- WHISPER SPOON > END
----------------------------------------------------------------------------------------------------
