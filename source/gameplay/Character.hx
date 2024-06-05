package gameplay;

import flixel.math.FlxPoint;
import objects.HealthIcon;
import objects.DancingSprite;
import states.substates.GameOverScreen;
import states.substates.GameOverScreen.GameOverData;

#if ENGINE_SCRIPTING
import core.scripting.HScript;
import core.scripting.ScriptableState;
#end

typedef CharacterConfig = {
    var image:String;
    var animations:Array<YAMLAnimation>;

    var ?atlasType:String;
    var ?library:String;

    var ?antialiasing:Bool;
    var ?flip:Array<Bool>;
    var ?scale:Array<Float>;

    var ?singAnimations:Array<String>;
    var ?singDuration:Float;

    var ?danceSteps:Array<String>;
    var ?danceBeat:Float;

    var ?cameraOffsets:Array<Float>;
    var ?globalOffsets:Array<Float>;

    var ?icon:String;
    var ?noteSkin:String;
    var ?healthBarColor:Dynamic;

    var ?gameOverChar:String;
    var ?gameOverData:GameOverData;

    var ?playerFlip:Bool;
    var ?extra:Dynamic;
}

enum abstract CharacterType(String) from String to String {
    var DEFAULT = "default";
    var PLAYER = "player";
    var GAMEOVER = "gameover";
    var DEBUG = "debug";
}

class Character extends DancingSprite {
    public static final defaultAnimations:Array<String> = ["singLEFT", "singDOWN", "singUP", "singRIGHT"];

    public var character(default, set):String;
    public var data:CharacterConfig;
    public var type:CharacterType;

    public var singAnimations:Array<String> = defaultAnimations.copy();
    public var singDuration:Float = 4;

    public var animEndTime:Float = 0;
    public var holdTime:Float = 0;
    public var holding:Bool = false;

    public var cameraOffsets:Array<Float>;
    public var globalOffsets:Array<Float>;

    public var healthIcon:String = HealthIcon.DEFAULT_ICON;
    public var healthBarColor:FlxColor = FlxColor.GRAY;

    public var gameOverChar:String;
    public var gameOverData:GameOverData;

    public var noteSkin:String = "default";
    public var extra:Dynamic = null;

    #if ENGINE_SCRIPTING
    var script:HScript;
    #end

    public function new(x:Float = 0, y:Float = 0, character:String = "bf", type:CharacterType = DEFAULT):Void {
        super(x, y);

        this.type = type;
        this.character = character;
    }

    override function update(elapsed:Float):Void {
        super.update(elapsed);

        if (animation.curAnim == null || type == DEBUG)
            return;

        if (animEndTime > 0) {
            animEndTime -= elapsed;
            if (animEndTime <= 0) {
                animEndTime = 0;
                forceDance(true);
            }
        }

        if (singAnimations.contains(animation.curAnim.name))
            holdTime += elapsed;

        if (!holding && holdTime >= Conductor.self.stepCrochet * singDuration * 0.001)
            forceDance();
    }

    public function setup(config:CharacterConfig):Void {
        frames = Assets.getFrames(config.image, config.atlasType, config.library);
        Tools.addYamlAnimations(this, config.animations);

        singAnimations = config.singAnimations ?? singAnimations;
        singDuration = config.singDuration ?? 4;

        danceSteps = config.danceSteps ?? ["idle"];
        beat = config.danceBeat ?? 2;

        cameraOffsets = config.cameraOffsets;
        globalOffsets = config.globalOffsets;
        extra = config.extra;

        healthBarColor = (config.healthBarColor == null) ? ((type == PLAYER) ? 0xFF66FF33 : 0xFFFF0000) : Tools.getColor(config.healthBarColor);
        healthIcon = config.icon ?? HealthIcon.DEFAULT_ICON;

        gameOverChar = config.gameOverChar;
        noteSkin = config.noteSkin;

        if (type == GAMEOVER && config.gameOverData != null)
            gameOverData = GameOverScreen.formatData(config.gameOverData);

        forceDance(true);

        if (config.antialiasing != null)
            antialiasing = config.antialiasing;

        if (config.flip != null) {
            flipX = config.flip[0] ?? false;
            flipY = config.flip[1] ?? false;
        }

        if (config.scale != null) {
            scale.set(config.scale[0] ?? 1, config.scale[1] ?? 1);
            updateHitbox();
        }

        if (type == PLAYER && config.playerFlip) {
            // TODO: flipped offsets
            swapAnimations(singAnimations[0], singAnimations[3]);
            swapAnimations(singAnimations[0] + "miss", singAnimations[3] + "miss");
            flipX = !flipX;
        }
    }

    public inline function sing(direction:Int, suffix:String = "", forced:Bool = true):Void
        playAnimation(singAnimations[direction] + (suffix ?? ""), forced);

    function swapAnimations(firstAnimation:String, secondAnimation:String):Void {
        if (!animation.exists(firstAnimation) || !animation.exists(secondAnimation))
            return;

        @:privateAccess {
            var secondAnim = animation._animations.get(secondAnimation);
            animation._animations.set(secondAnimation, animation._animations.get(firstAnimation));
            animation._animations.set(firstAnimation, secondAnim);
        }

        if (offsets.exists(firstAnimation) && offsets.exists(secondAnimation)) {
            var secondOffsets = offsets.get(secondAnimation);
            offsets.addPoint(secondAnimation, offsets.get(firstAnimation));
            offsets.addPoint(firstAnimation, secondOffsets);
        }
    }

    override function dance(beat:Int, forced:Bool = false):Void {
        if (danceSteps.contains(animation.curAnim.name) || type == GAMEOVER)
            super.dance(beat, forced);
    }

    override function playAnimation(name:String, force:Bool = false, reversed:Bool = false, frame = 0):Void {
        super.playAnimation(name, force, reversed, frame);
        holdTime = 0;
    }

    public function getCamDisplace():FlxPoint {
        var point:FlxPoint = getMidpoint();
        
        if (cameraOffsets != null)
            point.add(cameraOffsets[0] ?? 0, cameraOffsets[1] ?? 0);

        return point;
    }

    #if ENGINE_SCRIPTING
    inline function destroyScript():Void {
        script?.destroy();
        script = null;
    }
    #end

    override function destroy():Void {
        #if ENGINE_SCRIPTING
        destroyScript();
        #end

        cameraOffsets = null;
        globalOffsets = null;

        gameOverData = null;
        gameOverChar = null;

        healthIcon = null;
        noteSkin = null;

        singAnimations = null;
        character = null;

        extra = null;
        data = null;
        type = null;

        super.destroy();
    }

    function set_character(v:String):String {
        if (v != null) {
            switch (v) {
                // case "name" to hardcode your characters
                default:
                    var filePath:String = Assets.yaml('data/characters/${v}');

                    if (FileTools.exists(filePath)) {
                        data = Tools.parseYAML(FileTools.getContent(filePath));
                        setup(data);
                    } else {
                        trace('Could not find character "${v}"!');
                        loadDefault();
                        data = null;
                    }

                    #if ENGINE_SCRIPTING
                    destroyScript();

                    if (type != DEBUG && FlxG.state is ScriptableState) {
                        var scriptPath:String = Assets.script('data/characters/${v}');
                        if (FileTools.exists(scriptPath)) {
                            script = new HScript(scriptPath);
                            script.set("this", this);

                            cast(FlxG.state, ScriptableState).addScript(script);
                            script.call("onCharacterCreation");
                        }
                    }
                    #end
            }

            animation.finish();
            currentDance = 0;
        }

        return character = v;
    }

    inline function loadDefault():Void {
        var file:String = Assets.yaml("data/characters/boyfriend");
        var content:String = FileTools.getContent(file);
        setup(Tools.parseYAML(content));

        healthIcon = HealthIcon.DEFAULT_ICON;
        healthBarColor = FlxColor.GRAY;
    }
}