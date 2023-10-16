--- === MetarMenu ===
---
--- Brief METAR information in menubar.
---
--- ```
---   hs.loadSpoon('MetarMenu'):start({stationIds = {'KARB', 'KYIP', 'KDTW'}})
--- ```
---
--- Download: [https://github.com/flav/MetarMenu/raw/main/Spoon/MetarMenu.spoon.zip](https://github.com/flav/MetarMenu/raw/main/Spoon/MetarMenu.spoon.zip)
local obj = {}
obj.__index = obj

-- Metadata
obj.name = "MetarMenu"
obj.version = "1.0"
obj.author = "Flavio daCosta <flav@binaryservice.com>"
obj.homepage = "https://github.com/flav/MetarMenu"
obj.license = "MIT - https://opensource.org/licenses/MIT"

obj.stationId = nil
obj.stationIds = {'KARB', 'KYIP', 'KDTW'}

function obj:init()
    self.menubar = hs.menubar.new(false, 'metarMenu')
end

--- MetarMenu:start(stationId) -> MetarMenu
--- Method
--- Starts MetarMenu
---
--- Parameters:
---  * config - Configuration for fetching METAR
---     * stationId - Station identifier
---     * stationIds - List of station identifiers reporting the first successful
---
--- Returns:
---  * The MetarMenu object
---
--- Notes:
---  * Will show METAR in the menu, and poll for updates. Requires a valid METAR
--     station id (https://aviationweather.gov/docs/metar/stations.txt)
function obj:start(config)
    if config ~= nil and type(config) == 'table' then
        obj.stationId = config.stationId or nil

        if config.stationIds ~= nil and type(config.stationIds) == 'table' then
            obj.stationIds = config.stationIds
        end
    end

    obj.menubar:returnToMenuBar()

    obj:updateTitle("— —")
    obj:refresh()

    obj.refreshTimer = hs.timer.doEvery(10 * 60, function()
        obj:refresh()
    end)
    return self
end

--- MetarMenu:stop() -> MetarMenu
--- Method
--- Stops MetarMenu
---
--- Parameters:
---  * None
---
--- Returns:
---  * The MetarMenu object
---
--- Notes:
---  * This will remove menu item and stop polling for updates
function obj:stop()
    obj.refreshTimer:stop()
    obj.menubar:removeFromMenuBar()
    return self
end

function obj:refresh()
    -- IF single stationId and we get a result - then done
    if obj.stationId then
        if obj:getMetarXml(obj.stationId) then
            return
        end
    end
    -- Otherwise, loop thorugh stations and stop when we get one
    for i = 1, #obj.stationIds do
        if obj:getMetarXml(obj.stationIds[i]) then
            return
        end
    end

    -- local metarReport = {
    --     station_id = 'KARB',
    --     winds = '32009G23KT',
    --     temp_f = '25',
    --     dewpoint_f = '10',
    --     flight_category = 'MVFR',
    --     raw_short = "KARB 262353Z 32009G23KT 10SM OVC025 M01/M06 A2980",
    --     raw_rmk = "RMK AO2 PK WND 32026/2301 SLP099 T10061061 10011 21006 51024"
    -- }
    -- obj:updateMenu(metarReport)
end

function obj:updateTitle(title)
    obj.menubar:setTitle(title)
end

function obj:updateMenu(metarReport)
    -- Title bar
    local title = metarReport.station_id or '?'
    if metarReport.winds then
        title = title .. ' • ' .. metarReport.winds
    end
    if metarReport.temp_f then
        title = title .. ' • ' .. metarReport.temp_f .. '°F'
    end

    local colors = {
        LIFR = "#FF00FF",
        IFR = "#FF0000",
        VFR = "#00FF00",
        MVFR = "#0000FF"
    }
    if colors[metarReport.flight_category] then
        obj:updateTitle(hs.styledtext.new(title, {
            color = {
                hex = colors[metarReport.flight_category]
            }
        }))
    else
        -- no color - use default for light/dark
        obj:updateTitle(title)
    end

    -- Menu items
    local menuitems_table = {}
    if metarReport then
        table.insert(menuitems_table, {
            title = metarReport.raw_short,
            fn = function()
                hs.pasteboard.setContents(metarReport.raw_short)
            end
        })
    end
    if metarReport.raw_rmk then
        table.insert(menuitems_table, {
            title = metarReport.raw_rmk,
            fn = function()
                hs.pasteboard.setContents(metarReport.raw_rmk)
            end
        })
    end
    if metarReport.temp_f and metarReport.dewpoint_f then
        table.insert(menuitems_table, {
            title = metarReport.temp_f .. '°F / ' .. metarReport.dewpoint_f .. '°F'
        })
    end

    table.insert(menuitems_table, {
        title = "Refresh",
        fn = function()
            obj:refresh()
        end
    })
    obj.menubar:setMenu(menuitems_table)
end

function obj:buildQueryString(q)
    local queryString = {}
    for key, val in pairs(q) do
        table.insert(queryString, string.format("%s=%s", hs.http.encodeForQuery(key), hs.http.encodeForQuery(val)))
    end
    return table.concat(queryString, "&")
end

function obj:getMetarXml(station)
    if not station then
        return
    end
    -- https://aviationweather.gov/dataserver
    -- https://aviationweather.gov/metar/help?page=text
    local baseUrl = "https://www.aviationweather.gov/adds/dataserver_current/httpparam"
    local queryParams = {
        datasource = "metars",
        requestType = "retrieve",
        format = "xml",
        mostRecentForEachStation = "constraint",
        hoursBeforeNow = "2.25",
        stationString = station
    }
    local url = baseUrl .. "?" .. obj:buildQueryString(queryParams)

    local code, body, table = hs.http.get(url, nil)
    if code ~= 200 then
        print('-- Could not get weather. Response code: ' .. code)
    else
        local metarReport = obj:metarParser(body)
        if metarReport == nil then
            obj:updateTitle("No data")
            return false
        else
            obj:updateMenu(metarReport)
            return true
        end
    end
end

function obj:metarParser(metarXml)
    -- https://www.lua.org/manual/5.1/
    -- https://learnxinyminutes.com/docs/lua/
    -- Patterns: https://www.lua.org/manual/5.1/manual.html#5.4.1
    metarXml = metarXml:match "<METAR>(.*)</METAR>"
    if metarXml == nil then
        return
    end

    local metarReport = {}
    for entity, value in string.gmatch(metarXml, "<([^/<]+)>([^<]+)") do
        -- Note: skipping sky_condition
        metarReport[entity] = value:gsub("%s+$", "")
    end

    metarReport.raw_short = string.match(metarReport.raw_text or '', "^(.*) RMK")
    metarReport.raw_rmk = string.match(metarReport.raw_text or '', "(RMK.*)$")
    metarReport.winds = string.match(metarReport.raw_text or '', " ([^%s]+KT) ")
    if metarReport.temp_c then
        metarReport.temp_f = obj:toFahrenheit(metarReport.temp_c)
    end
    if metarReport.dewpoint_c then
        metarReport.dewpoint_f = obj:toFahrenheit(metarReport.dewpoint_c)
    end

    return metarReport
end

function obj:toFahrenheit(c)
    local forRounding = .5
    return math.floor((c * (9 / 5)) + 32 + forRounding)
end

return obj
