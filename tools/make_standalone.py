#!/usr/bin/env python3
"""Package the identical exported Godot WASM + PCK as one offline HTML file.

The normal Web ZIP remains an unmodified Godot export. This optional carrier
uses the same bytes and Engine, mapping its resources to in-memory responses.
Requires a modern browser with DecompressionStream, WebAssembly and WebGL 2.
"""
import argparse
import base64
import gzip
from pathlib import Path


def package(source: Path, target: Path):
    html = (source / "index.html").read_text()
    project = Path(__file__).resolve().parents[1]
    notices = []
    for name in ["GODOT_LICENSE.txt", "assets/fonts/LICENSE-DejaVu.txt", "assets/audio/LICENSE.txt"]:
        file = project / name
        if file.is_file():
            notices.append(name + "\n" + file.read_text())
    html = html.replace("</head>", '<script type="text/plain" id="license-notices">' + "\n\n".join(notices).replace("</script", "<\\/script") + '</script>\n</head>')
    data = []
    for name in ["index.wasm", "index.pck", "index.audio.worklet.js", "index.audio.position.worklet.js"]:
        raw = (source / name).read_bytes()
        data.append(f'<script type="application/octet-stream" id="embedded-{name}">'
                    + base64.b64encode(gzip.compress(raw, compresslevel=9, mtime=0)).decode() + '</script>')
    runtime = (source / "index.js").read_text().replace("</script", "<\\/script")
    adapter = r'''
async function unpackResource(name) {
  const node=document.getElementById('embedded-'+name);
  const binary=atob(node.textContent.trim());
  const packed=Uint8Array.from(binary,c=>c.charCodeAt(0));
  node.remove();
  const stream=new Blob([packed]).stream().pipeThrough(new DecompressionStream('gzip'));
  return new Uint8Array(await new Response(stream).arrayBuffer());
}
const embeddedReady = Promise.all(['index.wasm','index.pck','index.audio.worklet.js','index.audio.position.worklet.js'].map(async name=>[name,await unpackResource(name)])).then(entries=>new Map(entries));
const originalFetch=window.fetch.bind(window);
window.fetch=async function(input,init) {
  const url=typeof input==='string'?input:input.url;
  const name=String(url).split('/').pop().split('?')[0];
  const resources=await embeddedReady;
  if(resources.has(name)) {
    const bytes=resources.get(name);
    return new Response(bytes,{status:200,headers:{'Content-Type':name.endsWith('.wasm')?'application/wasm':name.endsWith('.js')?'text/javascript':'application/octet-stream','Content-Length':String(bytes.length)}});
  }
  return originalFetch(input,init);
};
const originalModuleConfig=engine.config.getModuleConfig.bind(engine.config);
engine.config.getModuleConfig=function(base,response) {
  const config=originalModuleConfig(base,response);
  const originalLocate=config.locateFile;
  config.locateFile=function(name) {
    if(name.endsWith('.audio.position.worklet.js')) return window.embeddedWorklets.position;
    if(name.endsWith('.audio.worklet.js')) return window.embeddedWorklets.audio;
    return originalLocate(name);
  };
  return config;
};
const standaloneStart=embeddedReady.then(resources=>{
  window.embeddedWorklets={
    audio:URL.createObjectURL(new Blob([resources.get('index.audio.worklet.js')],{type:'text/javascript'})),
    position:URL.createObjectURL(new Blob([resources.get('index.audio.position.worklet.js')],{type:'text/javascript'}))
  };
});
'''
    html = html.replace('<script src="index.js"></script>', '\n'.join(data) + '\n<script>\n' + runtime + '\n</script>')
    needle = "engine.startGame({"
    html = html.replace(needle, adapter + "\nstandaloneStart.then(()=>engine.startGame({", 1)
    html = html.replace("}).then(()=>{loading.style.display", "})).then(()=>{loading.style.display", 1)
    html = html.replace("Откройте игру через HTTP(S)-сервер, а не двойным щелчком по HTML. Нужны WebAssembly и WebGL 2.",
                        "Нужен современный браузер с WebAssembly, WebGL 2 и DecompressionStream. Попробуйте обычный Web ZIP через HTTP(S)-сервер.")
    html = html.replace("Маленький мир внутри тебя", "Маленький мир внутри тебя · распаковываем дом…")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(html)
    print(f"Standalone Godot HTML: {target} ({target.stat().st_size:,} bytes)")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("target", type=Path)
    args = parser.parse_args()
    package(args.source, args.target)

