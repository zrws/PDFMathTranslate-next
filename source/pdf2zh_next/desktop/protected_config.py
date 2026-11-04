"""Lossless DPAPI archive for native-owned legacy configuration backups."""
import base64
import hashlib
import json
import os
import stat
import uuid
from collections.abc import Mapping
from pathlib import Path
import tomlkit
from .storage import atomic_json
from .channels import crypt,SECRET,GUI_PASSWORD_FIELDS


def identity(raw):return {'size_bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest()}


def owned_path(home,path):
    home=Path(os.path.abspath(home));path=Path(os.path.abspath(path))
    try:parts=path.relative_to(home).parts
    except ValueError:raise ValueError('配置路径不属于当前应用，未修改文件。') from None
    current=home
    for component in (None,*parts):
        if component is not None:current=current/component
        try:attributes=current.lstat()
        except FileNotFoundError:continue
        if stat.S_ISLNK(attributes.st_mode) or getattr(attributes,'st_file_attributes',0)&getattr(stat,'FILE_ATTRIBUTE_REPARSE_POINT',0x400):raise ValueError('配置路径的祖先或文件是重解析点，未修改文件。')
    resolved=path.resolve()
    if not resolved.is_relative_to(home.resolve()):raise ValueError('配置路径越界，未修改文件。')
    return resolved


def archive(path,raw,home):
    path=owned_path(home,path)
    if path.exists():
        if restore(path)!=raw:raise ValueError('旧配置归档已有不同内容，已保留两份原件，请检查后重试。')
    else:atomic_json(path,{'schema':1,'format':'dpapi-original-bytes-v1',**identity(raw),'ciphertext':crypt(base64.b64encode(raw).decode('ascii'))})
    if restore(path)!=raw:raise ValueError('旧配置归档校验失败，原配置未删除。')


def restore(path):
    data=json.loads(Path(path).read_text(encoding='utf-8'))
    if data.get('schema')!=1 or data.get('format')!='dpapi-original-bytes-v1':raise ValueError('旧配置归档格式不受支持。')
    raw=base64.b64decode(crypt(data['ciphertext'],True),validate=True)
    if identity(raw)!={k:data[k] for k in ('size_bytes','sha256')}:raise ValueError('旧配置归档内容校验失败。')
    return raw


def redact_toml(raw):
    data=tomlkit.parse(raw.decode('utf-8-sig'))
    def visit(node):
        for key,value in list(node.items()):
            if isinstance(value,str) and (key in GUI_PASSWORD_FIELDS or SECRET.search(key)):node[key]=''
            elif isinstance(value,Mapping):visit(value)
    visit(data)
    return tomlkit.dumps(data).encode('utf-8')


def protect_existing(home,marker):
    home=Path(home);marker=owned_path(home,marker);data=json.loads(marker.read_text(encoding='utf-8'));changed=False
    backup_root=owned_path(home,home/'config/legacy-backup')
    for record in data.get('config',[]):
        path=owned_path(home,record['backup'])
        if not path.is_relative_to(backup_root):raise ValueError('旧备份路径不属于当前应用，未修改文件。')
        if path.is_dir():path=owned_path(home,path/'config.v3.toml')
        if record.get('backup_format')=='dpapi-original-bytes-v1':
            restore(path)
            if not record.get('original_backup_path'):continue
            old=owned_path(home,record['original_backup_path'])
            if not old.is_relative_to(backup_root):raise ValueError('旧备份路径越界，未删除文件。')
            if old.exists():
                if old.read_bytes()!=restore(path):raise ValueError('旧备份已改变，请保留原件并检查。')
                owned_path(home,old).unlink()
            continue
        raw=path.read_bytes();protected=path.with_name(path.name+'.dpapi.json');archive(protected,raw,home)
        record.update(backup=str(protected),original_backup_path=str(path),backup_format='dpapi-original-bytes-v1',original_identity=identity(raw));changed=True
        atomic_json(marker,data)  # Durable recovery path before removing the native-owned plaintext backup.
        owned_path(home,path).unlink()
    if changed:atomic_json(marker,data)


def resume_prepared(home,marker):
    marker=owned_path(home,marker);data=json.loads(marker.read_text(encoding='utf-8'))
    if data.get('phase')!='prepared':return
    expected=owned_path(home,Path(home)/'.config/pdf2zh/config.v3.toml')
    for record in data.get('config',[]):
        target=owned_path(home,record['target']);backup=owned_path(home,record['backup'])
        if target!=expected or not backup.is_relative_to(owned_path(home,Path(home)/'config/legacy-backup')):raise ValueError('迁移恢复路径无效，原件已保留。')
        raw=redact_toml(restore(backup))
        if target.exists():
            if target.read_bytes()!=raw:raise ValueError('迁移中的目标配置已改变，已保留原件与归档，请检查。')
        else:
            target.parent.mkdir(parents=True,exist_ok=True);owned_path(home,target)
            temp=target.with_name(target.name+'.'+uuid.uuid4().hex+'.migration.partial')
            try:
                with temp.open('xb') as stream:stream.write(raw);stream.flush();os.fsync(stream.fileno())
                owned_path(home,target)
                if os.name=='nt':os.rename(temp,target)
                else:os.link(temp,target)
            finally:
                if temp.exists():owned_path(home,temp).unlink()
    data['phase']='committed';atomic_json(marker,data)


def migrate_protected(home,source,target):
    home=Path(home);backup=owned_path(home,home/'config/legacy-backup'/uuid.uuid4().hex)
    backup.mkdir(parents=True);owned_path(home,backup)
    raw=source.read_bytes();protected=backup/'config.v3.toml.dpapi.json';archive(protected,raw,home)
    marker=owned_path(home,home/'config/migration-v1.json')
    record={'source':str(source),'backup':str(protected),'target':str(target),'backup_format':'dpapi-original-bytes-v1','original_identity':identity(raw)}
    atomic_json(marker,{'version':1,'phase':'prepared','config':[record],'native_bootstrap_secrets':True,'policy':'original source retained; lossless DPAPI archive; never overwrite current configuration'})
    resume_prepared(home,marker)


def inject_bootstrap(home,cli):
    home=Path(home);marker=owned_path(home,home/'config/migration-v1.json')
    if not marker.exists():return
    data=json.loads(marker.read_text(encoding='utf-8'))
    if not data.get('native_bootstrap_secrets'):return
    for record in data.get('config',[]):
        path=owned_path(home,record['backup'])
        if not path.is_relative_to((home/'config/legacy-backup').resolve()) or record.get('backup_format')!='dpapi-original-bytes-v1':raise ValueError('旧配置归档不属于当前应用。')
        values=tomlkit.parse(restore(path).decode('utf-8-sig'))
        def apply(model,node):
            for key,value in node.items():
                if key not in type(model).model_fields:continue
                current=getattr(model,key)
                if isinstance(value,str) and value not in {'','null'} and (key in GUI_PASSWORD_FIELDS or SECRET.search(key)) and not current:setattr(model,key,value)
                elif hasattr(type(current),'model_fields') and isinstance(value,Mapping):apply(current,value)
        apply(cli,values)
