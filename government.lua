local imgui = require("imgui")
local inicfg = require("inicfg")
require('lib.moonloader')
local dlstatus = require('lib.moonloader').download_status
local encoding = require("encoding")
local sampev = require('lib.samp.events')
local vk = require 'vkeys'

encoding.default = "CP1251"
local u8 = encoding.UTF8

update_state = false -- Если переменная == true, значит начнётся обновление.
update_found = false -- Если будет true, будет доступна команда /update.

local script_vers = 1.5
local script_vers_text = "v1.5" -- Название нашей версии. В будущем будем её выводить ползователю.

local update_url = 'https://raw.githubusercontent.com/sergeykonar/arp-government/refs/heads/main/config/gov_update.ini' -- Путь к ini файлу. Позже нам понадобиться.
local update_path = getWorkingDirectory() .. "\\config\\gov_update.ini"


local script_url = '' -- Путь скрипту.
local script_path = thisScript().path

local blackListPath = getWorkingDirectory().."\\config\\blue_blacklist.txt"

function file_exists(file_path)
    local file = io.open(file_path, "r") -- пытаемся открыть файл на чтение
    if file then
        file:close()  -- если файл существует, закрываем его
        return true
    else
        return false  -- файл не существует
    end
end

function loadBlacklist()
    local list = {}
    local file = io.open(blackListPath, "r")

    if file then
        for line in file:lines() do
            local nick = line:match("^%s*(.-)%s*$") -- trim
            if nick ~= "" then
                table.insert(list, nick)
            end
        end
        file:close()
    end

    return list
end


function check_update(onDone)
    downloadUrlToFile(update_url, update_path, function(id, status)
        if status ~= dlstatus.STATUSEX_ENDDOWNLOAD then
            return
        end

        -- Файл не загрузился
        if not file_exists(update_path) then
            sampAddChatMessage("{FF0000}Ошибка: файл gov_update.ini не загружен!", -1)
            if onDone then onDone() end
            return
        end

        local updateIni = inicfg.load(nil, update_path)

        if not updateIni then
            sampAddChatMessage("{FF0000}Ошибка чтения gov_update.ini!", -1)
            if onDone then onDone() end
            return
        end

        if not updateIni.info or not updateIni.info.vers then
            sampAddChatMessage("{FF0000}Неверный формат gov_update.ini!", -1)
            if onDone then onDone() end
            return
        end

        -- Проверка версии
        if tonumber(updateIni.info.vers) > script_vers then
            sampAddChatMessage("{FFFFFF}Найдена новая версия: {32CD32}"..updateIni.info.vers_text, -1)
            sampAddChatMessage("{FFFFFF}Введите {32CD32}/update {FFFFFF}для обновления.", -1)

            update_found = true

            sampRegisterChatCommand('update', function()
                update_state = true
                sampAddChatMessage("{32CD32}Начинаю обновление...", -1)

                downloadUrlToFile(updateIni.info.blue_blacklist, blackListPath, function(_, st)
                    if st == dlstatus.STATUSEX_ENDDOWNLOAD then
                        sampAddChatMessage("{32CD32}Черный список обновлен.", -1)
                    end
                end)
                downloadUrlToFile(updateIni.info.script_url, script_path, function(_, st)
                    if st == dlstatus.STATUSEX_ENDDOWNLOAD then
                        sampAddChatMessage("{32CD32}Скрипт успешно обновлён! Перезагрузите его.", -1)
                    end
                end)
            end)
        else
            -- sampAddChatMessage("{FFFFFF}Обновлений нет.", -1)
        end

        -- ?? вызываем callback ПОСЛЕ завершения
        if onDone then onDone() end
    end)
end



-- Конфиг по умолчанию
local defaultConfig = {
    settings = {
        rank = 1,
        department = "LS",
        bind =  encodeJson({ 77 })
    }
}

local Color = {
    WHITE = "{FFFFFF}",
    RED = "{FF0000}",
    GREEN = "{00FF00}",
    ORANGE = "{FFA500}"
}


local iniFilePath = "gov_config.ini"
local gnewsFilePath = "gnews_config.ini"

local main_window_state = imgui.ImBool(false)
local license_window = imgui.ImBool(false)
local layer_window = imgui.ImBool(false)
local invite_window = imgui.ImBool(false)

-- Таблица соответствий
local department_map = {
    ["LS"] = u8"Мэрия ЛС",
    ["LV"] = u8"Мэрия ЛВ",
    ["SF"] = u8"Мэрия СФ"
}

local department_reverse_map = {
    [u8"Мэрия ЛС"] = "LS",
    [u8"Мэрия ЛВ"] = "LV",
    [u8"Мэрия СФ"] = "SF"
}

-- Загружаем или создаём конфиг
local config = inicfg.load(defaultConfig, iniFilePath)
inicfg.save(config, iniFilePath) -- сохраняем при первом запуске

-- Функция split
function split(str, sep)
    local t = {}
    for s in string.gmatch(str, "([^"..sep.."]+)") do
        table.insert(t, s)
    end
    return t
end

-- Теперь уже загружаем gnews
local defaultGnewsConfig = {
    news = {}
}

local gnewsCfg = inicfg.load(defaultGnewsConfig, gnewsFilePath)
inicfg.save(gnewsCfg, gnewsFilePath)

local gnews = {}
local gnewsBuffers = {}

local keys = {}
for k, _ in pairs(gnewsCfg.news) do
    table.insert(keys, k)
end
table.sort(keys, function(a, b)
    local na = tonumber(a:match("%d+")) or 0
    local nb = tonumber(b:match("%d+")) or 0
    return na < nb
end)

-- Проходим в отсортированном порядке
for _, k in ipairs(keys) do
    local line = gnewsCfg.news[k]
    local lines = split(line, "|")
    table.insert(gnews, lines)

    local bufferLines = {}
    for _, l in ipairs(lines) do
        table.insert(bufferLines, imgui.ImBuffer(l or "", 256))
    end
    table.insert(gnewsBuffers, bufferLines)
end

-- Названия рангов
local rank_names = {
    u8"Охранник",
    u8"Начальник охраны",
    u8"Секретарь",
    u8"Старший секретарь",
    u8"Адвокат",
    u8"Лицензёр",
    u8"Старший лицензёр",
    u8"Дпетутат",
    u8"Зам. мэра",
    u8"Мэр"
}

-- Подразделения (отображаемые в интерфейсе)
local departments = { u8"Мэрия ЛС", u8"Мэрия ЛВ", u8"Мэрия СФ" }

-- Определяем индекс текущего департамента
local department_index = 1
for i, name in ipairs(departments) do
    if name == department_map[config.settings.department] then
        department_index = i
        break
    end
end

local playerLicenses = {}

local waitingForJailTime = false
local jailTimeReceived = false
local isWaitingResponse = false
local isWaitingForLic = false
local releasePrice = nil

local targetName = nil
local targetRPName = nil
local isTargetNameRP = nil
local targetId = nil
local exampleHotKey;

-- ImGui переменные
local rank_selected = imgui.ImInt(config.settings.rank - 1)
local department_selected = imgui.ImInt(department_index - 1)

-- Основное окно ImGui
-- текущее состояние вкладки
local current_tab = 1 -- 1 = Настройки, 2 = Помощь

local default_color = imgui.GetStyleColorVec4(imgui.Col.Button)
local inactive_color = imgui.ImVec4(0.5, 0.5, 0.5, 1.0) -- серый

function imgui.OnDrawFrame()

    if main_window_state.v then
        imgui.SetNextWindowSize(imgui.ImVec2(550, 250), imgui.Cond.FirstUseEver) 
        imgui.Begin(u8'Настройки Government Script', main_window_state)

        -- Левая панель с кнопками
        imgui.BeginChild("TabsPanel", imgui.ImVec2(150, 0), true)
        if current_tab == 1 then
            imgui.PushStyleColor(imgui.Col.Button, default_color)
        else
            imgui.PushStyleColor(imgui.Col.Button, inactive_color)
        end
        if imgui.Button(u8"Настройки", imgui.ImVec2(-1, 30)) then current_tab = 1 end
        imgui.PopStyleColor()
        imgui.Spacing()
        if current_tab == 2 then
            imgui.PushStyleColor(imgui.Col.Button, default_color)
        else
            imgui.PushStyleColor(imgui.Col.Button, inactive_color)
        end
    

        if imgui.Button(u8"Помощь", imgui.ImVec2(-1, 30)) then current_tab = 2 end
        imgui.PopStyleColor()

        -- Гос. новости (только для ранга 10)
        if getRang() == 10 then
            if current_tab == 3 then
                imgui.PushStyleColor(imgui.Col.Button, default_color)
            else
                imgui.PushStyleColor(imgui.Col.Button, inactive_color)
            end
            if imgui.Button(u8"Гос. новости", imgui.ImVec2(-1, 30)) then current_tab = 3 end
            imgui.PopStyleColor()
        end
        

        imgui.EndChild()

        imgui.SameLine() -- чтобы правая панель была справа

        -- Правая панель с содержимым вкладки
        imgui.BeginChild("ContentPanel", imgui.ImVec2(0, 0), false)
        if current_tab == 1 then
            imgui.Text(u8"Кнопка действия:")
            imgui.SameLine()
            if exampleHotKey:ShowHotKey("OpenMenu", imgui.ImVec2(150, 30)) then
                config.settings.bind = encodeJson(exampleHotKey:GetHotKey())
                inicfg.save(config, iniFilePath)
            end


            imgui.Text(u8"Ваше имя: "..getMyName())
            imgui.Text(u8"Выберите ваш ранг в правительстве:")
            imgui.Combo(u8"Ранг", rank_selected, rank_names, #rank_names)
            imgui.Text(u8"Выберите подразделение правительства:")
            imgui.Combo(u8"Подразделение", department_selected, departments, #departments)
            if imgui.Button(u8"Сохранить настройки", imgui.ImVec2(200, 30)) then
                config.settings.rank = rank_selected.v + 1
                local dep_name = departments[department_selected.v + 1]
                config.settings.department = department_reverse_map[dep_name] or "LS"
                inicfg.save(config, iniFilePath)
                sampAddChatMessage("{00FF00}[GovPanel]: Настройки успешно сохранены!", -1)
            end
            imgui.SameLine()
            if imgui.Button(u8"Закрыть", imgui.ImVec2(150, 30)) then
                main_window_state.v = false
            end
        elseif current_tab == 2 then
            local key = HOTKEY.getKeysText('OpenMenu')
            imgui.Text(u8"Помощь по скрипту:\n\n• Выберите свой ранг и подразделение.\n• Нажмите 'Сохранить настройки' чтобы применить изменения.\n• Выберите клаившу для взаимодействия с игроком\n• Наведите на игрока и нажмите ПКМ + "..key.."\n• Используйте эту вкладку, чтобы ознакомиться с инструкцией.")
        elseif current_tab == 3 then
            imgui.BeginChild("GNewsPanel", imgui.ImVec2(0, 0), true)

            local toDelete = nil
            local toAdd = false
            local toAddLine = nil

            for i, newsLines in ipairs(gnewsBuffers) do
                imgui.Text(u8("Гос. новость №" .. i))
                for j, buf in ipairs(newsLines) do
                    if imgui.InputText("##news_" .. tostring(newsLines) .. "_line_" .. j, buf) then
                        gnews[i][j] = buf.v or ""  -- сохраняем строку
                    end
                end

                if imgui.Button(u8("Добавить строку##add_line_" .. tostring(newsLines))) then
                    toAddLine = i
                end

                if imgui.Button(u8("Удалить новость##delete_news_" .. tostring(newsLines))) then
                    toDelete = i
                end

                imgui.Separator()
            end
        
            if imgui.Button(u8("Добавить новость"), imgui.ImVec2(-1, 25)) then
                toAdd = true
            end

            if imgui.Button(u8("Сохранить"), imgui.ImVec2(-1, 25)) then
                saveGnews()
                sampAddChatMessage("{00FF00}[GovPanel]: Гос. новости сохранены!", -1)
            end

            -- применяем изменения ПОСЛЕ рендера
            if toAddLine then
                table.insert(gnews[toAddLine], "")
                table.insert(gnewsBuffers[toAddLine], imgui.ImBuffer("", 256))
            end
            if toDelete then
                table.remove(gnews, toDelete)
                table.remove(gnewsBuffers, toDelete)
            end
            if toAdd then
                table.insert(gnews, {""})
                table.insert(gnewsBuffers, { imgui.ImBuffer("", 256) })
            end

            imgui.EndChild()

        end
        imgui.EndChild()

        imgui.End()
    end

    -- Окно лицензий
    if license_window.v then
        imgui.Begin(u8'Меню лицензий', license_window, imgui.WindowFlags.AlwaysAutoResize)

    
        if imgui.Button(u8'Попросить лицензии', imgui.ImVec2(200, 30)) then
           askLic()
        end

        if imgui.Button(u8'Продать лицензию на оружие', imgui.ImVec2(200, 30)) then
            lua_thread.create(function ()
                local currentDep = config.settings.department
            
                sampSendChat("/do Портфель с документами в руке.")
                wait(1000)
                sampSendChat("/me достал из папки бланк, ручку и печать")
                wait(800)
                sampSendChat("/me заполняет бланк для лицензии на оружие")
                wait(800)
                sampSendChat("/do Имя владельца лицензии: "..targetRPName..".")
                wait(250)
                sampSendChat("/me сверяет данные")
                wait(1000)
                sampSendChat("/do Бланк заполнен верно.")
                wait(500)
                sampSendChat("/me ставит подпись лицензера")
                wait(800)
                sampSendChat("/me ставит печать \"Администрация губернатора "..currentDep.."\".")
                wait(800)
                sampSendChat("/do Документ подписан, печать поставлена.")
                wait(800)
                sampSendChat("/givelic "..targetId.."2 30000")
                license_window.v = false
            end)
        end

        if imgui.Button(u8'Продать проф. права', imgui.ImVec2(200, 30)) then
            lua_thread.create(function ()
                if (hasBasicLicense(targetRPName)) then
                    local currentDep = config.settings.department

                    sampSendChat("/do Портфель с документами в руке.")
                    wait(1000)
                    sampSendChat("/me достал из папки бланк, ручку и печать")
                    wait(800)
                    sampSendChat("/me заполняет бланк для профессиональных прав")
                    wait(800)
                    sampSendChat("/do Имя владельца лицензии: "..targetRPName..".")
                    wait(250)
                    sampSendChat("/me сверяет данные")
                    wait(1000)
                    sampSendChat("/do Бланк заполнен верно.")
                    wait(500)
                    sampSendChat("/me ставит подпись лицензера")
                    wait(800)
                    sampSendChat("/me ставит печать \"Администрация губернатора "..currentDep.."\".")
                    wait(800)
                    sampSendChat("/do Документ подписан, печать поставлена.")
                    wait(800)
                    sampSendChat("/givelic "..targetId.."1 10000")
                    license_window.v = false
                elseif (hasProfessionalLicense(targetRPName)) then
                    sampAddChatMessage('У игрока уже есть проф. права', -1)
                else
                    sampAddChatMessage('Перед продажей лицензии необходимо, чтобы вы попросили игрока показать лицензии', -1)
                end
            end)
        end

        imgui.End()
    end

    if layer_window.v then
        imgui.Begin(u8'Меню адвоката', layer_window, imgui.WindowFlags.AlwaysAutoResize)

        if imgui.Button(u8'Сколько осталось сидеть?', imgui.ImVec2(200, 30)) then
            lua_thread.create(function ()
                waitingForJailTime = true
                sampSendChat("Подскажите пожалуйста сколько вам осталось сидеть?")
                wait(500)
                sampSendChat("Это необходимо для оформления УДО.")
                wait(250)
                sampSendChat("/n Введи /time")
            end)
        end

        if imgui.Button(u8'Выпустить из тюрьмы', imgui.ImVec2(200, 30)) then
            lua_thread.create(function ()
                if (jailTimeReceived) then
                    jailTimeReceived = false
                    isWaitingResponse = true
                    sampSendChat("/do Портфель в руке.")
                    wait(250)
                    sampSendChat("/me достал из портфеля документ об УДО и ручку")
                    wait(300)
                    sampSendChat("/me заполняет данные о клиенте")
                    wait(300)
                    sampSendChat("/do Имя клиента: "..targetRPName)
                    wait(500)
                    sampSendChat("Отлично. Еще пару моментов.")
                    wait(500)
                    sampSendChat("/me открыл базу данных МВД")
                    wait(800)
                    sampSendChat("/me открыл личное дело гражданина")
                    wait(300)
                    sampSendChat("/me вносит изменния в личное дело для выпуска по УДО")
                    wait(500)
                    sampSendChat("/me передает документ об УДО на подписание человеку напротив")
                    wait(500)
                    sampSendChat("/n /me подписался(-ась)")
                    wait(1000)
                    sampSendChat("/free "..targetId.." "..releasePrice)
                    layer_window.v = false
                else
                    sampAddChatMessage('Клиент должен вам сообщить оставщееся время в тюрьме через' ..Color.GREEN .. ' /time', -1)
                    sampAddChatMessage('Нажмите'..Color.ORANGE..' "Сколько осталось сидеть"', -1)
                    sampAddChatMessage('Скрипт автоматически определит стоимость выпуска по УДО', -1)
                end
            end)
        end

        imgui.End()
    end

    if invite_window.v then
        imgui.Begin(u8'Меню', invite_window, imgui.WindowFlags.AlwaysAutoResize)

        if imgui.Button(u8'Попросить паспорт и лицензии', imgui.ImVec2(200, 30)) then
            lua_thread.create(function ()
                waitingForJailTime = true
                sampSendChat("Подскажите пожалуйста сколько вам осталось сидеть?")
                wait(250)
                sampSendChat("/n /time")
                layer_window.v = false
            end)
        end

        if imgui.Button(u8'Проверить на ЧС', imgui.ImVec2(200, 30)) then
            invite_window.v = false
            local list = loadBlacklist()
            local isBlackListed = isBlacklisted(targetRPName, list)
            local status = ""
            if (isBlackListed == true) then
                status = Color.RED.."занесен в черный список правительства"
            else 
                status = Color.GREEN.."не находится в черном списке"
            end
            sampAddChatMessage("Гражданин "..Color.ORANGE..targetRPName.." "..status,-1)
        
        end

        imgui.End()
    end

end

function isBlacklisted(nick, list)
    for _, v in ipairs(list) do
        if v == nick then
            return true
        end
    end
    return false
end

function askLic()
    lua_thread.create(function ()
        sampSendChat("Покажите пожалуйста ваши лицензии.")
        wait(250)
        local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local r, i = sampGetPlayerIdByCharHandle(PLAYER_PED)
        targetName = sampGetPlayerNickname(i)
        sampSendChat("/n /lic "..id)
        isWaitingForLic = true
    end)
end


function sampev.onServerMessage(color, text)
    if (isWaitingResponse == true and text == "Вы вытащили "..targetName.." из тюрьмы") then
        isWaitingResponse = false
    end
    if (isWaitingResponse == true and text == "Этот человек - опасный преступник. Он не может быть освобождён досрочно") then
        lua_thread.create(function ()
            isWaitingResponse = false
            wait(1500)
            sampSendChat("/do Ответ от МВД: "..targetRPName.." явлется особо опасным преступником.")
            wait(2500)
            sampSendChat("Сер, к сожалению МВД не одобрило ваше УДО.")
            wait(1000)
            sampSendChat("Вы являетесь особо опысным преступником.")
            wait(1000)
            sampSendChat("Вероятнее всего вас посадили сотрудники ФБР.")
            wait(550)
            sampSendChat("/n Тебя посадили ФБР или админ")
        end)
    end
    if waitingForJailTime then
        -- Проверяем формат: Nick_Surname выйдет на свободу через 15 минут.
        local pattern = string.format("%s выйдет на свободу через {.-}?(%%d+):%%d+", targetName)

        local minutes = string.match(text, pattern)
        if minutes then
            lua_thread.create(function ()
                sampAddChatMessage(
                    string.format("{00FF00}[LawyerPanel]:".. targetName.. " выйдет на свободу через %s минут.", minutes),
                    -1
                )
                sampAddChatMessage("Цена выпуска из тюрьмы "..Color.GREEN..tostring(getReleasePrice(minutes).."$"), -1)
                local key = HOTKEY.getKeysText('OpenMenu')
                releasePrice = tostring(getReleasePrice(minutes))
                sampAddChatMessage("Для продолжения нацельтесь на игрока и нажмите ПКМ + "..key.." и нажмите \"Выпустить из тюрьмы\"", -1)
                waitingForJailTime = false
                jailTimeReceived = true
            end)
            
        end
    elseif isWaitingForLic then
        local cleanText = text:gsub("{%x%x%x%x%x%x}", ""):gsub("^%s+", "")
        -- Начало блока лицензий
         -- Убедимся, что targetRPName существует
        if not targetRPName then return end

        -- Если таблицы для игрока нет — создаём
        if not playerLicenses[targetRPName] then
            playerLicenses[targetRPName] = { transport = "Неизвестно", weapon = "Неизвестно" }
        end
        
        if cleanText:find("На транспорт:") then
            local transport = cleanText:match("На транспорт:%s*(.+)")
            playerLicenses[targetRPName].transport = transport or "Отсутствует"
        elseif cleanText:find("На оружие:") then
            local weapon = cleanText:match("На оружие:%s*(.+)")
            playerLicenses[targetRPName].weapon = weapon or "Отсутствует"
            isWaitingForLic = false
            sampAddChatMessage(tostring(playerLicenses[targetRPName].transport), -1)
        elseif cleanText:find("Лицензии") == nil and cleanText:find("На транспорт") == nil and cleanText:find("На оружие") == nil then
            -- Конец блока лицензий
            
        end
    end
end

function getReleasePrice(minutes)
    local min = tonumber(minutes)
    if min < 30 then
        return 50000
    elseif min <= 50 then
        return 75000
    else
        return 100000
    end
end

function hasBasicLicense(playerName)
    if not playerLicenses[playerName] then
        return false -- информации о игроке нет
    end

    local transportLicense = playerLicenses[playerName].transport or ""
    return transportLicense:find("Базовые") ~= nil
end

function hasProfessionalLicense(playerName)
    if not playerLicenses[playerName] then
        return false -- информации о игроке нет
    end

    local transportLicense = playerLicenses[playerName].transport or ""
    return transportLicense:find("Профессиональный уровень") ~= nil
end

function ud()
    lua_thread.create(function ()
        local rangName = u8:decode(rank_names[config.settings.rank])
        sampSendChat("/me достал из внутреннего кармана службеное удостоверение")
        wait(350)
        sampSendChat("/do Удостоверение в руке.")
        wait(350)
        sampSendChat("/me развернул удостоверение и показал его человеку напротив")
        wait(350)
        sampSendChat("/do На удостоверении указано: имя, подразделение и должность.")
        wait(350)
        sampSendChat("/do "..getMyRPName()..", Администрация губернатора "..config.settings.department..", должность: "..rangName..".")
    end)
end

-- Основной цикл
function main()
    if not isSampLoaded() or not isSampfuncsLoaded() then return end
    while not isSampAvailable() do wait(50) end

    check_update()
    sampRegisterChatCommand("updateBlackList", function ()
        local updateIni = inicfg.load(nil, update_path)
        downloadUrlToFile(updateIni.info.blue_blacklist, blackListPath, function(_, st)
            if st == dlstatus.STATUSEX_ENDDOWNLOAD then
                sampAddChatMessage("{32CD32}Черный список обновлен.", -1)
            end
        end)
    end)

    
    sampAddChatMessage("[GobPanel]: Версия скрипта: "..Color.GREEN..script_vers_text,-1)
    sampAddChatMessage("[GovPanel]: Нажмите "..Color.ORANGE.."B"..Color.WHITE..", чтобы открыть настройки.", -1)
    
    if (config.settings.rank == 10) then
        for i, newsLines in ipairs(gnews) do
        local commandName = "news" .. i

        sampRegisterChatCommand(commandName, function()
            -- sampAddChatMessage("{00FF00}[GovPanel]: Новости #" .. i, -1)
            lua_thread.create(
                function ()
                    for _, line in ipairs(newsLines) do
                        sampSendChat(u8:decode(line))
                        wait(250)
                    end
                end) 
            end)
        end
    end
    sampRegisterChatCommand("ud", ud)

    exampleHotKey = HOTKEY.RegisterHotKey(
        "OpenMenu",       -- имя хоткея
        false,            -- не одиночная клавиша
        decodeJson(config.settings.bind),     -- Ctrl + M (0x11 = Ctrl, 0x4D = M)
        function()
            local result, ped = getCharPlayerIsTargeting(playerHandle)
            if result then
                r, i = sampGetPlayerIdByCharHandle(ped)
                if r then
                    local name = sampGetPlayerNickname(i)
                    local isRPName, nameRP = getRPName(name)
                    isTargetNameRP = isRPName
                    local rang = getRang()
                    sampAddChatMessage(tostring(rang), -1)
                    if (rang == 6 or rang == 7) then
                        targetRPName = nameRP
                        targetId = i
                        license_window.v = true
                    elseif (rang == 5) then
                        targetName = sampGetPlayerNickname(i)
                        targetRPName = nameRP
                        targetId = i
                        layer_window.v = true
                    elseif (rang >= 9) then
                        invite_window.v = true
                        targetName = sampGetPlayerNickname(i)
                        targetRPName = nameRP
                        targetId = i
                    end
                end
            end
        end
    )
    while true do
        wait(0)
        if update_state then -- Если человек напишет /update и обновлени есть, начнётся скаачивание скрипта.
            downloadUrlToFile(script_url, script_path, function(id, status)
                if status == dlstatus.STATUS_ENDDOWNLOADDATA then
                    sampAddChatMessage("{FFFFFF}Скрипт {32CD32}успешно {FFFFFF}обновлён.", 0xFF0000)
                end
            end)
            break
        end
        
        if wasKeyPressed(VK_B) and not sampIsChatInputActive() and not sampIsDialogActive() then
            main_window_state.v = not main_window_state.v
        end
        imgui.Process = main_window_state.v or license_window.v or layer_window.v or invite_window.v
    end
end

function saveGnews()
    local data = { news = {} }

    for i, newsLines in ipairs(gnews) do

        local combined = table.concat(newsLines, "|")
        data.news["news_" .. i] = combined

        sampAddChatMessage("News #" .. i .. ": " .. combined, -1)
    end

    inicfg.save(data, gnewsFilePath)
    sampAddChatMessage("{00FF00}[GovPanel]: Гос. новости сохранены!", -1)

    for i, newsLines in ipairs(gnews) do
        local commandName = "news" .. i

        sampRegisterChatCommand(commandName, function()
            lua_thread.create(function ()
                -- sampAddChatMessage("{00FF00}[GovPanel]: Новости #" .. i, -1)
                for _, line in ipairs(newsLines) do
                    sampAddChatMessage(u8:decode(line), -1)
                    wait(250)
                end
            end)
        end)
    end
    thisScript():reload()
end



function getRPName(name)
    local isRP = name:match("^[A-Za-z]+_[A-Za-z]+$") ~= nil

    local nickname = ""
    if isRP then
        nickname = name:gsub("_", " ")
    end

    return isRP, nickname
end

function getMyName()
    local _, id = sampGetPlayerIdByCharHandle(playerPed)
    return sampGetPlayerNickname(id)
end

function getMyRPName()
    local _, id = sampGetPlayerIdByCharHandle(playerPed)
    local isMyNameRP, name = getRPName(sampGetPlayerNickname(id))
    if (isMyNameRP) then
        return name
    else
       return "" 
    end
end

function getRang()
    return config.settings.rank
end

-- Hot Key

HOTKEY = {
	MODULEINFO = {
		version = 1,
		author = 'СоМиК'
	},
	Text = {
		WaitForKey = 'Нажмите любую клавишу...',
		NoKey = '< Свободно >'
	},
	List = {},
	ActiveKeys = {},
	ReturnHotKeys = nil,
	HotKeyIsEdit = nil,
	CancelKey = 0x1B,
	RemoveKey = 0x08,
	True = true
}

local specialKeys = {
	0x10,
	0x11,
	0x12,
	0xA4,
	0xA5
}

deepcopy = function(orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[deepcopy(orig_key)] = deepcopy(orig_value)
		end
		setmetatable(copy, deepcopy(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

local keyIsSpecial = function(key)
	for k, v in ipairs(specialKeys) do
		if v == key then
			return true
		end
	end
	return false
end

local getKeysText = function(name)
	local keysText = {}
	if HOTKEY.List[name] ~= nil then
		for k, v in ipairs(HOTKEY.List[name].keys) do
			table.insert(keysText, vk.id_to_name(v))
		end
	end
	return table.concat(keysText, ' + ')
end

HOTKEY.getKeysText = getKeysText

local searchHotKey = function(keys)
	local needCombo = deepcopy(keys)
	table.sort(needCombo)
	needCombo = table.concat(needCombo, ':')
	for k, v in pairs(HOTKEY.List) do
		if next(v.keys) then
			local foundCombo = deepcopy(v.keys)
			table.sort(foundCombo)
			foundCombo = table.concat(foundCombo, ':')
			if foundCombo == needCombo then
				v.callback()
				break
			end
		end
	end
end

HOTKEY.RegisterHotKey = function(name, soloKey, keys, callback)
	if HOTKEY.List[name] == nil then
		HOTKEY.List[name] = {
			soloKey = soloKey,
			keys = keys,
			callback = callback
		}
		return {
			name,
			['ShowHotKey'] = setmetatable({}, {__call = function(self, arg1, arg2) return HOTKEY.ShowHotKey(arg1[1], arg2) end}),
			['EditHotKey'] = setmetatable({}, {__call = function(self, arg1, arg2) return HOTKEY.EditHotKey(arg1[1], arg2) end}),
			['RemoveHotKey'] = setmetatable({}, {__call = function(self, arg) return HOTKEY.RemoveHotKey(arg[1]) end}),
			['GetHotKey'] = setmetatable({}, {__call = function(self, arg) return HOTKEY.GetHotKey(arg[1]) end})
		}
	end
end

HOTKEY.EditHotKey = setmetatable(
	{},
	{
		__call = function(self, name, keys)
			if HOTKEY.List[name] ~= nil then
				HOTKEY.List[name].keys = keys
				return true
			end
			return false
		end
	}
)

HOTKEY.RemoveHotKey = setmetatable(
	{},
	{
		__call = function(self, name)
			HOTKEY.List[name] = nil
			return true
		end
	}
)

HOTKEY.ShowHotKey = setmetatable(
	{},
	{
		__call = function(self, name, sizeButton)
			if HOTKEY.List[name] ~= nil then
				local HotKeyText = #HOTKEY.List[name].keys == 0 and ((HOTKEY.HotKeyIsEdit ~= nil and HOTKEY.HotKeyIsEdit.NameHotKey == name) and HOTKEY.Text.WaitForKey or HOTKEY.Text.NoKey) or getKeysText(name)
				if imgui.Button(('%s##HK:%s'):format(HotKeyText, name), sizeButton) then
					HOTKEY.HotKeyIsEdit = {
						NameHotKey = name,
						BackupHotKeyKeys = HOTKEY.List[name].keys,
					}
					HOTKEY.ActiveKeys = {}
					HOTKEY.HotKeyIsEdit.ActiveKeys = {}
					HOTKEY.List[name].keys = {}
				end
				if HOTKEY.ReturnHotKeys == name then
					HOTKEY.ReturnHotKeys = nil
					return true
				end
			else
				imgui.Button('Хоткей не найден', sizeButton)
			end
		end
	}
)

HOTKEY.GetHotKey = setmetatable(
	{},
	{
		__call = function(self, name)
			if HOTKEY.List[name] ~= nil then
				return HOTKEY.List[name].keys
			end
		end
	}
)

addEventHandler('onWindowMessage', function(msg, key, lparam)
    if msg == 0x0005 then HOTKEY.ActiveKeys = {} end
	if msg == 0x100 or msg == 260 then
		if HOTKEY.HotKeyIsEdit == nil then
			if key ~= HOTKEY.CancelKey and key ~= HOTKEY.RemoveKey and key ~= 0x1B and key ~= 0x08 and next(HOTKEY.List) then
				local found = false
				for k, v in ipairs(HOTKEY.ActiveKeys) do
					if v == key then
						found = true
						break
					end
				end
				if not found then
					table.insert(HOTKEY.ActiveKeys, key)
					if keyIsSpecial(key) then
						table.sort(HOTKEY.ActiveKeys)
					else
						searchHotKey(HOTKEY.ActiveKeys)
						table.remove(HOTKEY.ActiveKeys)
					end
				end
			end
		else
			if key == HOTKEY.CancelKey then
				HOTKEY.List[HOTKEY.HotKeyIsEdit.NameHotKey].keys = HOTKEY.HotKeyIsEdit.BackupHotKeyKeys
				HOTKEY.HotKeyIsEdit = nil
			elseif key == HOTKEY.RemoveKey then
				HOTKEY.List[HOTKEY.HotKeyIsEdit.NameHotKey].keys = {}
				HOTKEY.ReturnHotKeys = HOTKEY.HotKeyIsEdit.NameHotKey
				HOTKEY.HotKeyIsEdit = nil
			elseif key ~= 0x1B and key ~= 0x08 then
				local found = false
				for k, v in ipairs(HOTKEY.HotKeyIsEdit.ActiveKeys) do
					if v == key then
						found = true
						break
					end
				end
				if not found then
					if keyIsSpecial(key) then
						if not HOTKEY.List[HOTKEY.HotKeyIsEdit.NameHotKey].soloKey then
							for k, v in ipairs(specialKeys) do
								if key == v then
									table.insert(HOTKEY.HotKeyIsEdit.ActiveKeys, v)
								end
							end
							table.sort(HOTKEY.HotKeyIsEdit.ActiveKeys)
							HOTKEY.List[HOTKEY.HotKeyIsEdit.NameHotKey].keys = HOTKEY.HotKeyIsEdit.ActiveKeys
						end
					else
						table.insert(HOTKEY.List[HOTKEY.HotKeyIsEdit.NameHotKey].keys, key)
						HOTKEY.ReturnHotKeys = HOTKEY.HotKeyIsEdit.NameHotKey
						HOTKEY.HotKeyIsEdit = nil
					end
				end
			end
			consumeWindowMessage(true, true)
		end
	elseif msg == 0x101 or msg == 261 then
		if keyIsSpecial(key) then
			local pizdec = HOTKEY.HotKeyIsEdit ~= nil and HOTKEY.HotKeyIsEdit.ActiveKeys or HOTKEY.ActiveKeys
			for k, v in ipairs(pizdec) do
				if v == key then
					table.remove(pizdec, k)
					break
				end
			end
		end
	end
end)
