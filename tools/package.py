#!/usr/bin/env python3
"""Create two clean deliverable ZIPs; never package .git, caches or local saves."""
from pathlib import Path
import hashlib
import json
import shutil
import zipfile
from make_standalone import package

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT.parent / 'deliverables'


def zip_directory(directory, target):
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(directory.rglob('*')):
            if f.is_file():
                z.write(f, f.relative_to(directory))


def run():
    OUT.mkdir(parents=True, exist_ok=True)
    web = OUT / 'web'
    web.mkdir(exist_ok=True)
    for file in (ROOT / 'build' / 'web').glob('index*'):
        if file.suffix != '.import':
            shutil.copy2(file, web / file.name)
    for generated_import in web.glob('index*.import'):
        generated_import.unlink()
    shutil.copy2(ROOT / 'tools' / 'serve.py', web / 'serve.py')
    for name in ['GODOT_LICENSE.txt', 'TEST_REPORT.md', 'ART_PLACEMENT.md']:
        shutil.copy2(ROOT / name, web / name)
    licenses = web / 'licenses'
    licenses.mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'assets/fonts/LICENSE-DejaVu.txt', licenses / 'DejaVu.txt')
    shutil.copy2(ROOT / 'assets/audio/LICENSE.txt', licenses / 'Original-Audio-CC0.txt')
    (web / 'README.txt').write_text('''ТЫ МОЙ ДОМ · ГОТОВЫЙ GODOT WEB EXPORT

Распакуйте весь архив. В этой папке запустите:
  python3 serve.py . --open
Windows: py serve.py . --open

Для публикации загрузите все index.* на статический HTTPS-хостинг.
Для локальной проверки подходит HTTP localhost. Звуку AudioWorklet нужен
безопасный контекст: HTTPS или локальный сервер.
MIME .wasm: application/wasm. Потоки выключены; COOP/COEP не нужны.
Файлы следует сохранять рядом и с исходными именами.
Ресурсы игры, музыка и шрифты включены в index.pck.
Не открывайте обычный index.html через file://: нужен HTTP(S).

Есть также отдельный самодостаточный You-Are-My-Home.html.
Он содержит ту же игру, WebAssembly и ресурсы внутри одного файла.
Проверен по HTTP без внешних ресурсов. Возможность открывать его через
file:// зависит от политики браузера и в этой среде не проверена:
управляемый браузер запрещает адреса file://.

Игра не опубликована на внешнем хостинге. Публичной ссылки нет.
Подробные результаты и ограничения — TEST_REPORT.md.
''')
    zip_directory(web, OUT / 'You-Are-My-Home-Web.zip')
    with zipfile.ZipFile(OUT / 'You-Are-My-Home-Godot.zip', 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for f in sorted(ROOT.rglob('*')):
            rel = f.relative_to(ROOT)
            if any(p in {'.git', '.godot', '__pycache__', 'build', 'test-results'} for p in rel.parts):
                continue
            if f.is_file():
                z.write(f, rel)
        z.writestr('build/web/', '')
    package(ROOT / 'build' / 'web', OUT / 'You-Are-My-Home.html')
    manifests = {}
    for f in sorted(OUT.iterdir()):
        if f.suffix in {'.zip', '.html'}:
            with f.open('rb') as stream:
                digest = hashlib.file_digest(stream, 'sha256').hexdigest()
            manifests[f.name] = {'bytes': f.stat().st_size, 'sha256': digest}
    (OUT / 'SHA256.json').write_text(json.dumps(manifests, indent=2))
    print(json.dumps(manifests, indent=2))


if __name__ == '__main__':
    run()
