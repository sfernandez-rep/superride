const {chromium}=require('playwright');
const fs=require('node:fs');
const path=require('node:path');
const project=path.resolve(__dirname,'../..').replaceAll('\\','/');
const root=project+'/.cache/superrstudio/gui-baseline';
async function run(page,command){
 const before=await page.evaluate(text=>{window.rstudio.commands.activateConsole(); const e=document.getElementById('rstudio_console_input').env.editor;e.setValue(text,1);e.focus();return window.rstudio.console.promptCount;},command);
 await page.keyboard.press('Enter');
 await page.waitForFunction(n=>window.rstudio.console.promptCount>n,before,{timeout:30000});
}
(async()=>{
 const b=await chromium.connectOverCDP('http://127.0.0.1:19381');
 const p=b.contexts()[0].pages().find(p=>p.url().startsWith('http:'));
 await p.waitForFunction(()=>window.rstudio?.ready);
 await p.evaluate(()=>window.rstudio.documents.closeAllNoSave());
 await run(p,`setwd(${JSON.stringify(root)}); data <- read.csv('${project}/tests/superrstudio/scientific.csv', check.names=FALSE); stopifnot(nrow(data)==5L, is.numeric(data[['length cm']])); model <- lm(mass_g ~ \u0060length cm\u0060, data=data); stopifnot(isTRUE(all.equal(unname(coef(model)), c(1,2),tolerance=1e-10))); plot(data[['length cm']],data$mass_g); write.csv(data,'roundtrip.csv',row.names=FALSE); pdf('baseline.pdf'); plot(data[['length cm']],data$mass_g); dev.off(); writeLines(c('Version: 1.0','RestoreWorkspace: No','SaveWorkspace: No','AlwaysSaveHistory: No'), 'Baseline.Rproj'); writeLines('x <- 1 + 2','baseline.R'); cat('BASELINE_GUI_R_PASS\\n')`);
 const output=await p.locator('#rstudio_workbench_panel_console').innerText();
 if(!output.includes('BASELINE_GUI_R_PASS\n'))throw new Error(output);
 await run(p,"View(data, title='Baseline data')");
 await p.frameLocator('#rstudio_data_viewer_frame').locator('th[data-col-idx][title]').first().waitFor();
 console.log('PASS live data viewer column headers');
 await p.evaluate(file=>window.rstudio.documents.open(file),root+'/baseline.R');
 await p.waitForFunction(()=>window.rstudio.documents.active()?.path?.endsWith('baseline.R'));
 await p.evaluate(()=>window.rstudio.documents.activeEditor().setValue('x <- 1 + 2\nstopifnot(x == 3)\n',1));
 await p.evaluate(()=>window.rstudio.commands.saveSourceDoc());
 await p.waitForFunction(()=>window.rstudio.documents.active()?.dirty===false);
 if(!fs.readFileSync(root+'/baseline.R','utf8').includes('stopifnot(x == 3)'))throw Error('File save failed');
 await p.screenshot({path:root+'/baseline-data-plot.png'});
 console.log('PASS console/R4.6.1, import/types, lm, plot device, CSV/PDF, editor save');
 console.log('client errors:',await p.evaluate(()=>window.rstudio.errors.list()));
 await p.evaluate(file=>window.rstudio.project.open(file),root+'/Baseline.Rproj');
 await p.waitForFunction(()=>window.rstudio?.ready&&window.rstudio.project.isActive(),null,{timeout:60000});
 await run(p,"stopifnot(basename(getwd()) == 'gui-baseline'); cat('BASELINE_PROJECT_PASS\\n')");
 await p.screenshot({path:root+'/baseline-project.png'});
 console.log('PASS project open:',await p.evaluate(()=>window.rstudio.project.path()));
 await b.close();
})().catch(e=>{console.error(e);process.exitCode=1;});
