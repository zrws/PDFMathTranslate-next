"""Independent network fallback safety net (P0 systematic closure, T1).

This module provides a LAST-RESORT safety layer BELOW the guard. It patches
socket and asyncio at the lowest level, wrapping the ORIGINAL functions.

Architecture:
    original_function -> fallback_patch -> guard_patch (if guard active)

If the guard is working: guard rejects first, fallback never reached.
If the guard is missing/partially broken: fallback catches the attempt,
  records it to PDF2ZH_FALLBACK_LOG, and rejects.

The fallback is deliberately in a SEPARATE file from the guard (sitecustomize.py)
so a bug in the guard cannot disable the fallback. It uses its own logging
variable (PDF2ZH_FALLBACK_LOG) and its own counter.

Activation: only when PDF2ZH_FALLBACK_LOG is set (test runs only).
Never shipped to users; never modifies the product or system state.
"""

import os
import socket
import sys

_FALLBACK_LOG = os.environ.get("PDF2ZH_FALLBACK_LOG")
if _FALLBACK_LOG:
    _fallback_hits = 0
    _orig_connect = socket.socket.connect
    _orig_connect_ex = socket.socket.connect_ex
    _orig_getaddrinfo = socket.getaddrinfo

    def _is_loopback_strict(host):
        """Strict: empty/None/invalid is NOT loopback; use IP address parsing.
        Only accept: IP address in 127.0.0.0/8, ::1, or exact "localhost".
        Octets must be ASCII digits only (int() would accept '0_0' or
        unicode digits - PEP-515/Unicode hole closed here)."""
        h = str(host).lower().strip() if host else ""
        if not h:
            return False
        if h == "localhost":
            return True
        if h == "::1":
            return True
        # Try to parse as IPv4 with strict ASCII digit validation
        parts = h.split(".")
        if len(parts) == 4:
            try:
                octets = []
                for p in parts:
                    if not p or any(ch not in "0123456789" for ch in p):
                        raise ValueError("non-ascii-digit octet")
                    if len(p) > 1 and p.startswith("0"):
                        # R1: '01'/'0127' style octets are octal-ambiguity on
                        # Windows (0127.0.0.1 -> 87.0.0.1); reject outright
                        raise ValueError("leading-zero octet (ambiguous)")
                    o = int(p)
                    if o > 255:
                        raise ValueError("octet out of range")
                    octets.append(o)
                if octets[0] == 127:
                    return True
            except (ValueError, TypeError):
                pass
        return False

    def _record_fallback(kind, host):
        global _fallback_hits
        _fallback_hits += 1
        try:
            with open(_FALLBACK_LOG, "a", encoding="utf-8") as f:
                f.write("FALLBACK_HIT %d %s %s\n" % (_fallback_hits, kind, host))
        except Exception:
            pass

    def _fb_connect(self, address):
        try:
            host = address[0] if isinstance(address, tuple) else str(address)
        except Exception:
            host = str(address)
        if not _is_loopback_strict(host):
            _record_fallback("connect", host)
            raise OSError(
                "FALLBACK: outbound blocked to %r "
                "(guard failed; fallback safety net active)" % (host,)
            )
        return _orig_connect(self, address)

    def _fb_connect_ex(self, address):
        try:
            host = address[0] if isinstance(address, tuple) else str(address)
        except Exception:
            host = str(address)
        if not _is_loopback_strict(host):
            _record_fallback("connect_ex", host)
            raise OSError("FALLBACK: outbound blocked to %r" % (host,))
        return _orig_connect_ex(self, address)

    def _fb_getaddrinfo(host, *args, **kwargs):
        if not _is_loopback_strict(host):
            _record_fallback("dns", host)
            raise OSError("FALLBACK: DNS blocked for %r (guard failed)" % (host,))
        return _orig_getaddrinfo(host, *args, **kwargs)

    socket.socket.connect = _fb_connect
    socket.socket.connect_ex = _fb_connect_ex
    socket.getaddrinfo = _fb_getaddrinfo

    # Patch asyncio's create_connection as well
    try:
        import asyncio.base_events
        _orig_create_conn = asyncio.base_events.BaseEventLoop.create_connection

        def _fb_create_connection(self, protocol_factory, host=None, port=None, *args, **kwargs):
            if host is not None and not _is_loopback_strict(host):
                _record_fallback("async_connect", host)
                raise OSError(
                    "FALLBACK: async outbound blocked to %r "
                    "(guard failed; fallback active)" % (host,)
                )
            return _orig_create_conn(self, protocol_factory, host, port, *args, **kwargs)

        asyncio.base_events.BaseEventLoop.create_connection = _fb_create_connection
    except ImportError:
        pass

    # Write activation confirmation
    try:
        with open(_FALLBACK_LOG, "a", encoding="utf-8") as f:
            f.write("FALLBACK_ACTIVE %d %s\n" % (os.getpid(), sys.version.split()[0]))
    except Exception:
        pass


def get_fallback_hits():
    """Return the number of times the fallback was triggered (guard failed)."""
    return _fallback_hits if _FALLBACK_LOG else -1  # -1 = not active


def is_fallback_active():
    """Return True if the fallback safety net is installed."""
    return bool(_FALLBACK_LOG)
