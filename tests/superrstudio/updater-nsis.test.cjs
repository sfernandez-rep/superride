const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

test('NSIS stops before replacement when the previous uninstaller fails', {skip:process.platform !== 'win32'}, async () => {
  const makensis='C:\\Program Files (x86)\\NSIS\\makensis.exe';
  const root=path.resolve(__dirname,'../../.cache/superrstudio/nsis-tests');
  await fs.mkdir(root,{recursive:true});
  const base=await fs.realpath(root);
  const dir=await fs.mkdtemp(path.join(base,'case-'));
  try {
    const app=path.join(dir,'app'); await fs.mkdir(app);
    const template=await fs.readFile(path.resolve(__dirname,'../../package/win32/cmake/modules/NSIS.template.in'),'utf8');
    const start=template.indexOf('  ; check for uninstaller',template.indexOf('Section "-Remove previous installation"'));
    const end=template.indexOf('SectionEnd',start);
    assert.ok(start>0 && end>start);
    const fragment=template.slice(start,end).replaceAll('$MultiUser.InstallMode','$9');
    const script=path.join(dir,'update.nsi'), update=path.join(dir,'update.exe');
    await fs.writeFile(script, `!include "LogicLib.nsh"\nName "SuperR isolated fixture"\nOutFile "${update}"\nRequestExecutionLevel user\nSilentInstall silent\nInstallDir "${app}"\nSection\nStrCpy $9 "CurrentUser"\n${fragment}\nSectionEnd\nSection\nSetOutPath "$INSTDIR"\nFileOpen $0 "$INSTDIR\\marker.txt" w\nFileWrite $0 "updated"\nFileClose $0\nSectionEnd\n`);
    const compile=spawnSync(makensis,[script],{encoding:'utf8'});
    assert.equal(compile.status,0,compile.stdout + compile.stderr);
    for (const code of [7,0]) {
      const uninstallerScript=path.join(dir,`uninstall-${code}.nsi`);
      const uninstaller=path.join(app,'Uninstall.exe');
      await fs.writeFile(uninstallerScript,`Name "SuperR isolated mock"\nOutFile "${uninstaller}"\nRequestExecutionLevel user\nSilentInstall silent\nSection\nSetErrorLevel ${code}\nSectionEnd\n`);
      const built=spawnSync(makensis,[uninstallerScript],{encoding:'utf8'});
      assert.equal(built.status,0,built.stdout + built.stderr);
      const run=spawnSync(update,['/S'],{encoding:'utf8',timeout:30000});
      if (code) { assert.notEqual(run.status,0); await assert.rejects(fs.access(path.join(app,'marker.txt'))); }
      else { assert.equal(run.status,0,run.stderr); assert.equal(await fs.readFile(path.join(app,'marker.txt'),'utf8'),'updated'); }
    }
  } finally {
    const rel=path.relative(base,dir); const info=await fs.lstat(dir);
    if (!rel.startsWith('case-') || rel.includes(path.sep) || info.isSymbolicLink() || await fs.realpath(dir)!==dir)
      throw new Error('Invalid isolated test directory');
    await fs.rm(dir,{recursive:true,force:true});
  }
});
