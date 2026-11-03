"""Test-only outbound network guard v3 (P0 systematic closure, T1).

Auto-loaded in measurement child processes via PYTHONPATH (site module
imports sitecustomize at interpreter startup BEFORE any app code).

When imported as a module by guard_test.py (NOT via site), it patches the
functions that guard_fallback.py has already wrapped, creating the chain:
    original -> fallback -> guard (this module)

Coverage:
1. socket.socket.connect          - sync connections
2. socket.socket.connect_ex        - sync variant
3. socket.getaddrinfo             - DNS resolution
4. BaseEventLoop.create_connection - asyncio TCP (httpx/AnyIO on Windows Proactor)

Note: this patches the create_connection ENTRY POINT, which covers the
babeldoc -> httpx -> AnyIO -> asyncio chain on Windows. It does NOT directly
patch the native ConnectEx function; all Python-level connection initiators
go through create_connection first.

Activation: only when PDF2ZH_GUARD_LOG is set (measurement roots only).
Partial-failure simulation: PDF2ZH_GUARD_SKIP=<comma-separated patches to skip>
  e.g. PDF2ZH_GUARD_SKIP=async disables only the asyncio patch (for testing).
"""

import os
import socket
import sys
import time

_LOG = os.environ.get("PDF2ZH_GUARD_LOG")
_SKIP = set(filter(None, os.environ.get("PDF2ZH_GUARD_SKIP", "").split(",")))

if _LOG:
    _orig_connect = socket.socket.connect
    _orig_connect_ex = socket.socket.connect_ex
    _orig_getaddrinfo = socket.getaddrinfo

    def _is_loopback(host):
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
        # Strict dotted-quad: 4 ASCII-digit octets, NO leading zeros, 0..255.
        # R1: Windows resolves '0127.0.0.1'/'00127.0.0.1' as 87.0.0.1
        # (octal-flavored parse), so a decimal-only octet check would hand a
        # NON-loopback address to the OS. We validate the SAME interpretation
        # the OS will execute: only canonical dotted-quads are accepted.
        parts = h.split(".")
        if len(parts) == 4:
            try:
                octets = []
                for p in parts:
                    if not p or any(ch not in "0123456789" for ch in p):
                        raise ValueError("non-ascii-digit octet")
                    if len(p) > 1 and p.startswith("0"):
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

    def _record_blocked(kind, host):
        try:
            with open(_LOG, "a", encoding="utf-8") as f:
                f.write("%s BLOCKED %s %s\n" % (time.time(), kind, host))
        except Exception:
            pass

    # --- sync paths ---
    if "sync" not in _SKIP:
        def _guarded_connect(self, address):
            try:
                host = address[0] if isinstance(address, tuple) else str(address)
            except Exception:
                host = str(address)
            if not _is_loopback(host):
                _record_blocked("connect", host)
                raise OSError(
                    "net-guard: outbound blocked to %r (measurement runs are "
                    "offline; assets must be pre-staged and verified)" % (host,)
                )
            return _orig_connect(self, address)

        def _guarded_connect_ex(self, address):
            try:
                host = address[0] if isinstance(address, tuple) else str(address)
            except Exception:
                host = str(address)
            if not _is_loopback(host):
                _record_blocked("connect_ex", host)
                raise OSError("net-guard: outbound blocked to %r" % (host,))
            return _orig_connect_ex(self, address)

        socket.socket.connect = _guarded_connect
        socket.socket.connect_ex = _guarded_connect_ex

    # --- DNS ---
    if "dns" not in _SKIP:
        def _guarded_getaddrinfo(host, *args, **kwargs):
            if not _is_loopback(host):
                _record_blocked("dns", host)
                raise OSError("net-guard: DNS blocked for %r (offline)" % (host,))
            return _orig_getaddrinfo(host, *args, **kwargs)

        socket.getaddrinfo = _guarded_getaddrinfo

    # --- asyncio paths ---
    if "async" not in _SKIP:
        try:
            import asyncio.base_events

            _orig_create_conn = asyncio.base_events.BaseEventLoop.create_connection

            def _guarded_create_connection(self, protocol_factory, host=None,
                                            port=None, *args, **kwargs):
                if host is not None and not _is_loopback(host):
                    _record_blocked("async_connect", host)
                    raise OSError(
                        "net-guard: async outbound blocked to %r "
                        "(offline measurement)" % (host,)
                    )
                return _orig_create_conn(
                    self, protocol_factory, host, port, *args, **kwargs
                )

            asyncio.base_events.BaseEventLoop.create_connection = _guarded_create_connection
        except ImportError:
            pass

    # --- write load confirmation ---
    try:
        with open(_LOG, "a", encoding="utf-8") as f:
            f.write("GUARD_ACTIVE %d %s\n" % (os.getpid(), sys.version.split()[0]))
    except Exception:
        pass
