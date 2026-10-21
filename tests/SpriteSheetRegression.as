package
{
    import flash.desktop.NativeApplication;
    import by.blooddy.crypto.MD5;
    import flash.display.Bitmap;
    import flash.display.BitmapData;
    import flash.display.Loader;
    import flash.display.Sprite;
    import flash.events.Event;
    import flash.events.IOErrorEvent;
    import flash.events.InvokeEvent;
    import flash.events.SecurityErrorEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.geom.Point;
    import flash.geom.Rectangle;
    import flash.net.URLRequest;
    import flash.utils.Dictionary;
    import mx.resources.ResourceManager;
    import nail.logging.Log;
    import ob.settings.ObjectBuilderSettings;
    import otlib.animation.FrameDuration;
    import otlib.animation.FrameGroup;
    import otlib.geom.Size;
    import otlib.core.VersionStorage;
    import otlib.obd.OBDEncoder;
    import otlib.obd.OBDVersions;
    import otlib.resources.Resources;
    import otlib.sprites.SpriteData;
    import otlib.things.FrameGroupType;
    import otlib.things.ThingCategory;
    import otlib.things.ThingData;
    import otlib.things.ThingType;

    public class SpriteSheetRegression extends Sprite
    {
        private var output:File;
        private var checks:uint;
        private var loader:Loader;

        public function SpriteSheetRegression()
        {
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, run);
        }
        private function run(event:InvokeEvent):void
        {
            try
            {
                output = new File(event.arguments[0]);
                output.createDirectory();
                Resources.manager = ResourceManager.getInstance();
                Log.commnunicator = new TestCommunicator();
                VersionStorage.getInstance().addVersion(1098,0x42A3,0x57BBD603,57);
                layoutCase(group(17), "17 single-tile frames");
                layoutCase(group(1), "one static frame");
                var wide:FrameGroup = group(3); wide.width = 2;
                layoutCase(wide, "non-square multi-tile frames");
                var complex:FrameGroup = group(3);
                complex.width = 2; complex.height = 3; complex.layers = 2;
                complex.patternX = 2; complex.patternY = 2; complex.patternZ = 2;
                layoutCase(complex, "patterns, layers and multi-tile frames");
                otherGroups();
                if (event.arguments.length > 1)
                {
                    loader = new Loader();
                    loader.contentLoaderInfo.addEventListener(Event.COMPLETE, loaded);
                    loader.contentLoaderInfo.addEventListener(IOErrorEvent.IO_ERROR, loadError);
                    loader.contentLoaderInfo.addEventListener(SecurityErrorEvent.SECURITY_ERROR, loadError);
                    loader.load(new URLRequest(new File(event.arguments[1]).url));
                }
                else finish();
            }
            catch (error:Error) { fail(error); }
        }
        private function group(frames:uint):FrameGroup
        {
            var g:FrameGroup = new FrameGroup();
            g.frames = frames; g.isAnimation = frames > 1;
            g.frameDurations = new Vector.<FrameDuration>(frames, true);
            for (var i:uint = 0; i < frames; i++) g.frameDurations[i] = new FrameDuration(100,100);
            return g;
        }
        private function data(groups:Array):ThingData
        {
            var thing:ThingType = new ThingType();
            thing.id = 100; thing.category = ThingCategory.ITEM; thing.frameGroups = [];
            var sprites:Dictionary = new Dictionary();
            for (var n:uint = 0; n < groups.length; n++)
            {
                var g:FrameGroup = groups[n];
                thing.setFrameGroup(n,g);
                g.spriteIndex = new Vector.<uint>(g.getTotalSprites(),true);
                var list:Vector.<SpriteData> = new Vector.<SpriteData>(g.getTotalSprites(),true);
                for (var i:uint = 0; i < list.length; i++) list[i] = SpriteData.createSpriteData(0);
                sprites[n] = list;
            }
            return ThingData.create(OBDVersions.OBD_VERSION_3,1098,thing,sprites);
        }
        private function pattern(g:FrameGroup):BitmapData
        {
            var size:Size = g.getSpriteSheetSize();
            var bitmap:BitmapData = new BitmapData(size.width,size.height,true,0);
            for (var y:int = 0; y < bitmap.height; y++)
                for (var x:int = 0; x < bitmap.width; x++)
                    bitmap.setPixel32(x,y, (x % 11 == 0 ? 0 : 0xFF000000) |
                        ((x * 31 + y * 7) & 255) << 16 | ((y * 17 + x) & 255) << 8 | ((x + y * 3) & 255));
            return bitmap;
        }
        private function horizontal(vertical:BitmapData, frames:uint):BitmapData
        {
            var height:int = vertical.height / frames;
            var bitmap:BitmapData = new BitmapData(vertical.width * frames,height,true,0);
            for (var f:uint = 0; f < frames; f++)
                bitmap.copyPixels(vertical,new Rectangle(0,f*height,vertical.width,height),new Point(f*vertical.width,0));
            return bitmap;
        }
        private function same(actual:BitmapData, expected:BitmapData, label:String):void
        {
            var diff:Object = actual.compare(expected);
            var equal:Boolean = diff is Number && Number(diff) == 0;
            if (diff is BitmapData) BitmapData(diff).dispose();
            actual.dispose();
            check(equal,label);
        }
        private function layoutCase(g:FrameGroup, label:String):void
        {
            var imported:ThingData = data([g]);
            var vertical:BitmapData = pattern(g);
            var across:BitmapData = horizontal(vertical,g.frames);
            check(g.matchesSpriteSheetSize(vertical.width,vertical.height),label+": vertical accepted");
            check(g.matchesSpriteSheetSize(across.width,across.height),label+": horizontal accepted");
            imported.setSpriteSheet(g,across);
            same(imported.getSpriteSheet(g,null,0),vertical,label+": horizontal preserves all pixels and orientation");
            imported.setSpriteSheet(g,vertical);
            same(imported.getSpriteSheet(g,null,0),vertical,label+": vertical stays compatible");
            var invalid:BitmapData = new BitmapData(across.width+1,across.height,true,0);
            check(!g.matchesSpriteSheetSize(invalid.width,invalid.height),label+": invalid size rejected");
            var first:SpriteData = imported.sprites[g.type][0];
            imported.setSpriteSheet(g,invalid);
            check(imported.sprites[g.type][0] === first,label+": rejected sheet does not change sprites");
            invalid.dispose(); across.dispose(); vertical.dispose();
        }
        private function otherGroups():void
        {
            var idle:FrameGroup = group(2), walk:FrameGroup = group(3);
            var imported:ThingData = data([idle,walk]);
            var idleSheet:BitmapData = pattern(idle), walkSheet:BitmapData = pattern(walk);
            imported.setSpriteSheet(idle,idleSheet);
            var before:SpriteData = imported.sprites[FrameGroupType.DEFAULT][0];
            var across:BitmapData = horizontal(walkSheet,walk.frames);
            imported.setSpriteSheet(walk,across);
            check(imported.sprites[FrameGroupType.DEFAULT][0] === before,"import into walking group preserves idle sprites");
            same(imported.getSpriteSheet(walk,null,0),walkSheet,"walking frames remain in order");
            var combined:BitmapData = imported.getTotalSpriteSheet(null,0);
            var target:ThingData = data([group(2),group(3)]);
            target.setTotalSpriteSheet(combined);
            same(target.getTotalSpriteSheet(null,0),combined,"existing combined idle/walking sheet remains compatible");
            across.dispose(); idleSheet.dispose(); walkSheet.dispose(); combined.dispose();
        }
        private function loaded(event:Event):void
        {
            try
            {
                var image:BitmapData = Bitmap(loader.content).bitmapData;
                check(image.width == 544 && image.height == 32,"provided PNG is a 544x32 horizontal strip");
                var g:FrameGroup = group(17);
                var imported:ThingData = data([g]);
                check(g.matchesSpriteSheetSize(image.width,image.height),"provided PNG accepted by drag/drop size gate");
                imported.setSpriteSheet(g,image);
                var encoder:OBDEncoder = new OBDEncoder(new ObjectBuilderSettings());
                var reloaded:ThingData = encoder.decode(encoder.encode(imported));
                check(reloaded.getFrameGroup(0).frames == 17,"17 animation frames survive OBD round trip");
                for (var f:uint = 0; f < 17; f++)
                {
                    var expected:BitmapData = new BitmapData(32,32,true,0);
                    expected.copyPixels(image,new Rectangle(f*32,0,32,32),new Point());
                    // Compare stored ARGB bytes directly. An extra setPixels/getPixels
                    // cycle rounds nearly opaque channels in AIR's premultiplied bitmap.
                    var expectedHash:String = MD5.hashBytes(expected.getPixels(expected.rect));
                    check(MD5.hashBytes(SpriteData(imported.sprites[0][f]).pixels) == expectedHash,
                        "PNG frame "+f+": pixel-accurate left-to-right import");
                    check(MD5.hashBytes(SpriteData(reloaded.sprites[0][f]).pixels) == expectedHash,
                        "PNG frame "+f+": pixels survive OBD round trip");
                    expected.dispose();
                }
                finish();
            }
            catch (error:Error) { fail(error); }
        }
        private function check(ok:Boolean,label:String):void
        {
            if (!ok) throw new Error("FAILED: "+label);
            checks++; trace("PASS: "+label);
        }
        private function loadError(event:Event):void { fail(new Error(event.toString())); }
        private function report(message:String):void
        {
            var stream:FileStream = new FileStream();
            stream.open(output.resolvePath("RESULT.txt"),FileMode.WRITE);
            stream.writeUTFBytes(message); stream.close(); trace(message);
        }
        private function finish():void { report("PASS: "+checks+" checks"); NativeApplication.nativeApplication.exit(0); }
        private function fail(error:Error):void
        {
            report("FAIL: "+error.message+"\n"+error.getStackTrace());
            NativeApplication.nativeApplication.exit(1);
        }
    }
}
