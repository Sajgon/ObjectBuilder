package
{
    import com.mignari.workers.WorkerCommand;
    import com.mignari.workers.WorkerCommunicator;

    /** Storage tests run in one AIR process; only the UI log transport is stubbed. */
    public class TestCommunicator extends WorkerCommunicator
    {
        override public function sendCommand(command:WorkerCommand, priority:uint = 0):void
        {
        }
    }
}
