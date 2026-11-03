"""Cancellation owns the renderer until its pipes are drained and PID exits."""
import asyncio
import os
import subprocess


class PreviewDisconnected(Exception):
    pass


async def while_connected(operation, disconnected=None):
    if disconnected is None:
        return await operation
    work = asyncio.create_task(operation)
    lost = False
    async def monitor():
        nonlocal lost
        while not work.done():
            if await disconnected():
                lost = True
                work.cancel()
                return
            await asyncio.sleep(.05)
    watcher = asyncio.create_task(monitor())
    try:
        return await work
    except asyncio.CancelledError:
        if lost: raise PreviewDisconnected() from None
        raise
    finally:
        watcher.cancel()
        if not work.done(): work.cancel()
        await asyncio.gather(watcher, work, return_exceptions=True)


async def capture_process(command, timeout=20, *, spawn=subprocess.Popen):
    child = spawn(command, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                  stderr=subprocess.PIPE, creationflags=0x08000000 if os.name == 'nt' else 0)
    reader = asyncio.create_task(asyncio.to_thread(child.communicate))
    try:
        output, error = await asyncio.wait_for(asyncio.shield(reader), timeout)
        return child.returncode, output, error
    finally:
        if child.poll() is None:
            child.kill()
        # Exactly one communicate call owns the pipes, including cancellation.
        await asyncio.shield(reader)
