version_num="0.1"
imgScale=1024/1024
diffNames={"Easy","Medium","Hard","Expert"}
movequant=10
quants={1/32,1/24,1/16,1/12,1/8,1/6,1/4,1/3,1/2,1,2,4}
-- highway rendering vars
midiHash=""
beatHash=""
eventsHash=""
trackSpeed=1.75
inst=1 -- Guitar 3x2 (GHL)
diff=4 -- Expert
pR={
	{{58,64},{120,121}}, -- Normal notes = Easy | Lift notes = Easy (not used)
	{{70,76},{122,123}}, -- Normal notes = Medium | Lift notes = Medium (not used)
	{{82,88},{124,125}}, -- Normal notes = Hard | Lift notes = Hard (not used)
	{{94,100},{126,127}} -- Normal notes = Expert | Lift notes = Expert (not used)
}

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
nxoff=178 -- x offset
nxm=0.15 -- x mult of offset
nyoff=150.5 -- y offset
nsm=0.05 -- scale multiplier

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

gfx.clear = rgb2num(35, 38, 52) -- background color
gfx.init("GHL Preview", 700, 700, 0, 1150, 50) -- wight, height, x pos, y pos.

local script_folder = string.gsub(debug.getinfo(1).source:match("@?(.*[\\|/])"),"\\","/")
highway = gfx.loadimg(1,script_folder.."assets/highway.png")

white_note = gfx.loadimg(7, script_folder.."assets/white_note.png")
black_note = gfx.loadimg(8, script_folder.."assets/black_note.png")
square_note = gfx.loadimg(9, script_folder.."assets/square_note.png") -- (nota de acorde de cejilla)
open_note = gfx.loadimg(10, script_folder.."assets/open_note.png")

white_hopo_notee = gfx.loadimg(11, script_folder.."assets/white_hopo_note.png")
black_hopo_notee = gfx.loadimg(12, script_folder.."assets/black_hopo_note.png")
square_hopo_notee = gfx.loadimg(13, script_folder.."assets/square_hopo_note.png")

hero_icon = gfx.loadimg(14, script_folder.."assets/hero_icon.png")

instrumentTracks={
	{"Guitar GHL",findTrack("PART GUITAR GHL")}
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
        elseif pitch >= pR[diff][2][1] and pitch <= pR[diff][2][2] then
            lane = pitch - pR[diff][2][1]
            noteIndex = getNoteIndex(ntime, lane)
            if noteIndex ~= -1 then
                notes[noteIndex][4] = true
            else
                table.insert(notes, {ntime, -1, lane, true, false})
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
		{"Guitar GHL",findTrack("PART GUITAR GHL")}
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

function mapLane(lane)
    -- Si el carril es 0, se asigna a los carriles visuales 1, 2 y 3
    if lane == 0 then
        return {1, 2, 3}  -- Devuelve una tabla con los carriles 1, 2 y 3
    end
    
    -- Se ajusta el mapeo para que el carril sea correctamente asignado
    return {(lane - 1) % 3 + 1}  -- Devuelve una tabla con un único carril
end

function drawNotes()
    for i = curNote, #notes do
        ntime = notes[i][1]
        nlen = notes[i][2]
        lane = notes[i][3]
        square = notes[i][5]
        heropower = notes[i][6]
        hopo_notes = notes[i][7]
        curend = ((notes[curNote][1] + notes[curNote][2]) - curBeat) * trackSpeed
        if ntime > curBeat + (4 / trackSpeed) then break end
        rtime = ((ntime - curBeat) * trackSpeed)
        rend = (((ntime + nlen) - curBeat) * trackSpeed)
        if nlen <= 0.27 then
            rend = rtime
        end
        
        if rtime < 0 then rtime = 0 end
        
        if rend <= 0 and curNote ~= #notes and curend <= 0 then
            curNote = i + 1
        end

        if rend > 4 then
            rend = 4
        end
        
        noteScale = imgScale * (1 - (nsm * rtime))
        noteScaleEnd = imgScale * (1 - (nsm * rend))
        
        local mappedLanes = mapLane(lane)
        
        for _, mappedLane in ipairs(mappedLanes) do
            if diff < 4 then
                -- mappedLane = mappedLane + 0.5
                mappedLane = mappedLane
            end

            notex = ((gfx.w / 2) - (63 * noteScale) + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
            notey = gfx.h - (82.3 * noteScale) - (243 * noteScale) - ((nyoff * rtime) * noteScale)

            susx = ((gfx.w / 2) + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
            susy = gfx.h - (227 * noteScale) - ((nyoff * rtime) * noteScale)
            endx = ((gfx.w / 2) + ((nxoff * (1 - (nxm * rend))) * noteScaleEnd * (mappedLane - 2)))
            endy = gfx.h - (219.5 * noteScaleEnd) - ((nyoff * rend) * noteScaleEnd)
            
            if rend >= -0.05 then
                local gfxid = 2
                if lane == 1 then gfxid = 7 -- white_note_1
                elseif lane == 2 then gfxid = 7 -- white_note_2
                elseif lane == 3 then gfxid = 7 -- white_note_3
                elseif lane == 4 then gfxid = 8 -- black_note_1
                elseif lane == 5 then gfxid = 8 -- black_note_2
                elseif lane == 6 then gfxid = 8 -- black_note_3
                end
                if lane == 0 then
                    gfxid = 10 -- open_note
					-- gfx.blit(gfxid, noteScale, 0, 0, 0, 128, 128, notex, notey)
                end

                if square then gfxid = 9 end  -- Cambiar a la imagen square
                if hopo_notes then
                    if lane == 1 or lane == 2 or lane == 3 then
                        if square then
                            gfxid = 13 -- white_hopo_square_note
                        else
                            gfxid = 11 -- white_hopo_note
                        end
                    elseif lane == 4 or lane == 5 or lane == 6 then
                        if square then
                            gfxid = 13 -- black_hopo_square_note
                        else
                            gfxid = 12 -- black_hopo_note
                        end
                    end
                end

                if rend > rtime then
                    gfx.r = 0.9
                    gfx.g = 0.9
                    gfx.b = 0.9
                    gfx.line(susx-5,susy,endx-5,endy,5)
                    gfx.line(susx-4,susy,endx-4,endy,4)
                    gfx.line(susx-3,susy,endx-3,endy,3)
                    gfx.line(susx-2,susy,endx-2,endy,2)
                    gfx.line(susx-1,susy,endx-1,endy,1)
                    gfx.line(susx,susy,endx,endy,1)
                    gfx.line(susx+1,susy,endx+1,endy,1)
                    gfx.line(susx+2,susy,endx+2,endy,2)
                    gfx.line(susx+3,susy,endx+3,endy,3)
                    gfx.line(susx+4,susy,endx+4,endy,4)
                    gfx.line(susx+5,susy,endx+5,endy,5)
                end

                gfx.blit(gfxid, noteScale, 0, 0, 0, 128, 128, notex, notey)
            end
        end
    end

    -- Ahora dibuja las notas Hero Power encima de las demás
    for i = curNote, #notes do
        if notes[i][6] then -- Si la nota es una nota Hero Power
            ntime = notes[i][1]
            nlen = notes[i][2]
            lane = notes[i][3]
            curend = ((notes[curNote][1] + notes[curNote][2]) - curBeat) * trackSpeed
            if ntime > curBeat + (4 / trackSpeed) then break end
            rtime = ((ntime - curBeat) * trackSpeed)
            rend = (((ntime + nlen) - curBeat) * trackSpeed)
            if nlen <= 0.27 then
                rend = rtime
            end
            
            if rtime < 0 then rtime = 0 end
            
            if rend <= 0 and curNote ~= #notes and curend <= 0 then
                curNote = i + 1
            end

            if rend > 4 then
                rend = 4
            end
            
            noteScale = imgScale * (1 - (nsm * rtime))
            noteScaleEnd = imgScale * (1 - (nsm * rend))
            
            local mappedLanes = mapLane(lane)
            
            for _, mappedLane in ipairs(mappedLanes) do
                if diff < 4 then
                    -- mappedLane = mappedLane + 0.5
                    mappedLane = mappedLane
                end

                notex = ((gfx.w / 2) - (62 * noteScale) + ((nxoff * (1 - (nxm * rtime))) * noteScale * (mappedLane - 2)))
                notey = gfx.h - (79.5 * noteScale) - (243 * noteScale) - ((nyoff * rtime) * noteScale)
                
                if rend >= -0.05 then
                    gfxid = 14 -- Hero Power icon
                    gfx.blit(gfxid, noteScale, 0, 0, 0, 128, 128, notex, notey)
                end
            end
        end
    end
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

keyBinds={
	[59]=function()
		if diff==1 then diff=4 else diff=diff-1 end
		midiHash=""
		updateMidi()
	end,
	[39]=function()
		if diff==4 then diff=1 else diff=diff+1 end
		midiHash=""
		updateMidi()
	end,
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
	[26161.0]=function() showHelp = not showHelp end
}

local function Main()
	imgScale=math.min(gfx.w,gfx.h)/900 -- Zoom del highway y las notas
	local char = gfx.getchar()
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
		curBeat=curCursorTime
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
	updateMidi()
	
	updateBeatLines()
	drawBeats()
	drawNotes()
	gfx.r = 0.77
	gfx.g = 0.81
	gfx.b = 0.96
	gfx.x,gfx.y=5,5
	gfx.setfont(1, "Arial", 25)
	gfx.drawstr(string.format(
		[[%s %s
		Note: %d/%d
		Current Beat: %.01f
		Snap: %s
		Highway Speed: %.02f
		Offset: %.02f
		]],
		diffNames[diff],
		instrumentTracks[inst][1],
		curNote,
		tostring(#notes),
		curBeat,
		toFractionString(quants[movequant]),
		trackSpeed,
		offset
	))
	gfx.x,gfx.y=5,gfx.h-20
	gfx.setfont(1, "Arial", 15) -- Genshin Impact font
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
		 
		Change difficulty: ; | '
		Change highway speed: + | -
		Change offset: { | } (Shift + [ | ])
		Change snap: Left (<-) | Right (->) arrows
		Scroll: Up | Down arrows
		]],1,gfx.w,gfx.h)
	end
	gfx.update()
end

Main()
