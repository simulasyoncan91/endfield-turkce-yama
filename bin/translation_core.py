#!/usr/bin/env python3
"""Checked Endfield text migration/repacking core. No network or game writes.

prepare selects catalog rows against fresh English source/references and emits
an appended SparkBuffer copy. PowerShell encrypts that logical file, then
finalize rebuilds the containing chunk and plain metadata. Crypto and atomic
installation remain the bridge's responsibility.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import re
import struct
import sys
import zlib
from pathlib import Path

SCHEMA = 'endfield.local_build_plan.v1'
CATALOG_SCHEMA = 'endfield.translation_catalog.v1'
COMPACT_CATALOG_SCHEMA = 'endfield.translation_catalog.compact.v1'
TOKEN_RE = re.compile(r'<[^>]*>|\{[^{}]*\}|%(?:\d+\$)?[-+0 #]*(?:\d+|\*)?(?:\.(?:\d+|\*))?[a-zA-Z%]|\r\n|\r|\n|\t')
PERCENT_EXCEPTIONS = {
 '-6730231947724868112': ('Deliver or transfer now to get a 30% deposit', '% d'),
 '5807238442710209203': ('110% ORIGEOMETRY RETURNS!', '% O'),
 '-5844513251810116982': ('When the <@toast.key>Bonekrusher Executioner</> drops below 50% HP, he will become frenzied and gain greatly increased DEF', '% H'),
}
MAX_JSON = 128 * 1024 * 1024
MAX_PAYLOAD = 256 * 1024 * 1024
MAX_CHUNK = 512 * 1024 * 1024

class CoreError(ValueError):
    pass

def check(value, message):
    if not value:
        raise CoreError(message)

def sha(data):
    return hashlib.sha256(data).hexdigest()

def md5(data):
    return hashlib.md5(data).digest()

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':')).encode('utf-8')

def unique_object(pairs):
    result = {}
    for key, value in pairs:
        check(key not in result, 'Duplicate JSON key: ' + key)
        result[key] = value
    return result

def read_json(path):
    p = Path(path)
    check(p.is_file() and p.stat().st_size <= MAX_JSON, 'Missing/oversize JSON: ' + str(p))
    return json.loads(p.read_text('utf-8-sig'), object_pairs_hook=unique_object)

def read_bytes(path, limit=MAX_PAYLOAD):
    p = Path(path)
    check(p.is_file() and p.stat().st_size <= limit, 'Missing/oversize binary: ' + str(p))
    return p.read_bytes()

def write_new(path, data):
    p = Path(path)
    if p.exists():
        check(p.is_file() and p.read_bytes() == data, 'Refusing to overwrite different output: ' + str(p))
        return
    with p.open('xb') as f:
        f.write(data)

def write_json(path, value):
    write_new(path, (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))

def valid_id(key):
    return isinstance(key, str) and re.fullmatch(r'-?(?:0|[1-9]\d*)', key) and -(1 << 63) <= int(key) < (1 << 63)

class Reader:
    def __init__(self, data):
        self.data = data
        self.p = 0
    def take(self, length):
        check(isinstance(length, int) and length >= 0 and self.p + length <= len(self.data), 'Truncated binary metadata')
        result = bytes(self.data[self.p:self.p + length])
        self.p += length
        return result
    def read(self, fmt):
        values = struct.unpack('<' + fmt, self.take(struct.calcsize('<' + fmt)))
        return values[0] if len(values) == 1 else values
    def text(self):
        length = self.read('H')
        return self.take(length).decode('utf-8', 'strict')
    def count(self, minimum=1):
        value = self.read('i')
        check(value >= 0 and value <= (len(self.data) - self.p) // minimum, 'Invalid metadata count')
        return value

def parse_metadata(data):
    check(4 <= len(data) <= MAX_PAYLOAD, 'Invalid metadata length')
    check(zlib.crc32(data[:-4]) == struct.unpack_from('<I', data, len(data)-4)[0], 'Metadata CRC mismatch')
    r = Reader(data[:-4])
    raw_version = r.read('i')
    if raw_version < 11:
        code_version, version = raw_version, r.read('i')
    else:
        code_version, version = 3, raw_version
    check(code_version in (3, 4, 5) and version > 0, 'Unsupported VFS metadata version')
    name = r.text()
    r.take(8)  # signed name hash, preserved verbatim
    total_files = r.count()
    total_offset = r.p
    total_length = r.read('q')
    block_type = r.read('B')
    check(total_length >= 0 and block_type == 18 and name == 'Table', 'Expected a Table block')
    tag_bytes = 8 if code_version == 5 else 4 if code_version == 4 else 0
    chunks = []
    chunk_names = set()
    all_files = []
    names = set()
    for _ in range(r.count(45 + tag_bytes)):
        identity = r.take(16)
        check(identity not in chunk_names, 'Duplicate chunk identity')
        chunk_names.add(identity)
        content_md5_offset = r.p
        digest = r.take(16)
        length_offset = r.p
        length = r.read('q')
        check(length >= 0 and r.read('B') == block_type, 'Invalid chunk length/type')
        r.take(tag_bytes)
        chunk = {'name': identity.hex().upper() + '.chk', 'identity': identity.hex(),
                 'content_md5': digest.hex(), 'content_md5_offset': content_md5_offset,
                 'length': length, 'length_offset': length_offset, 'files': []}
        for _ in range(r.count(60 + tag_bytes)):
            file_name = r.text()
            check(file_name not in names, 'Duplicate logical filename')
            names.add(file_name)
            r.take(8)
            file_chunk_identity = r.take(16)
            data_md5_offset = r.p
            data_md5 = r.take(16)
            offset_offset = r.p
            offset = r.read('q')
            file_length_offset = r.p
            file_length = r.read('q')
            check(r.read('B') == block_type, 'Invalid logical file type')
            encrypted_value = r.read('B')
            check(encrypted_value in (0, 1), 'Unknown encryption flag')
            seed = r.read('q') if encrypted_value else None
            r.take(tag_bytes)
            check(offset >= 0 and file_length >= 0 and offset <= length and file_length <= length-offset, 'Logical file outside chunk')
            f = {'name': file_name, 'chunk': chunk['name'], 'file_chunk_identity': file_chunk_identity.hex(),
                 'data_md5': data_md5.hex(), 'data_md5_offset': data_md5_offset,
                 'offset': offset, 'offset_offset': offset_offset,
                 'length': file_length, 'length_offset': file_length_offset,
                 'encrypted': bool(encrypted_value), 'iv_seed': seed}
            chunk['files'].append(f)
            all_files.append(f)
        previous_end = 0
        for f in sorted(chunk['files'], key=lambda f: (f['offset'], f['length'])):
            check(f['offset'] >= previous_end, 'Overlapping logical file ranges')
            previous_end = f['offset'] + f['length']
        chunks.append(chunk)
    check(len(all_files) == total_files, 'Logical file count mismatch')
    check(sum(c['length'] for c in chunks) == total_length, 'Chunk length sum mismatch')
    trailer = r.take(len(r.data) - r.p)
    check(len(trailer) in (0, 10), 'Unknown metadata trailer')
    return {'version': version, 'code_version': code_version, 'total_length': total_length,
            'total_length_offset': total_offset, 'chunks': chunks, 'files': all_files,
            'trailer': trailer.hex()}

def cstring(data, offset):
    check(0 <= offset < len(data), 'String pointer out of bounds')
    end = data.find(b'\0', offset)
    check(end >= 0, 'Unterminated string')
    return data[offset:end].decode('utf-8', 'strict'), end + 1

def parse_i18n(data, expected=None, pristine=False):
    check(20 <= len(data) <= MAX_PAYLOAD, 'Invalid SparkBuffer payload length')
    type_offset, root_offset, data_offset = struct.unpack_from('<iii', data)
    check(0 <= type_offset <= len(data)-4 and 0 <= root_offset < len(data) and 0 <= data_offset <= len(data)-4, 'Invalid SparkBuffer header')
    check(struct.unpack_from('<i', data, type_offset)[0] == 0, 'Unexpected I18n type definitions')
    check(data[root_offset] == 10, 'Expected root map')
    root_name, root_end = cstring(data, root_offset + 1)
    check(root_name == 'I18nTextTable_EN' and data[root_end:root_end+2] == bytes((3, 7)), 'Expected EN int64/string map')
    count = struct.unpack_from('<i', data, data_offset)[0]
    check(0 <= count <= (len(data)-data_offset-4)//8, 'Invalid I18n count')
    p = data_offset + 4 + count * 8
    values, slots, max_end = {}, {}, 0
    for _ in range(count):
        p = (p + 7) & ~7
        check(p + 12 <= len(data), 'Truncated I18n entry')
        key, string_offset = struct.unpack_from('<qi', data, p)
        key = str(key)
        check(key not in values, 'Duplicate I18n ID')
        # -1 is the format's empty-string sentinel. Offset zero is a real
        # absolute pointer, never a missing-value boolean.
        if string_offset == -1:
            value, end = '', 0
        else:
            value, end = cstring(data, string_offset)
        values[key], slots[key] = value, p + 8
        max_end = max(max_end, end)
        p += 12
    if pristine:
        check(p == len(data), 'English payload is already appended/patched or has unsupported trailing data')
    else:
        check(max(p, max_end) == len(data), 'Unreferenced trailing payload data')
    if expected is not None:
        check(isinstance(expected, dict) and values == expected, 'English/expected payload values do not match binary')
    return {'values': values, 'slots': slots, 'map_end': p}

def normalized_refs(refs):
    check(isinstance(refs, list), 'References must be a list')
    for ref in refs:
        check(isinstance(ref, dict) and all(isinstance(ref.get(k), str) for k in ('table', 'row', 'field')), 'Malformed reference')
    return sorted(canonical(ref).decode('utf-8') for ref in refs)

def expected_tokens(identifier, source):
    result = TOKEN_RE.findall(source)
    exception = PERCENT_EXCEPTIONS.get(identifier)
    if exception and exception[0] == source:
        check(exception[1] in result, 'Invalid narrow percentage exception')
        result.remove(exception[1])
    return result

def validate_catalog_row(row):
    check(isinstance(row, dict) and all(k in row for k in ('id', 'source_en', 'translation_tr', 'references', 'protected_tokens', 'source_sha256')), 'Incomplete catalog row')
    identifier, source, translation = row['id'], row['source_en'], row['translation_tr']
    check(valid_id(identifier) and isinstance(source, str) and isinstance(translation, str), 'Invalid catalog ID/source/translation')
    check(row['source_sha256'] == sha(source.encode('utf-8')), 'Catalog source hash mismatch: ' + identifier)
    check(row['protected_tokens'] == TOKEN_RE.findall(source), 'Catalog token metadata mismatch: ' + identifier)
    normalized_refs(row['references'])
    check('\x00' not in translation and '\ufffd' not in translation, 'Invalid translation character: ' + identifier)
    check(not source.strip() or bool(translation.strip()), 'Translation empties a nonempty source: ' + identifier)
    if source != translation:
        check(expected_tokens(identifier, source) == TOKEN_RE.findall(translation), 'Translation token mismatch: ' + identifier)
    check(re.match(r'^\s*', source).group() == re.match(r'^\s*', translation).group() and
          re.search(r'\s*$', source).group() == re.search(r'\s*$', translation).group(), 'Translation edge whitespace mismatch: ' + identifier)

def compact_row(row):
    """Validate compact transport metadata without requiring an old English copy."""
    check(isinstance(row, dict) and 'source_en' not in row, 'Compact catalog must not contain source_en')
    result = dict(row)
    for short, full in (('tr', 'translation_tr'), ('refs', 'references')):
        if short in result:
            check(full not in result or result[full] == result[short], 'Conflicting compact aliases: ' + full)
            result[full] = result.pop(short)
    required = ('id', 'translation_tr', 'source_sha256', 'references', 'protected_tokens')
    check(all(k in result for k in required), 'Incomplete compact catalog row')
    check(valid_id(result['id']) and isinstance(result['translation_tr'], str), 'Invalid compact ID/translation')
    check(isinstance(result['source_sha256'], str) and re.fullmatch(r'[0-9a-fA-F]{64}', result['source_sha256']), 'Invalid compact source hash')
    result['source_sha256'] = result['source_sha256'].lower()
    check(isinstance(result['protected_tokens'], list) and all(isinstance(x, str) for x in result['protected_tokens']), 'Invalid compact protected_tokens')
    normalized_refs(result['references'])
    check('\x00' not in result['translation_tr'] and '\ufffd' not in result['translation_tr'], 'Invalid compact translation character')
    return result

def select_translations(catalog, source, references):
    check(isinstance(catalog, dict) and catalog.get('schema') in (CATALOG_SCHEMA, COMPACT_CATALOG_SCHEMA), 'Unsupported translation catalog')
    check(isinstance(catalog.get('source_build'), int) and not isinstance(catalog['source_build'], bool) and catalog['source_build'] > 0, 'Invalid catalog source_build')
    check(isinstance(catalog.get('records'), list) and isinstance(source, dict) and isinstance(references, dict), 'Invalid catalog/source/references')
    compact = catalog['schema'] == COMPACT_CATALOG_SCHEMA
    selected, review, retained, seen = {}, [], 0, set()
    for raw_row in catalog['records']:
        if compact:
            row = compact_row(raw_row)
        else:
            row = raw_row
            validate_catalog_row(row)
        identifier, translation = row['id'], row['translation_tr']
        check(identifier not in seen, 'Duplicate catalog ID: ' + identifier)
        seen.add(identifier)
        old = row.get('source_en')
        reason = None
        if identifier not in source:
            reason = 'removed_from_current_source'
        elif compact and sha(source[identifier].encode('utf-8')) != row['source_sha256']:
            reason = 'source_changed'
        elif not compact and source[identifier] != old:
            reason = 'source_changed'
        else:
            if compact:
                # Only a matching fresh-source hash supplies the transient
                # English text. Compact public catalogs never carry it.
                row = {**row, 'source_en': source[identifier]}
                validate_catalog_row(row)
            if row['source_en'] == translation:
                retained += 1
                continue
            if identifier not in references:
                reason = 'fresh_context_unavailable'
            elif normalized_refs(references[identifier]) != normalized_refs(row['references']):
                reason = 'context_changed'
        if reason:
            review.append({'id': identifier, 'reason': reason, 'previous_source': old,
                           'previous_source_sha256': row['source_sha256'],
                           'current_source': source.get(identifier), 'previous_translation': translation,
                           'previous_references': row['references'], 'current_references': references.get(identifier)})
        else:
            selected[identifier] = translation
    return selected, review, retained

def patch_i18n(original, source, translations):
    parsed = parse_i18n(original, source, pristine=True)
    check(all(k in source and isinstance(v, str) and '\x00' not in v for k, v in translations.items()), 'Invalid selected translations')
    result = bytearray(original)
    for identifier, slot in parsed['slots'].items():
        if identifier not in translations:
            continue
        check(translations[identifier] != source[identifier], 'Identity row should not be appended')
        check(len(result) < (1 << 31), 'SparkBuffer string offsets exceed int32')
        struct.pack_into('<i', result, slot, len(result))
        result.extend(translations[identifier].encode('utf-8') + b'\0')
    expected = dict(source)
    expected.update(translations)
    parse_i18n(result, expected, pristine=not translations)
    return bytes(result)

def target_info(metadata, context):
    check(metadata['version'] == int(context['Version']), 'Detected build differs from metadata')
    matches = [f for f in metadata['files'] if f['name'] == context['FileName']]
    check(len(matches) == 1, 'English logical file not unique')
    f = matches[0]
    check(f['chunk'] == context['Chunk'] and f['offset'] == int(context['Offset']) and
          f['length'] == int(context['Length']) and f['iv_seed'] == (int(context['IvSeed']) if f['encrypted'] else None), 'Dynamic context differs from original metadata')
    chunk = next(c for c in metadata['chunks'] if c['name'] == f['chunk'])
    check(chunk['length'] == int(context['ChunkLength']), 'Context chunk length differs')
    return f, chunk

def rebuild_container(metadata_plain, context, original_payload, translated_payload, original_chunk, encrypted_file):
    metadata = parse_metadata(metadata_plain)
    f, chunk = target_info(metadata, context)
    check(len(original_payload) == f['length'] and md5(original_payload).hex() == f['data_md5'], 'Original logical payload MD5 differs from metadata')
    check(len(original_chunk) == chunk['length'] and md5(original_chunk).hex() == chunk['content_md5'], 'Original chunk MD5/length differs from metadata')
    check(len(encrypted_file) == len(translated_payload), 'Encrypted logical file length differs')
    if not f['encrypted']:
        check(encrypted_file == translated_payload, 'Unencrypted payload unexpectedly transformed')
    begin, end = f['offset'], f['offset'] + f['length']
    output_chunk = original_chunk[:begin] + encrypted_file + original_chunk[end:]
    delta = len(translated_payload) - len(original_payload)
    output_meta = bytearray(metadata_plain)
    struct.pack_into('<q', output_meta, metadata['total_length_offset'], metadata['total_length'] + delta)
    struct.pack_into('<q', output_meta, chunk['length_offset'], chunk['length'] + delta)
    output_meta[chunk['content_md5_offset']:chunk['content_md5_offset']+16] = md5(output_chunk)
    struct.pack_into('<q', output_meta, f['length_offset'], len(translated_payload))
    output_meta[f['data_md5_offset']:f['data_md5_offset']+16] = md5(translated_payload)
    for other in chunk['files']:
        if other is f:
            continue
        if other['offset'] >= end:
            struct.pack_into('<q', output_meta, other['offset_offset'], other['offset'] + delta)
        else:
            check(other['offset'] + other['length'] <= begin, 'Overlapping file range cannot be moved')
    struct.pack_into('<I', output_meta, len(output_meta)-4, zlib.crc32(output_meta[:-4]))
    reparsed = parse_metadata(output_meta)
    nf, nc = target_info(reparsed, {**context, 'Length': len(translated_payload), 'ChunkLength': len(output_chunk)})
    # The identity/reference names remain bytewise unchanged. Only ciphertext
    # content MD5s and logical plaintext data MD5s are updated, separately.
    check(nc['identity'] == chunk['identity'] and nf['file_chunk_identity'] == f['file_chunk_identity'], 'Reference identity changed')
    for before, after in zip(chunk['files'], nc['files']):
        if before['name'] == f['name']:
            continue
        old = original_chunk[before['offset']:before['offset']+before['length']]
        new = output_chunk[after['offset']:after['offset']+after['length']]
        check(old == new and before['data_md5'] == after['data_md5'], 'Unrelated logical bytes changed')
    return output_chunk, bytes(output_meta)

def prepare(args):
    original_path, source_path, meta_path = map(lambda x: Path(x).resolve(), (args.original_bytes, args.source_json, args.metadata_plain))
    context_path, references_path, catalog_path = map(lambda x: Path(x).resolve(), (args.context, args.references, args.catalog))
    original = read_bytes(original_path)
    source, context, references, catalog = map(read_json, (source_path, context_path, references_path, catalog_path))
    check(all(valid_id(k) and isinstance(v, str) for k, v in source.items()), 'Invalid English source mapping')
    metadata_plain = read_bytes(meta_path)
    metadata = parse_metadata(metadata_plain)
    f, chunk = target_info(metadata, context)
    check(len(original) == f['length'] and md5(original).hex() == f['data_md5'], 'Pristine logical source differs from metadata')
    selected, review, retained = select_translations(catalog, source, references)
    translated = patch_i18n(original, source, selected)
    output = Path(args.output).resolve()
    check(not output.exists(), 'Output directory already exists')
    check(all(output != p and not output.is_relative_to(p) for p in (original_path, source_path, meta_path, context_path, references_path, catalog_path)), 'Output conflicts with an input')
    output.mkdir(parents=True)
    report = {'source_build': metadata['version'], 'catalog_build': catalog['source_build'],
              'total_records': len(source), 'selected_translations': len(selected),
              'needs_review': len(review), 'catalog_retained': retained,
              'original_payload_sha256': sha(original), 'output_payload_sha256': sha(translated),
              'catalog_sha256': sha(catalog_path.read_bytes()), 'references_sha256': sha(references_path.read_bytes()),
              'added_bytes': len(translated)-len(original), 'status': 'PREPARED_NOT_INSTALLED'}
    plan = {'schema': SCHEMA, 'output': str(output), 'context': context,
            'original_payload': str(original_path), 'original_payload_sha256': sha(original),
            'original_metadata': str(meta_path), 'original_metadata_sha256': sha(metadata_plain),
            'translated_payload': str(output/'translated.bytes'), 'translated_payload_sha256': sha(translated),
            'catalog': str(catalog_path), 'catalog_sha256': report['catalog_sha256'],
            'source_json': str(source_path), 'source_json_sha256': sha(source_path.read_bytes()),
            'selected_translations': str(output/'selected_translations.json'),
            'selected_translations_sha256': sha((json.dumps(selected, ensure_ascii=False, indent=2) + '\n').encode('utf-8'))}
    write_new(output/'translated.bytes', translated)
    write_json(output/'selected_translations.json', selected)
    write_json(output/'needs_review.json', review)
    write_json(output/'selection_report.json', report)
    write_json(output/'build_plan.json', plan)
    return report

def finalize(args):
    plan = read_json(args.plan)
    check(plan.get('schema') == SCHEMA, 'Unknown build plan')
    output = Path(plan['output']).resolve()
    check(Path(args.plan).resolve() == output/'build_plan.json' and output.is_dir(), 'Build plan/output mismatch')
    original = read_bytes(plan['original_payload'])
    translated = read_bytes(plan['translated_payload'])
    metadata = read_bytes(plan['original_metadata'])
    for data, key in ((original, 'original_payload_sha256'), (translated, 'translated_payload_sha256'), (metadata, 'original_metadata_sha256')):
        check(sha(data) == plan[key], 'Build input changed: ' + key)
    check(sha(read_bytes(plan['catalog'], MAX_JSON)) == plan['catalog_sha256'], 'Catalog changed after prepare')
    source = read_json(plan['source_json'])
    check(sha(Path(plan['source_json']).read_bytes()) == plan['source_json_sha256'], 'Source JSON changed after prepare')
    selected_data = read_bytes(plan['selected_translations'], MAX_JSON)
    check(sha(selected_data) == plan['selected_translations_sha256'], 'Selected translations changed after prepare')
    selected = read_json(plan['selected_translations'])
    check(isinstance(selected, dict) and all(k in source and isinstance(v, str) and v != source[k] for k, v in selected.items()), 'Invalid selected translation mapping')
    expected = dict(source); expected.update(selected)
    parse_i18n(original, source, pristine=True)
    parse_i18n(translated, expected, pristine=not selected)
    encrypted = read_bytes(args.encrypted_file)
    original_chunk = read_bytes(args.original_chunk, MAX_CHUNK)
    new_chunk, new_metadata = rebuild_container(metadata, plan['context'], original, translated, original_chunk, encrypted)
    write_new(output/'translated.chk', new_chunk)
    write_new(output/'metadata.translated.plain', new_metadata)
    report = {'source_build': int(plan['context']['Version']), 'status': 'FINALIZED_NOT_INSTALLED',
              'translations': len(selected), 'chunk_identity': plan['context']['Chunk'],
              'original_chunk_sha256': sha(original_chunk), 'output_chunk_sha256': sha(new_chunk),
              'original_metadata_plain_sha256': sha(metadata), 'output_metadata_plain_sha256': sha(new_metadata),
              'catalog_sha256': plan['catalog_sha256'], 'output_payload_sha256': sha(translated),
              'unrelated_chunk_ranges_preserved': True, 'metadata_crc_validated': True}
    write_json(output/'finalize_report.json', report)
    return report

def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='command', required=True)
    p = sub.add_parser('prepare')
    for field in ('original-bytes', 'source-json', 'metadata-plain', 'context', 'references', 'catalog', 'output'):
        p.add_argument('--'+field, required=True)
    p = sub.add_parser('finalize')
    for field in ('plan', 'encrypted-file', 'original-chunk'):
        p.add_argument('--'+field, required=True)
    p = sub.add_parser('inspect-metadata'); p.add_argument('--metadata-plain', required=True)
    args = parser.parse_args(argv)
    try:
        if args.command == 'prepare': result = prepare(args)
        elif args.command == 'finalize': result = finalize(args)
        else: result = parse_metadata(read_bytes(args.metadata_plain))
        print(json.dumps(result, ensure_ascii=False, indent=2))
        return 0
    except (CoreError, OSError, ValueError, KeyError, struct.error) as error:
        print('ERROR: '+str(error), file=sys.stderr)
        return 2
if __name__ == '__main__':
    raise SystemExit(main())
