package objects;

class DancingSprite extends OffsetSprite {
    public var danceSteps:Array<String> = [];
    public var currentDance:Int = 0;
    public var beat:Float = 1;

    public function dance(beat:Int, forced:Bool = false):Void {
        if (beat % this.beat == 0)
            forceDance(forced);
    }

    public function forceDance(forced:Bool = false):Void {
        playAnimation(danceSteps[currentDance], forced);
        currentDance = (currentDance + 1) % danceSteps.length;
    }

    override function destroy():Void {
        danceSteps = null;
        super.destroy();
    }
}