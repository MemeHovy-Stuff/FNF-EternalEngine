package objects;

import flixel.math.FlxPoint;
import flixel.graphics.FlxGraphic;
import flixel.graphics.frames.FlxAtlasFrames;

class HealthIcon extends OffsetSprite {
    public static final DEFAULT_ICON:String = "face";

    public var state(default, set):HealthState = "neutral";
    public var character(get, set):String;

    public var size:FlxPoint = FlxPoint.get(150, 150);
    public var healthAnim:Bool = true;

    public var bopSize:Float = 25;
    public var bopDuration:Float = 1.5;
    public var bopStep:Int = -1;
    
    var storedOffsets:FlxPoint = FlxPoint.get();
    var animOffsets:FlxPoint = FlxPoint.get();
    var _character:String;

    public function new(x:Float = 0, y:Float = 0, icon:String = "face") {
        super(x, y);

        changeIcon(icon);
        moves = false;
    }

    override function update(elapsed:Float):Void {
        if (healthAnim) {
            if (health > 20) {
                if (health > 80 && state != WINNING) state = WINNING;
                else if (health < 80 && state != NEUTRAL) state = NEUTRAL;
            }
            else if (state != LOSING) state = LOSING;
        }

        if (bopStep != -1) {            
            var ratio:Float = Math.min(Conductor.self.decStep - bopStep, bopDuration) / bopDuration;

            setGraphicSize(FlxMath.lerp(size.x + bopSize, size.x, ratio), FlxMath.lerp(size.y + bopSize, size.y, ratio));
            updateHitbox();

            offset.addPoint(storedOffsets);
            offset.addPoint(animOffsets);
        }

        super.update(elapsed);
    }

    public inline function bop():Void {
        bopStep = Conductor.self.step;
    }

    public function resetBop():Void {
        setGraphicSize(size.x, size.y);
        updateHitbox();
        bopStep = -1;

        offset.addPoint(storedOffsets);
        offset.addPoint(animOffsets);
    }

    override function destroy():Void {
        storedOffsets = FlxDestroyUtil.put(storedOffsets);
        animOffsets = FlxDestroyUtil.put(animOffsets);
        size = FlxDestroyUtil.put(size);

        _character = null;
        state = null;

        super.destroy();
    }

    public function changeIcon(icon:String):Void {
        var configPath:String = Assets.yaml('images/icons/${icon}');
        _character = icon;

        if (!FileTools.exists(configPath))
            changeSimple(icon);
        else
            changeAdvanced(Tools.parseYAML(FileTools.getContent(configPath)));

        playAnimation("neutral", true);
        size.set(width, height);
    }

    function changeAdvanced(config:HealthIconConfig):Void {
        var possibleFrames:FlxAtlasFrames = Assets.findFrames('icons/${character}');

        if (possibleFrames != null)
            frames = possibleFrames;
        else {
            var newGraphic:FlxGraphic = Assets.image('icons/${character}');
            if (newGraphic == null) newGraphic = Assets.image('icons/${DEFAULT_ICON}');
            loadGraphic(newGraphic, true, Math.floor(newGraphic.width / (config.frames ?? Math.floor(newGraphic.width / newGraphic.height))), newGraphic.height);
        }

        resetValues();

        Tools.addYamlAnimations(this, config.animations);
        scale.set(config.scale == null ? 1 : (config.scale[0] ?? 1), config.scale == null ? 1 : (config.scale[1] ?? 1));
        updateHitbox();

        var offsetX:Float = -(config.globalOffsets != null ? (config.globalOffsets[0] ?? 0) : 0);
        var offsetY:Float = -(config.globalOffsets != null ? (config.globalOffsets[1] ?? 0) : 0);
        offset.add(offsetX, offsetY);

        antialiasing = config.antialiasing ?? FlxSprite.defaultAntialiasing;
        storedOffsets.set(offset.x, offset.y);
    }

    function changeSimple(icon:String):Void {
        var newGraphic:FlxGraphic = Assets.image('icons/${icon}');
        if (newGraphic == null) {
            newGraphic = Assets.image('icons/${DEFAULT_ICON}');
            _character = DEFAULT_ICON;
        }

        var size:Int = Math.floor(newGraphic.width / newGraphic.height);
        loadGraphic(newGraphic, true, Math.floor(newGraphic.width / size), newGraphic.height);
        for (i in 0...size) animation.add([NEUTRAL, LOSING, WINNING][i], [i], 0);

        scale.set(1, 1);
        updateHitbox();
        resetValues();
    }

    function resetValues():Void {
        antialiasing = FlxSprite.defaultAntialiasing;
        animationOffsets.clear();
        storedOffsets.set();
        animOffsets.set();
    }

    override function playAnimation(name:String, force:Bool = false, reversed:Bool = false, frame:Int = 0) {
        super.playAnimation(name, force, reversed, frame);
        animOffsets.set(offset.x, offset.y);
        offset.addPoint(storedOffsets);
    }

    function set_state(v:HealthState):HealthState {
        if (v != null && exists && animation.exists(v) && animation.curAnim.name != v)
            playAnimation(v, true);

        return state = v;
    }

    inline function set_character(v:String):String {
        changeIcon(v);
        return v;
    }

    inline function get_character():String
        return _character;
}

typedef HealthIconConfig = {
    var ?frames:Int;
    var ?animations:Array<YAMLAnimation>;
    var ?globalOffsets:Array<Float>;

    var ?scale:Array<Float>;
    var ?antialiasing:Bool;
}

enum abstract HealthState(String) from String to String {
    var NEUTRAL = "neutral";
    var WINNING = "winning";
    var LOSING = "losing";
}
