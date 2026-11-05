#!/usr/bin/env python3
"""Move verified Endfield text translations between extracted data packages.

This tool never runs code supplied by a package and never touches game binaries.
Python 3.9+ and the standard library are sufficient.
"""
from __future__ import annotations

import argparse
import collections
import contextlib
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import tempfile
import zipfile

MAX_ARCHIVE_UNCOMPRESSED_BYTES = 512 * 1024 * 1024
MAX_FILE_BYTES = 64 * 1024 * 1024
MAX_ARCHIVE_ENTRIES = 10000
CATALOG_SCHEMA = 'endfield.translation_catalog.v1'
SOURCE_FILE = 'source/I18nTextTable_EN.original.json'
ROW_PARTS = ('translated', 'pending', 'retained')
TOKEN_RE = re.compile(r'<[^>]*>|\{[^{}]*\}|%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z%]|\r\n|\r|\n|\t')
ID_RE = re.compile(r'-?(?:0|[1-9]\d*)\Z')
LITERAL_PERCENT_FALSE_MATCHES = {
    '-6730231947724868112': ('Deliver or transfer now to get a 30% deposit', '% d'),
    '5807238442710209203': ('110% ORIGEOMETRY RETURNS!', '% O'),
    '-5844513251810116982': ('When the <@toast.key>Bonekrusher Executioner</> drops below 50% HP, he will become frenzied and gain greatly increased DEF', '% H'),
}


class MigrationError(ValueError):
    pass


def check(condition, message):
    if not condition:
        raise MigrationError(message)


def sha_bytes(data):
    return hashlib.sha256(data).hexdigest()


def sha_file(path):
    h = hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b''):
            h.update(block)
    return h.hexdigest()


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        check(key not in result, f'Yinelenen JSON anahtarı: {key}')
        result[key] = value
    return result


def read_json(path):
    check(path.is_file(), f'Gerekli dosya bulunamadı: {path}')
    check(path.stat().st_size <= MAX_FILE_BYTES, f'Dosya boyut sınırını aşıyor: {path}')
    try:
        return json.loads(path.read_text('utf-8-sig'), object_pairs_hook=unique_object)
    except (UnicodeError, json.JSONDecodeError) as exc:
        raise MigrationError(f'Geçersiz UTF-8/JSON: {path}: {exc}') from exc


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')


def safe_relative(name):
    check(isinstance(name, str) and bool(name), 'Boş veya geçersiz göreli yol')
    check('\\' not in name and '\x00' not in name and ':' not in name, f'Güvensiz yol: {name!r}')
    raw = name[:-1] if name.endswith('/') else name
    check(bool(raw) and not raw.startswith('/'), f'Mutlak/arşiv kök yolu reddedildi: {name!r}')
    check(all(p not in ('', '.', '..') for p in raw.split('/')), f'Yol geçişi reddedildi: {name!r}')
    path = PurePosixPath(raw)
    check(not path.is_absolute(), f'Mutlak yol reddedildi: {name!r}')
    return Path(*path.parts)


def inspect_tree(root):
    check(not root.is_symlink(), f'Sembolik bağlantı reddedildi: {root}')
    total = 0
    count = 0
    seen = set()
    for current, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            path = Path(current) / name
            check(not path.is_symlink(), f'Sembolik bağlantı reddedildi: {path}')
            rel = path.relative_to(root).as_posix()
            safe_relative(rel)
            check(rel.casefold() not in seen, f'Büyük/küçük harf yol çakışması: {rel}')
            seen.add(rel.casefold())
            count += 1
            check(count <= MAX_ARCHIVE_ENTRIES, 'Paket dosya sayısı sınırını aşıyor')
            mode = path.stat().st_mode
            check(stat.S_ISDIR(mode) or stat.S_ISREG(mode), f'Özel dosya türü reddedildi: {path}')
            if path.is_file():
                size = path.stat().st_size
                check(size <= MAX_FILE_BYTES, f'Dosya boyut sınırını aşıyor: {rel}')
                total += size
                check(total <= MAX_ARCHIVE_UNCOMPRESSED_BYTES, 'Paket toplam boyut sınırını aşıyor')


def extract_secure(zip_path, destination):
    with zipfile.ZipFile(zip_path) as archive:
        entries = archive.infolist()
        check(len(entries) <= MAX_ARCHIVE_ENTRIES, 'ZIP dosya sayısı sınırını aşıyor')
        total = 0
        seen = set()
        planned = []
        for entry in entries:
            rel = safe_relative(entry.filename)
            check(rel.as_posix().casefold() not in seen, f'Yinelenen ZIP yolu: {entry.filename}')
            seen.add(rel.as_posix().casefold())
            mode = (entry.external_attr >> 16) & 0o170000
            check(mode in (0, stat.S_IFREG, stat.S_IFDIR), f'ZIP sembolik/özel dosyası reddedildi: {entry.filename}')
            check(not entry.flag_bits & 1, 'Şifreli ZIP girdileri desteklenmiyor')
            check(0 <= entry.file_size <= MAX_FILE_BYTES, f'ZIP dosya boyut sınırını aşıyor: {entry.filename}')
            total += entry.file_size
            check(total <= MAX_ARCHIVE_UNCOMPRESSED_BYTES, 'ZIP toplam açılmış boyut sınırını aşıyor')
            planned.append((entry, rel))
        for entry, rel in planned:
            out = destination / rel
            if entry.is_dir():
                out.mkdir(parents=True, exist_ok=True)
                continue
            out.parent.mkdir(parents=True, exist_ok=True)
            count = 0
            with archive.open(entry) as incoming, out.open('xb') as outgoing:
                for block in iter(lambda: incoming.read(1024 * 1024), b''):
                    count += len(block)
                    check(count <= entry.file_size and count <= MAX_FILE_BYTES, 'ZIP bildirilen boyutla eşleşmiyor')
                    outgoing.write(block)
            check(count == entry.file_size, 'Eksik ZIP girdisi')


def package_root(path):
    if (path / SOURCE_FILE).is_file():
        return path
    children = [p for p in path.iterdir() if p.is_dir() and (p / SOURCE_FILE).is_file()]
    check(len(children) == 1, f'Paket kökü bulunamadı veya belirsiz: {path}')
    return children[0]


@contextlib.contextmanager
def open_package(path):
    path = Path(path).expanduser().absolute()
    check(path.exists(), f'Girdi bulunamadı: {path}')
    check(not path.is_symlink(), f'Sembolik bağlantı reddedildi: {path}')
    if path.is_dir():
        inspect_tree(path)
        yield Package(package_root(path), {'kind': 'package_directory', 'path': str(path)})
    else:
        check(zipfile.is_zipfile(path), f'Paket dizin veya ZIP olmalı: {path}')
        digest = sha_file(path)
        with tempfile.TemporaryDirectory(prefix='endfield_input_') as temporary:
            destination = Path(temporary)
            extract_secure(path, destination)
            inspect_tree(destination)
            yield Package(package_root(destination), {'kind': 'package_zip', 'path': str(path), 'sha256': digest})


def validate_id(value, label):
    check(isinstance(value, str) and ID_RE.fullmatch(value), f'{label}: kimlik string/sayısal dize olmalı')
    check(-(1 << 63) <= int(value) < (1 << 63), f'{label}: kimlik 64 bit aralığının dışında')


def expected_tokens(identifier, source):
    tokens = TOKEN_RE.findall(source)
    exception = LITERAL_PERCENT_FALSE_MATCHES.get(identifier)
    if exception and source == exception[0]:
        tokens.remove(exception[1])
    return tokens


def references_key(references):
    # Ordering of actual references is not semantics; all fields still count.
    return sorted(canonical(value).decode('utf-8') for value in references)


def validate_row(row, label, source_index=None):
    check(isinstance(row, dict), f'{label}: kayıt nesne olmalı')
    required = ('id', 'source_en', 'translation_tr', 'references', 'protected_tokens', 'source_sha256')
    check(all(key in row for key in required), f'{label}: eksik kayıt alanı')
    identifier = row['id']
    validate_id(identifier, label)
    source = row['source_en']
    check(isinstance(source, str), f'{label}: source_en string olmalı')
    if source_index is not None:
        check(identifier in source_index and source_index[identifier] == source, f'{label}: özgün İngilizce kaynak eşleşmiyor')
    check(row['source_sha256'] == sha_bytes(source.encode('utf-8')), f'{label}: kaynak SHA-256 eşleşmiyor')
    check(row['protected_tokens'] == TOKEN_RE.findall(source), f'{label}: korunan işaret listesi kaynağa uymuyor')
    refs = row['references']
    check(isinstance(refs, list), f'{label}: references liste olmalı')
    for ref in refs:
        check(isinstance(ref, dict) and all(isinstance(ref.get(key), str) for key in ('table', 'row', 'field')), f'{label}: geçersiz references bağlamı')
    tr = row['translation_tr']
    check(tr is None or isinstance(tr, str), f'{label}: translation_tr string veya null olmalı')
    if tr is None:
        return
    check('\x00' not in tr and '\ufffd' not in tr, f'{label}: geçersiz metin karakteri')
    check(not source.strip() or bool(tr.strip()), f'{label}: dolu kaynak boş çeviriye dönüşmüş')
    # Keeping the exact original string cannot lose any real token. In the
    # three reviewed literal-percentage cases it also keeps the same regex
    # false positive, which must not invalidate an identity translation.
    if tr != source:
        check(expected_tokens(identifier, source) == TOKEN_RE.findall(tr), f'{label}: gerçek işaret/yer tutucu/satır sonu değişmiş')
    check(re.match(r'^\s*', source).group() == re.match(r'^\s*', tr).group(), f'{label}: baş boşlukları değişmiş')
    check(re.search(r'\s*$', source).group() == re.search(r'\s*$', tr).group(), f'{label}: son boşlukları değişmiş')


class Package:
    def __init__(self, root, provenance):
        self.root = root
        self.provenance = provenance
        self.source = read_json(root / SOURCE_FILE)
        check(isinstance(self.source, dict) and bool(self.source), 'İngilizce ana kaynak boş veya nesne değil')
        for key, value in self.source.items():
            validate_id(key, SOURCE_FILE)
            check(isinstance(value, str), f'{SOURCE_FILE}: tüm değerler string olmalı')
        self.summary = read_json(root / 'durum_ozeti.json')
        check(isinstance(self.summary, dict), 'durum_ozeti.json nesne olmalı')
        self.build = self.summary.get('vfs_build')
        check(isinstance(self.build, int) and not isinstance(self.build, bool) and self.build > 0, 'Geçerli vfs_build gerekli')
        check(self.summary.get('total_english_ids') == len(self.source), 'Ana kaynak sayısı durum özetiyle eşleşmiyor')
        self.rows = {}
        self.files = {}
        self.locations = {}
        for part in ROW_PARTS:
            directory = root / part
            if not directory.is_dir():
                continue
            for path in sorted(directory.rglob('*.jsonl')):
                rows = []
                relative = path.relative_to(root).as_posix()
                check(path.stat().st_size <= MAX_FILE_BYTES, f'JSONL çok büyük: {relative}')
                for number, line in enumerate(path.read_text('utf-8-sig').splitlines(), 1):
                    if not line.strip():
                        continue
                    try:
                        row = json.loads(line, object_pairs_hook=unique_object)
                    except json.JSONDecodeError as exc:
                        raise MigrationError(f'{relative}:{number}: geçersiz JSONL') from exc
                    validate_row(row, f'{relative}:{number}', self.source)
                    identifier = row['id']
                    check(identifier not in self.rows, f'Yinelenen kayıt kimliği: {identifier}')
                    rows.append(row)
                    self.rows[identifier] = row
                    self.locations[identifier] = relative
                self.files[relative] = rows
        check(self.rows.keys() == self.source.keys(), 'JSONL kataloğu tüm İngilizce kaynağı tam bir kez kapsamıyor')
        self.applied_path = root / 'translated/id_to_tr.json'
        self.applied = read_json(self.applied_path)
        check(isinstance(self.applied, dict), 'Uygulanan id_to_tr.json nesne olmalı')
        for key, tr in self.applied.items():
            validate_id(key, 'id_to_tr.json')
            check(isinstance(tr, str) and key in self.rows and self.rows[key]['translation_tr'] == tr, 'Uygulanan eşleme JSONL ile çelişiyor')
        self.applied_bytes = self.applied_path.read_bytes()
        self.manifest = read_json(root / 'batch_manifest.json') if (root / 'batch_manifest.json').is_file() else []
        check(isinstance(self.manifest, list), 'batch_manifest liste olmalı')
        seen_manifest = set()
        for batch in self.manifest:
            check(isinstance(batch, dict) and isinstance(batch.get('file'), str), 'Geçersiz batch_manifest girdisi')
            relative = safe_relative(batch['file']).as_posix()
            check(relative in self.files and relative not in seen_manifest, 'Batch dosyası yok veya yineleniyor')
            seen_manifest.add(relative)
            check(batch.get('records') == len(self.files[relative]), 'Manifest kayıt sayısı eşleşmiyor')
        self.check_hash_manifest()
        self.source_index_sha256 = sha_file(root / SOURCE_FILE)
        self.provenance = dict(provenance, source_build=self.build)
        if 'sha256' not in self.provenance:
            self.provenance['sha256'] = sha_bytes(canonical({'source_index_sha256': self.source_index_sha256, 'rows': self.rows}))

    def check_hash_manifest(self):
        path = self.root / 'paket_sha256.json'
        if not path.is_file():
            return
        manifest = read_json(path)
        check(isinstance(manifest, list), 'paket_sha256 liste olmalı')
        seen = set()
        for entry in manifest:
            check(isinstance(entry, dict) and isinstance(entry.get('path'), str), 'Geçersiz SHA256 manifest girdisi')
            relative = safe_relative(entry['path']).as_posix()
            check(relative not in seen, 'Yinelenen SHA256 manifest yolu')
            seen.add(relative)
            p = self.root / relative
            check(p.is_file() and p.stat().st_size == entry.get('bytes') and sha_file(p) == entry.get('sha256'), f'Paket SHA256/boyut kontrolü başarısız: {relative}')


def catalog_from_package(package):
    rows = [row for key, row in sorted(package.rows.items()) if row['translation_tr'] is not None]
    translated = sum(row['translation_tr'] != row['source_en'] for row in rows)
    return {
        'schema': CATALOG_SCHEMA,
        'source_build': package.build,
        'source_index_sha256': package.source_index_sha256,
        'coverage': 'translated_and_reviewed_rows_only',
        'counts': {'source_total': len(package.source), 'records': len(rows), 'translated': translated, 'reviewed_unchanged': len(rows) - translated},
        'records': rows,
    }


@contextlib.contextmanager
def open_catalog(path):
    path = Path(path).expanduser().absolute()
    if path.is_file() and not zipfile.is_zipfile(path):
        check(not path.is_symlink(), 'Katalog sembolik bağlantı olamaz')
        document = read_json(path)
        check(isinstance(document, dict) and document.get('schema') == CATALOG_SCHEMA, 'Kaynak/hash/bağlam içeren katalog gerekli; sade id→Türkçe eşleme güvenli göç girdisi değildir')
        build = document.get('source_build')
        check(isinstance(build, int) and not isinstance(build, bool) and build > 0, 'Katalog source_build gerekli')
        check(document.get('coverage') == 'translated_and_reviewed_rows_only', 'Desteklenmeyen katalog kapsamı')
        check(isinstance(document.get('source_index_sha256'), str) and re.fullmatch(r'[0-9a-f]{64}', document['source_index_sha256']), 'Katalog kaynak parmak izi gerekli')
        check(isinstance(document.get('records'), list), 'Katalog records listesi gerekli')
        rows = {}
        for number, row in enumerate(document['records'], 1):
            validate_row(row, f'katalog:{number}')
            check(row['translation_tr'] is not None, 'Dışa aktarılan katalogda null çeviri olamaz')
            check(row['id'] not in rows, 'Katalogda yinelenen kimlik')
            rows[row['id']] = row
        counts = document.get('counts')
        check(isinstance(counts, dict) and counts.get('records') == len(rows), 'Katalog kayıt sayısı yanlış')
        translated = sum(row['translation_tr'] != row['source_en'] for row in rows.values())
        check(counts.get('translated') == translated and counts.get('reviewed_unchanged') == len(rows) - translated, 'Katalog çeviri/korunan sayıları yanlış')
        yield {'rows': rows, 'source': None, 'build': build, 'provenance': {'kind': 'standalone_catalog', 'path': str(path), 'source_build': build, 'sha256': sha_file(path)}}
    else:
        with open_package(path) as package:
            yield {'rows': {key: row for key, row in package.rows.items() if row['translation_tr'] is not None}, 'source': package.source, 'build': package.build, 'provenance': package.provenance}


def prepare_output(path, inputs):
    path = Path(path).expanduser().absolute()
    check(not os.path.lexists(path), f'Çıktı zaten var; üzerine yazılmaz: {path}')
    resolved = path.resolve()
    for incoming in inputs:
        incoming = Path(incoming).expanduser().absolute()
        if incoming.is_dir():
            base = incoming.resolve()
            check(resolved != base and base not in resolved.parents, 'Çıktı girdi paketinin içine yerleştirilemez')
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def source_difference(source, target):
    if source is None:
        return {'status': 'unknown_partial_catalog', 'added_ids': None, 'removed_ids': None, 'changed_source_ids': None, 'note': 'Bağımsız katalog yalnız çevrilmiş/incelenmiş kayıtları içerir; tüm sürüm farkı bu girdiden çıkarılamaz.'}
    return {'status': 'complete', 'added_ids': sorted(target.keys() - source.keys()), 'removed_ids': sorted(source.keys() - target.keys()), 'changed_source_ids': sorted(key for key in source.keys() & target.keys() if source[key] != target[key])}


def regenerate_metadata(output, target, report):
    counts = collections.Counter()
    pending_by_category = collections.Counter()
    tables = collections.defaultdict(dict)
    for relative, rows in target.files.items():
        for row in rows:
            tr = row['translation_tr']
            state = 'pending' if tr is None else ('retained' if tr == row['source_en'] else 'translated')
            counts[state] += 1
            parts = PurePosixPath(relative).parts
            if state == 'pending' and parts[0] == 'pending':
                pending_by_category[parts[1] if len(parts) > 2 else '_root'] += 1
            for ref in row['references']:
                tables[ref['table']][row['id']] = (state, row['id'] in target.applied)
    ready = {key: row['translation_tr'] for key, row in target.rows.items() if row['translation_tr'] is not None and row['translation_tr'] != row['source_en']}
    new = {key: tr for key, tr in ready.items() if key not in target.applied}
    write_json(output / 'translated/id_to_tr_hazir.json', ready)
    write_json(output / 'translated/id_to_tr_yeni.json', new)
    check((output / 'translated/id_to_tr.json').read_bytes() == target.applied_bytes, 'Önceki uygulanmış eşleme bytewise değişti')
    manifest = target.manifest
    pending_batches = 0
    for batch in manifest:
        rows = target.files[batch['file']]
        remaining = sum(row['translation_tr'] is None for row in rows)
        if remaining:
            pending_batches += 1
        batch.update({'status': 'pending' if remaining else 'prepared_not_applied', 'records': len(rows), 'source_words': sum(len(row['source_en'].split()) for row in rows), 'prepared_records': len(rows) - remaining, 'translated_records': sum(row['translation_tr'] is not None and row['translation_tr'] != row['source_en'] for row in rows), 'reviewed_unchanged_records': sum(row['translation_tr'] == row['source_en'] for row in rows), 'pending_records': remaining})
    write_json(output / 'batch_manifest.json', manifest)
    summary = dict(target.summary)
    categories = sorted(set(summary.get('pending_by_category', {})) | set(pending_by_category))
    summary.update({'vfs_build': target.build, 'total_english_ids': len(target.source), 'translated_applied': len(target.applied), 'translated_total_prepared': len(ready), 'new_translation_prepared_not_applied': len(new), 'retained_not_translation': counts['retained'], 'pending': counts['pending'], 'pending_by_category': {cat: pending_by_category.get(cat, 0) for cat in categories}, 'pending_batch_files': pending_batches, 'total_batch_files': len(manifest), 'translation_stage': 'migrated_data_not_applied', 'runtime_status': 'Migration prepares text data only. No game binary, account, service, or runtime verification was changed.'})
    # Prior per-run UI numbers are historical and must not masquerade as new work.
    for key in ('transferred_from_old_build', 'newly_prepared_records_this_run', 'retained_original', 'reviewed_ui_unchanged'):
        summary.pop(key, None)
    if 'pending/01_kalan_arayuz' in str(list(target.files)):
        ui = [row for relative, rows in target.files.items() if relative.startswith('pending/01_kalan_arayuz/') for row in rows]
        summary['completed_ui_records'] = sum(row['translation_tr'] is not None for row in ui)
        summary['completed_ui_batch_files'] = sum(all(row['translation_tr'] is not None for row in rows) for relative, rows in target.files.items() if relative.startswith('pending/01_kalan_arayuz/'))
    write_json(output / 'durum_ozeti.json', summary)
    state_path = output / 'dosya_durumu.json'
    if state_path.is_file():
        states = read_json(state_path)
        check(isinstance(states, list), 'dosya_durumu liste olmalı')
        lines = ['**Göç sonrası hazırlık durumu — oyun ikililerine uygulanmadı**', '', 'Uygulanan sayısı hedef paketin önceki kaydına dayanır. Bağlam tablosu çözülemediyse sıfır, çeviri gerekmiyor kanıtı değildir. Tablo toplamları tekil genel toplama eklenmez.', '', '| Tablo | Kimlik | Önceki uygulanmış | Yeni hazır | Korunan | Bekleyen |', '|---|---:|---:|---:|---:|---:|']
        for item in states:
            check(isinstance(item, dict) and isinstance(item.get('Table'), str), 'Geçersiz dosya_durumu kaydı')
            refs = tables.get(item['Table'], {})
            c = collections.Counter(state for state, _ in refs.values())
            applied = sum(ap for _, ap in refs.values())
            if item.get('Status') != 'OK':
                state = 'context_not_decoded'
            elif not refs:
                state = 'no_matched_localized_id'
            elif c['pending'] == 0:
                state = 'complete_prepared_pending_game_review'
            else:
                state = 'partially_prepared' if c['translated'] else 'pending'
            item.update({'localized_ids': len(refs), 'translated_ids': c['translated'], 'reported_applied_v1_ids': applied, 'new_prepared_translation_ids': c['translated'] - applied, 'retained_ids': c['retained'], 'pending_ids': c['pending'], 'translation_status': state})
            lines.append(f"| {item['Table']} | {len(refs)} | {applied} | {c['translated'] - applied} | {c['retained']} | {c['pending']} |")
        write_json(state_path, states)
        (output / 'dosya_durumu.md').write_text('\n'.join(lines) + '\n', encoding='utf-8')
    report['counts'].update({'translations_ready': len(ready), 'reviewed_unchanged_total': counts['retained'], 'pending_total': counts['pending'], 'existing_applied_mapping_preserved': len(target.applied)})
    # Keep all original input documents byte-for-byte, but mark stale prose clearly.
    archive_name = 'migration_target_input'
    archive = output / 'history' / archive_name
    suffix = 1
    while archive.exists():
        suffix += 1
        archive_name = f'migration_target_input_{suffix}'
        archive = output / 'history' / archive_name
    archive.mkdir(parents=True, exist_ok=False)
    report['target_input_archive'] = 'history/' + archive_name
    for name in ('BULUTTA_DEVAM.md', 'CEVIRI_DURUMU.md', 'durum_ozeti.json', 'batch_manifest.json', 'dosya_durumu.json', 'dosya_durumu.md', 'paket_sha256.json', 'dogrulama_raporu.json'):
        original = target.root / name
        if original.is_file():
            shutil.copy2(original, archive / name)
    banner = '**Göç sonrası güncel giriş:** `GOC_SONRASI_OKU.md`, `migration_report.json`, `needs_review.json` ve `durum_ozeti.json` esas alınır. Aşağıdaki önceki paket metni tarihsel olabilir; yeni göç sonucu değildir.\n\n'
    for name in ('BULUTTA_DEVAM.md', 'CEVIRI_DURUMU.md'):
        original = target.root / name
        if original.is_file():
            (output / name).write_text(banner + original.read_text('utf-8-sig'), encoding='utf-8')
    note = f'''**Endfield {target.build} — metin çevirisi göçü**

Bu çıktı yalnız çıkarılmış metin verileridir; oyuna uygulanmadı. Oyun .chk/.blc dosyalarını yeniden derlemez, hesap veya arka plan görevi değiştirmez ve paketteki Python/PowerShell dosyalarını çalıştırmaz.

- Önceki uygulanmış eşleme: {len(target.applied)} kayıt; `translated/id_to_tr.json` bytewise korundu.
- Bu göçte taşınan yeni çeviri: {report['counts']['translations_transferred']}.
- Bu göçte taşınan aynen korunmuş/incelenmiş kayıt: {report['counts']['reviewed_unchanged_transferred']} (çeviri sayılmaz).
- Toplam hazır Türkçe: {len(ready)}; aynen korunan: {counts['retained']}; bekleyen: {counts['pending']}.
- Kaynak sürüm: {report['source_build']}; hedef sürüm: {target.build}. Sürüm değişmemiş olması da geçerli bir katalog birleştirmesidir.

`needs_review.json` içindeki kaynak/bağlam değişikliklerini ve çeviri çakışmalarını elle incele. Hedefin dolu çevirileri otomatik değiştirilmedi. Aynı id ve metnin bağlamı değişmişse katalogdaki metin hedefe taşınmadı. Çözülemeyen kayıtların hedefte önceden bulunan değeri korunmuş olabilir; rapor bunu onaylama saymaz.

`translated/id_to_tr_hazir.json` toplam hazır karşılıkları, `id_to_tr_yeni.json` önceki uygulanmış eşlemede bulunmayan hazır karşılıkları içerir. Bu dosyalar tek başına güvenli sürüm geçişi kataloğu değildir. `ceviri_katalogu.json` kaynak/hash/bağlam taşıyan kalıcı katalogdur; oyun klasörünün dışında sakla. Sonraki güncellemede hedef olarak **yeni sürümden çıkarılmış özgün İngilizce paketi** ver.

Bağımsız katalog yalnız dolu kayıtları içerdiği için tüm sürüme eklenen/silinen/değişen metin sayısı bundan hesaplanamaz; `source_diff.status=unknown_partial_catalog` bu sınırlamayı açıklar. Tam eski paket girdi olduğunda genel kaynak farkı da hesaplanır.

Kontrol etmek için `python endfield_update.py validate --package "BU_CIKTI_DIZINI"` komutunu kullan. Bu komut yalnız aracın kendi şema/hash/yer tutucu/boşluk kontrollerini çalıştırır. Hedef paketten korunan `validate_translations.py` gibi betikler tarihsel olabilir ve literal yüzde ifadelerini yanlış yorumlayabilir; göç aracı bunları çalıştırmaz veya otomatik düzenlemez.

Eski paket belgeleri `history/{archive_name}/` altında korunur. Özellikle eski dosya hashleri, yedek yolları, fiziksel parça konumları ve önceki çalışma sayıları güncel uygulama talimatı sayılmaz. Bu aracın veri kontrolleri, oyunda çalışırlık veya ekran yerleşimi testi değildir.
'''
    (output / 'GOC_SONRASI_OKU.md').write_text(note, encoding='utf-8')
    return counts


def migrate(catalog_path, target_path, output_path):
    output = prepare_output(output_path, [catalog_path, target_path])
    with open_catalog(catalog_path) as catalog, open_package(target_path) as target:
        report = {'tool': 'endfield_update.py', 'source_build': catalog['build'], 'target_build': target.build, 'catalog_provenance': catalog['provenance'], 'target_provenance': target.provenance, 'source_diff': source_difference(catalog['source'], target.source), 'runtime_applied': False, 'counts': dict.fromkeys(('translations_transferred', 'reviewed_unchanged_transferred', 'catalog_translations_already_present', 'catalog_retained_already_present', 'conflicts', 'source_changed_needs_review', 'context_changed_needs_review', 'protected_tokens_changed_needs_review', 'catalog_translations_removed'), 0)}
        review = []
        changed_files = set()
        for identifier, old in sorted(catalog['rows'].items()):
            new = target.rows.get(identifier)
            reason = None
            if new is None:
                reason = 'removed'
                report['counts']['catalog_translations_removed'] += 1
            elif old['source_en'] != new['source_en'] or old['source_sha256'] != new['source_sha256']:
                reason = 'source_changed'
                report['counts']['source_changed_needs_review'] += 1
            elif references_key(old['references']) != references_key(new['references']):
                reason = 'context_changed'
                report['counts']['context_changed_needs_review'] += 1
            elif old['protected_tokens'] != new['protected_tokens']:
                reason = 'protected_tokens_changed'
                report['counts']['protected_tokens_changed_needs_review'] += 1
            elif new['translation_tr'] is not None and new['translation_tr'] != old['translation_tr']:
                reason = 'translation_conflict'
                report['counts']['conflicts'] += 1
            elif new['translation_tr'] is not None:
                key = 'catalog_retained_already_present' if old['translation_tr'] == old['source_en'] else 'catalog_translations_already_present'
                report['counts'][key] += 1
            else:
                new['translation_tr'] = old['translation_tr']
                key = 'reviewed_unchanged_transferred' if old['translation_tr'] == old['source_en'] else 'translations_transferred'
                report['counts'][key] += 1
                changed_files.add(target.locations[identifier])
            if reason:
                review.append({'id': identifier, 'reason': reason, 'catalog_source_en': old['source_en'], 'catalog_source_sha256': old['source_sha256'], 'catalog_translation_tr': old['translation_tr'], 'catalog_references': old['references'], 'target_source_en': new['source_en'] if new else None, 'target_source_sha256': new['source_sha256'] if new else None, 'target_translation_tr': new['translation_tr'] if new else None, 'target_references': new['references'] if new else None, 'action': 'target_preserved_no_automatic_overwrite'})
        # Stage beside output for an atomic final directory rename.
        with tempfile.TemporaryDirectory(prefix='.' + output.name + '.', dir=output.parent) as temporary:
            staged = Path(temporary) / 'package'
            shutil.copytree(target.root, staged)
            for relative in sorted(changed_files):
                rows = target.files[relative]
                for row in rows:
                    validate_row(row, f'çıktı:{relative}', target.source)
                (staged / relative).write_text(''.join(json.dumps(row, ensure_ascii=False, separators=(',', ':')) + '\n' for row in rows), encoding='utf-8')
            regenerate_metadata(staged, target, report)
            catalog_document = catalog_from_package(target)
            write_json(staged / 'ceviri_katalogu.json', catalog_document)
            report['output_catalog'] = {'path': 'ceviri_katalogu.json', 'sha256': sha_file(staged / 'ceviri_katalogu.json'), 'source_build': target.build, 'counts': catalog_document['counts']}
            report['checks'] = {'all_source_ids_covered_once': len(target.rows), 'all_source_rows_validated': True, 'only_translation_tr_modified_in_records': True, 'applied_mapping_bytewise_preserved': True, 'supplied_code_executed': False, 'literal_percent_exceptions_are_exact_id_and_source': True}
            write_json(staged / 'needs_review.json', {'items': review, 'count': len(review), 'automatic_overwrite': False})
            write_json(staged / 'migration_report.json', report)
            # Original standalone verification fingerprints still cover immutable fields.
            # Any prior successful run report is explicitly historical now.
            prior_report = staged / 'dogrulama_raporu.json'
            if prior_report.is_file():
                write_json(prior_report, {'status': 'superseded_by_migration_report', 'current_report': 'migration_report.json', 'previous_report': report['target_input_archive'] + '/dogrulama_raporu.json', 'runtime_applied': False})
            # The complete original English source remains byte-for-byte identical.
            for original in (target.root / 'source').rglob('*'):
                if original.is_file():
                    check(sha_file(original) == sha_file(staged / original.relative_to(target.root)), 'İngilizce kaynak dosyası göçte değişti')
            write_json(staged / 'paket_sha256.json', [{'path': file.relative_to(staged).as_posix(), 'bytes': file.stat().st_size, 'sha256': sha_file(file)} for file in sorted(staged.rglob('*')) if file.is_file() and file != staged / 'paket_sha256.json'])
            check(not os.path.lexists(output), 'Çıktı çalışma sırasında oluşturulmuş; üzerine yazılmaz')
            os.rename(staged, output)
        return {'output': str(output), 'source_build': catalog['build'], 'target_build': target.build, 'counts': report['counts'], 'needs_review': len(review), 'runtime_applied': False}


def export_catalog(package_path, output_path):
    output = prepare_output(output_path, [package_path])
    with open_package(package_path) as package:
        document = catalog_from_package(package)
        document['export_provenance'] = package.provenance
        with tempfile.TemporaryDirectory(prefix='.' + output.name + '.', dir=output.parent) as temporary:
            staged = Path(temporary) / 'catalog.json'
            write_json(staged, document)
            digest = sha_file(staged)
            check(not os.path.lexists(output), 'Katalog çıktısı çalışma sırasında oluşturulmuş')
            os.rename(staged, output)
        return {'output': str(output), 'sha256': digest, 'source_build': package.build, 'counts': document['counts'], 'coverage': document['coverage'], 'runtime_applied': False}


def validate_package(package_path):
    with open_package(package_path) as package:
        counts = collections.Counter()
        for row in package.rows.values():
            tr = row['translation_tr']
            state = 'pending' if tr is None else ('reviewed_unchanged' if tr == row['source_en'] else 'translated')
            counts[state] += 1
        return {'package': str(Path(package_path).absolute()), 'source_build': package.build,
                'records': len(package.rows), 'counts': dict(counts), 'errors': 0,
                'package_provenance': package.provenance, 'supplied_code_executed': False,
                'runtime_applied': False}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest='command', required=True)
    migration = commands.add_parser('migrate', help='Kataloğu yeni çıkarılmış özgün İngilizce hedef paketine taşı')
    migration.add_argument('--catalog', required=True)
    migration.add_argument('--target', required=True)
    migration.add_argument('--output', required=True)
    export = commands.add_parser('export-catalog', help='Oyun dışında saklanacak kaynak/hash/bağlamlı kalıcı katalog üret')
    export.add_argument('--package', required=True)
    export.add_argument('--output', required=True)
    validation = commands.add_parser('validate', help='Paket verilerini kendi doğrulayıcısıyla salt okunur kontrol et; yüklenmiş betik çalıştırma')
    validation.add_argument('--package', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'migrate':
            result = migrate(args.catalog, args.target, args.output)
        elif args.command == 'export-catalog':
            result = export_catalog(args.package, args.output)
        else:
            result = validate_package(args.package)
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (MigrationError, OSError, zipfile.BadZipFile, RuntimeError, UnicodeError) as exc:
        print(f'HATA: {exc}', file=sys.stderr)
        return 2


if __name__ == '__main__':
    sys.exit(main())
