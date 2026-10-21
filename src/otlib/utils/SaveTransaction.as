package otlib.utils
{
    import flash.filesystem.File;
    import flash.filesystem.FileMode;
    import flash.filesystem.FileStream;

    /** Same-volume staged replacements, with rollback and recoverable originals. */
    public class SaveTransaction
    {
        private var entries:Array = [];
        private var finished:Boolean = false;

        public function stage(target:File):File
        {
            if (finished || !target || !target.parent || target.isDirectory)
                throw new Error("Invalid save destination: " + (target ? target.nativePath : "null"));
            for each (var existing:Object in entries)
                if (File(existing.target).nativePath.toLowerCase() == target.nativePath.toLowerCase())
                    throw new Error("Two project outputs use the same destination: " + target.nativePath);

            target.parent.createDirectory();
            var directory:File;
            do
            {
                directory = target.parent.resolvePath(".objectbuilder-save-" + new Date().time + "-" + uint(Math.random() * uint.MAX_VALUE));
            }
            while (directory.exists);
            directory.createDirectory();
            var staged:File = directory.resolvePath(target.name);
            var backup:File = directory.resolvePath("previous");
            var entry:Object = {target: target, staged: staged, backup: backup, directory: directory, installed: false};
            entries.push(entry);
            var note:FileStream = new FileStream();
            try
            {
                note.open(directory.resolvePath("RECOVERY.txt"), FileMode.WRITE);
                note.writeUTFBytes("Object Builder interrupted save recovery\r\nDestination: " + target.nativePath +
                    "\r\nprevious = original file; " + target.name + " = staged new file.\r\n" +
                    "Do not mix files from different saves. Keep all files until recovery is verified.\r\n");
            }
            finally { note.close(); }
            return staged;
        }

        public function commit():void
        {
            if (finished)
                throw new Error("Save transaction is already finished.");
            for each (var entry:Object in entries)
            {
                if (!File(entry.staged).exists || File(entry.staged).isDirectory)
                    throw new Error("Missing staged output: " + File(entry.staged).nativePath);
            }
            // Never delete an original. A sharing violation fails here with it intact.
            for each (entry in entries)
            {
                if (File(entry.target).exists)
                    File(entry.target).moveTo(entry.backup, false);
                File(entry.staged).moveTo(entry.target, false);
                entry.installed = true;
            }
        }

        public function rollback():void
        {
            if (finished)
                return;
            var failures:Array = [];
            for (var i:int = entries.length - 1; i >= 0; i--)
            {
                var entry:Object = entries[i];
                try
                {
                    if (entry.installed)
                    {
                        File(entry.target).moveTo(entry.staged, false);
                        entry.installed = false;
                    }
                    if (File(entry.backup).exists)
                        File(entry.backup).moveTo(entry.target, false);
                }
                catch (error:Error)
                {
                    failures.push(File(entry.directory).nativePath + ": " + error.message);
                }
            }
            if (failures.length)
                throw new Error("Could not fully restore the previous files. Recovery files retained at:\n" + failures.join("\n"));
            // Keep completed staging files after failure, in case the user needs recovery.
            finished = true;
        }

        /** If rollback was blocked, keep reading the intact original backup. */
        public function originalFor(target:File):File
        {
            if (!target) return null;
            for each (var entry:Object in entries)
                if (File(entry.target).nativePath.toLowerCase() == target.nativePath.toLowerCase() && File(entry.backup).exists)
                    return entry.backup;
            return target;
        }

        public function complete():void
        {
            finished = true;
            for each (var entry:Object in entries)
            {
                // Cleanup must never turn a successful commit into a failed save.
                try { File(entry.directory).deleteDirectory(true); }
                catch (error:Error) { trace("Save cleanup: " + error.message); }
            }
        }
    }
}
