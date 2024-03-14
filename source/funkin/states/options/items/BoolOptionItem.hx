package funkin.states.options.items;

import flixel.text.FlxText.FlxTextFormat;
import flixel.text.FlxText.FlxTextFormatMarkerPair;

class BoolOptionItem extends BaseOptionItem<Bool> {
    static var ON_MARKUP = new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.LIME), '<>');
    static var OFF_MARKUP = new FlxTextFormatMarkerPair(new FlxTextFormat(FlxColor.RED), '<>');

    var skippedFrame:Bool = false;
    var value:Bool = false;

    public function new(option:String):Void {
        super(option);

        value = Settings.get(option);
        updateText();

        inputs.push("accept");
    }

    override function handleInputs(elapsed:Float):Void {
        // skip one frame so pressing the accept keybind won't open the substate and change the value at the same time
        if (!skippedFrame) {
            skippedFrame = true;
            return;
        }

        super.handleInputs(elapsed);
    }

    override function updateValue(mult:Int):Void {
        value = !value;
        saveValue(value);
    }

    override function updateText():Void {
        valueText.text = '<>${(value) ? "ON" : "OFF"}<>';
        valueText.applyMarkup(valueText.text, [value ? ON_MARKUP : OFF_MARKUP]);
        repositionValueText();
    }
}
