version_num="1.1"
imgScale=1024/1024
diffNames={"Easy","Medium","Hard","Expert"}
movequant=10
quants={1/32,1/24,1/16,1/12,1/8,1/6,1/4,1/3,1/2,1,2,4}
-- highway rendering vars
midiHash=""
beatHash=""
eventsHash=""
trackSpeed=1.80
inst=1 -- Guitar 3x2 (GHL)
diff=4 -- Expert
pR={
	{{58,64}}, -- Normal notes = Easy
	{{70,76}}, -- Normal notes = Medium
	{{82,88}}, -- Normal notes = Hard
	{{94,100}} -- Normal notes = Expert
}

-- Rastrea el proyecto actual
local currentProject = reaper.EnumProjects(-1)

-- Variables para los botones de interacción
local difficultyButtons = {}
local speedButtons = {}
local offsetButtons = {}
local mouseDown = false

-- Variables para el visualizador de letras
local vocalsTrack = nil
local phrases = {}
local currentPhrase = 1
local phraseMarkerNote = 105  -- Nota MIDI para el marcador de frases
local showLyrics = true       -- Controla si se muestra el visualizador de letras
local showNotesHUD = true	  -- Controla si se muestra el visualizador de líneas de notas

-- Colores para las letras
local textColorInactive = {r = 0.15, g = 0.9, b = 0.0, a = 1.0}  -- Verde
local textColorActive = {r = 0.0, g = 1.0, b = 1.0, a = 1.0}    -- Azul
local textColorSung = {r = 0.1176471, g = 0.5647059, b = 1.0, a = 1.0}  -- Azul claro para letras ya cantadas
local bgColorLyrics = {r = 0.15, g = 0.15, b = 0.25, a = 0.8}   -- Fondo para letras

-- Color para la próxima frase (notas con tono)
local textColorNextPhrase = {r = 0.0, g = 1.0, b = 0.5, a = 1.0}  -- Verde más claro para próxima frase

-- Color para letras sin tono (marcadas con #)
local textColorToneless = {r = 0.55, g = 0.55, b = 0.55, a = 1.0}  -- Gris para letras sin tono
local textColorTonelessActive = {r = 1.0, g = 1.0, b = 1.0, a = 1.0}  -- Blanco puro para letras sin tono activas
local textColorTonelessSung = {r = 0.75, g = 0.75, b = 0.75, a = 1.0}  -- Blanco puro para letras sin tono ya cantadas

-- Colores en la sección de colores al inicio del script
local textColorHeroPower = {r = 1.0, g = 1.0, b = 0.15, a = 1.0}        -- Amarillo para letras con Hero Power
local textColorHeroPowerActive = {r = 1.0, g = 0.5, b = 0.3, a = 1.0}  -- Amarillo brillante para letras Hero Power activas
local textColorHeroPowerSung = {r = 0.9764706, g = 0.8999952, b = 0.5372549, a = 1.0}    -- Amarillo más oscuro para letras Hero Power ya cantadas

-- Variables configurables para ajustar la posición y tamaño del visualizador de letras
local lyricsConfig = {
    height = 110,           -- Altura total del visualizador
    bottomMargin = 30,     	-- Margen inferior (negativo = se superpone con el borde)
    phraseHeight = 35,      -- Altura de cada frase (reducida ligeramente)
    phraseSpacing = 1,      -- Espacio entre frases
    bgOpacity = 0.8,        -- Opacidad del fondo (0.0 - 1.0)
    fontSize = {            -- Tamaños de fuente
        current = 22,       -- Tamaño para frase actual
        next = 20           -- Tamaño para próxima frase
    }
}

-- Variables para el visualizador de secciones
local eventsTrack = nil
local sections = {}
local currentSection = 1
local eventsHash = "" -- Detecta cambios en la pista EVENTS
local showSections = true  -- Controla si se muestra el visualizador de secciones
local sectionDisplayConfig = {
    width = 150,              -- Ancho del recuadro de sección
    height = 40,              -- Altura del recuadro
    xOffset = 20,             -- Posición X desde el borde izquierdo
    yOffset = 280,            -- Posición Y desde arriba
    bgColor = {r = 0.15, g = 0.15, b = 0.25, a = 0.9},  -- Color de fondo
    textColor = {r = 0.9, g = 0.9, b = 1.0, a = 1.0},   -- Color del texto
    fontSize = 20,            -- Tamaño de la fuente
    fadeTime = 2.0            -- Tiempo en segundos antes de la siguiente sección para empezar a desvanecer
}

-- Detecta cambios en la pista de voces
local vocalsHash = ""

-- Rastrea el tiempo anterior
local lastBeatTime = 0

hopo_marker_expert=101 -- Hopo marker
hopo_marker_hard=89 -- Hopo marker
hopo_marker_medium=77 -- Hopo marker
hopo_marker_easy=65 -- Hopo marker
HP=116 -- Hero Power note
offset=0.0
notes={}
beatLines={}
eventsData={}
trackRange={0,0}
curBeat=0
curBeatLine=1
curEvent=1
curNote=1
nxoff=178 -- X offset
nxm=0.15 -- X mult of offset
nyoff=150.5 -- Y offset
nsm=0.05 -- Scale multiplier

lastCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())

showHelp=false

local function rgb2num(r, g, b)
	g = g * 256
	b = b * 256 * 256
	return r + g + b
end

function toFractionString(number)
	if number<1 then
		return string.format('1/%d', math.floor(1/number))
	else
		return string.format('%d',number)
	end
end

-- Esto soluciona el "-0.00" en el botón del Offset
function formatNumber(number, precision)
    -- Si el número está muy cerca de cero
    if math.abs(number) < 0.005 then
        return string.format("%."..precision.."f", 0)
    else
        return string.format("%."..precision.."f", number)
    end
end

function getNoteIndex(time, lane)
	for i, note in ipairs(notes) do
		if note[1] == time and note[3] == lane then
			return i
		end
	end
	return -1
end

function findTrack(trackName)
	local numTracks = reaper.CountTracks(0)
	for i = 0, numTracks - 1 do
		local track = reaper.GetTrack(0, i)
		local _, currentTrackName = reaper.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
		if currentTrackName == trackName then
			return track
		end
	end
	return nil
end

-- Función para dibujar los botones de dificultad
function drawDifficultyButtons()
    local buttonWidth = 80
    local buttonHeight = 30
    local startX = gfx.w - (buttonWidth * 4 + 15) -- posición inicial X
    local startY = 5 -- Posición Y
    local spacing = 5 -- Espacio entre botones
    
    difficultyButtons = {} -- reinicia la tabla de botones
    
    for i = 1, 4 do
        local x = startX + (i-1) * (buttonWidth + spacing)
        local y = startY
        local isSelected = (i == diff)
        
        -- Guarda información del botón para detección de clics
        difficultyButtons[i] = {x = x, y = y, width = buttonWidth, height = buttonHeight}
        
        -- Dibuja el fondo del botón
        if isSelected then
            gfx.r, gfx.g, gfx.b = 0.3, 0.7, 1.0 -- Color para botón seleccionado
        else
            gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3 -- Color para botones no seleccionados
        end
        
        gfx.rect(x, y, buttonWidth, buttonHeight, 1) -- Dibuja el fondo
        
        -- Dibuja el borde
        gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
        gfx.rect(x, y, buttonWidth, buttonHeight, 0) -- Dibuja el borde
        
        -- Dibuja el texto
        gfx.r, gfx.g, gfx.b = 1, 1, 1
        gfx.setfont(1, "SDK_JP_Web 85W", 18) -- Genshin Impact font
        
        local textW, textH = gfx.measurestr(diffNames[i])
        local textX = x + (buttonWidth - textW) / 2
        local textY = y + (buttonHeight - textH) / 2
        
        gfx.x, gfx.y = textX, textY
        gfx.drawstr(diffNames[i])
    end
end

-- Función para dibujar los controles de Highway Speed
function drawSpeedControls()
    local buttonWidth = 25
    local buttonHeight = 25
    local spacing = 5
    local textStartX = 12
    local speedTextY = 115 -- Ajustado para estar más cerca de Snap
    local buttonStartX = 238 -- Posición fija para los botones
    
    speedButtons = {}
    
    -- Highway Speed (texto)
    gfx.r, gfx.g, gfx.b = 0.77, 0.81, 0.96
    gfx.setfont(1, "SDK_JP_Web 85W", 25) -- Genshin Impact font
    gfx.x, gfx.y = textStartX, speedTextY
    gfx.drawstr("Highway Speed: " .. formatNumber(trackSpeed, 2))
    
    -- Botón para disminuir velocidad
    gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3
    gfx.rect(buttonStartX, speedTextY, buttonWidth, buttonHeight, 1)
    
    -- Borde del botón
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(buttonStartX, speedTextY, buttonWidth, buttonHeight, 0)
    
    -- Triángulo izquierdo (disminuir)
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.triangle(
        buttonStartX + buttonWidth - 8, speedTextY + 5,
        buttonStartX + buttonWidth - 8, speedTextY + buttonHeight - 5,
        buttonStartX + 8, speedTextY + buttonHeight/2
    )
    
    -- Botón para aumentar velocidad
    gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3
    gfx.rect(buttonStartX + buttonWidth + spacing, speedTextY, buttonWidth, buttonHeight, 1)
    
    -- Borde del botón
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(buttonStartX + buttonWidth + spacing, speedTextY, buttonWidth, buttonHeight, 0)
    
    -- Triángulo derecho (aumentar)
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.triangle(
        buttonStartX + buttonWidth + spacing + 8, speedTextY + 5,
        buttonStartX + buttonWidth + spacing + 8, speedTextY + buttonHeight - 5,
        buttonStartX + buttonWidth + spacing + buttonWidth - 8, speedTextY + buttonHeight/2
    )
    
    -- Guarda los botones de velocidad
    speedButtons[1] = {x = buttonStartX, y = speedTextY, width = buttonWidth, height = buttonHeight, action = "decrease"}
    speedButtons[2] = {x = buttonStartX + buttonWidth + spacing, y = speedTextY, width = buttonWidth, height = buttonHeight, action = "increase"}
end

-- Función para dibujar los controles de Offset
function drawOffsetControls()
    local buttonWidth = 25
    local buttonHeight = 25
    local spacing = 5
    local textStartX = 12
    local offsetTextY = 145 -- Ajustado para estar más cerca del texto "Highway Speed"
    local buttonStartX = 160 -- Posición fija para los botones (más cerca del texto que los de Speed)
    
    offsetButtons = {}
    
    -- Offset (texto)
    gfx.r, gfx.g, gfx.b = 0.77, 0.81, 0.96
    gfx.setfont(1, "SDK_JP_Web 85W", 25) -- Genshin Impact font
    gfx.x, gfx.y = textStartX, offsetTextY
    gfx.drawstr("Offset: " .. formatNumber(offset, 2))
    
    -- Botón para disminuir offset
    gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3
    gfx.rect(buttonStartX, offsetTextY, buttonWidth, buttonHeight, 1)
    
    -- Borde del botón
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(buttonStartX, offsetTextY, buttonWidth, buttonHeight, 0)
    
    -- Triángulo izquierdo (disminuir)
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.triangle(
        buttonStartX + buttonWidth - 8, offsetTextY + 5,
        buttonStartX + buttonWidth - 8, offsetTextY + buttonHeight - 5,
        buttonStartX + 8, offsetTextY + buttonHeight/2
    )
    
    -- Botón para aumentar offset
    gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3
    gfx.rect(buttonStartX + buttonWidth + spacing, offsetTextY, buttonWidth, buttonHeight, 1)
    
    -- Borde del botón
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(buttonStartX + buttonWidth + spacing, offsetTextY, buttonWidth, buttonHeight, 0)
    
    -- Triángulo derecho (aumentar)
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.triangle(
        buttonStartX + buttonWidth + spacing + 8, offsetTextY + 5,
        buttonStartX + buttonWidth + spacing + 8, offsetTextY + buttonHeight - 5,
        buttonStartX + buttonWidth + spacing + buttonWidth - 8, offsetTextY + buttonHeight/2
    )
    
    -- Guarda los botones de offset
    offsetButtons[1] = {x = buttonStartX, y = offsetTextY, width = buttonWidth, height = buttonHeight, action = "decrease"}
    offsetButtons[2] = {x = buttonStartX + buttonWidth + spacing, y = offsetTextY, width = buttonWidth, height = buttonHeight, action = "increase"}
end

-- Función para dibujar un botón para activar/desactivar letras
function drawLyricsToggleButton()
    local buttonWidth = 120
    local buttonHeight = 30
    local x = 12
    local y = 175 -- Posicionado debajo de los controles de offset
    
    -- Dibuja el fondo del botón
    if showLyrics then
        gfx.r, gfx.g, gfx.b = 0.3, 0.7, 1.0 -- Color azul claro para activado
    else
        gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3 -- Color gris oscuro para desactivado
    end
    
    gfx.rect(x, y, buttonWidth, buttonHeight, 1) -- dibuja el fondo
    
    -- Dibuja el borde
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(x, y, buttonWidth, buttonHeight, 0) -- dibuja el borde
    
    -- Dibuja el texto
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.setfont(1, "SDK_JP_Web 85W", 18) -- Genshin Impact font
    
    local buttonText = showLyrics and "Lyrics: ON" or "Lyrics: OFF"
    local textW, textH = gfx.measurestr(buttonText)
    local textX = x + (buttonWidth - textW) / 2
    local textY = y + (buttonHeight - textH) / 2
    
    gfx.x, gfx.y = textX, textY
    gfx.drawstr(buttonText)
    
    -- Guarda información del botón para detección de clics
    return {x = x, y = y, width = buttonWidth, height = buttonHeight}
end

-- Función para dibujar un botón para activar/desactivar el HUD de notas
function drawNotesHUDToggleButton()
    local buttonWidth = 120
    local buttonHeight = 30
    local x = 12
    local y = 215  -- Posicionado debajo del botón de Lyrics
    
    -- Dibuja el fondo del botón
    if showNotesHUD then
        gfx.r, gfx.g, gfx.b = 0.3, 0.7, 1.0  -- Color azul claro para activado
    else
        gfx.r, gfx.g, gfx.b = 0.2, 0.2, 0.3  -- Color gris oscuro para desactivado
    end
    
    gfx.rect(x, y, buttonWidth, buttonHeight, 1)  -- dibuja el fondo
    
    -- Dibuja el borde
    gfx.r, gfx.g, gfx.b = 0.8, 0.8, 0.9
    gfx.rect(x, y, buttonWidth, buttonHeight, 0)  -- dibuja el borde
    
    -- Dibuja el texto
    gfx.r, gfx.g, gfx.b = 1, 1, 1
    gfx.setfont(1, "SDK_JP_Web 85W", 18)  -- Genshin Impact font
    
    local buttonText = showNotesHUD and "Vocal HUD: ON " or "Vocal HUD: OFF"
    local textW, textH = gfx.measurestr(buttonText)
    local textX = x + (buttonWidth - textW) / 2
    local textY = y + (buttonHeight - textH) / 2
    
    gfx.x, gfx.y = textX, textY
    gfx.drawstr(buttonText)
    
    -- Guarda información del botón para detección de clics
    return {x = x, y = y, width = buttonWidth, height = buttonHeight}
end

-- Función para manejar clics en los botones
function handleMouseClick(x, y)
    -- Comprobar botones de dificultad
    for i, button in ipairs(difficultyButtons) do
        if x >= button.x and x <= button.x + button.width and 
           y >= button.y and y <= button.y + button.height then
            if diff ~= i then
                diff = i
                midiHash = ""
                updateMidi()
            end
            return true
        end
    end
    
    -- Comprobar botones de velocidad
    for i, button in ipairs(speedButtons) do
        if x >= button.x and x <= button.x + button.width and 
           y >= button.y and y <= button.y + button.height then
           
            if button.action == "decrease" then
                if trackSpeed > 0.25 then 
                    trackSpeed = trackSpeed - 0.05 
                end
            elseif button.action == "increase" then
                trackSpeed = trackSpeed + 0.05
            end
            return true
        end
    end
    
    -- Comprobar botones de offset
    for i, button in ipairs(offsetButtons) do
        if x >= button.x and x <= button.x + button.width and 
           y >= button.y and y <= button.y + button.height then
           
            if button.action == "decrease" then
                offset = offset - 0.01
            elseif button.action == "increase" then
                offset = offset + 0.01
            end
            return true
        end
    end
    
    -- Comprobar botón de lyrics
    local lyricsButton = drawLyricsToggleButton()
    if x >= lyricsButton.x and x <= lyricsButton.x + lyricsButton.width and 
       y >= lyricsButton.y and y <= lyricsButton.y + lyricsButton.height then
        showLyrics = not showLyrics
        if showLyrics and #phrases == 0 then
            parseVocals()
        end
        return true
    end
    
    -- Comprobar botón de Notes HUD
    local notesHUDButton = drawNotesHUDToggleButton()
    if x >= notesHUDButton.x and x <= notesHUDButton.x + notesHUDButton.width and 
       y >= notesHUDButton.y and y <= notesHUDButton.y + notesHUDButton.height then
        showNotesHUD = not showNotesHUD
        return true
    end

    return false
end

gfx.clear = rgb2num(35, 38, 52) -- Background color
gfx.init("GHL Preview", 700, 700, 0, 1150, 50) -- Wight, Geight, X Pos, Y Pos.

local script_folder = string.gsub(debug.getinfo(1).source:match("@?(.*[\\|/])"),"\\","/")
highway = gfx.loadimg(1,script_folder.."assets/highway.png")

white_note = gfx.loadimg(7, script_folder.."assets/white_note.png")
black_note = gfx.loadimg(8, script_folder.."assets/black_note.png")
square_note = gfx.loadimg(9, script_folder.."assets/square_note.png") -- (nota de acorde de cejilla)
open_note = gfx.loadimg(10, script_folder.."assets/open_note.png")

white_hopo_notee = gfx.loadimg(11, script_folder.."assets/white_note_hopo.png")
black_hopo_notee = gfx.loadimg(12, script_folder.."assets/black_note_hopo.png")
square_hopo_notee = gfx.loadimg(13, script_folder.."assets/square_note_hopo.png")

hero_icon = gfx.loadimg(14, script_folder.."assets/hero_icon.png")
open_note_herocollect = gfx.loadimg(15, script_folder.."assets/open_note_herocollect.png")

instrumentTracks={
	{"Guitar 3x2",findTrack("PART GUITAR GHL")}
}

function parseNotes(take)
    notes = {}
    heropower_phrases = {}
    hopomark_expert = {}
    hopomark_hard = {}
    hopomark_medium = {}
    hopomark_easy = {}
    heropower = false
    cur_heropower_phrase = 1
    cur_hopo_marker_expert = 1
    cur_hopo_marker_hard = 1
    cur_hopo_marker_medium = 1
    cur_hopo_marker_easy = 1
    _, notecount = reaper.MIDI_CountEvts(take)
    
    for i = 0, notecount - 1 do
        _, _, _, spos, epos, _, pitch, _ = reaper.MIDI_GetNote(take, i)
        ntime = reaper.MIDI_GetProjQNFromPPQPos(take, spos)
        nend = reaper.MIDI_GetProjQNFromPPQPos(take, epos)
        
        if pitch == hopo_marker_expert then
            table.insert(hopomark_expert, {ntime, nend}) -- Hopo marker (Expert)

        elseif pitch == hopo_marker_hard then
            table.insert(hopomark_hard, {ntime, nend}) -- Hopo marker (Hard)

        elseif pitch == hopo_marker_medium then
            table.insert(hopomark_medium, {ntime, nend}) -- Hopo marker (Medium)

        elseif pitch == hopo_marker_easy then
            table.insert(hopomark_easy, {ntime, nend}) -- Hopo marker (Easy)

        elseif pitch == HP then
            table.insert(heropower_phrases, {ntime, nend}) -- Hero Power marker

        elseif pitch >= pR[diff][1][1] and pitch <= pR[diff][1][2] then
            lane = pitch - pR[diff][1][1]
            noteIndex = getNoteIndex(ntime, lane)
            if noteIndex ~= -1 then
                notes[noteIndex][2] = nend - ntime
            else
                table.insert(notes, {ntime, nend - ntime, lane, false, false})
            end
        end
    end
    
    -- Detectar acordes de cejilla (notas square)
    local function isWhite(lane)
        return lane >= 1 and lane <= 3
    end

    local function isBlack(lane)
        return lane >= 4 and lane <= 6
    end

    local function isChordOfFret1(lane1, lane2)
        return (lane1 == 1 and lane2 == 4) or (lane1 == 4 and lane2 == 1)
    end

    local function isChordOfFret2(lane1, lane2)
        return (lane1 == 2 and lane2 == 5) or (lane1 == 5 and lane2 == 2)
    end

    local function isChordOfFret3(lane1, lane2)
        return (lane1 == 3 and lane2 == 6) or (lane1 == 6 and lane2 == 3)
    end

    for i = 1, #notes do
        for j = i + 1, #notes do
            if notes[i][1] == notes[j][1] and notes[i][3] ~= notes[j][3] then
                local lane1, lane2 = notes[i][3], notes[j][3]
                if isWhite(lane1) and isBlack(lane2) or isWhite(lane2) and isBlack(lane1) then
                    if isChordOfFret1(lane1, lane2) or isChordOfFret2(lane1, lane2) or isChordOfFret3(lane1, lane2) then
                        notes[i][5] = true
                        notes[j][5] = true
                    end
                end
            end
        end
    end
    
    -- Identificar el estado de notas Hero Power
    if #heropower_phrases ~= 0 then
        for i = 1, #notes do
            if notes[i][1] > heropower_phrases[cur_heropower_phrase][2] then
                if cur_heropower_phrase < #heropower_phrases then cur_heropower_phrase = cur_heropower_phrase + 1 end
            end
            if notes[i][1] >= heropower_phrases[cur_heropower_phrase][1] and notes[i][1] < heropower_phrases[cur_heropower_phrase][2] then
                notes[i][6] = true
            end
        end
    end

	-- Identificar notas HOPO (Expert)
	if #hopomark_expert ~= 0 then
		for i = 1, #notes do
			if notes[i][1] > hopomark_expert[cur_hopo_marker_expert][2] then
				if cur_hopo_marker_expert < #hopomark_expert then cur_hopo_marker_expert = cur_hopo_marker_expert + 1 end
			end
			if notes[i][1] >= hopomark_expert[cur_hopo_marker_expert][1] and notes[i][1] < hopomark_expert[cur_hopo_marker_expert][2] then
				if diff == 4 then
					notes[i][7] = true
				end
			end
		end
	end

	-- Identificar notas HOPO (Hard)
	if #hopomark_hard ~= 0 then
		for i = 1, #notes do
			if notes[i][1] > hopomark_hard[cur_hopo_marker_hard][2] then
				if cur_hopo_marker_hard < #hopomark_hard then cur_hopo_marker_hard = cur_hopo_marker_hard + 1 end
			end
			if notes[i][1] >= hopomark_hard[cur_hopo_marker_hard][1] and notes[i][1] < hopomark_hard[cur_hopo_marker_hard][2] then
				if diff == 3 then
					notes[i][7] = true
				end
			end
		end
	end

	-- Identificar notas HOPO (Medium)
	if #hopomark_medium ~= 0 then
		for i = 1, #notes do
			if notes[i][1] > hopomark_medium[cur_hopo_marker_medium][2] then
				if cur_hopo_marker_medium < #hopomark_medium then cur_hopo_marker_medium = cur_hopo_marker_medium + 1 end
			end
			if notes[i][1] >= hopomark_medium[cur_hopo_marker_medium][1] and notes[i][1] < hopomark_medium[cur_hopo_marker_medium][2] then
				if diff == 2 then
					notes[i][7] = true
				end
			end
		end
	end

	-- Identificar notas HOPO (Easy)
	if #hopomark_easy ~= 0 then
		for i = 1, #notes do
			if notes[i][1] > hopomark_easy[cur_hopo_marker_easy][2] then
				if cur_hopo_marker_easy < #hopomark_easy then cur_hopo_marker_easy = cur_hopo_marker_easy + 1 end
			end
			if notes[i][1] >= hopomark_easy[cur_hopo_marker_easy][1] and notes[i][1] < hopomark_easy[cur_hopo_marker_easy][2] then
				if diff == 1 then
					notes[i][7] = true
				end
			end
		end
	end
end

function updateMidi()
    instrumentTracks={
        {"Guitar 3x2", findTrack("PART GUITAR GHL")}
    }
    if instrumentTracks[inst][2] then
        local numItems = reaper.CountTrackMediaItems(instrumentTracks[inst][2])
        for i = 0, numItems-1 do
            local item = reaper.GetTrackMediaItem(instrumentTracks[inst][2], i)
            local take = reaper.GetActiveTake(item)
            local _,hash=reaper.MIDI_GetHash(take,true)
            if midiHash~=hash then
                parseNotes(take)
                curNote=1
                for i=1,#notes do
                    curNote=i
                    if notes[i][1]+notes[i][2]>=curBeat then
                        break
                    end
                end
                midiHash=hash
            end
        end
    else
        midiHash=""
        notes={}
    end
end

-- Función para reiniciar el estado cuando cambia el proyecto
function resetState()
    -- Reiniciar variables de tracks
    vocalsTrack = nil
    instrumentTracks = {
        {"Guitar 3x2", nil}
    }
    
    -- Reiniciar variables de datos
    midiHash = ""
    vocalsHash = ""
    notes = {}
    phrases = {}
    beatLines = {}
    
	eventsTrack = nil
	sections = {}
	currentSection = 1
	eventsHash = ""

    -- Reiniciar estados
    curNote = 1
    curBeatLine = 1
    currentPhrase = 1
    
    -- También reiniciar estas variables específicas de letras
    lastBeatTime = 0
    
    -- Reinicializar rango del proyecto si hay un proyecto abierto
    if isProjectOpen() then
        trackRange = {
            reaper.TimeMap2_timeToQN(0, 0),
            reaper.TimeMap2_timeToQN(0, reaper.GetProjectLength(0))
        }
    else
        trackRange = {0, 0}
    end
end

-- Función de seguridad para comprobar si una pista sigue siendo válida
function isTrackValid(track)
    if track == nil then return false end
    
    -- Uso de pcall para capturar errores al intentar acceder a la pista
    local success, _ = pcall(function()
        reaper.GetTrackGUID(track)
    end)
    
    return success
end

-- Función para comprobar si hay algún proyecto abierto
function isProjectOpen()
    local proj = reaper.EnumProjects(-1)
    return proj ~= nil
end

-- Función para verificar si la pista PART VOCALS sigue siendo válida
function checkVocalsTrack()
    -- Si la pista PART VOCALS no está definida o no es válida, se resetea
    if not vocalsTrack or not isTrackValid(vocalsTrack) then
        vocalsTrack = nil
        return false
    end
    return true
end

-- Estructura para una frase de letras
function createPhrase(startTime, endTime)
    return {
        startTime = startTime,
        endTime = endTime,
        lyrics = {},
        currentLyric = 1
    }
end

-- Función completa createLyric con soporte para Hero Power
function createLyric(text, startTime, endTime, pitch, hasHeroPower)
    -- Procesar el texto
    local processedText = text
    local originalText = text  -- Guardar el texto original para referencia
    
    -- Detectar si es una letra sin tono (#)
    local hasTonelessMarker = processedText:match("#") ~= nil
    
    -- Análisis de conectores en el texto ORIGINAL
    -- Buscar todos los posibles patrones de conector al final
    local connectsWithNext = false
    if originalText:match("%-$") or originalText:match("%+$") or originalText:match("=$") or
       originalText:match("%-#$") or originalText:match("%+#$") or originalText:match("=#$") then
        connectsWithNext = true
    end
    
    -- Buscar todos los posibles patrones de conector al principio
    local connectsWithPrevious = false
    if originalText:match("^%-") or originalText:match("^%+") or originalText:match("^=") or
       originalText:match("^%-#") or originalText:match("^%+#") or originalText:match("^=#") then
        connectsWithPrevious = true
    end
    
    -- Busca patrones específicos para tratamiento especial
    -- Detectar signos = (que serán visibles como -)
    local hasVisibleEquals = processedText:match("=") ~= nil
    
    -- Guardar posiciones donde hay signos = (para no eliminarlos después)
    local equalsPositions = {}
    local i = 1
    while true do
        i = string.find(processedText, "=", i)
        if i == nil then break end
        equalsPositions[i] = true
        i = i + 1
    end
    
    -- Procesamiento del texto para visualización
    
    -- Convertir = a - (estos guiones serán visibles)
    processedText = processedText:gsub("=", "-")
    
    -- Eliminar todos los marcadores #
    processedText = processedText:gsub("#", "")
    
    -- Eliminar todos los símbolos +
    processedText = processedText:gsub("%+", "")
    
    -- Eliminar el nombre de la pista
    processedText = processedText:gsub("PART VOCALS", "")
    
    -- Eliminar el nombre del charter de la pista
    -- processedText = processedText:gsub("GHCripto", "") -- Omite el evento de texto de Copyright (de quien hizo el chart Vocal)
    
    -- Eliminar todo el texto entre corchetes, incluyendo los corchetes
    processedText = processedText:gsub("%[.-%]", "")
    
    -- Eliminar guiones originales (que no eran =)
    -- Hacer esto carácter por carácter para preservar los guiones que eran =
    local result = ""
    for j = 1, #processedText do
        local char = processedText:sub(j, j)
        if char == "-" and not equalsPositions[j] then
            -- Omitir guiones originales
        else
            result = result .. char
        end
    end
    processedText = result
    
    -- Elimina espacios extras que pudieran quedar después de eliminar el texto entre corchetes
    processedText = processedText:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%s+", " ")
    
    -- Crear y devolver la estructura de datos
    return {
        originalText = originalText,
        text = processedText,
        startTime = startTime,
        endTime = endTime,
        isActive = false,
        hasBeenSung = false,
        isToneless = hasTonelessMarker,
        -- Usar los resultados del análisis de conectores
        endsWithHyphen = connectsWithNext,
        beginsWithHyphen = connectsWithPrevious,
        pitch = pitch or 0,
        hasHeroPower = hasHeroPower or false  -- Hero Power
    }
end

-- Función para actualizar las letras en tiempo real
function updateVocals()
    if not showLyrics then
        return false
    end
    
    -- Verificar que hay un proyecto abierto
    if not isProjectOpen() then
        return false
    end
    
    -- Verificar validez de la pista PART VOCALS
    if not checkVocalsTrack() then
        -- Intentar encontrar la pista PART VOCALS
        if not findVocalsTrack() then
            return false
        end
    end
    
    -- Comprobar si hay cambios en la pista PART VOCALS
    local currentHash = ""
    
    -- Usar pcall para evitar errores
    local success, result = pcall(function()
        -- Recopilar un hash de todos los items MIDI en la pista PART VOCALS
        if vocalsTrack then
            local numItems = reaper.CountTrackMediaItems(vocalsTrack)
            for i = 0, numItems-1 do
                local item = reaper.GetTrackMediaItem(vocalsTrack, i)
                local take = reaper.GetActiveTake(item)
                
                if take and reaper.TakeIsMIDI(take) then
                    local _, hash = reaper.MIDI_GetHash(take, true)
                    currentHash = currentHash .. hash
                end
            end
        end
        
        -- Si el hash ha cambiado, necesitamos actualizar las letras
        if vocalsHash ~= currentHash then
            vocalsHash = currentHash
            return parseVocals() -- Analizar las letras de nuevo
        end
        
        return #phrases > 0
    end)
    
    -- En caso de error, devolver false
    if not success then
        return false
    end
    
    return result
end

-- Función para encontrar la pista PART VOCALS
function findVocalsTrack()
    vocalsTrack = findTrack("PART VOCALS")
    return vocalsTrack ~= nil
end

-- Función para encontrar la pista EVENTS
function findEventsTrack()
    eventsTrack = findTrack("EVENTS")
    return eventsTrack ~= nil
end

-- Función para parsear eventos de letras/Hero Power
function parseVocals()
    phrases = {}
    
    if not vocalsTrack then
        if not findVocalsTrack() then
            return false
        end
    end
    
    local numItems = reaper.CountTrackMediaItems(vocalsTrack)
    local currentHash = ""
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(vocalsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            local _, hash = reaper.MIDI_GetHash(take, true)
            currentHash = currentHash .. hash
        end
    end
    
    if vocalsHash == currentHash and #phrases > 0 then
        return true  -- No hay cambios, usar las frases ya parseadas
    end
    
    vocalsHash = currentHash
    phrases = {}  -- Reiniciar frases
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(vocalsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            -- Descomentar para depurar eventos
            -- debugTextEvents(take)
            
            local _, noteCount, _, textSysexCount = reaper.MIDI_CountEvts(take)
            -- reaper.ShowConsoleMsg("Item " .. i .. ": " .. noteCount .. " notas, " .. textSysexCount .. " eventos de texto\n")
            
            -- NUEVO: Recolectar todas las notas de Hero Power
            local heroPowerNotes = {}
            for n = 0, noteCount-1 do
                local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                if pitch == HP then
                    local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                    local noteEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                    table.insert(heroPowerNotes, {startTime = noteStartTime, endTime = noteEndTime})
                end
            end
            
            -- Busca los marcadores de frases
            for j = 0, noteCount-1 do
                local _, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(take, j)
                local startTime = reaper.MIDI_GetProjQNFromPPQPos(take, startppq)
                local endTime = reaper.MIDI_GetProjQNFromPPQPos(take, endppq)
                
                if pitch == phraseMarkerNote then
                    table.insert(phrases, createPhrase(startTime, endTime))
                end
            end
            
            -- Si no hay marcadores de frase, crear una frase que abarque todo el ítem
            if #phrases == 0 then
                local itemStart = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
                local itemEnd = itemStart + reaper.GetMediaItemInfo_Value(item, "D_LENGTH")
                local startQN = reaper.TimeMap2_timeToQN(0, itemStart)
                local endQN = reaper.TimeMap2_timeToQN(0, itemEnd)
                table.insert(phrases, createPhrase(startQN, endQN))
                -- reaper.ShowConsoleMsg("Creada frase automática para todo el ítem\n")
            end
            
            -- NOTA: En Reaper, los eventos de texto de tipo "Letras"
            -- no necesariamente están asociados con notas. Se leerán directamente.
            local textEvents = {}
			for j = 0, textSysexCount-1 do
				local retval, selected, muted, ppqpos, type, msg = reaper.MIDI_GetTextSysexEvt(take, j)
				
				if retval and msg and msg ~= "" then
					local time = reaper.MIDI_GetProjQNFromPPQPos(take, ppqpos)
					local foundPitch = nil
					local noteEndTime = time + 0.25  -- Duración predeterminada
					
					-- Buscar una nota MIDI que coincida con este evento de texto
					for n = 0, noteCount-1 do
						local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
						local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
						local nEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
						
						-- Si la nota no es un marcador de frase y coincide con el tiempo del evento
						if pitch ~= phraseMarkerNote and math.abs(noteStartTime - time) < 0.01 then
							foundPitch = pitch
							noteEndTime = nEndTime
							break
						end
					end
					
					table.insert(textEvents, {
						text = msg,
						time = time,
						endTime = noteEndTime,
						pitch = foundPitch
					})
				end
			end
            
            -- Ordenar eventos de texto por tiempo
            table.sort(textEvents, function(a, b) return a.time < b.time end)
            
            -- Buscar notas asociadas a los eventos de texto para obtener duración
            for _, event in ipairs(textEvents) do
                for n = 0, noteCount-1 do
                    local _, _, _, noteStartppq, noteEndppq, _, pitch, _ = reaper.MIDI_GetNote(take, n)
                    local noteStartTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteStartppq)
                    local noteEndTime = reaper.MIDI_GetProjQNFromPPQPos(take, noteEndppq)
                    
                    -- Si la nota no es un marcador de frase y coincide con el tiempo del evento
                    if pitch ~= phraseMarkerNote and math.abs(noteStartTime - event.time) < 0.01 then
                        event.endTime = noteEndTime
                        break
                    end
                end
            end
            
            -- Asignar eventos de texto a frases
			for _, event in ipairs(textEvents) do
				local assignedToPhrase = false
				
				for k, phrase in ipairs(phrases) do
					if event.time >= phrase.startTime and event.time <= phrase.endTime then
                        -- MODIFICADO: Comprobar si este evento coincide con alguna nota Hero Power
                        local hasHeroPower = false
                        for _, hpNote in ipairs(heroPowerNotes) do
                            -- Comprobar si el evento está dentro del rango de la nota Hero Power
                            -- o muy cercano a su inicio (con un margen de tolerancia mayor)
                            if (event.time >= hpNote.startTime and event.time <= hpNote.endTime) or
                               math.abs(event.time - hpNote.startTime) < 0.03 then
                                hasHeroPower = true
                                break
                            end
                        end
                        
						table.insert(phrase.lyrics, createLyric(
							event.text,
							event.time,
							event.endTime,
							event.pitch,
							hasHeroPower  -- Pasar el flag de Hero Power
						))
						assignedToPhrase = true
						break
					end
				end
                
                -- Si no se asignó a ninguna frase, crear una nueva frase
                if not assignedToPhrase and #phrases > 0 then
                    -- Asignar al más cercano
                    local closestPhrase = 1
                    local minDistance = math.huge
                    
                    for k, phrase in ipairs(phrases) do
                        local distance = math.min(
                            math.abs(event.time - phrase.startTime),
                            math.abs(event.time - phrase.endTime)
                        )
                        
                        if distance < minDistance then
                            minDistance = distance
                            closestPhrase = k
                        end
                    end
                    
                    -- MODIFICADO: Comprobar si este evento coincide con alguna nota Hero Power
                    local hasHeroPower = false
                    for _, hpNote in ipairs(heroPowerNotes) do
                        -- Comprobar si el evento está dentro del rango de la nota Hero Power
                        -- o muy cercano a su inicio (con un margen de tolerancia mayor)
                        if (event.time >= hpNote.startTime and event.time <= hpNote.endTime) or
                           math.abs(event.time - hpNote.startTime) < 0.03 then
                            hasHeroPower = true
                            break
                        end
                    end
                    
					table.insert(phrases[closestPhrase].lyrics, createLyric(
						event.text,
						event.time,
						event.endTime,
						event.pitch,
						hasHeroPower  -- Pasar el flag de Hero Power
					))
				end
			end
        end
    end
    
    -- Ordenar las letras dentro de cada frase por tiempo de inicio
    for k, phrase in ipairs(phrases) do
        table.sort(phrase.lyrics, function(a, b) return a.startTime < b.startTime end)
        -- reaper.ShowConsoleMsg("Frase " .. k .. ": " .. #phrase.lyrics .. " eventos de texto\n")
    end
    
    -- Ordenar las frases por tiempo de inicio
    table.sort(phrases, function(a, b) return a.startTime < b.startTime end)
    
    return #phrases > 0
end

-- Función para actualizar el estado activo de las letras basado en el tiempo actual
function updateLyricsActiveState(currentTime)
    -- Encontrar la frase actual
    currentPhrase = 1
    for i, phrase in ipairs(phrases) do
        if currentTime >= phrase.startTime then
            currentPhrase = i
        end
    end
    
    -- Actualizar todas las letras en todas las frases
    for _, phrase in ipairs(phrases) do
        for i, lyric in ipairs(phrase.lyrics) do
            -- Una letra está activa normalmente si el tiempo actual está entre su inicio y fin
            local isCurrentlyActive = (currentTime >= lyric.startTime and currentTime <= lyric.endTime)
            
            -- Comprobar si hay que extender el tiempo activo debido a signos +
            local extendedActive = false
            local extendedEndTime = lyric.endTime
            
            -- Buscar hacia adelante para encontrar todos los + consecutivos
            local j = i + 1
            while j <= #phrase.lyrics do
                local nextLyric = phrase.lyrics[j]
                -- Si la siguiente letra comienza con +, extender la activación
                if nextLyric.originalText:find("^%+") then
                    extendedEndTime = nextLyric.endTime
                    -- Extender el tiempo activo hasta incluir este +
                    if currentTime >= lyric.startTime and currentTime <= extendedEndTime then
                        extendedActive = true
                    end
                    j = j + 1  -- Seguir buscando más +
                else
                    break  -- No hay más + consecutivos
                end
            end
            
            -- La letra está activa si cumple los criterios normales o la extensión de los +
            lyric.isActive = isCurrentlyActive or extendedActive
            
            -- Una letra está cantada si ya pasó su tiempo final extendido
            lyric.hasBeenSung = (currentTime > extendedEndTime)
            
            -- Caso especial: si una letra está activa, no está cantada todavía
            if lyric.isActive then
                lyric.hasBeenSung = false
            end
            
            -- Las letras que son + no deben mostrar su propio estado activo
            -- ya que ese tiempo lo absorbe la letra anterior
			if lyric.originalText:find("^%+") then
				if i > 1 and phrase.lyrics[i-1].isActive then
					lyric.isActive = true  -- heredar estado activo si la anterior está activa
				end
			end
        end
    end
end

function drawLyricsVisualizer()
    if #phrases == 0 then
        return
    end
    
    -- Calcular posición y dimensiones para el visualizador de letras con los nuevos valores
    local visualizerHeight = lyricsConfig.height
    local visualizerY = gfx.h - visualizerHeight - 40 + lyricsConfig.bottomMargin
    
    -- Dibujar fondo para el visualizador con opacidad ajustada
    gfx.r, gfx.g, gfx.b, gfx.a = 0.1, 0.1, 0.15, lyricsConfig.bgOpacity
    gfx.rect(0, visualizerY - 30, gfx.w, visualizerHeight + 40, 1)
    
    -- Encontrar la frase actual y la siguiente
    local currentPhraseObj = phrases[currentPhrase]
    local nextPhraseObj = currentPhrase < #phrases and phrases[currentPhrase + 1] or nil
    
    -- Configuración para las líneas de notas
    local noteLineConfig = {
        activeColor = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color cian para notas activas
        inactiveColor = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color cian para notas inactivas
        sungColor = {r = 0.2, g = 0.8, b = 1.0, a = 1.0},  -- Color azul para notas ya cantadas
        hitColor = {r = 1.0, g = 1.0, b = 0.3, a = 1.0},    -- Color amarillo brillante para golpes
        linesSpacing = 9,  -- Separación entre las líneas superior e inferior
        specialNoteRadius = 7,  -- Radio para las notas especiales (26 y 29)
        minPitch = 26,  -- Nota MIDI más baja a mostrar (D1, rango mínimo según mis pruebas en GHL)
        maxPitch = 86,  -- Nota MIDI más alta a mostrar (D6, rango máximo según mis pruebas en GHL)
        areaHeight = 230,  -- Altura total del área de líneas de notas
        yOffset = visualizerY - 30,  -- Posición Y base para las líneas de notas
        hitLineX = 150,  -- Posición X de la línea de golpeo (recogedor)
        hitCircleRadius = 8,  -- Radio del círculo que aparece cuando se golpea una nota
        guideLineCount = 10  -- Número de líneas guía a dibujar (incluyendo la superior e inferior)
    }
    
    -- Solo dibujar el HUD de notas si está activado
    if showNotesHUD then
        -- Dibujar fondo para las líneas de notas
        gfx.r, gfx.g, gfx.b, gfx.a = 0.1, 0.1, 0.15, 0.8
        gfx.rect(0, noteLineConfig.yOffset - noteLineConfig.areaHeight, gfx.w, noteLineConfig.areaHeight, 1)
        
        -- Dibujar líneas guía horizontales (las líneas grises que dividen la zona de notas)
        gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 1.0, 0.065  -- Color gris semi-transparente
        
        -- Calculamos el espaciado vertical entre líneas guía
        local guideLineSpacing = noteLineConfig.areaHeight / (noteLineConfig.guideLineCount - 1)
        
        -- Dibujamos las líneas guía horizontales
        for i = 0, noteLineConfig.guideLineCount - 1 do
            local lineY = (noteLineConfig.yOffset - noteLineConfig.areaHeight) + (i * guideLineSpacing)
            gfx.line(0, lineY, gfx.w, lineY, 1)  -- Línea delgada
        end
        
        -- Dibujar varias líneas para crear una línea más gruesa (línea de golpeo vertical)
        gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 0.3, 0.3, 1.0  -- Color rojo para la línea de golpeo
        for i = -1, 1 do
            gfx.line(
                noteLineConfig.hitLineX + i, 
                noteLineConfig.yOffset - noteLineConfig.areaHeight, 
                noteLineConfig.hitLineX + i, 
                noteLineConfig.yOffset, 
                1
            )
        end
        
        -- Variable para rastrear si hay alguna nota activa cruzando la línea de golpeo
        local hitDetected = false
        local hitY = 0
        
        -- Función para dibujar líneas de notas para una frase
        local function drawNoteLines(phrase, opacity)
            if not phrase then return end
            
            -- Variables para rastrear la letra anterior
            local prevLyric = nil
            local prevEndX = nil
            local prevLineY = nil
            local prevUpperLineY = nil
            local prevLowerLineY = nil
            
            -- Variables para detectar primera y última nota de la frase
            local firstNoteIndex = nil
            local lastNoteIndex = nil
            
            -- Encontrar la primera y última nota con pitch en la frase
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    if not firstNoteIndex then
                        firstNoteIndex = i
                    end
                    lastNoteIndex = i
                end
            end
            
            -- Primera pasada: identificar las cadenas de notas conectadas
            local connectChains = {} -- Para rastrear las cadenas completas de notas conectadas
            local chainIds = {} -- Para asignar un ID único a cada cadena
            local nextChainId = 1
            
            -- Construir las cadenas de notas conectadas
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    if lyric.originalText:match("^%+") then
                        -- Esta es una nota conectora, buscar su nota anterior
                        local foundPrev = false
                        for j = i-1, 1, -1 do
                            if phrase.lyrics[j].pitch and phrase.lyrics[j].pitch > 0 then
                                -- Encontramos la nota anterior que está conectada a esta
                                foundPrev = true
                                
                                -- Verificar si la nota anterior ya pertenece a una cadena
                                if chainIds[j] then
                                    -- Añadir esta nota a la cadena existente
                                    chainIds[i] = chainIds[j]
                                    table.insert(connectChains[chainIds[j]], i)
                                else
                                    -- Crear una nueva cadena con ambas notas
                                    chainIds[j] = nextChainId
                                    chainIds[i] = nextChainId
                                    connectChains[nextChainId] = {j, i}
                                    nextChainId = nextChainId + 1
                                end
                                break
                            end
                        end
                    end
                end
            end
            
            -- Determinar qué cadenas deben iluminarse
            local shouldHighlight = {}
            local chainsToHighlight = {}
            
            -- Primero, verificar qué cadenas tienen al menos un elemento activo
            for i, lyric in ipairs(phrase.lyrics) do
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    local startTime = lyric.startTime
                    local endTime = lyric.endTime
                    local startX = noteLineConfig.hitLineX + (gfx.w - 40) * ((startTime - curBeat) / 4.0)
                    local endX = noteLineConfig.hitLineX + (gfx.w - 40) * ((endTime - curBeat) / 4.0)
                    
                    -- Si esta nota está activa (sin importar si cruza el recogedor)
                    if lyric.isActive then
                        if chainIds[i] then
                            -- Marcar toda esta cadena para iluminar
                            chainsToHighlight[chainIds[i]] = true
                        else
                            -- Es una nota individual, iluminarla si cruza el recogedor
                            if startX <= noteLineConfig.hitLineX and endX >= noteLineConfig.hitLineX then
                                shouldHighlight[i] = true
                            end
                        end
                    end
                end
            end
            
            -- Marcar todas las notas de las cadenas que deben iluminarse
            for chainId, highlight in pairs(chainsToHighlight) do
                if highlight then
                    for _, noteIndex in ipairs(connectChains[chainId]) do
                        shouldHighlight[noteIndex] = true
                    end
                end
            end
            
            -- Para notas que ya pasaron el recogedor pero están en una cadena activa
            for chainId, chain in pairs(connectChains) do
                -- Verificar si al menos una nota de la cadena está activa
                local chainActive = false
                for _, noteIndex in ipairs(chain) do
                    local lyric = phrase.lyrics[noteIndex]
                    if lyric.isActive then
                        chainActive = true
                        break
                    end
                end
                
                -- Si la cadena está activa, iluminar todas las notas incluso las que ya pasaron
                if chainActive then
                    for _, noteIndex in ipairs(connectChains[chainId]) do
                        shouldHighlight[noteIndex] = true
                    end
                end
            end
            
            for i, lyric in ipairs(phrase.lyrics) do
                -- Solo dibujar si tiene pitch (tono) y no es toneless (sin tono)
                if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                    -- Calcular posición Y basada en el pitch
                    local pitchRangeSize = noteLineConfig.maxPitch - noteLineConfig.minPitch
                    local pitchNormalized = (lyric.pitch - noteLineConfig.minPitch) / pitchRangeSize
                    pitchNormalized = math.max(0, math.min(1, pitchNormalized))  -- Asegurar que esté entre 0 y 1
                    
                    -- Centrar verticalmente las notas 26 y 29 en el HUD (estilo GHL)
                    local lineY
                    if lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless then
                        lineY = noteLineConfig.yOffset - noteLineConfig.areaHeight / 2
                    else
                        lineY = noteLineConfig.yOffset - noteLineConfig.areaHeight * pitchNormalized
                    end
                    
                    -- Calcular posición X y ancho basados en el tiempo
                    local timeRange = 4.5  -- Mostrar 4 beats en la pantalla
                    local timeOffset = curBeat  -- Tiempo actual
                    
                    -- Ajustar los tiempos para que la nota golpee la línea cuando sea activa
                    local startX = noteLineConfig.hitLineX + (gfx.w - 40) * ((lyric.startTime - timeOffset) / timeRange)
                    local endX = noteLineConfig.hitLineX + (gfx.w - 40) * ((lyric.endTime - timeOffset) / timeRange)
                    
                    -- Limitar a la ventana visible
                    local originalStartX = startX  -- Guarda el valor original antes de limitarlo
                    local originalEndX = endX
                    startX = math.max(150, math.min(gfx.w - 20, startX))
                    endX = math.max(20, math.min(gfx.w - 20, endX))
                    
                    -- Determinar si esta nota está visible
                    local isVisible = (endX > 20 and startX < gfx.w - 20)
                    
                    -- Verificar si la nota está tocando la línea de golpeo
                    local isHitting = (startX <= noteLineConfig.hitLineX and endX >= noteLineConfig.hitLineX and lyric.isActive)
                    
                    -- Verificar si esta nota debe iluminarse debido a una nota conectora
                    local shouldIlluminate = isHitting or shouldHighlight[i] or false
                    
                    -- Solo dibujar si la línea es visible
                    if isVisible then
                        -- Definir el color según el estado de la lírica
                        if shouldIlluminate then
                            -- Nota en una cadena activa o golpeando la línea - usar color de efecto de golpeo
                            gfx.r = noteLineConfig.hitColor.r
                            gfx.g = noteLineConfig.hitColor.g
                            gfx.b = noteLineConfig.hitColor.b
                            gfx.a = noteLineConfig.hitColor.a * opacity
                            
                            -- Solo registrar el golpe y su posición Y si realmente está tocando el recogedor
                            if isHitting then
                                hitDetected = true
                                hitY = lineY
                            end
                        elseif lyric.isActive then
                            gfx.r = noteLineConfig.activeColor.r
                            gfx.g = noteLineConfig.activeColor.g
                            gfx.b = noteLineConfig.activeColor.b
                            gfx.a = noteLineConfig.activeColor.a * opacity
                        elseif lyric.hasBeenSung then
                            gfx.r = noteLineConfig.sungColor.r
                            gfx.g = noteLineConfig.sungColor.g
                            gfx.b = noteLineConfig.sungColor.b
                            gfx.a = noteLineConfig.sungColor.a * opacity
                        else
                            gfx.r = noteLineConfig.inactiveColor.r
                            gfx.g = noteLineConfig.inactiveColor.g
                            gfx.b = noteLineConfig.inactiveColor.b
                            gfx.a = noteLineConfig.inactiveColor.a * opacity
                        end
                        
                        -- Calcular las posiciones Y para las líneas superior e inferior
                        local upperLineY = lineY - noteLineConfig.linesSpacing/2
                        local lowerLineY = lineY + noteLineConfig.linesSpacing/2
                        
                        -- Solo dibujar la parte de las líneas que están a la derecha del recogedor
                        local visibleStartX = math.max(startX, noteLineConfig.hitLineX)
                        
                        -- Solo dibujar si al menos parte de la nota está a la derecha del recogedor
                        if endX > noteLineConfig.hitLineX then
                            -- Comprobar si es una nota especial (pitch 26 o 29)
                            if lyric.pitch == 29 then
                                -- Nota 29: Dibujar solo un círculo
                                local circleRadius = noteLineConfig.specialNoteRadius
                                if startX >= noteLineConfig.hitLineX then
                                    gfx.circle(startX, lineY, circleRadius, 1, 1)
                                elseif endX > noteLineConfig.hitLineX then
                                    gfx.circle(noteLineConfig.hitLineX, lineY, circleRadius, 1, 1)
                                end
                            elseif lyric.pitch == 26 or lyric.isToneless then
                                -- Nota 26: Dibujar círculo al inicio y líneas normales
                                local circleRadius = noteLineConfig.specialNoteRadius
                                gfx.line(visibleStartX, upperLineY, endX, upperLineY, 1) -- Línea superior
                                gfx.line(visibleStartX, lowerLineY, endX, lowerLineY, 1) -- Línea inferior
                                if startX >= noteLineConfig.hitLineX then
                                    gfx.circle(startX, lineY, circleRadius, 1, 1)
                                elseif endX > noteLineConfig.hitLineX then
                                    gfx.circle(noteLineConfig.hitLineX, lineY, circleRadius, 1, 1)
                                end
                                if i == lastNoteIndex and endX < gfx.w - 20 then
                                    gfx.line(endX, upperLineY, endX, lowerLineY, 1)
                                end
                            else
                                -- Notas normales: Dibujar las dos líneas horizontales
                                gfx.line(visibleStartX, upperLineY, endX, upperLineY, 1) -- Línea superior
                                gfx.line(visibleStartX, lowerLineY, endX, lowerLineY, 1) -- Línea inferior
                                if i == firstNoteIndex and visibleStartX == startX then
                                    gfx.line(startX, upperLineY, startX, lowerLineY, 1)
                                end
                                if i == lastNoteIndex and endX < gfx.w - 20 then
                                    gfx.line(endX, upperLineY, endX, lowerLineY, 1)
                                end
                            end
                        end
                    end
                    
                    -- Guardar información de esta nota para la próxima iteración
                    prevLyric = lyric
                    prevEndX = endX
                    prevLineY = lineY
                    prevUpperLineY = upperLineY
                    prevLowerLineY = lowerLineY
                end
            end
            
            -- Reiniciar el prevLyric para la siguiente frase
            prevLyric = nil
            prevEndX = nil
            prevLineY = nil
        end
        
        -- Nueva función para dibujar las líneas conectoras grises para todas las frases visibles
        local function drawAllGreyConnectorLines()
            local timeRange = 4.5
            local timeOffset = curBeat
            local pitchRangeSize = noteLineConfig.maxPitch - noteLineConfig.minPitch
            
            -- Iterar sobre todas las frases visibles (actual + 4 futuras)
            for phraseIndex = currentPhrase, math.min(currentPhrase + 4, #phrases) do
                local phrase = phrases[phraseIndex]
                if not phrase then break end
                
                -- Usar opacidad fija para todas las frases
                local opacity = 0.2
                
                -- Dibujar conexiones dentro de la frase actual
                for i = 1, #phrase.lyrics - 1 do
                    local currentLyric = phrase.lyrics[i]
                    local nextLyric = phrase.lyrics[i + 1]
                    
                    -- Solo conectar si ambas notas tienen pitch y no son notas de Hero Power (HP)
                    if currentLyric.pitch and nextLyric.pitch and 
                       currentLyric.pitch > 0 and nextLyric.pitch > 0 and 
                       currentLyric.pitch ~= HP and nextLyric.pitch ~= HP then
                        
                        -- Calcular posiciones Y basadas en los pitches o si es toneless
                        local currentLineY
                        if currentLyric.pitch == 26 or currentLyric.pitch == 29 or currentLyric.isToneless then
                            currentLineY = noteLineConfig.yOffset - noteLineConfig.areaHeight / 2
                        else
                            local currentPitchNormalized = (currentLyric.pitch - noteLineConfig.minPitch) / pitchRangeSize
                            currentPitchNormalized = math.max(0, math.min(1, currentPitchNormalized))
                            currentLineY = noteLineConfig.yOffset - noteLineConfig.areaHeight * currentPitchNormalized
                        end
                        
                        local nextLineY
                        if nextLyric.pitch == 26 or nextLyric.pitch == 29 or nextLyric.isToneless then
                            nextLineY = noteLineConfig.yOffset - noteLineConfig.areaHeight / 2
                        else
                            local nextPitchNormalized = (nextLyric.pitch - noteLineConfig.minPitch) / pitchRangeSize
                            nextPitchNormalized = math.max(0, math.min(1, nextPitchNormalized))
                            nextLineY = noteLineConfig.yOffset - noteLineConfig.areaHeight * nextPitchNormalized
                        end
                        
                        -- Calcular posiciones X basadas en tiempos
                        local currentEndX = noteLineConfig.hitLineX + (gfx.w - 40) * ((currentLyric.endTime - timeOffset) / timeRange)
                        local nextStartX = noteLineConfig.hitLineX + (gfx.w - 40) * ((nextLyric.startTime - timeOffset) / timeRange)
                        
                        -- Determinar si la conexión es visible (al menos una parte debe estar en el HUD)
                        local isVisible = (currentEndX < gfx.w - 20 and nextStartX > 20)
                        
                        if isVisible then
                            -- Calcular posiciones Y para las líneas superior e inferior
                            local upperCurrentY = currentLineY - noteLineConfig.linesSpacing/2
                            local lowerCurrentY = currentLineY + noteLineConfig.linesSpacing/2
                            local upperNextY = nextLineY - noteLineConfig.linesSpacing/2
                            local lowerNextY = nextLineY + noteLineConfig.linesSpacing/2
                            
                            -- Guardar los valores originales de X para los cálculos de interpolación
                            local originalCurrentEndX = currentEndX
                            local originalNextStartX = nextStartX
                            
                            -- Limitar las posiciones X para que no se dibujen a la izquierda de la línea de golpeo (x = 150)
                            currentEndX = math.max(noteLineConfig.hitLineX, currentEndX)
                            nextStartX = math.max(noteLineConfig.hitLineX, nextStartX)
                            
                            -- Ajustar también para que no se dibujen fuera del HUD
                            currentEndX = math.min(gfx.w - 20, currentEndX)
                            nextStartX = math.min(gfx.w - 20, nextStartX)
                            
                            -- Si ajustamos currentEndX, interpolar las posiciones Y correspondientes
                            if currentEndX ~= originalCurrentEndX then
                                local mUpper = (upperNextY - upperCurrentY) / (originalNextStartX - originalCurrentEndX)
                                local mLower = (lowerNextY - lowerCurrentY) / (originalNextStartX - originalCurrentEndX)
                                upperCurrentY = upperCurrentY + mUpper * (currentEndX - originalCurrentEndX)
                                lowerCurrentY = lowerCurrentY + mLower * (currentEndX - originalCurrentEndX)
                            end
                            
                            -- Si ajustamos nextStartX, interpolar las posiciones Y correspondientes
                            if nextStartX ~= originalNextStartX then
                                local mUpper = (upperNextY - upperCurrentY) / (originalNextStartX - originalCurrentEndX)
                                local mLower = (lowerNextY - lowerCurrentY) / (originalNextStartX - originalCurrentEndX)
                                upperNextY = upperCurrentY + mUpper * (nextStartX - originalCurrentEndX)
                                lowerNextY = lowerCurrentY + mLower * (nextStartX - originalCurrentEndX)
                            end
                            
                            -- Solo dibujar si las posiciones X son diferentes (evitar líneas verticales)
                            if currentEndX ~= nextStartX and nextStartX >= noteLineConfig.hitLineX then
                                -- Usar opacidad fija para las líneas conectoras grises
                                gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 1.0, opacity
                                -- Línea superior
                                gfx.line(currentEndX, upperCurrentY, nextStartX, upperNextY, 1)
                                -- Línea inferior
                                gfx.line(currentEndX, lowerCurrentY, nextStartX, lowerNextY, 1)
                            end
                        end
                    end
                end
            end
        end
        
        -- Función ajustada para dibujar las líneas conectoras "+" con iluminación y movimiento correcto del círculo
        local function drawAllPlusConnectorLines()
            local timeRange = 4.5
            local timeOffset = curBeat
            local pitchRangeSize = noteLineConfig.maxPitch - noteLineConfig.minPitch
            
            -- Iterar sobre todas las frases visibles (actual + 4 futuras)
            for phraseIndex = currentPhrase, math.min(currentPhrase + 4, #phrases) do
                local phrase = phrases[phraseIndex]
                if not phrase then break end
                
                -- Usar opacidad fija para todas las frases
                local opacity = 1.0
                
                -- Variables para rastrear la nota anterior
                local prevLyric = nil
                local prevEndX = nil
                local prevLineY = nil
                
                -- Iterar sobre las letras de la frase para encontrar notas con "+"
                for i, lyric in ipairs(phrase.lyrics) do
                    -- Solo procesar si tiene pitch y no es Hero Power (HP)
                    if lyric.pitch and lyric.pitch > 0 and lyric.pitch ~= HP then
                        -- Calcular posición Y basada en el pitch
                        local pitchNormalized = (lyric.pitch - noteLineConfig.minPitch) / pitchRangeSize
                        pitchNormalized = math.max(0, math.min(1, pitchNormalized))
                        
                        local lineY
                        if lyric.pitch == 26 or lyric.pitch == 29 or lyric.isToneless then
                            lineY = noteLineConfig.yOffset - noteLineConfig.areaHeight / 2
                        else
                            lineY = noteLineConfig.yOffset - noteLineConfig.areaHeight * pitchNormalized
                        end
                        
                        -- Calcular posición X basada en el tiempo
                        local startX = noteLineConfig.hitLineX + (gfx.w - 40) * ((lyric.startTime - timeOffset) / timeRange)
                        local endX = noteLineConfig.hitLineX + (gfx.w - 40) * ((lyric.endTime - timeOffset) / timeRange)
                        
                        -- Dibujar línea conectora si esta es una sílaba "+"
                        if lyric.originalText:match("^%+") and prevLyric then
                            -- Determinar si la línea es visible (al menos parcialmente)
                            local isVisible = (prevEndX < gfx.w - 20 and startX > noteLineConfig.hitLineX)
                            
                            if isVisible then
                                -- Ajustar los puntos de inicio y fin para que estén dentro del HUD
                                local drawStartX = prevEndX
                                local drawStartY = prevLineY
                                local drawEndX = startX
                                local drawEndY = lineY
                                
                                -- Guardar los valores originales para cálculos de interpolación y detección de golpeo
                                local originalStartX = drawStartX
                                local originalStartY = drawStartY -- Guardar el valor original de Y
                                local originalEndX = drawEndX
                                local originalEndY = drawEndY -- Guardar el valor original de Y
                                local originalStartTime = prevLyric.endTime
                                local originalEndTime = lyric.startTime
                                
                                -- Si el inicio está a la izquierda del recogedor, calcular la intersección
                                if drawStartX < noteLineConfig.hitLineX then
                                    local m = (drawEndY - drawStartY) / (drawEndX - drawStartX)
                                    drawStartX = noteLineConfig.hitLineX
                                    drawStartY = drawStartY + m * (noteLineConfig.hitLineX - originalStartX)
                                end
                                
                                -- Si el final está más allá del borde derecho, calcular la intersección
                                if drawEndX > gfx.w - 20 then
                                    local m = (drawEndY - drawStartY) / (drawEndX - drawStartX)
                                    drawEndX = gfx.w - 20
                                    drawEndY = drawStartY + m * (gfx.w - 20 - originalStartX)
                                end
                                
                                -- Calcular las posiciones Y para las líneas superior e inferior
                                local startUpperY = drawStartY - noteLineConfig.linesSpacing/2
                                local startLowerY = drawStartY + noteLineConfig.linesSpacing/2
                                local endUpperY = drawEndY - noteLineConfig.linesSpacing/2
                                local endLowerY = drawEndY + noteLineConfig.linesSpacing/2
                                
                                -- Verificar si la línea conectora está activa (basado en el tiempo de la nota conectora)
                                local isConnectorActive = lyric.isActive
                                
                                -- Aplicar color según el estado de la línea conectora
                                if isConnectorActive then
                                    -- Línea conectora activa: usar color de golpeo
                                    gfx.r = noteLineConfig.hitColor.r
                                    gfx.g = noteLineConfig.hitColor.g
                                    gfx.b = noteLineConfig.hitColor.b
                                    gfx.a = noteLineConfig.hitColor.a * opacity
                                else
                                    -- Línea conectora inactiva: usar el mismo color que las líneas de notas inactivas (cian)
                                    gfx.r = noteLineConfig.inactiveColor.r
                                    gfx.g = noteLineConfig.inactiveColor.g
                                    gfx.b = noteLineConfig.inactiveColor.b
                                    gfx.a = noteLineConfig.inactiveColor.a * opacity
                                end
                                
                                -- Dibujar las dos líneas diagonales
                                gfx.line(drawStartX, startUpperY, drawEndX, endUpperY, 1) -- Línea superior
                                gfx.line(drawStartX, startLowerY, drawEndX, endLowerY, 1) -- Línea inferior
                                
                                -- Detectar si la línea conectora está activa y cruza el recogedor
                                if isConnectorActive and originalStartX < noteLineConfig.hitLineX and originalEndX > noteLineConfig.hitLineX then
                                    -- Calcular la posición Y donde la línea conectora intersecta el recogedor
                                    -- usando la ecuación de la recta: y = m*(x - x1) + y1
                                    -- donde m = (y2 - y1) / (x2 - x1)
                                    -- Usar los valores originales para evitar errores por ajustes previos
                                    local m = (originalEndY - originalStartY) / (originalEndX - originalStartX)
                                    local hitConnectorY = originalStartY + m * (noteLineConfig.hitLineX - originalStartX)
                                    
                                    -- Activar el círculo en el recogedor
                                    hitDetected = true
                                    hitY = hitConnectorY -- Actualizar la posición del círculo amarillo
                                end
                            end
                        end
                        
                        -- Guardar información de esta nota para la próxima iteración
                        prevLyric = lyric
                        prevEndX = endX
                        prevLineY = lineY
                    end
                end
            end
        end
        
        -- Dibujar líneas de notas para varias frases futuras (actual + 4 más)
        drawNoteLines(currentPhraseObj, 1.0)
        
        -- Dibujar las próximas 4 frases con la misma opacidad (1.0)
        for i = 1, 4 do
            local nextPhrase = currentPhrase + i
            if nextPhrase <= #phrases then
                local nextPhraseObj = phrases[nextPhrase]
                drawNoteLines(nextPhraseObj, 1.0)
            end
        end
        
        -- Dibujar todas las líneas conectoras grises
        drawAllGreyConnectorLines()
        
        -- Dibujar todas las líneas conectoras "+"
        drawAllPlusConnectorLines()
        
        -- Dibujar el efecto de golpeo si se detectó
        if hitDetected then
            -- Dibujar círculos de efecto en la línea de golpeo
            gfx.r, gfx.g, gfx.b, gfx.a = noteLineConfig.hitColor.r, noteLineConfig.hitColor.g, noteLineConfig.hitColor.b, 0.7
            local outerRadius = noteLineConfig.hitCircleRadius * 1.5
            gfx.circle(noteLineConfig.hitLineX, hitY, outerRadius, 0, 1)
            
            -- Dibujar círculo interno
            gfx.r, gfx.g, gfx.b, gfx.a = 1.0, 1.0, 0.3, 1.0
            gfx.circle(noteLineConfig.hitLineX, hitY, noteLineConfig.hitCircleRadius, 1, 1)
        end
    end
    
    -- Dibujar título del visualizador
    gfx.r, gfx.g, gfx.b, gfx.a = 1, 1, 1, 1
    gfx.setfont(1, "SDK_JP_Web 85W", 18)
    local titleText = "Phrase: " .. currentPhrase .. "/" .. #phrases
    local titleW, titleH = gfx.measurestr(titleText)
    
    gfx.x, gfx.y = (gfx.w - titleW) / 2, visualizerY - 25
    gfx.drawstr(titleText)
    
    -- Función para renderizar una frase con los espacios correctos
    local function renderPhrase(phrase, font_size, y_pos, alpha_mult)
        if #phrase.lyrics == 0 then
            gfx.r, gfx.g, gfx.b, gfx.a = 1, 1, 1, alpha_mult or 1
            gfx.setfont(1, "SDK_JP_Web 85W", font_size)
            local noLyricsText = "[No lyrics found]"
            local textW, _ = gfx.measurestr(noLyricsText)
            gfx.x, gfx.y = (gfx.w - textW) / 2, y_pos
            gfx.drawstr(noLyricsText)
            return
        end
        
        -- Primero, agrupa las letras basándose en conectores
        local word_groups = {}
        local current_group = {}
        
        for i, lyric in ipairs(phrase.lyrics) do
            table.insert(current_group, lyric)
            
            -- Si esta letra no termina con guion, o es la última letra de la frase,
            -- cierra el grupo actual y comienza uno nuevo
            if not lyric.endsWithHyphen or i == #phrase.lyrics then
                table.insert(word_groups, current_group)
                current_group = {}
            end
        end
        
        -- Ahora calcular el ancho total incluyendo espacios entre palabras
        gfx.setfont(1, "SDK_JP_Web 85W", font_size)
        local spaceWidth = gfx.measurestr(" ")
        local totalWidth = 0
        
        for i, group in ipairs(word_groups) do
            for _, lyric in ipairs(group) do
                local textW, _ = gfx.measurestr(lyric.text)
                totalWidth = totalWidth + textW
            end
            
            -- Añadir espacio después de cada grupo excepto el último
            if i < #word_groups then
                totalWidth = totalWidth + spaceWidth
            end
        end
        
        -- Dibujar los grupos de palabras
        local startX = (gfx.w - totalWidth) / 2
        
        for i, group in ipairs(word_groups) do
            for j, lyric in ipairs(group) do
                local textW, _ = gfx.measurestr(lyric.text)
                
                -- Establecer color basado en el estado, si es sin tono o si tiene Hero Power
                if lyric.hasHeroPower then
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPowerActive.r, textColorHeroPowerActive.g, textColorHeroPowerActive.b, textColorHeroPowerActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPowerSung.r, textColorHeroPowerSung.g, textColorHeroPowerSung.b, textColorHeroPowerSung.a * (alpha_mult or 1)
                    else
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorHeroPower.r, textColorHeroPower.g, textColorHeroPower.b, textColorHeroPower.a * (alpha_mult or 1)
                    end
                elseif lyric.isToneless then
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorTonelessActive.r, textColorTonelessActive.g, textColorTonelessActive.b, textColorTonelessActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorTonelessSung.r, textColorTonelessSung.g, textColorTonelessSung.b, textColorTonelessSung.a * (alpha_mult or 1)
                    else
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorToneless.r, textColorToneless.g, textColorToneless.b, textColorToneless.a * (alpha_mult or 1)
                    end
                else
                    if lyric.isActive then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorActive.r, textColorActive.g, textColorActive.b, textColorActive.a * (alpha_mult or 1)
                    elseif lyric.hasBeenSung then
                        gfx.r, gfx.g, gfx.b, gfx.a = textColorSung.r, textColorSung.g, textColorSung.b, textColorSung.a * (alpha_mult or 1)
                    else
                        if alpha_mult and alpha_mult < 1.0 then
                            gfx.r, gfx.g, gfx.b, gfx.a = textColorNextPhrase.r, textColorNextPhrase.g, textColorNextPhrase.b, textColorNextPhrase.a * (alpha_mult or 1)
                        else
                            gfx.r, gfx.g, gfx.b, gfx.a = textColorInactive.r, textColorInactive.g, textColorInactive.b, textColorInactive.a * (alpha_mult or 1)
                        end
                    end
                end
                
                gfx.x, gfx.y = startX, y_pos
                gfx.drawstr(lyric.text)
                startX = startX + textW
            end
            
            -- Añadir espacio después de cada grupo excepto el último
            if i < #word_groups then
                startX = startX + spaceWidth
            end
        end
    end
    
    -- Dibujar la frase actual con tamaño ajustado
    if currentPhraseObj then
        gfx.r, gfx.g, gfx.b, gfx.a = bgColorLyrics.r, bgColorLyrics.g, bgColorLyrics.b, bgColorLyrics.a
        gfx.rect(20, visualizerY, gfx.w - 40, lyricsConfig.phraseHeight, 1)
        renderPhrase(currentPhraseObj, lyricsConfig.fontSize.current, visualizerY + 6)
    end
    
    -- Dibujar la próxima frase con tamaño ajustado
    if nextPhraseObj then
        gfx.r, gfx.g, gfx.b, gfx.a = bgColorLyrics.r * 0.8, bgColorLyrics.g * 0.8, bgColorLyrics.b * 0.8, bgColorLyrics.a * 0.8
        gfx.rect(20, visualizerY + lyricsConfig.phraseHeight + lyricsConfig.phraseSpacing, 
                 gfx.w - 40, lyricsConfig.phraseHeight, 1)
        renderPhrase(nextPhraseObj, lyricsConfig.fontSize.next, 
                    visualizerY + lyricsConfig.phraseHeight + lyricsConfig.phraseSpacing + 6, 0.9)
    end
end

-- Función para actualizar el estado de las letras y dibujarlas
function updateAndDrawLyrics()
    -- Verificar si hay proyecto activo
    if not isProjectOpen() then
        return
    end
    
    -- Verificar si hay letras válidas
    if #phrases == 0 then
        -- Intentar analizar las letras si aún no se ha hecho
        local success = pcall(function() return parseVocals() end)
        if not success or #phrases == 0 then 
            return 
        end
    end
    
    -- Actualizar el estado activo de las letras
    updateLyricsActiveState(curBeat)
    
    -- Dibujar el visualizador de letras
    drawLyricsVisualizer()
end


-- Función para parsear los eventos de sección de la pista EVENTS
function parseSections()
    sections = {}
    
    if not eventsTrack then
        if not findEventsTrack() then
            return false
        end
    end
    
    local numItems = reaper.CountTrackMediaItems(eventsTrack)
    local currentHash = ""
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(eventsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            local _, hash = reaper.MIDI_GetHash(take, true)
            currentHash = currentHash .. hash
        end
    end
    
    if eventsHash == currentHash and #sections > 0 then
        return true  -- No hay cambios, usar las secciones ya parseadas
    end
    
    eventsHash = currentHash
    sections = {}  -- Reiniciar secciones
    
    for i = 0, numItems-1 do
        local item = reaper.GetTrackMediaItem(eventsTrack, i)
        local take = reaper.GetActiveTake(item)
        
        if reaper.TakeIsMIDI(take) then
            local _, _, _, textSysexCount = reaper.MIDI_CountEvts(take)
            
            for j = 0, textSysexCount-1 do
                local retval, selected, muted, ppqpos, type, msg = reaper.MIDI_GetTextSysexEvt(take, j)
                
                if retval and msg and msg ~= "" then
                    -- Intentar detectar primero el formato [section Nombre]
                    local sectionName = msg:match("%[section%s+(.-)%]")
                    
                    -- Si no encuentra el formato [section Nombre], usar el texto completo
                    if not sectionName then
                        -- Limpiar el texto si contiene corchetes o está en otro formato
                        sectionName = msg:gsub("%[.*%]", ""):gsub("^%s*(.-)%s*$", "%1")
                        
                        -- Si después de limpiar, sigue habiendo contenido, usarlo como nombre de sección
                        if sectionName == "" then
                            sectionName = msg  -- Usar el mensaje completo si la limpieza resultó en un string vacío
                        end
                    end
                    
                    -- Solo añadir si hay un nombre de sección
                    if sectionName and sectionName ~= "" then
                        local time = reaper.MIDI_GetProjQNFromPPQPos(take, ppqpos)
                        table.insert(sections, {time = time, name = sectionName})
                    end
                end
            end
        end
    end
    
    -- Ordenar las secciones por tiempo
    table.sort(sections, function(a, b) return a.time < b.time end)
    
    return #sections > 0
end

-- Función para actualizar la sección actual basada en el tiempo
function updateCurrentSection(currentTime)
    currentSection = 1
    
    for i = 1, #sections do
        if currentTime >= sections[i].time then
            currentSection = i
        else
            break
        end
    end
end

-- Función para dibujar la sección actual
function drawCurrentSection()
    if #sections == 0 or currentSection > #sections then
        return
    end
    
    local config = sectionDisplayConfig
    local currentTime = curBeat
    local section = sections[currentSection]
    local nextSection = currentSection < #sections and sections[currentSection + 1] or nil
    
    -- Calcular opacidad (fade out cercano a la siguiente sección)
    local opacity = 1.0
    if nextSection then
        local timeToNext = nextSection.time - currentTime
        if timeToNext < config.fadeTime then
            opacity = timeToNext / config.fadeTime
            opacity = math.max(0.1, opacity)  -- No desaparece completamente
        end
    end
    
    -- Guardar los valores originales de color y alfa
    local orig_r, orig_g, orig_b, orig_a = gfx.r, gfx.g, gfx.b, gfx.a
    
    -- Dibujar fondo
    gfx.r, gfx.g, gfx.b, gfx.a = config.bgColor.r, config.bgColor.g, config.bgColor.b, config.bgColor.a * opacity
    gfx.rect(config.xOffset, config.yOffset, config.width, config.height, 1)
    
    -- Dibujar borde
    gfx.r, gfx.g, gfx.b, gfx.a = 0.8, 0.8, 0.9, opacity
    gfx.rect(config.xOffset, config.yOffset, config.width, config.height, 0)
    
    -- Dibujar texto
    gfx.r, gfx.g, gfx.b, gfx.a = config.textColor.r, config.textColor.g, config.textColor.b, config.textColor.a * opacity
    gfx.setfont(1, "SDK_JP_Web 85W", config.fontSize)
    
    local sectionText = section.name
    local textW, textH = gfx.measurestr(sectionText)
    local textX = config.xOffset + (config.width - textW) / 2
    local textY = config.yOffset + (config.height - textH) / 2
    
    gfx.x, gfx.y = textX, textY
    gfx.drawstr(sectionText)
    
    -- Restaurar los valores originales de color y alfa
    gfx.r, gfx.g, gfx.b, gfx.a = orig_r, orig_g, orig_b, orig_a
end

function mapLane(lane)
    -- Si el carril es 0 (open note), asignar a los tres carriles para máxima perspectiva
    if lane == 0 then
        return {1, 2, 3}  -- Devuelve una tabla con los tres carriles
    end
    
    -- Se ajusta el mapeo para que el carril sea correctamente asignado
    return {(lane - 1) % 3 + 1}  -- Devuelve una tabla con un único carril
end

function drawNotes()
    -- Recolectar todas las notas visibles primero
    local visibleNotes = {}

    -- Identificar notas visibles dentro del rango
    for i = curNote, #notes do
        local ntime = notes[i][1]
        -- Si la nota está más allá del rango visible, salir del bucle
        if ntime > curBeat + (4 / trackSpeed) then break end
        
        -- Añadir esta nota a la lista de visibles
        if ntime + notes[i][2] >= curBeat - (1 / trackSpeed) then
            table.insert(visibleNotes, i)
        end
    end
    
    -- Ordenar notas para que las más recientes se dibujen primero (evita solapamiento visual)
    table.sort(visibleNotes, function(a, b) return notes[a][1] > notes[b][1] end)
    
    -- Dibujar las líneas de sustain (si las hay)
    for _, i in ipairs(visibleNotes) do
        local ntime = notes[i][1]
        local nlen = notes[i][2]
        local lane = notes[i][3]
        local square = notes[i][5]
        local heropower = notes[i][6]
        local hopo_notes = notes[i][7]
        
        local curend = ((notes[curNote][1] + notes[curNote][2]) - curBeat) * trackSpeed
        local rtime = ((ntime - curBeat) * trackSpeed)
        local rend = (((ntime + nlen) - curBeat) * trackSpeed)
        
        if nlen <= 0.27 then rend = rtime end
        if rtime < 0 then rtime = 0 end
        if rend <= 0 and curNote ~= #notes and curend <= 0 then curNote = i + 1 end
        if rend > 4 then rend = 4 end
        
        noteScale = imgScale * (1 - (nsm * rtime))
        noteScaleEnd = imgScale * (1 - (nsm * rend))
        
        local mappedLanes = mapLane(lane)
        
        for _, mappedLane in ipairs(mappedLanes) do
            if diff < 4 then mappedLane = mappedLane end
            susx = ((gfx.w / 2) + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
            susy = gfx.h - (227 * noteScale) - ((nyoff * rtime) * noteScale)
            endx = ((gfx.w / 2) + ((nxoff * (1 - (nxm * rend))) * noteScaleEnd * (mappedLane - 2)))
            endy = gfx.h - (219.5 * noteScaleEnd) - ((nyoff * rend) * noteScaleEnd)
            
            if rend >= -0.05 and rend > rtime then
                -- Las líneas de sustain no tendrán fade-in para mantener claridad
                gfx.set(0.9, 0.9, 0.9, 1)
                for j = -5, 5 do
                    gfx.line(susx + j, susy, endx + j, endy, math.abs(j) + 1)
                end
            end
        end
    end
    
    -- Dibujar las notas con fade-in rápido (sin fade-out)
    for _, i in ipairs(visibleNotes) do
        local ntime = notes[i][1]
        local nlen = notes[i][2]
        local lane = notes[i][3]
        local square = notes[i][5]
        local heropower = notes[i][6]
        local hopo_notes = notes[i][7]
        
        local rtime = ((ntime - curBeat) * trackSpeed)
        local rend = (((ntime + nlen) - curBeat) * trackSpeed)
        
        if nlen <= 0.27 then rend = rtime end
        if rtime < 0 then rtime = 0 end
        if rend > 4 then rend = 4 end
        
        noteScale = imgScale * (1 - (nsm * rtime))
        
        -- Calcular opacidad para un fade-in rápido
        local fadeDistance = 0.35 -- Distancia en beats para un fade-in rápido (ajusta este valor para hacerlo más rápido o lento)
        local alpha = 1 -- Por defecto, opacidad completa
        if rtime > (4 - fadeDistance) then
            -- Aplicar fade-in cuando la nota está en el rango superior del highway
            alpha = math.min(1, math.max(0, (rtime - (4 - fadeDistance)) / fadeDistance))
            alpha = 1 - alpha -- Invertimos para que el fade-in sea de 0 a 1
        end
        
        local mappedLanes = mapLane(lane)
        
        for laneIndex, mappedLane in ipairs(mappedLanes) do
            if diff < 4 then mappedLane = mappedLane end
            notey = gfx.h - (82.3 * noteScale) - (243 * noteScale) - ((nyoff * rtime) * noteScale)
            
            if rend >= -0.05 then
                local gfxid = 2
                local noteWidth = 128
                local noteHeight = 128
                local xOffset = 63 * noteScale
                local srcX = 0
                local useSpecialHeroImage = false
                
                if lane == 1 then gfxid = 7
                elseif lane == 2 then gfxid = 7
                elseif lane == 3 then gfxid = 7
                elseif lane == 4 then gfxid = 8
                elseif lane == 5 then gfxid = 8
                elseif lane == 6 then gfxid = 8
                end
                
                if lane == 0 then
                    if heropower then
                        gfxid = 15
                        useSpecialHeroImage = true
                    else
                        gfxid = 10
                    end
                    if #mappedLanes == 3 then
                        local partWidth = math.floor(540 / 3)
                        noteWidth = partWidth
                        xOffset = (partWidth/2) * noteScale
                        if laneIndex == 1 then srcX = 0
                        elseif laneIndex == 2 then srcX = partWidth
                        else
                            srcX = partWidth * 2
                            if laneIndex == 3 then noteWidth = 540 - (partWidth * 2) end
                        end
                    else
                        noteWidth = 540
                        xOffset = 245 * noteScale
                    end
                end
                
                if square then gfxid = 9 end
                if hopo_notes then
                    if lane == 1 or lane == 2 or lane == 3 then
                        if square then gfxid = 13 else gfxid = 11 end
                    elseif lane == 4 or lane == 5 or lane == 6 then
                        if square then gfxid = 13 else gfxid = 12 end
                    end
                end
                
                local adjustedNoteX = ((gfx.w / 2) - xOffset + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
                -- Aplicar opacidad al dibujar la nota
                gfx.a = alpha
                gfx.blit(gfxid, noteScale, 0, srcX, 0, noteWidth, noteHeight, adjustedNoteX, notey)
                
                if heropower and not useSpecialHeroImage then
                    local heroXOffset = 62 * noteScale
                    local heroNoteX = ((gfx.w / 2) - heroXOffset + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
                    local heroNoteY = gfx.h - (79.5 * noteScale) - (243 * noteScale) - ((nyoff * rtime) * noteScale)
                    local heroGfxId = 14
                    -- Aplicar opacidad al icono de Hero Power
                    gfx.a = alpha
                    gfx.blit(heroGfxId, noteScale, 0, 0, 0, 128, 128, heroNoteX, heroNoteY)
                end
            end
        end
    end
    -- Restaurar opacidad por defecto para otros elementos
    gfx.a = 1
end

function updateBeatLines()
    local bpmTimes = {}
    local startQN = reaper.TimeMap2_timeToQN(0, 0)
    local endQN = reaper.TimeMap2_timeToQN(0, reaper.GetProjectLength(0))
    local curQN = startQN

    while curQN < endQN do
        local time = reaper.TimeMap2_QNToTime(0, curQN)
        local timeSignatureNumerator, timeSignatureDenominator, beatDuration = reaper.TimeMap_GetTimeSigAtTime(0, time)
        local beatPosition = (curQN % (1 / timeSignatureDenominator)) * timeSignatureDenominator -- Ajuste de la posición del beat

        -- Considerar los beats fuertes y débiles
        if beatPosition == 0 then
            table.insert(bpmTimes, {curQN, "strong"})
        -- elseif beatPosition == 0.5 then
            -- table.insert(bpmTimes, {curQN, "weak"})
        end

        curQN = curQN + (4 / timeSignatureDenominator) -- Incrementar el índice para el siguiente beat
    end

    beatLines = bpmTimes
end

function drawBeats()
    local baseWidth = 255
    local thickness = 5 -- Grosor base de la línea

    for i = curBeatLine, #beatLines do
        local btime = beatLines[i][1]
        if btime > curBeat + (4 / trackSpeed) then break end
        if curBeat > btime + 2 then
            curBeatLine = i
        end

        local rtime = ((btime - curBeat) * trackSpeed) - 0.08
        local beatScale = imgScale * (1 - (nsm * rtime))

        local sx = ((gfx.w / 2) - ((baseWidth * (1 - (nxm * rtime))) * beatScale))
        local ex = ((gfx.w / 2) + ((baseWidth * (1 - (nxm * rtime))) * beatScale))
        local y = gfx.h - (250.1 * beatScale) - ((nyoff * rtime) * beatScale)

        y = y + 15  -- Ajuste de posición vertical

        -- Calcular el grosor de la línea
        local lineThickness = thickness * (1 - (nxm * rtime)) * beatScale

        if beatLines[i][2] == "strong" then -- Beat fuerte
            gfx.r = 0.80
            gfx.g = 0.80
            gfx.b = 0.80

            -- Dibujar un rectángulo para la línea más gruesa
            gfx.rect(sx, y - lineThickness / 2, ex - sx, lineThickness, true)

        -- elseif beatLines[i][2] == "weak" then -- Beat débil
            -- gfx.r = 0.80
            -- gfx.g = 0.80
            -- gfx.b = 0.80
            -- gfx.rect(sx, y - lineThickness / 2, ex - sx, lineThickness, true)
        end
    end
end

-- Inicializar el rango del proyecto
trackRange[1] = reaper.TimeMap2_timeToQN(0, 0)
trackRange[2] = reaper.TimeMap2_timeToQN(0, reaper.GetProjectLength(0))

updateMidi()
updateBeatLines()

function moveCursorByBeats(increment)
    local currentPosition = reaper.GetCursorPosition()
    local currentBeats = reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1), currentPosition)

    -- Calculate the new position in beats
	local newBeats = currentBeats + increment
	newBeats=math.floor(newBeats*(1/quants[movequant])+0.5)/(1/quants[movequant])

	-- Convert the new beats position to seconds
    local newPosition = reaper.TimeMap2_QNToTime(reaper.EnumProjects(-1), newBeats)

    -- Move the edit cursor to the new position
    reaper.SetEditCurPos2(0, newPosition, true, true)
end

-- Modificar keyBinds, manteniendo atajos adicionales
keyBinds={
	[43]=function()
		trackSpeed = trackSpeed+0.05
	end,
	[61]=function()
		trackSpeed = trackSpeed+0.05
	end,
	[45]=function()
		if trackSpeed>0.25 then trackSpeed = trackSpeed-0.05 end
	end,
	[125]=function()
		offset = offset+0.01
	end,
	[123]=function()
		offset = offset-0.01
	end,
	[32]=function()
		if reaper.GetPlayState()==1 then
			reaper.OnStopButton()
		else
			reaper.OnPlayButton()
		end
	end,
	[30064]=function()
		moveCursorByBeats(quants[movequant])
	end,
	[1685026670]=function()
		moveCursorByBeats(-quants[movequant])
	end,
	[1818584692.0]=function() 
		if movequant==1 then movequant=#quants else movequant=movequant-1 end
	end,
	[1919379572.0]=function() 
		if movequant==#quants then movequant=1 else movequant=movequant+1 end
	end,
	[26161.0]=function() showHelp = not showHelp end,
    [76]=function() -- Tecla 'L'
        showLyrics = not showLyrics
        if showLyrics and #phrases == 0 then
            parseVocals()
        end
    end,
    [108]=function() -- Tecla 'l' (minúscula)
        showLyrics = not showLyrics
        if showLyrics and #phrases == 0 then
            parseVocals()
        end
    end,
    [78]=function() -- Tecla 'N'
        showNotesHUD = not showNotesHUD
    end,
    [110]=function() -- Tecla 'n' (minúscula)
        showNotesHUD = not showNotesHUD
    end
}

local function Main()
	imgScale=math.min(gfx.w,gfx.h)/900 -- Zoom del highway y las notas
	local char = gfx.getchar()
	
    -- Detectar si hay un proyecto abierto y si ha cambiado
    local hasProject = isProjectOpen()
    local newProject = hasProject and reaper.EnumProjects(-1) or nil
    
    -- Si el proyecto cambió o no hay proyecto pero había uno antes
    if newProject ~= currentProject then
        currentProject = newProject
        resetState()  -- Reiniciar estado si el proyecto cambió
    end
    
    -- Si no hay proyecto abierto, solo mantener el script activo
    if not hasProject then
        if char ~= -1 then
            reaper.defer(Main)
        end
        return -- No hacer nada más hasta que haya un proyecto
    end
	
	-- Detectar clic del mouse
    if gfx.mouse_cap & 1 == 1 then
        if not mouseDown then
            mouseDown = true
            handleMouseClick(gfx.mouse_x, gfx.mouse_y)
        end
    else
        mouseDown = false
    end
	
	if char ~= -1 then
		reaper.defer(Main)
	end
	playState=reaper.GetPlayState()
	if keyBinds[char] then
        keyBinds[char]()
    end
	
	if diff<=4 then
		gfx.blit(1,imgScale,0,0,0,1024,1024,(gfx.w/2)-(imgScale*399),gfx.h-(676*imgScale)); 
	else
		gfx.blit(0,imgScale,0,0,0,1024,1024,(gfx.w/2)-(imgScale*399),gfx.h-(676*imgScale));   
	end 
	if playState==1 then
		curBeat=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetPlayPosition())-offset
	end
	curCursorTime=reaper.TimeMap2_timeToQN(reaper.EnumProjects(-1),reaper.GetCursorPosition())
	if playState~=1  then
		curBeat=curCursorTime-offset
	end
	if curCursorTime~=lastCursorTime then
		lastCursorTime=curCursorTime
	end
	curNote=1
	for i=1,#notes do
		curNote=i
		if notes[i][1]+notes[i][2]>=curBeat then
			break
		end
	end
	curBeatLine=1
	for i=1,#beatLines do
		curBeatLine=i
		if beatLines[i][1]>=curBeat-2 then
			break
		end
	end
	
	-- Usar pcall para las funciones que pueden fallar si cambia el proyecto
	pcall(function() updateMidi() end)
    
    -- Actualizar letras en tiempo real de forma segura
    if showLyrics then
        pcall(function() updateVocals() end)
    end
	
	pcall(function() parseSections() end)

	if #sections > 0 then
		updateCurrentSection(curBeat)
		drawCurrentSection()
	end

	updateBeatLines()
	drawBeats()
	drawNotes()
	
    -- Dibujar visualizador de letras si está activo
    if showLyrics then
        -- Solo mostrar letras si hay un proyecto abierto
        if isProjectOpen() then
            updateAndDrawLyrics()
        end
    end
	
	-- Dibujar los botones de dificultad
	drawDifficultyButtons()
	
	-- Dibujar la información principal
	gfx.r = 0.77
	gfx.g = 0.81
	gfx.b = 0.96
	gfx.x,gfx.y=12,12
	gfx.setfont(1, "SDK_JP_Web 85W", 25) -- Genshin Impact font
	gfx.drawstr(string.format(
		[[%s %s
		Note: %d/%d
		Current Beat: %.01f
		Snap: %s]],
		diffNames[diff],
		instrumentTracks[inst][1],
		curNote,
		tostring(#notes),
		curBeat,
		toFractionString(quants[movequant])
	))
	
	-- Dibujar los controles de velocidad y offset
	drawSpeedControls()
	drawOffsetControls()
    
    -- Dibujar botón de activar/desactivar letras
    drawLyricsToggleButton()
    
    -- Dibujar botón de activar/desactivar HUD de notas
    drawNotesHUDToggleButton()
	
	gfx.x,gfx.y=5,gfx.h-20
	gfx.setfont(1, "SDK_JP_Web 85W", 15) -- Genshin Impact font
	gfx.drawstr(string.format("Version %s",version_num))
	strx,stry=gfx.measurestr("F1: Controls")
	gfx.x,gfx.y=gfx.w-strx-5,gfx.h-stry-5
	gfx.drawstr("F1: Controls")
	if showHelp then
		gfx.mode=0
		gfx.r,gfx.g,gfx.b,gfx.a=0,0,0,0.75
		gfx.rect(0,0,gfx.w,gfx.h)
		gfx.r,gfx.g,gfx.b,gfx.a=1,1,1,1
		gfx.x,gfx.y=0,320*imgScale
		gfx.drawstr([[Keybinds
		 
		Change highway speed: + | -
		Change offset: { | } (Shift + [ | ])
		Change snap: Left (<-) | Right (->) arrows
		Scroll: Up | Down arrows
        Show/Hide Lyrics: L
		]],1,gfx.w,gfx.h)
	end
	gfx.update()
end

Main()
