package
{
    import flash.display.Sprite;
    import nail.logging.Log;
    import mx.resources.ResourceManager;
    import otlib.resources.Resources;
    import flash.desktop.NativeApplication;
    import flash.events.InvokeEvent;
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;
    import flash.utils.ByteArray;
    import flash.utils.Endian;
    import flash.utils.setTimeout;
    import by.blooddy.crypto.MD5;
    import ob.settings.ObjectBuilderSettings;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.core.otlib_internal;
    import otlib.items.ServerItem;
    import otlib.items.ServerItemList;
    import otlib.items.ServerItemStorage;
    import otlib.items.OtbWriter;
    import otlib.sprites.SpriteStorage;
    import otlib.things.ThingCategory;
    import otlib.things.ThingTypeStorage;
    import otlib.utils.ProjectSaver;
    import otlib.utils.SaveTransaction;
    import otlib.utils.SpriteExtent;
    use namespace otlib_internal;

    public class SaveRegression extends Sprite
    {
        private var testDirectory:File;
        private var version:Version;
        private var features:ClientFeatures;
        private var things:ThingTypeStorage;
        private var sprites:SpriteStorage;
        private var items:ServerItemStorage;
        private var checks:uint = 0;
        private var before:Object;
        private var attempts:uint = 0;
        private var fixture:String;
        private var expectedFullGround:Boolean;

        public function SaveRegression()
        {
            NativeApplication.nativeApplication.addEventListener(InvokeEvent.INVOKE, run);
        }
        private function run(event:InvokeEvent):void
        {
            try
            {
                Resources.manager = ResourceManager.getInstance();
                Log.commnunicator = new TestCommunicator();
                testDirectory = new File(event.arguments[0]);
                testDirectory.createDirectory();
                fixture = event.arguments.length > 1 ? event.arguments[1] : null;
                version = new Version();
                version.value = 1098; version.valueStr = "10.98";
                version.datSignature = 0x42A3; version.sprSignature = 0x57BBD603;
                features = new ClientFeatures(true, true, true, true);
                things = new ThingTypeStorage(new ObjectBuilderSettings());
                sprites = new SpriteStorage();
                items = new ServerItemStorage();
                if (fixture)
                {
                    for each (var name:String in ["Tibia.dat", "Tibia.spr", "items.otb", "items.xml", "Tibia.otfi"])
                        new File(fixture).resolvePath(name).copyTo(testDirectory.resolvePath(name), false);
                    things.load(testDirectory.resolvePath("Tibia.dat"), version, features);
                    sprites.load(testDirectory.resolvePath("Tibia.spr"), version, features);
                    check(items.load(testDirectory.resolvePath("items.otb")), "load recovered OTB/XML fixture");
                }
                else
                {
                    things.createNew(version, features);
                    sprites.createNew(version, features);
                    sprites.addSprite(pixels(0xFF123456));
                    sprites.addSprite(pixels(0xFF789ABC));
                    sprites.invalidate();
                    var list:ServerItemList = new ServerItemList();
                    list.majorVersion=3; list.minorVersion=57; list.clientVersion=1098;
                    var item:ServerItem = new ServerItem();
                    item.id=100; item.clientId=100; item.fullGround=true;
                    list.add(item);
                    check(new OtbWriter(list).write(testDirectory.resolvePath("items.otb")), "create server fixture");
                    check(items.load(testDirectory.resolvePath("items.otb")), "load server fixture");
                    items.getItem(100).nameXml="original";
                }
                var fixtureBefore:Object = fixture ? hashes() : null;
                save();
                if (fixtureBefore)
                {
                    var fixtureAfter:Object = hashes();
                    check(fixtureBefore["Tibia.dat"] == fixtureAfter["Tibia.dat"], "recovered DAT round trip is byte-identical");
                    check(fixtureBefore["Tibia.spr"] == fixtureAfter["Tibia.spr"], "recovered SPR round trip is byte-identical");
                }
                check(!things.changed && !sprites.changed && !items.changed, "successful save clears dirty state");
                // Reload so unchanged sprites must be read lazily from the live SPR file.
                sprites.unload(); sprites.load(testDirectory.resolvePath("Tibia.spr"), version, features);
                expectedFullGround = !things.getThingType(100, ThingCategory.ITEM).isFullGround;
                things.getThingType(100, ThingCategory.ITEM).isFullGround = expectedFullGround;
                things.invalidate();
                sprites.replaceSprite(2, pixels(0xFFAABBCC)); sprites.invalidate();
                items.getItem(100).fullGround = !items.getItem(100).fullGround;
                items.getItem(100).nameXml = "unsaved recovery check"; items.invalidate();
                before = hashes();

                // A late server serialization error must not publish the staged DAT/SPR.
                expectFailure(function():void {
                    ProjectSaver.save(things,sprites,items,testDirectory.resolvePath("Tibia.dat"),testDirectory.resolvePath("Tibia.spr"),
                        testDirectory.resolvePath("items.otb"),"unsupported", "otb",version,features);
                }, "unsupported server definitions");
                unchanged("server export failure");
                dirty("server export failure");

                // The original regression: a retry with a closed SPR reader must abort.
                sprites.closeSource();
                expectFailure(save, "closed source SPR reader");
                unchanged("closed source reader"); dirty("closed source reader");
                sprites.reopenSource();
                check(sprites.getSprite(3).id != uint.MAX_VALUE, "source reader recovers without placeholders");

                // Reject overlapping output paths before any replacement.
                expectFailure(function():void {
                    ProjectSaver.save(things,sprites,items,testDirectory.resolvePath("Tibia.dat"),testDirectory.resolvePath("Tibia.dat"),
                        testDirectory.resolvePath("items.otb"),"xml","otb",version,features);
                }, "overlapping output files");
                unchanged("overlapping output files");

                if (!fixture) malformedSprite();
                textFile(testDirectory.resolvePath("LOCK_READY"), "items.otb");
                setTimeout(waitForLock,100);
            }
            catch (error:Error) { fail(error); }
        }
        private function waitForLock():void
        {
            try
            {
                if (!testDirectory.resolvePath("LOCK_HELD").exists)
                {
                    if (++attempts > 300) throw new Error("Timed out waiting for the external Windows lock.");
                    setTimeout(waitForLock,100); return;
                }
                expectFailure(save, "locked OTB after DAT, SPR and XML replacements");
                unchanged("locked target rollback"); dirty("locked target rollback");
                check(sprites.getSprite(3).id != uint.MAX_VALUE, "SPR reader reopened after commit failure");
                textFile(testDirectory.resolvePath("LOCK_TESTED"), "release");
                attempts=0; setTimeout(waitForUnlock,100);
            }
            catch (error:Error) { fail(error); }
        }
        private function waitForUnlock():void
        {
            try
            {
                if (!testDirectory.resolvePath("LOCK_RELEASED").exists)
                {
                    if (++attempts > 300) throw new Error("Timed out waiting for unlock.");
                    setTimeout(waitForUnlock,100); return;
                }
                var expectedPixels:String=MD5.hashBytes(sprites.getPixels(2));
                save();
                check(!things.changed && !sprites.changed && !items.changed, "retry succeeds after unlocking");
                sprites.unload(); sprites.load(testDirectory.resolvePath("Tibia.spr"),version,features);
                check(MD5.hashBytes(sprites.getPixels(2))==expectedPixels,"sprite edit survives failure and retry");
                check(sprites.getSprite(3).id != uint.MAX_VALUE,"uncached sprites survive failure and retry");
                var savedThings:ThingTypeStorage = new ThingTypeStorage(new ObjectBuilderSettings());
                savedThings.load(testDirectory.resolvePath("Tibia.dat"),version,features);
                check(savedThings.loaded && savedThings.getThingType(100,ThingCategory.ITEM).isFullGround == expectedFullGround,
                    "client item property survives failure and retry");
                savedThings.unload();
                var savedItems:ServerItemStorage = new ServerItemStorage();
                check(savedItems.load(testDirectory.resolvePath("items.otb")),"saved OTB/XML reloads");
                check(savedItems.getItem(100).nameXml=="unsaved recovery check","XML edit survives failure and retry");
                check(savedItems.getItem(100).fullGround==items.getItem(100).fullGround,"OTB flags survive failure and retry");
                before=hashes(); save(); unchanged("second unchanged save");
                sprites.unload();
                textFile(testDirectory.resolvePath("RESULT.txt"),"PASS: "+checks+" checks");
                trace("PASS: "+checks+" checks"); NativeApplication.nativeApplication.exit(0);
            }
            catch (error:Error) { fail(error); }
        }
        private function malformedSprite():void
        {
            var file:File=testDirectory.resolvePath("malformed.spr");
            var stream:FileStream=new FileStream();
            stream.open(file,FileMode.WRITE); stream.endian=Endian.LITTLE_ENDIAN;
            stream.writeUnsignedInt(version.sprSignature); stream.writeUnsignedInt(1); stream.writeUnsignedInt(12);
            stream.writeByte(255); stream.writeByte(0); stream.writeByte(255); stream.writeShort(4);
            stream.writeShort(1025); stream.writeShort(0); stream.close();
            var bad:SpriteStorage=new SpriteStorage(); bad.load(file,version,features);
            expectFailure(function():void{bad.writeStaged(testDirectory.resolvePath("malformed-output.spr"),version,features);},"malformed sprite RLE");
            bad.unload();
        }
        private function save():void
        {
            ProjectSaver.save(things,sprites,items,testDirectory.resolvePath("Tibia.dat"),testDirectory.resolvePath("Tibia.spr"),
                testDirectory.resolvePath("items.otb"),"xml","otb",version,features);
        }
        private function pixels(color:uint):ByteArray
        {
            var bytes:ByteArray=new ByteArray();
            for(var i:uint=0;i<SpriteExtent.DEFAULT_SIZE*SpriteExtent.DEFAULT_SIZE;i++) bytes.writeUnsignedInt(color);
            bytes.position=0; return bytes;
        }
        private function hashes():Object
        {
            var result:Object={};
            for each(var name:String in ["Tibia.dat","Tibia.spr","items.otb","items.xml","Tibia.otfi"])
            {
                var stream:FileStream=new FileStream(); var bytes:ByteArray=new ByteArray();
                stream.open(testDirectory.resolvePath(name),FileMode.READ); stream.readBytes(bytes); stream.close();
                result[name]=MD5.hashBytes(bytes); bytes.clear();
            }
            return result;
        }
        private function unchanged(label:String):void
        {
            var now:Object=hashes();
            for(var name:String in before) check(now[name]==before[name],label+" preserves "+name);
        }
        private function dirty(label:String):void
        {
            check(things.changed && sprites.changed && items.changed,label+" preserves dirty state");
            check(items.getItem(100).nameXml=="unsaved recovery check",label+" preserves in-memory attributes");
        }
        private function expectFailure(action:Function,label:String):void
        {
            var failed:Boolean=false;
            try{action();}catch(error:Error){failed=true; trace("Expected "+label+": "+error.message);}
            check(failed,label+" must fail");
        }
        private function check(ok:Boolean,label:String):void
        {
            if(!ok) throw new Error("FAILED: "+label);
            checks++; trace("PASS: "+label);
        }
        private function textFile(file:File,text:String):void
        {
            var stream:FileStream=new FileStream(); stream.open(file,FileMode.WRITE); stream.writeUTFBytes(text); stream.close();
        }
        private function fail(error:Error):void
        {
            trace(error.getStackTrace());
            if(testDirectory)textFile(testDirectory.resolvePath("RESULT.txt"),"FAIL: "+error.message+"\n"+error.getStackTrace());
            NativeApplication.nativeApplication.exit(1);
        }
    }
}
