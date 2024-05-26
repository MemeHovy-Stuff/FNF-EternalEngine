package gameplay.notes;

import flixel.FlxCamera;
import flixel.math.FlxRect;
import objects.OffsetSprite;

import globals.NoteSkin;
import globals.ChartFormat.ChartNote;

class Note extends OffsetSprite {
    public static final defaultTypes:Array<String> = ["Alt Animation", "No Animation"];
    public static final directions:Array<String> = ["left", "down", "up", "right"];

    public static var safeZoneOffset(get, never):Float;
    static function get_safeZoneOffset():Float
        return 166.66 * Conductor.self.playbackRate;

    public var beenHit:Bool = false;
    public var missed:Bool = false;

    public var canBeHit(get, default):Bool = false;
    public var late(get, default):Bool = false;

    public var time:Float = 0;
    public var direction:Int = 0;

    public var parentStrumline:StrumLine;
    public var holdCover:HoldCover;
    public var strumline:Int = 0;

    public var length(default, set):Float = 0;
    public var sustain(default, set):Sustain;

    public var holdable(get, never):Bool;
    public var invalidatedHold(get, never):Bool;
    public var finishedHold:Bool = false;
    public var perfectHold:Bool = true;
    public var unheldTime:Float;

    public var type(default, set):String;
    public var skin(default, set):String;

    public var animSuffix:String;
    public var noSingAnim:Bool = false;
    public var noMissAnim:Bool = false;
    public var avoid:Bool = false;

    public var earlyHitMult:Float = 1;
    public var lateHitMult:Float = 1;

    public var alphaMult:Float = 1;
    public var sustainAlpha:Float = 0.6;

    public var overrideSustain:Bool = false;
    public var quantizeSustain:Bool = false;

    public var downscroll(get, default):Bool = Options.downscroll;
    public var scrollSpeed(get, default):Float = 1;
    public var distance(get, default):Float = 0;

    public function new(time:Float = 0, direction:Int = 0, type:String = null, skin:String = "default"):Void {
        super();

        this.time = time;
        this.direction = direction;
        this.type = type;
        this.skin = skin;

        moves = false;
    }

    /**
     * Reset this `Note`'s properties, making it ready to use for recycling.
     * @param data The chart note data
     * @return `this`
     */
    public function setup(data:ChartNote):Note {
        time = data.time;
        direction = data.direction;
        strumline = data.strumline;
        length = data.length;
        type = data.type;

        beenHit = false;
        missed = false;
        visible = true;

        perfectHold = true;
        finishedHold = false;
        unheldTime = 0;
        holdCover = null;

        alphaMult = 1;
        alpha = 1;

        playAnimation(directions[direction], true);
        updateHitbox();
        
        return this;
    }

    public function follow(receptor:FlxSprite):Void {
        x = receptor.x;
        y = receptor.y + distance;
        alpha = receptor.alpha * alphaMult;

        if (holdable)
            sustain.alpha = sustainAlpha * alpha * (invalidatedHold ? 0.5 : 1);
    }

    public function clipSustain(receptor:FlxSprite):Void {
        var receptorCenter:Float = receptor.y + (receptor.height * 0.5);
        var tail:FlxSprite = sustain.tail;

        var tailRect:FlxRect = (tail.clipRect ?? FlxRect.get(0, 0, tail.frameWidth));
        var sustainRect:FlxRect = (sustain.clipRect ?? FlxRect.get());

        if (downscroll) {
            sustainRect.height = sustain.height - Math.max(sustain.y + sustain.height - receptorCenter, 0);
            tailRect.height = (receptorCenter - tail.y) / tail.scale.y;
            tailRect.y = tail.frameHeight - tailRect.height;
        } else {
            sustainRect.y = Math.max(receptorCenter - sustain.y, 0);
            sustainRect.height = sustain.height - sustainRect.y;
            tailRect.y = (receptorCenter - tail.y) / tail.scale.y;
            tailRect.height = tail.frameHeight - tailRect.y;
        }

        sustain.clipRect = sustainRect;
        tail.clipRect = tailRect;
    }

    public inline function findRating(ratings:Array<Rating>):Rating {
        var diff:Float = (Math.abs(Conductor.self.time - time) / Conductor.self.playbackRate);
        var rating:Rating = ratings[ratings.length - 1];
        var i:Int = ratings.length - 2;

        while (i >= 0 && diff <= ratings[i].hitWindow)
            rating = ratings[i--];

        return rating;
    }

    public inline function resetTypeProps():Void {
        animSuffix = null;
        earlyHitMult = 1;
        lateHitMult = 1;
        noSingAnim = false;
        noMissAnim = false;
        overrideSustain = false;
        avoid = false;
    }

    public inline function getScrollSpeed():Float {
        return Math.abs(parentStrumline?.scrollSpeed ?? @:bypassAccessor this.scrollSpeed);
    }

    override function update(elapsed:Float):Void {
        if (holdable && sustain.exists && sustain.active)
            sustain.update(elapsed);

        super.update(elapsed);
    }

    override function kill():Void {
        sustain?.kill();
        sustain = null;
        super.kill();
    }

    override function destroy():Void {
        sustain = null;
        holdCover = null;
        parentStrumline = null;
        skin = null;
        type = null;

        super.destroy();
    }

    function set_length(v:Float):Float {
        return length = Math.max(v, 0);
    }

    function set_sustain(v:Sustain):Sustain {
        if (v != null)
            v.parent = this;

        return sustain = v;
    }

    function set_type(v:String):String {
        resetTypeProps();

        if (v != null) {
            // case "Type" to hardcode your notetypes
            switch (v) {
                case "Alt Animation":
                    animSuffix = "-alt";
                case "No Animation":
                    noSingAnim = true;
            }
        }

        return type = v;
    }

    function set_skin(v:String):String {
        if (v != null) {
            switch (v) {
                // case "name" to hardcode your noteskins
                case "default":
                    // default noteskin
                    frames = Assets.getSparrowAtlas("notes/notes");

                    for (dir in directions) {
                        animation.addByPrefix(dir, '${dir}0', 0);
                        animation.addByPrefix(dir + " hold", '${dir} hold piece', 0);
                        animation.addByPrefix(dir + " tail", '${dir} hold end', 0);
                    }

                    playAnimation(directions[direction], true);

                    scale.set(0.7, 0.7);
                    updateHitbox();

                    // make sure to reset some props for noteskin swapping.
                    antialiasing = FlxSprite.defaultAntialiasing;
                    flipX = flipY = false;

                    quantizeSustain = false;
                    sustainAlpha = 0.6;
                default:
                    // softcoded noteskin
                    var config:NoteSkinConfig = NoteSkin.get(v);
                    if (config == null || config.note == null)
                        return set_skin("default");

                    var dir:String = directions[direction];
                    NoteSkin.applyGenericSkin(this, config.note, dir, dir);

                    quantizeSustain = config.note.tiledSustain ?? false;
                    sustainAlpha = config.note.sustainAlpha ?? 0.6;
            }
        }

        return skin = v;
    }

    inline function get_scrollSpeed():Float
        return getScrollSpeed() * 0.45;

    inline function get_downscroll():Bool
        return parentStrumline?.downscroll ?? this.downscroll;

    inline function get_invalidatedHold():Bool
        return unheldTime > 1;

    inline function get_holdable():Bool
        return length != 0;

    function get_distance():Float {
        var timing:Float = (Conductor.self.enableInterpolation ? Conductor.self.interpolatedTime : Conductor.self.time);
        return (downscroll ? -1 : 1) * ((time - timing) * scrollSpeed);
    }

    function get_late():Bool {
        return this.late || (Conductor.self.time - time) > (safeZoneOffset * lateHitMult);
    }

    function get_canBeHit():Bool {
        if (beenHit || missed)
            return false;

        if (parentStrumline != null)
            return (parentStrumline.cpu && time <= Conductor.self.time)
                || (!parentStrumline.cpu && Conductor.self.time >= time - (safeZoneOffset * earlyHitMult) && Conductor.self.time <= time + (safeZoneOffset * lateHitMult));
        
        return this.canBeHit;
    }

    override function set_cameras(v:Array<FlxCamera>):Array<FlxCamera> {
        if (holdable) sustain.cameras = v;
        return super.set_cameras(v);
    }

    override function set_camera(v:FlxCamera):FlxCamera {
        if (holdable) sustain.camera = v;
        return super.set_camera(v);
    }
}
