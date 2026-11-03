"""Opt-in loopback-fixture observation; never part of the product payload."""
import builtins
import json
import os
from pathlib import Path
import re
import sys

destination=os.environ.get('PDF2ZH_TEST_ERROR_OBSERVATION')
original=builtins.__import__

def observed_import(name, globals=None, locals=None, fromlist=(), level=0):
    result=original(name,globals,locals,fromlist,level)
    if destination and name=='pdf2zh_next.high_level' and '_translate_wrapper' in (fromlist or ()):
        module=sys.modules[name]
        if not getattr(module,'_fixture_observation',False):
            module._fixture_observation=True
            real=module._translate_wrapper
            def observe(settings,file,pipe,cancel,logs):
                from pdf2zh_next.desktop.snapshots import SECRET
                from pdf2zh_next.config.translate_engine_model import GUI_PASSWORD_FIELDS
                secret_values=[];urls=[]
                def collect(value):
                    if isinstance(value,dict):
                        for key,child in value.items():
                            if (key in GUI_PASSWORD_FIELDS or SECRET.search(key)) and isinstance(child,str) and child:secret_values.append(child)
                            if 'base_url' in key and isinstance(child,str) and child:urls.append(child)
                            collect(child)
                    elif isinstance(value,list):
                        for child in value:collect(child)
                collect(settings.model_dump(mode='json'))
                # Observation is restricted to this explicitly generated fake
                # provider; fail closed rather than log a user's credentials.
                if not any(url.startswith('http://127.0.0.1:') for url in urls) or any(value!='local-fixture-only' for value in secret_values):
                    raise RuntimeError('diagnostics require the local fixture only')
                class Pipe:
                    def send(self,value):
                        if isinstance(value,BaseException):
                            text=str(value)
                            for secret in secret_values:text=text.replace(secret,'[fixture-secret-redacted]')
                            text=re.sub(r'\b[0-9a-fA-F]{64}\b','[digest-or-nonce]',text)
                            path=Path(destination)/('worker-error-'+str(os.getpid())+'.json')
                            path.parent.mkdir(parents=True,exist_ok=True)
                            path.write_text(json.dumps({'pid':os.getpid(),'type':type(value).__name__,'exception':text,'scope':'explicit loopback-fixture observation; unchanged wrapper and pipe payload'},ensure_ascii=False,indent=2),encoding='utf-8')
                        pipe.send(value)
                    def close(self):pipe.close()
                return real(settings,file,Pipe(),cancel,logs)
            module._translate_wrapper=observe
    return result

if destination:builtins.__import__=observed_import
