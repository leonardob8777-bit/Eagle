#!/usr/bin/env python3
"""Check Vietnamese coverage and execute the real phrase/template translator."""
from pathlib import Path
import json
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
LITERAL = r'"(?:\\.|[^"\\])*"'

def table(source):
    return {json.loads(k): json.loads(v) for k, v in re.findall(
        rf'^\s*({LITERAL}):\s*({LITERAL}),?$', source, re.M)}

def main():
    config = ROOT / 'lara/config'
    source = (config / 'EagleVietnameseText.swift').read_text()
    phrases = table(source)
    chinese = table((config / 'EagleChineseText.swift').read_text())
    assert chinese.keys() <= phrases.keys(), sorted(chinese.keys() - phrases.keys())
    for path in (ROOT / 'lara').rglob('*.swift'):
        if '/broken/' in str(path) or path.name.endswith('Text.swift'):
            continue
        for literal in re.findall(rf'\ben:\s*({LITERAL})', path.read_text()):
            try:
                english = json.loads(literal)
            except json.JSONDecodeError:  # Swift interpolations are checked through templates below.
                continue
            assert english in phrases, (str(path.relative_to(ROOT)), english)
    assertions = []
    def check(english, vietnamese, translator="EagleVietnameseText"):
        assert vietnamese.strip(), english
        literal = json.dumps(english, ensure_ascii=False)
        expected = json.dumps(vietnamese, ensure_ascii=False)
        failure = json.dumps('FAIL: ' + english + ' EXPECTED: ' + vietnamese + ' GOT: ', ensure_ascii=False)
        assertions.append(f'if {translator}.translate({literal}) != {expected} {{ fatalError({failure} + {translator}.translate({literal})) }}')

    for english, vietnamese in phrases.items():
        check(english, vietnamese)
    templates = re.findall(rf'Template\(english: (\[.*?\]), vietnamese: ({LITERAL})\)', source)
    assert len(templates) == 83
    for fragments, translated in templates:
        fragments, translated = json.loads(fragments), json.loads(translated)
        english = fragments[0]
        for i, fragment in enumerate(fragments[1:]):
            value = f'VALUE_{i}'
            english += value + fragment
            assert '{' + str(i) + '}' in translated
            translated = translated.replace('{' + str(i) + '}', value)
        assert not re.search(r'\{\d+\}', translated)
        check(english, translated)
    for language, field in [("Chinese", "chinese"), ("Russian", "russian")]:
        text = (config / f'Eagle{language}Text.swift').read_text()
        for english, translated in table(text).items():
            check(english, translated, f'Eagle{language}Text')
        for fragments, translated in re.findall(rf'Template\(english: (\[.*?\]), {field}: ({LITERAL})\)', text):
            fragments, translated = json.loads(fragments), json.loads(translated)
            english = fragments[0]
            for i, fragment in enumerate(fragments[1:]):
                value = f'VALUE_{i}'
                english += value + fragment
                translated = translated.replace('{' + str(i) + '}', value)
            check(english, translated, f'Eagle{language}Text')
    def strings(language, name):
        path = ROOT / 'lara' / f'{language}.lproj' / name
        return json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(path)]))
    for name in ['Localizable.strings', 'InfoPlist.strings']:
        english, vietnamese = strings('en', name), strings('vi', name)
        assert english.keys() == vietnamese.keys(), (name, english.keys() - vietnamese.keys())
        for key, value in vietnamese.items():
            assert value.strip(), key
            assert re.findall(r'%(?:\d+\$)?[a-zA-Z@]', english[key]) == re.findall(r'%(?:\d+\$)?[a-zA-Z@]', value), key
    with tempfile.TemporaryDirectory(prefix='eagle-vietnamese-') as directory:
        work = Path(directory)
        main = work / 'Checks.swift'
        main.write_text('@main enum Checks { static func main() {\n' + '\n'.join(assertions) + '\n} }\n')
        subprocess.run(['swiftc', '-parse-as-library', str(config / 'EagleChineseText.swift'),
                        str(config / 'EagleRussianText.swift'), str(config / 'EagleVietnameseText.swift'), str(main), '-o', str(work / 'checks')], check=True)
        subprocess.run([str(work / 'checks')], check=True)
    print(f'PASS: {len(phrases)} Vietnamese phrases, {len(templates)} runtime templates, active literal coverage and system resources')

if __name__ == '__main__':
    main()
