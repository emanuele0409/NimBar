#!/usr/bin/env python3
"""Check the real SettingsView icon renderer through SwiftUI's native Menu bridge."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
source = (root / 'NimBar/SettingsView.swift').read_text()
start = source.index('    @ViewBuilder\n    private func menuIconSymbol')
end = source.index('    private var privacyPanel:', start)
renderer = source[start:end]
asset = root / 'NimBar/Assets.xcassets/NimBarMenuBarMark.imageset/NimBarMenuBarMark.png'
swift = '''import AppKit
import SwiftUI
enum SettingsStore {
 enum MenuBarIconStyle: CaseIterable { case original, chevron, chevronDown, dot }
}
struct Probe: View {
 let style: SettingsStore.MenuBarIconStyle
 var body: some View {
  Menu { Button("Option") {} } label: {
   HStack(spacing: 6) {
    menuIconSymbol(style)
    Text("Same label").font(.system(size:11, weight:.medium))
   }.padding(.horizontal,8).padding(.vertical,5)
  }.controlSize(.small).menuStyle(.borderlessButton)
 }
''' + renderer + '''
}
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
let image = NSImage(contentsOfFile: CommandLine.arguments[1])!
image.setName("NimBarMenuBarMark")
var sizes: [NSSize] = []
for style in SettingsStore.MenuBarIconStyle.allCases {
 let view = NSHostingView(rootView: Probe(style:style))
 let window = NSWindow(contentRect:NSRect(x:0,y:0,width:500,height:400), styleMask:[.borderless], backing:.buffered, defer:false)
 window.contentView = view
 view.layoutSubtreeIfNeeded()
 RunLoop.main.run(until:Date(timeIntervalSinceNow:0.1))
 let size = view.fittingSize
 sizes.append(size)
 print("\\(style): \\(size)")
}
let pass = sizes.allSatisfy { $0.height <= 24 && abs($0.height - sizes[1].height) <= 2 }
print(pass ? "PASS: all icon choices retain the same compact height" : "FAIL: icon choice expands the native selector")
exit(pass ? 0 : 1)
'''
with tempfile.TemporaryDirectory(prefix='NimBarSelector-') as temporary:
    folder = Path(temporary)
    probe = folder / 'Probe.swift'
    executable = folder / 'Probe'
    probe.write_text(swift)
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', str(folder / 'cache'), str(probe), '-o', str(executable)], check=True)
    subprocess.run([str(executable), str(asset)], check=True)
