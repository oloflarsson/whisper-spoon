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

local function whisperSpoonTranscribe(callback, customFilePath)
    local apiConfig, error = whisperSpoonGetApiConfig()
    if not apiConfig then
        callback(nil, error)
        return false
    end
    
    local audioFile = customFilePath or whisperSpoonFileAudio
    
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
    table.insert(curlArgs, "file=@" .. audioFile)
    
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
-- WHISPER SPOON > FILE SELECTION
----------------------------------------------------------------------------------------------------

local function whisperSpoonSelectAudioFile()
    -- Check API configuration first
    local apiConfig, error = whisperSpoonGetApiConfig(true)
    if not apiConfig then
        whisperSpoonShowAlert("API configuration error:\n" .. error, 5)
        return false
    end
    
    -- Open file picker dialog with audio file filters
    local selectedFiles = hs.dialog.chooseFileOrFolder(
        "Select Audio File for Transcription", 
        "~/", -- Start in home directory
        true, -- Allow files
        false, -- Don't allow directories
        false, -- Don't allow multiple selections
        {"wav", "mp3", "m4a", "flac", "ogg", "aac"}, -- Audio file extensions
        true -- Resolve aliases
    )
    
    if not selectedFiles then
        -- User canceled
        return
    end
    
    -- Get the file path from the first element
    local filePath = selectedFiles[1]
    
    -- Check if we got a valid file path
    if not filePath then
        whisperSpoonShowAlert("Error: Could not get file path", 3)
        return false
    end
    
    -- Show transcription in progress alert
    whisperSpoonShowAlert("📝 Transcribing file...", 2)
    
    -- Start transcription with the selected file
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
    end, filePath)
    
    return true
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

-- Simplified menu builder that processes menu items directly
local function buildMenu(menuItems)
    local result = {}
    
    for _, item in ipairs(menuItems) do
        -- Skip items with a condition that evaluates to false
        if item.condition ~= nil and not item.condition() then
            goto continue
        end
        
        local menuItem = {}
        
        -- Process title
        menuItem.title = type(item.title) == "function" and item.title() or item.title
        
        -- Process other properties directly
        menuItem.disabled = type(item.disabled) == "function" and item.disabled() or item.disabled
        menuItem.fn = item.fn
        menuItem.tooltip = item.tooltip
        
        -- Handle checked state
        if item.checked ~= nil then
            menuItem.checked = type(item.checked) == "function" and item.checked() or item.checked
        end
        
        -- Process submenu if present
        if item.submenu ~= nil then
            local submenuItems = type(item.submenu) == "function" and item.submenu() or item.submenu
            menuItem.menu = buildMenu(submenuItems)
        end
        
        table.insert(result, menuItem)
        
        ::continue::
    end
    
    return result
end

-- Menu definitions - separated from the rendering logic
local menuDefinitions = {
    -- Setup mode menu items
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
                
                if packagesInstalled then
                    return "✅ Install Packages"
                elseif installInProgress then
                    return "⏳ Installing Packages..."
                elseif whisperSpoonIsHomebrewInstalled() then
                    return "➡️ Install Packages"
                else
                    return "Install Packages"
                end
            end,
            disabled = function()
                return not whisperSpoonIsHomebrewInstalled() or 
                       (whisperSpoonIsSoxInstalled() and whisperSpoonIsSwitchAudioInstalled()) or 
                       whisperSpoonPidFileRunning(whisperSpoonFilePidSetup)
            end,
            fn = function()
                if not whisperSpoonIsHomebrewInstalled() or 
                   (whisperSpoonIsSoxInstalled() and whisperSpoonIsSwitchAudioInstalled()) or 
                   whisperSpoonPidFileRunning(whisperSpoonFilePidSetup) then
                    return
                end
                
                whisperSpoonInstallBrewPackages()
            end
        }
    },
    
    -- Normal mode menu items
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
            disabled = function() return whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) end,
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
            title = "Transcribe File...",
            fn = whisperSpoonSelectAudioFile,
            disabled = function() return whisperSpoonPidFileRunning(whisperSpoonFilePidTranscribe) end,
            condition = function() return whisperSpoonGetApiConfig(true) ~= nil end
        },
        {
            title = function()
                local _, error = whisperSpoonGetApiConfig(true)
                return "⚠️ " .. error
            end,
            disabled = true,
            condition = function() return whisperSpoonGetApiConfig(true) == nil end
        },
        {
            title = function()
                local apiConfig = whisperSpoonGetApiConfig(true)
                return "Configure API Key" .. (apiConfig and " (" .. apiConfig.provider .. ")" or "")
            end,
            fn = whisperSpoonShowApiKeyDialog
        },
        -- Microphone menu item
        {
            title = function()
                local currentMic = hs.audiodevice.defaultInputDevice()
                return "Microphone (" .. (currentMic and currentMic:name() or "Unknown") .. ")"
            end,
            submenu = function()
                local items = {}
                local inputDevices = hs.audiodevice.allInputDevices()
                local currentDevice = hs.audiodevice.defaultInputDevice()
                
                if #inputDevices == 0 then
                    table.insert(items, {
                        title = "No microphone found",
                        disabled = true
                    })
                else
                    for _, device in ipairs(inputDevices) do
                        local deviceName = device:name()
                        table.insert(items, {
                            title = deviceName,
                            checked = currentDevice and device:uid() == currentDevice:uid(),
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
                
                return items
            end
        },
        -- Language menu item
        {
            title = function()
                local config = whisperSpoonConfigRead()
                local langName = whisperSpoonGetLanguageDisplayName(config.language or "")
                return "Language (" .. langName .. ")"
            end,
            submenu = function()
                local config = whisperSpoonConfigRead()
                local currentLang = config.language or ""
                local items = {}
                
                for _, lang in ipairs(whisperSpoonLanguages) do
                    table.insert(items, {
                        title = lang.name .. (lang.code ~= "" and " (" .. lang.code .. ")" or ""),
                        checked = currentLang == lang.code,
                        fn = function() whisperSpoonSetLanguageAndAlert(lang.code) end
                    })
                end
                
                table.insert(items, {title = "-"})
                table.insert(items, {
                    title = "Other...",
                    fn = whisperSpoonShowCustomLanguageDialog
                })
                
                return items
            end
        },
        -- History menu item
        {
            title = "History",
            submenu = function()
                local config = whisperSpoonConfigRead()
                local items = {}
                
                if #config.history > 0 then
                    for _, text in ipairs(config.history) do
                        local displayText = #text > 50 and text:sub(1, 47) .. "..." or text
                        table.insert(items, {
                            title = displayText,
                            fn = function() 
                                hs.pasteboard.setContents(text)
                                whisperSpoonShowAlert("📋 Copied to clipboard", 2)
                            end,
                            tooltip = text
                        })
                    end
                    
                    table.insert(items, {title = "-"})
                    table.insert(items, {
                        title = "Clear History",
                        fn = function()
                            whisperSpoonConfigHistoryClear()
                            whisperSpoonMenubarRebuild()
                            whisperSpoonShowAlert("🗑️ History cleared", 2)
                        end
                    })
                else
                    table.insert(items, {
                        title = "No previous transcripts",
                        disabled = true
                    })
                end
                
                return items
            end
        }
    }
}

-- Simplified menu creation function
function whisperSpoonMenubarCreateMenuItems()
    local menuType = whisperSpoonAreAllDependenciesInstalled() and "normal" or "setup"
    return buildMenu(menuDefinitions[menuType])
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
