package otlib.utils
{
    import flash.filesystem.File;
    import otlib.core.ClientFeatures;
    import otlib.core.Version;
    import otlib.items.ServerItemStorage;
    import otlib.sprites.SpriteStorage;
    import otlib.things.ThingTypeStorage;
    import otlib.utils.OTFormat;

    /** Stages the entire project before replacing any of its files. */
    public class ProjectSaver
    {
        public static function save(things:ThingTypeStorage, sprites:SpriteStorage,
                items:ServerItemStorage, dat:File, spr:File, itemsFile:File,
                definitionFormat:String, binaryFormat:String, version:Version,
                features:ClientFeatures, progress:Function = null):void
        {
            var transaction:SaveTransaction = new SaveTransaction();
            var sourceSpr:File = sprites ? sprites.file : null;
            var definitions:File;
            var peer:File;
            try
            {
                if (progress != null) progress(0, "Saving DAT");
                var stagedDat:File = transaction.stage(dat);
                things.writeStaged(stagedDat, version, features);
                if (progress != null) progress(1, "Saving SPR");
                sprites.writeStaged(transaction.stage(spr), version, features);

                if (itemsFile)
                {
                    if (progress != null) progress(2, "Saving server items");
                    if (!items || !items.loaded)
                        throw new Error("Server items are not loaded.");
                    var name:String = itemsFile.name;
                    var dot:int = name.lastIndexOf(".");
                    if (dot >= 0) name = name.substring(0, dot);
                    definitions = itemsFile.parent.resolvePath(name + "." + (definitionFormat == OTFormat.TOML ? "toml" : "xml"));
                    if (!items.saveDefinitions(transaction.stage(definitions), definitionFormat))
                        throw new Error("Failed to save server definitions: " + definitions.nativePath);
                    if (binaryFormat != null)
                    {
                        peer = itemsFile.parent.resolvePath(name + "." + (binaryFormat == OTFormat.OTB ? "otb" : "dat"));
                        if (!items.save(transaction.stage(peer), binaryFormat, stagedDat, false))
                            throw new Error("Failed to save server binary: " + peer.nativePath);
                    }
                }

                var datName:String = dat.name;
                var datDot:int = datName.lastIndexOf(".");
                if (datDot >= 0) datName = datName.substring(0, datDot);
                var otfi:OTFI = new OTFI(features, dat.name, spr.name, SpriteExtent.DEFAULT_SIZE, SpriteExtent.DEFAULT_DATA_SIZE);
                if (!otfi.save(transaction.stage(dat.parent.resolvePath(datName + ".otfi"))))
                    throw new Error("Failed to save project features.");

                sprites.closeSource();
                transaction.commit();
                // Open the newly saved SPR before removing rollback copies or clearing edits.
                sprites.acceptSave(spr, version, features);
            }
            catch (error:Error)
            {
                var message:String = "Save failed: " + error.message;
                try { transaction.rollback(); }
                catch (rollbackError:Error) { message += "\n" + rollbackError.message; }
                try { sprites.reopenSource(transaction.originalFor(sourceSpr)); }
                catch (reopenError:Error) { message += "\nCould not reopen the source SPR: " + reopenError.message; }
                throw new Error(message);
            }

            things.acceptSave(dat, version, features);
            if (itemsFile)
                items.acceptSave(peer ? peer : items.file, definitionFormat, binaryFormat);
            transaction.complete();
        }
    }
}
