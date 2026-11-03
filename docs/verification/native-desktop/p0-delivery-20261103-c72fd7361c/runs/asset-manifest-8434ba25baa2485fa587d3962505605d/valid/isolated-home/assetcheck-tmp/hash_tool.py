import hashlib, sys, json
try:
    h = hashlib.sha3_256()
    with open(sys.argv[1], 'rb') as f:
        for chunk in iter(lambda: f.read(1024*1024), b''):
            h.update(chunk)
    print(json.dumps({"sha3_256": h.hexdigest()}))
except Exception as e:
    print(json.dumps({"error": str(e)[:200]}))
