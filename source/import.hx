package;

#if !macro
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.math.FlxMath;
import flixel.util.FlxColor;
import flixel.util.FlxTimer;
import flixel.util.FlxDestroyUtil;

import globals.Controls;
import globals.HighScore;
import globals.Options;
import tools.*;

#if ENGINE_MODDING import core.mods.Mods; #end
#if ENGINE_DISCORD_RPC import core.DiscordPresence; #end
import core.assets.Assets;

import music.Conductor;
import music.MusicBeatState;
import states.PlayState;
import states.Transition;

using tools.Tools;
using StringTools;
#end
