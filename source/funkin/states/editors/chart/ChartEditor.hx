package funkin.states.editors.chart;

import flixel.FlxSubState;
import flixel.sound.FlxSound;
import funkin.objects.Camera;

import flixel.text.FlxText;
import flixel.group.FlxSpriteGroup;
import flixel.addons.display.FlxBackdrop;

import funkin.states.editors.chart.*;
import funkin.states.editors.chart.ChartNoteGroup;
import funkin.states.editors.chart.ChartEventGroup;
import funkin.states.editors.chart.ChartUndos;
import funkin.states.editors.UndoList;

import funkin.objects.HealthIcon;
import funkin.gameplay.notes.Note;
import funkin.gameplay.notes.Receptor;

import funkin.music.MusicPlayback;
import funkin.globals.ChartFormat;
import funkin.gameplay.EventManager;

import haxe.ui.core.Screen;
import haxe.ui.notifications.*;
import haxe.ui.components.VerticalScroll;

import flixel.util.FlxStringUtil;
import haxe.Json;

class ChartEditor extends MusicBeatState #if ENGINE_CRASH_HANDLER implements eternal.core.crash.CrashHandler.ICrashListener #end {
    public static final hoverColor:FlxColor = 0x9B9BFA;
    public static final lateAlpha:Float = 0.6;
    public static final separatorWidth:Int = 4;
    public static final checkerSize:Int = 45;

    public var music:MusicPlayback;
    public var difficulty:String;
    public var chart:Chart;

    public var eventList:Map<String, EventDetails>;
    public var noteTypes:Array<String>;

    public var currentEvent:EventDetails;
    public var currentNoteType:String;
    public var eventArgs:Array<Any>;

    public var notes:ChartNoteGroup;
    public var events:ChartEventGroup;

    public var checkerboard:ChartCheckerboard;
    public var line:FlxSprite;

    public var selectedNote(default, set):DebugNote;
    public var selectedEvent(default, set):EventSprite;

    public var mouseCursor:FlxSprite;
    public var hoverBox:HoverBox;

    public var receptors:FlxTypedSpriteGroup<Receptor>;
    public var beatIndicators:FlxSpriteGroup;
    public var measureBackdrop:FlxBackdrop;

    public var substateCam:Camera;
    public var miniMap:Camera;
    public var ui:ChartUI;

    public var timeBar:VerticalScroll;
    public var musicText:FlxText;
    public var overlay:FlxSprite;

    public var opponentIcon:HealthIcon;
    public var playerIcon:HealthIcon;

    public var hitsound:openfl.media.Sound;
    public var hitsoundVolume:Float = 0;
    public var metronome:FlxSound;

    public var preferences(get, set):Dynamic; // for convenience
    public var beatSnap:Int;

    public var skipUpdate:Bool = false;
    public var runAutosave:Bool = false; // autosaving is slow, this is a workaround to avoid freezes

    public var requestSortNotes:Bool = false;
    public var requestSortEvents:Bool = false;

    public var startTime:Float = 0;
    public var lastTime:Float = 0;
    public var lastStep:Int = 0;

    // used for undos
    public var noteDrags:Array<NoteDragData> = [];
    public var eventDrags:Array<EventDragData> = [];
    //

    public var clipboard:Clipboard<ChartClipboardItems>;
    public var undoList:UndoList<ChartUndos>;
    public var selection:SelectionHelper;

    // workaround so clicking on a ui item doesn't spawn an object
    var wasInteracting:Bool = false;

    var lastBpmChange:Float = 0;
    var awaitBPMReload:Bool = false;
    var eventBPM:Bool = false;

    public function new(chart:Chart, difficulty:String = "normal", startTime:Float = 0):Void {
        super();

        this.chart = chart;
        this.difficulty = difficulty;
        this.startTime = startTime;
    }

    override function create():Void {
        super.create();

        FlxG.cameras.reset(new Camera());
        FlxG.mouse.visible = FlxG.mouse.useSystemCursor = true;

        #if ENGINE_DISCORD_RPC
        DiscordPresence.presence.details = "Charting " + chart.meta.name;
        #end

        // make sure save data isn't null (note: save data is saved automatically on exit, no need to do it ourselves)
        if (preferences == null) preferences = {};

        loadSong();
        loadData();
        createBackground();
        createGrid();
        createUI();

        hitsound = Assets.sound("editors/hitsound");
        hitsoundVolume = Settings.get("CHART_hitsoundVolume");

        metronome = FlxG.sound.load(Assets.sound("editors/metronome"));
        metronome.volume = Settings.get("CHART_metronomeVolume");

        // cache a small amount of note sprites
        for (i in 0...32) notes.add(new DebugNote()).kill();

        // make sure notes are sorted to avoid odd behaviours
        sortNotes();

        // also sort events for normal bpm change behaviour
        sortEvents();

        // spawn existing events
        if (chart.events.length > 0)
            spawnEvents(chart.events);

        FlxG.stage.window.onClose.add(autoSave);
    }

    override function update(elapsed:Float):Void {
        if (FlxG.keys.justPressed.ESCAPE) {
            playTest(FlxG.keys.pressed.SHIFT, FlxG.keys.pressed.P);
            return;
        }

        if (FlxG.keys.justPressed.ENTER) {
            goToPlayState(FlxG.keys.pressed.SHIFT);
            return;
        }

        if (skipUpdate) {
            skipUpdate = false;
            return;
        }

        var interacting:Bool = Screen.instance.hasComponentUnderPoint(FlxG.mouse.screenX, FlxG.mouse.screenY);

        var mouseX:Float = quantizePos(FlxG.mouse.x - checkerboard.x);
        mouseCursor.x = Math.min(checkerboard.x + mouseX + separatorWidth * Math.floor(mouseX / checkerSize / 4), checkerboard.x + checkerboard.width);
        mouseCursor.y = FlxMath.bound(getMouseY(), 0, checkerboard.bottom - checkerSize);
        mouseCursor.visible = (mouseValid() && !interacting && !selection.dragging);

        if (mouseCursor.visible && !wasInteracting) {
            if (FlxG.mouse.justReleased && !hoverBox.enabled) {
                if (FlxG.mouse.x >= checkerboard.x)
                    checkSpawnNote();
                else if (FlxG.mouse.x < checkerboard.x - separatorWidth)
                    checkSpawnEvent();
            }
            else if (FlxG.keys.pressed.Z)
                checkObjectDeletion();

            if (FlxG.mouse.justPressedRight)
                checkObjectSelect();
        }

        if (FlxG.keys.pressed.CONTROL) {
            // text inputs have copy paste too
            if (!interacting) {
                if (FlxG.keys.justPressed.C) clipboardCopy();
                if (FlxG.keys.justPressed.V) clipboardPaste();
            }

            if (FlxG.keys.justPressed.Z) undo(FlxG.keys.pressed.ALT);
            if (FlxG.keys.justPressed.Y) redo(FlxG.keys.pressed.ALT);

            if (FlxG.keys.justPressed.S) {
                Tools.saveData('${difficulty.toLowerCase()}.json', Json.stringify(chart.toStruct()));
                pauseMusic();
            }
        }

        if (FlxG.keys.justPressed.SPACE && !interacting) {
            if (music.playing)
                pauseMusic();
            else
                music.play(Conductor.time);
        }

        if (selectedNote != null && !interacting) {
            var pressed:Bool = (FlxG.keys.justPressed.Q || FlxG.keys.justPressed.E);
            var holding:Bool = (FlxG.keys.pressed.SHIFT && (FlxG.keys.pressed.Q || FlxG.keys.pressed.E));

            if (pressed || holding) {
                var mult:Int = (FlxG.keys.pressed.E) ? 1 : -1;
                selectedNote.data.length += (holding) ? (Conductor.stepCrochet / 10 * Tools.framerateMult() * mult) : (Conductor.stepCrochet * mult);

                if (selectedNote.data.length < 0) {
                    undoList.register(RemoveNote(selectedNote.data));
                    selectedNote.data.length = 0; // for undo
                    killNote(selectedNote);
                }
            }
        }

        if (FlxG.mouse.wheel != 0 && !interacting)
            incrementTime(-FlxG.mouse.wheel * Conductor.stepCrochet * Tools.framerateMult(120));
        if ((FlxG.keys.pressed.UP || FlxG.keys.pressed.DOWN) && !interacting)
            incrementTime(Conductor.stepCrochet / 4 * ((FlxG.keys.pressed.UP) ? -1 : 1) * Tools.framerateMult());

        super.update(elapsed);

        if (requestSortNotes) {
            requestSortNotes = false;
            sortNotes();
        }

        if (requestSortEvents) {
            requestSortEvents = false;
            sortEvents();
        }

        updateCurrentBPM();

        // reposition the follow line
        if (music.playing || Settings.get("CHART_strumlineSnap") || FlxG.keys.justPressed.SHIFT)
            line.y = getYFromTime(Conductor.time + Conductor.timeApprox);
        else
            line.y = Tools.lerp(line.y, getYFromTime(Conductor.time), 12);

        if (!music.playing && Conductor.time >= music.instrumental.length) {
            music.instrumental.time = 0;
            line.y = 0;
        }

        if (receptors.visible) {
            for (receptor in receptors)
                receptor.y = line.y - (receptor.height * 0.5);
        }

        if (beatIndicators.visible) {
            for (ind in beatIndicators) {
                ind.color = FlxColor.interpolate(FlxColor.CYAN, FlxColor.RED, (music.playing) ? (Conductor.decimalBeat - Conductor.currentBeat) : 1);
                ind.y = line.y - ((line.height + ind.height) * 0.25);
            }
        }

        // only update notes after so it gets updated values
        notes.update(elapsed);

        updateMusicText();

        wasInteracting = interacting;
        lastStep = Conductor.currentStep;
        lastTime = Conductor.time;
    }

    override function stepHit(currentStep:Int):Void {
        if (music.playing)
            music.resync();

        super.stepHit(currentStep);
    }

    override function beatHit(currentBeat:Int):Void {
        // sometimes it just mutes itself, and sometimes it proceeds to play hitsound instead of metronome
        // TODO: fix this bug
        
        if (music.playing && metronome.volume > 0)
            metronome.play(true);

        super.beatHit(currentBeat);
    }

    inline function checkSpawnNote():Void {
        var direction:Int = Math.floor((mouseCursor.x - checkerboard.x) / checkerSize);
        var strumline:Int = Math.floor(direction / 4);
        direction %= 4;

        var existingNote:DebugNote = notes.getFirst((n) -> n.alive && n.data.direction == direction && FlxG.mouse.overlaps(n));

        // no existing note found, create one
        if (existingNote == null) {
            var note:DebugNote = notes.recycle(DebugNote);
            note.setPosition(mouseCursor.x, getMouseY());
            note.data = {
                time: getTimeFromY(note.y),
                strumline: strumline,
                direction: direction,
                type: currentNoteType,
                length: 0
            };

            chart.notes.push(note.data);
            sortNotes();

            notes.pushNote(note);
            selectedNote = note;

            undoList.register(AddNote(note.data));
        }
        else if (!existingNote.selected) {
            // existing note found, delete it if CONTROL isn't pressed
            if (!FlxG.keys.pressed.CONTROL) {
                undoList.register(RemoveNote(existingNote.data));
                killNote(existingNote);   
            }
            // otherwise, (un)select it
            else {
                if (selectedNote == existingNote)
                    selectedNote = null;
                else
                    selectedNote = existingNote;
            }
        }
    }

    inline function checkSpawnEvent():Void {
        var existingEvent:EventSprite = events.getFirst((e) -> e.alive && FlxG.mouse.overlaps(e));

        // no existing event found, create one
        if (existingEvent == null) {
            var event:EventSprite = events.recycle(EventSprite);
            event.y = getMouseY();
            event.data = {
                time: getTimeFromY(event.y),
                event: currentEvent.name,
                arguments: eventArgs.copy()
            };

            chart.events.push(event.data);
            sortEvents();

            undoList.register(AddEvent(event.data));
            selectedEvent = event;
        }
        else if (!existingEvent.selected) {
            // existing event found, delete it if CONTROL isn't pressed
            if (!FlxG.keys.pressed.CONTROL) {
                undoList.register(RemoveEvent(existingEvent.data));
                killEvent(existingEvent);
            }
            // otherwise, (un)select it
            else {
                if (selectedEvent == existingEvent)
                    selectedEvent = null;
                else {
                    selectedEvent = existingEvent;
                    if (ui.eventsOpened) ui.refreshEvent();
                }
            }
        }
    }

    inline function checkObjectDeletion():Void {
        // look for notes to delete
        notes.forEachAlive((note) -> {
            if (FlxG.mouse.overlaps(note) && !note.selected) {
                undoList.register(RemoveNote(note.data));
                killNote(note);
            }
        });

        // look for events to delete
        events.forEachAlive((event) -> {
            if (FlxG.mouse.overlaps(event) && !event.selected) {
                undoList.register(RemoveEvent(event.data));
                killEvent(event);
            }
        });
    }

    inline function checkObjectSelect():Void {
        // register clicked notes to the selection
        notes.forEachAlive((note) -> {
            if (FlxG.mouse.overlaps(note))
                !note.selected ? selection.register(note) : selection.unregister(note);
        });

        // register clicked events to the selection
        events.forEachAlive((event) -> {
            if (FlxG.mouse.overlaps(event))
                !event.selected ? selection.register(event) : selection.unregister(event);
        });
    }

    function onHoverBoxRelease():Void {
        // check for objects to select
        notes.forEachAlive((note) -> {
            if (hoverBox.contains(note))
                selection.register(note);
        });

        events.forEachAlive((event) -> {
            if (hoverBox.contains(event))
                selection.register(event);
        });
    }
    
    function onSelectionRelease():Void {
        undoList.register(ObjectDrag(noteDrags.copy(), eventDrags.copy()));
        eventDrags.splice(0, eventDrags.length);
        noteDrags.splice(0, noteDrags.length);
    }

    inline function incrementTime(val:Float):Void {
        if (music.playing)
            pauseMusic();

        music.instrumental.time += val * ((FlxG.keys.pressed.SHIFT) ? 10 : 1);
        music.instrumental.time = FlxMath.bound(music.instrumental.time, -1000, music.instrumental.length);

        if (music.instrumental.time < 0) {
            music.instrumental.time = music.instrumental.length - 100;
            line.y = getYFromTime(music.instrumental.time);
        }

        for (vocals in music.vocals)
            vocals.time = music.instrumental.time;

        Conductor.resetPrevTime();
    }

    override function openSubState(SubState:FlxSubState):Void {
        if (SubState is TransitionSubState)
            Transition.noPersistentUpdate = (cast(SubState, TransitionSubState).type == OUT);
        else {
            SubState.camera = substateCam;
            pauseMusic();
        }

        super.openSubState(SubState);
    }

    override function closeSubState():Void {
        if (!(subState is TransitionSubState) && awaitBPMReload) {
            reloadGrid(false, !eventBPM);
            awaitBPMReload = false;
        }

        super.closeSubState();
    }

    public function goToPlayState(here:Bool = false):Void {
        var currentTime:Float = Conductor.time;

        runAutosave = true;
        selection.unselectAll();
        music.stop();

        FlxG.mouse.visible = false;
        Assets.clearAssets = Settings.get("reload assets");
        skipUpdate = true;

        PlayState.currentDifficulty = difficulty;
        PlayState.song = chart;

        var time:Float = (here ? currentTime : 0);
        FlxG.switchState(Assets.clearAssets ? LoadingScreen.new.bind(time) : PlayState.new.bind(time));
    }

    public function playTest(here:Bool = false, asOpponent:Bool = false):Void {
        var time:Float = Conductor.time;

        FlxG.mouse.visible = false;
        skipUpdate = true;

        selection.unselectAll();
        music.stop();

        openSubState(new ChartPlayState(this, (here ? time : 0), asOpponent));
    }

    public function openHelpPage():Void {
        openSubState(new HelpSubState("SPACE: Play/Stop music\n"
            + "UP/DOWN/Mouse wheel: Increase/Decrease music time (faster if SHIFT pressed)\n"
            + "Mouse click on grid: Place a note/event\n"
            + "E/Q: Increase/Decrease selected note hold length (faster if SHIFT pressed)\n"
            + "CTRL + Mouse click: Select hovered note/event\n"
            + "SHIFT (hold): Un-snap cursor to grid\n"
            + "Z (hold): Delete hovered notes/events\n\n"

            + "TAB: Open Sub-screen\n"
            + "ESCAPE: Play chart in the chart editor\n"
            + "ESCAPE+SHIFT: Play chart in the chart editor at current time\n"
            + "ENTER: Play chart\n"
            + "ENTER+SHIFT: Play chart at current time\n"
            + "CTRL+S: Save chart"));
    }

    inline function killNote(note:DebugNote):Void {
        if (selectedNote == note)
            selectedNote = null;

        selection.unregister(note);
        chart.notes.remove(note.data);
        notes.killNote(note);
    }

    inline function killEvent(event:EventSprite):Void {
        if (selectedEvent == event)
            selectedEvent = null;

        selection.unregister(event);
        chart.events.remove(event.data);
        event.kill();
    }

    inline function pauseMusic():Void {
        music.pause();
        metronome.stop();
    }

    inline function updateMusicText():Void {
        if (!musicText.visible)
            return;

        musicText.text = '${getTimeInfo()}\n\n' + 'Step: ${Conductor.currentStep}\n' + 'Beat: ${Conductor.currentBeat}\n'
            + 'Measure: ${Conductor.currentMeasure}\n\n' + '${getBPMInfo()}\n' + 'Time Signature: ${Conductor.getSignature()}';

        overlay.scale.x = musicText.width + 15;
        overlay.updateHitbox();

        if (!timeBar.hitTest(FlxG.mouse.screenX, FlxG.mouse.screenY) || !FlxG.mouse.pressed)
            timeBar.pos = music.instrumental.time;
    }

    inline public function getTimeInfo():String {
        var currentTime:String = FlxStringUtil.formatTime(music.instrumental.time * 0.001);
        var maxTime:String = FlxStringUtil.formatTime(music.instrumental.length * 0.001);

        var playbackRate:String = Std.string(music.pitch);
        if (music.pitch is Int)
            playbackRate += ".0";

        return '${currentTime} / ${maxTime} (${playbackRate}x)';
    }

    inline public function getBPMInfo():String
        return 'BPM: ${Conductor.bpm} (${chart.gameplayInfo.bpm})';

    inline public function reloadGrid(updateMeasure:Bool = true, resetTime:Bool = true):Void {
        checkerboard.bottom = getYFromTime(music.instrumental.length);
        line.y = getYFromTime(music.instrumental.time);

        notes.forEachAlive((note) -> note.y = getYFromTime(note.data.time));
        events.forEachAlive((event) -> event.y = getYFromTime(event.data.time));

        if (updateMeasure) refreshMeasureMark();
        if (resetTime) Conductor.resetPrevTime();
    }

    public inline function refreshMeasureMark():Void {
        // without reducing by 1 makes the spacing somehow
        measureBackdrop.spacing.y = checkerSize * Conductor.measureLength / measureBackdrop.height - 1;
    }

    public inline function updateCurrentBPM():Void {
        var currentBPM:Float = chart.gameplayInfo.bpm;
        var stepOffset:Float = 0;
        var lastChange:Float = 0;

        eventBPM = false;

        if (chart.events.length > 0) {
            for (event in chart.events) {
                if (event.event.toLowerCase().trim() != "change bpm") continue;
                if (event.time > Conductor.time) break;

                stepOffset += ((event.time - lastChange) / (((60 / currentBPM) * 1000) / Conductor.stepsPerBeat));
                currentBPM = event.arguments[0];
                lastChange = event.time;
                eventBPM = true;
            }
        }

        Conductor.beatOffset.time = lastChange;
        Conductor.beatOffset.step = stepOffset;

        if (currentBPM != Conductor.bpm || lastBpmChange != lastChange) {
            Conductor.bpm = currentBPM;
            lastBpmChange = lastChange;

            awaitBPMReload = (subState != null);
            if (!awaitBPMReload) {
                reloadGrid(false, !eventBPM);
                // notes.forceRegen = true;
            }
        }
    }

    inline function loadSong():Void {
        music = new MusicPlayback(chart.meta.folder);
        music.setupInstrumental(chart.gameplayInfo.instrumental);

        if (chart.gameplayInfo.voices?.length > 0)
            for (voiceFile in chart.gameplayInfo.voices)
                music.createVoice(voiceFile);

        music.onSongEnd.add(() -> {
            Conductor.resetPrevTime();
            line.y = 0;
        });

        music.instrumental.time = startTime;
        add(music);

        music.instrumental.volume = (Settings.get("CHART_muteInst")) ? 0 : 1;
        music.pitch = Settings.get("CHART_pitch");

        Conductor.beatsPerMeasure = chart.gameplayInfo.beatsPerMeasure ?? 4;
        Conductor.stepsPerBeat = chart.gameplayInfo.stepsPerBeat ?? 4;
        Conductor.bpm = chart.gameplayInfo.bpm;
        Conductor.music = music.instrumental;
    }

    inline function loadData():Void {
        eventList = EventManager.getEventList();
        currentEvent = EventManager.defaultEvents[0];
        eventArgs = [for (arg in currentEvent.arguments) arg.value];

        noteTypes = Note.defaultTypes.copy();

        #if ENGINE_SCRIPTING
        var softcodedTypes:String = Assets.getPath("scripts/notetypes", NONE);
        if (FileTools.exists(softcodedTypes))
            for (script in FileTools.readDirectory(softcodedTypes))
                noteTypes.push(script.substring(0, script.lastIndexOf(".")));
        #end

        add(clipboard = new Clipboard<ChartClipboardItems>());
        add(undoList = new UndoList<ChartUndos>());

        beatSnap = preferences.beatSnap ?? 16;
    }

    public function undo(recursive:Bool = false):Void {
        if (recursive) {
            for (i in 0...5) undo(false);
            return;
        }

        var undo:ChartUndos = undoList.undo();
        if (undo == null) return;

        switch (undo) {
            case AddNote(data): undo_removeNote(data);
            case RemoveNote(data): undo_addNote(data);
            case AddEvent(data): undo_removeEvent(data);
            case RemoveEvent(data): undo_addEvent(data);

            case ObjectDrag(notes, events):
                for (note in notes) undo_noteDrag(note.ref, note.oldTime, note.oldDir, note.oldStl);
                for (event in events) undo_eventDrag(event.ref, event.oldTime);

            case CopyObjects(notes, events):
                if (notes != null) for (note in notes) undo_removeNote(note);
                if (events != null) for (event in events) undo_removeEvent(event);
        }
    }

    public function redo(recursive:Bool = false):Void {
        if (recursive) {
            for (i in 0...5) redo(false);
            return;
        }
        
        var redo:ChartUndos = undoList.redo();
        if (redo == null) return;

        switch (redo) {
            case AddNote(data): undo_addNote(data);
            case RemoveNote(data): undo_removeNote(data);
            case AddEvent(data): undo_addEvent(data);
            case RemoveEvent(data): undo_removeEvent(data);

            case ObjectDrag(notes, events):
                for (note in notes) undo_noteDrag(note.ref, note.time, note.dir, note.str);
                for (event in events) undo_eventDrag(event.ref, event.time);

            case CopyObjects(notes, events):
                if (notes != null) for (note in notes) undo_addNote(note);
                if (events != null) for (event in events) undo_addEvent(event);
        }
    }

    public function clipboardCopy():Void {
        clipboard.clear();

        notes.forEachAlive((note) -> {
            if (note.selected)
                clipboard.register(Note(note.data.time - Conductor.time, note.data.direction, note.data.strumline, note.data.length, note.data.type));
        });

        events.forEachAlive((event) -> {
            if (event.selected)
                clipboard.register(Event(event.data.event, event.data.time - Conductor.time, event.data.arguments?.copy() ?? null));
        });
    }

    public function clipboardPaste():Void {
        var noteRewinds:Array<ChartNote> = null;
        var eventRewinds:Array<ChartEvent> = null;

        var items:Array<ChartClipboardItems> = clipboard.get();
        selection.unselectAll();

        for (item in items) {
            switch (item) {
                case Note(conductorDiff, direction, strumline, length, type):
                    var data:ChartNote = {
                        time: Conductor.time + conductorDiff,
                        direction: direction,
                        strumline: strumline,
                        length: length,
                        type: type
                    };

                    selection.register(undo_addNote(data));

                    if (noteRewinds == null) noteRewinds = [];
                    noteRewinds.push(data);
                case Event(event, conductorDiff, arguments):
                    var data:ChartEvent = {
                        event: event,
                        time: Conductor.time + conductorDiff,
                        arguments: arguments
                    };

                    selection.register(undo_addEvent(data));

                    if (eventRewinds == null) eventRewinds = [];
                    eventRewinds.push(data);
            }
        }

        if (noteRewinds != null || eventRewinds != null)
            undoList.register(CopyObjects(noteRewinds, eventRewinds));
    }

    inline function undo_addNote(data:ChartNote):DebugNote {
        var note:DebugNote = notes.addNote(data);
        chart.notes.push(data);
        sortNotes();
        return note;
    }

    inline function undo_removeNote(data:ChartNote):Void {
        notes.forEachAlive((note) -> {
            if (note.data == data)
                killNote(note);
        });
    }

    inline function undo_addEvent(data:ChartEvent):EventSprite {
        var sprite:EventSprite = events.recycle(EventSprite);
        sprite.y = getYFromTime(data.time);
        sprite.data = data;

        chart.events.push(data);
        sortEvents();

        return sprite;
    }

    inline function undo_removeEvent(data:ChartEvent):Void {
        events.forEachAlive((event) -> {
            if (event.data == data)
                killEvent(event);
        });
    }

    inline function undo_noteDrag(note:ChartNote, time:Float, direction:Int, strumline:Int):Void {
        note.time = time;
        note.direction = direction;
        note.strumline = strumline;

        notes.forEachAlive((spr) -> {
            if (spr.data == note) {
                spr.x = checkerboard.x + checkerSize * (direction + 4 * strumline) + separatorWidth * strumline;
                spr.y = getYFromTime(time);

                spr.sustain.color = DebugNote.sustainColors[direction];
                spr.animation.play(Note.directions[direction]);
            }
        });

        requestSortNotes = true;
    }

    inline function undo_eventDrag(event:ChartEvent, time:Float):Void {
        event.time = time;
        events.forEachAlive((spr) -> {
            if (spr.data == event)
                spr.y = getYFromTime(time);
        });

        requestSortEvents = true;
    }

    inline function createGrid():Void {
        // thanks to RapperGF for the idea
        miniMap = new Camera(0, 0, checkerSize * 8 + separatorWidth + 10, Math.floor(checkerSize * 40), 0.15);
        miniMap.x = FlxG.width - 30 - miniMap.width * miniMap.zoom;
        miniMap.y = FlxG.height - 20 - miniMap.height * miniMap.zoom;
        miniMap.bgColor = FlxColor.GRAY;
        FlxG.cameras.add(miniMap, false);

        checkerboard = new ChartCheckerboard();
        checkerboard.bottom = getYFromTime(music.instrumental.length);
        add(checkerboard);

        line = new FlxSprite();
        line.makeRect(checkerSize * 10, 5);
        line.y = getYFromTime(startTime);
        line.screenCenter(X);
        line.active = false;

        FlxG.camera.follow(line, LOCKON);
        FlxG.camera.targetOffset.y = 125;

        miniMap.follow(line, LOCKON);
        miniMap.targetOffset.set(5, 125);

        notes = new ChartNoteGroup(this);
        events = new ChartEventGroup();

        notes.cameras = [FlxG.camera, miniMap];
        notes.active = false; // we're updating it manually

        measureBackdrop = new FlxBackdrop(null, Y);
        measureBackdrop.makeRect(checkerSize * 8 + separatorWidth, 5, FlxColor.WHITE);
        measureBackdrop.visible = Settings.get("CHART_measureMark");
        measureBackdrop.x = checkerboard.x;
        measureBackdrop.active = false;
        refreshMeasureMark();

        // create receptors
        receptors = new FlxTypedSpriteGroup<Receptor>(checkerboard.x);
        receptors.visible = Settings.get("CHART_receptors");
        receptors.moves = false;

        for (i in 0...8) {
            var receptor:Receptor = new Receptor(Std.int(i % 4));
            receptor.x = checkerSize * i + separatorWidth * Math.floor(i / 4);

            receptor.animation.finishCallback = (name) -> {
                if (name.startsWith("confirm"))
                    receptor.playAnimation("static", true);
            };

            receptor.setGraphicSize(checkerSize, checkerSize);
            receptor.updateHitbox();

            receptor.moves = false;
            receptors.add(receptor);
        }
        //

        beatIndicators = new FlxSpriteGroup();
        beatIndicators.visible = Settings.get("CHART_beatIndices");
        beatIndicators.active = false;

        for (i in 0...2) {
            var losange:FlxSprite = new FlxSprite();
            losange.makeRect(checkerSize * 0.35, checkerSize * 0.35, FlxColor.WHITE, false, "charteditor_losange");
            losange.x = (line.x - losange.width * 0.5) + ((line.width + losange.width * 0.5) * i);
            losange.color = FlxColor.RED;
            losange.angle = 45;
            losange.active = false;
            beatIndicators.add(losange);
        }

        mouseCursor = new FlxSprite();
        mouseCursor.makeRect(checkerSize, checkerSize, FlxColor.BLACK);
        mouseCursor.setPosition(checkerboard.x, checkerSize);
        mouseCursor.active = false;
        mouseCursor.alpha = 0.65;

        add(mouseCursor);
        add(measureBackdrop);
        add(events);
        add(notes);
        add(line);
        add(beatIndicators);
        add(receptors);
    }

    inline function createBackground():Void {
        var background:FlxSprite = new FlxSprite(0, 0, Assets.image("menus/menuDesat"));
        background.scrollFactor.set();
        background.color = 0x312c2d;
        background.active = false;
        add(background);
    }

    inline function createUI():Void {
        substateCam = new Camera();
        substateCam.bgColor.alpha = 0;
        FlxG.cameras.add(substateCam, false);

        opponentIcon = new HealthIcon(checkerboard.x, 35, getIcon(chart.gameplayInfo.opponent));
        opponentIcon.setGraphicSize(0, 100);
        opponentIcon.updateHitbox();
        opponentIcon.x -= opponentIcon.width;
        opponentIcon.scrollFactor.set();
        opponentIcon.healthAnim = false;
        add(opponentIcon);

        playerIcon = new HealthIcon(checkerboard.x + checkerboard.width, 35, getIcon(chart.gameplayInfo.player));
        playerIcon.setGraphicSize(0, 100);
        playerIcon.updateHitbox();
        playerIcon.scrollFactor.set();
        playerIcon.healthAnim = false;
        playerIcon.flipX = true;
        add(playerIcon);

        hoverBox = new HoverBox();
        hoverBox.onRelease = onHoverBoxRelease;

        selection = new SelectionHelper(hoverBox);
        selection.onRelease = onSelectionRelease;

        add(selection);
        add(hoverBox);

        overlay = new FlxSprite(0, 45);
        overlay.makeRect(1, 115, FlxColor.GRAY);
        overlay.visible = Settings.get("CHART_timeOverlay");
        overlay.scrollFactor.set();
        overlay.active = false;
        overlay.alpha = 0.4;
        add(overlay);

        musicText = new FlxText(5, overlay.y);
        musicText.setFormat(Assets.font("vcr"), 14);
        musicText.setBorderStyle(OUTLINE, FlxColor.BLACK, 0.5);
        musicText.visible = Settings.get("CHART_timeOverlay");
        musicText.scrollFactor.set();
        musicText.active = false;
        add(musicText);

        timeBar = new VerticalScroll();
        timeBar.hidden = timeBar.disabled = !Settings.get("CHART_timeOverlay");
        add(timeBar);

        // have to use customStyle for width
        var thumb = timeBar.findComponent("scroll-thumb-button");
        timeBar.customStyle.width = thumb.customStyle.width = 20;
        timeBar.invalidateComponentStyle();
        thumb.invalidateComponentStyle();
        //

        timeBar.left = FlxG.width - 20;
        timeBar.height = FlxG.height - 35;
        timeBar.thumbSize = 25;
        timeBar.top = 35;

        timeBar.max = music.instrumental.length - 1; // offset of 1ms so it can actually reach the end
        timeBar.onChange = (_) -> {
            if (!timeBar.hitTest(FlxG.mouse.screenX, FlxG.mouse.screenY) || !FlxG.mouse.pressed)
                return;

            pauseMusic();
            music.instrumental.time = timeBar.pos;

            for (vocals in music.vocals)
                vocals.time = music.instrumental.time;

            Conductor.resetPrevTime();
        }

        Main.fpsOverlay.relativeY = FlxG.height - 25;
        add(ui = new ChartUI());
    }

    // this reloads the current chart when clicking on the autosave stuff in the ui
    // TODO: fix that issue 
    
    public function loadAutoSave():Void {
        var oldChart:Chart = chart;

        Tools.invokeTempSave((save) -> {
            var saveMap:Map<String, ChartJson> = save.data.charts;
            if (saveMap != null && saveMap.exists(chart.meta.folder))
                chart = Chart.resolve(saveMap.get(chart.meta.folder));
        }, "chart_autosave");

        if (oldChart == chart) {
            NotificationManager.instance.addNotification({
                title: "Warning!",
                body: "No autosave has been found.",
                type: NotificationType.Warning
            });
            return;
        }

        chart.meta = oldChart.meta;

        // perhaps it's better not to switch states at all?

        Assets.clearAssets = false;
        FlxG.switchState(ChartEditor.new.bind(chart, difficulty, 0));
    }

    public function autoSave():Void {
        Tools.invokeTempSave((save) -> {
            var saveMap:Map<String, Dynamic> = save.data.charts;
            if (saveMap == null)
                saveMap = [];

            saveMap.set(chart.meta.folder, chart.toStruct());
            save.data.charts = saveMap;
        }, "chart_autosave");
    }

    public function onCrash():Void {
        autoSave();
    }

    inline function spawnEvents(eventArray:Array<ChartEvent>):Void {
        for (eventData in eventArray) {
            var event:EventSprite = new EventSprite();
            event.y = getYFromTime(eventData.time);
            event.data = eventData;
            events.add(event);
        }
    }

    public inline function sortNotes():Void {
        chart.notes.sort((a, b) -> Std.int(a.time - b.time));
    }

    public inline function sortEvents():Void {
        chart.events.sort((a, b) -> Std.int(a.time - b.time));
    }

    override function destroy():Void {
        if (runAutosave) autoSave();

        difficulty = null;
        chart = null;

        eventList = null;
        currentEvent = null;
        currentNoteType = null;
        noteDrags = null;
        eventDrags = null;
        eventArgs = null;
        noteTypes = null;
        hitsound = null;

        FlxG.stage.window.onClose.remove(autoSave);
        Main.fpsOverlay.resetPosition();

        super.destroy();
    }

    inline function set_selectedNote(v:DebugNote):DebugNote {
        if (selectedNote != null)
            selectedNote.editing = false;

        if (v != null) {
            notes.lastSelectedNote = null;
            v.editing = true;
        }

        return selectedNote = v;
    }

    inline function set_selectedEvent(v:EventSprite):EventSprite {
        if (selectedEvent != null)
            selectedEvent.rect.visible = false;

        if (v != null)
            v.rect.visible = true;

        return selectedEvent = v;
    }

    inline function get_preferences():Dynamic
        return FlxG.save.data.chartingPrefs;

    inline function set_preferences(v:Dynamic):Dynamic
        return FlxG.save.data.chartingPrefs = v;

    inline function mouseValid():Bool {
        // NOTE: we're checking the mouse's y so notes/events can't be placed outside of the grid

        return
            mouseCursor.x >= checkerboard.x - checkerSize - separatorWidth
            && mouseCursor.x < checkerboard.x + checkerboard.width
            && FlxG.mouse.y >= 0 && FlxG.mouse.y < checkerboard.bottom;
    }

    inline function getMouseY():Float {
        return (FlxG.keys.pressed.SHIFT) ? FlxG.mouse.y : quantizePosWithSnap(FlxG.mouse.y, beatSnap);
    }

    public static inline function quantizePos(position:Float):Float {
        return Math.ffloor(position / checkerSize) * checkerSize;
    }

    public static inline function quantizePosWithSnap(position:Float, snap:Int):Float {
        var mult:Float = checkerSize * (16 / snap);
        return Math.ffloor(position / mult) * mult;
    }

    public static inline function roundPos(position:Float):Float {
        return Math.fround(position / checkerSize) * checkerSize;
    }

    public static inline function getTimeFromY(y:Float):Float {
        return Conductor.beatOffset.time + Conductor.stepCrochet * ((y / checkerSize) - Conductor.beatOffset.step);
    }

    public static inline function getYFromTime(time:Float):Float {
        return checkerSize * (Conductor.beatOffset.step + ((time - Conductor.beatOffset.time) / Conductor.stepCrochet));
    }

    public static inline function getIcon(character:String):String {
        if (character == null)
            return HealthIcon.DEFAULT_ICON;

        var file:String = Assets.yaml('data/characters/${character}');
        if (!FileTools.exists(file))
            return HealthIcon.DEFAULT_ICON;

        var icon:String = Tools.parseYAML(FileTools.getContent(file)).icon;
        return (icon == null) ? HealthIcon.DEFAULT_ICON : icon;
    }
}