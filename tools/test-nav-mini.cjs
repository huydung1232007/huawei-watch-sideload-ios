const assert = require('assert');
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const root = path.resolve(__dirname,'../watch-apps/nav-mini/entry/src/main/js/default');
let passed = 0;
function test(name,fn) { fn(); passed++; process.stdout.write('PASS '+name+'\n'); }
function load(relative,extras) {
  let source = fs.readFileSync(path.join(root,relative),'utf8').replace(/^import .*;\r?\n/gm,'').replace('export default','module.exports =');
  const context = Object.assign({module:{exports:{}},console,setTimeout,clearTimeout},extras);
  vm.runInNewContext(source,context,{filename:relative}); return context.module.exports;
}
const protocol = load('common/protocol.js');
const packet = {t:'navmini.status',v:1,n:42,demo:true,instruction:'RE TRAI - DU LIEU THU',distance:'120 m',turn:'left',remaining:'3.2 km',duration:'9 phut',eta:'18:45',speed:'32 km/h',phoneTime:'18:36:00'};
test('matching sample reply displays all fields',()=>{
 const result=protocol.reply(packet,42); assert.equal(result.distance,'120 m'); assert.equal(result.arrow,'<');
 assert.equal(result.summary,'3.2 km - 9 phut'); assert.equal(result.footer,'18:45 - 32 km/h');
});
test('late or unsolicited replies cannot replace the screen',()=>{assert.equal(protocol.reply(packet,43),null);assert.equal(protocol.reply(packet,0),null);});
test('live or incompatible payloads are not mistaken for sample data',()=>{
 for(const patch of [{demo:false},{v:2},{t:'other'},{turn:'unknown'}]) assert.equal(protocol.reply({...packet,...patch},42),null);
});
test('malformed or excessively long strings are rejected',()=>{
 assert.equal(protocol.reply({...packet,distance:120},42),null);assert.equal(protocol.reply({...packet,instruction:'x'.repeat(41)},42),null);
 const missing={...packet}; delete missing.speed; assert.equal(protocol.reply(missing,42),null);
});
function page() {
 const sent=[],timers=new Map();let id=0,receiver;
 const bridge={listen(fn){receiver=fn;},start(report){report('');},send(message,done){sent.push(message);if(done)done(true);}};
 const model=load('pages/main/main.js',{bridge,protocol,setTimeout(fn){timers.set(++id,fn);return id;},clearTimeout(key){timers.delete(key);}});
 Object.assign(model,model.data);model.onInit();return {model,sent,timers,receive(m){if(receiver)receiver(m);}};
}
test('watch sends a bounded request and ignores repeated taps while pending',()=>{
 const p=page();p.model.request();p.model.request();assert.equal(p.sent.length,1);assert.equal(p.sent[0].t,'navmini.hello');assert(p.sent[0].n>0);
});
test('matching response updates UI and emits a separate render acknowledgement',()=>{
 const p=page();p.model.request();const n=p.sent[0].n;p.receive({...packet,n});
 assert.equal(p.model.distance,'120 m');assert.equal(p.model.pending,0);assert.equal(p.timers.size,0);
 assert.equal(p.sent[1].t,'navmini.rendered');assert.equal(p.sent[1].n,n);
});
test('timeout permits retry and rejects a late response',()=>{
 const p=page();p.model.request();const n=p.sent[0].n;Array.from(p.timers.values())[0]();p.receive({...packet,n});
 assert.equal(p.model.pending,0);assert.equal(p.model.distance,'-- m');assert.equal(p.model.button,'Thu lai');
});
test('destroyed page cancels timeout and ignores callbacks',()=>{
 const p=page();p.model.request();p.model.onDestroy();p.receive({...packet,n:p.sent[0].n});
 assert.equal(p.timers.size,0);assert.equal(p.model.distance,'-- m');
});
test('phone address and fingerprint match the iPhone bridge',()=>{
 const bridge=fs.readFileSync(path.join(root,'common/bridge.js'),'utf8');
 assert(bridge.includes("'com.huydung1232007.navmini.phone'"));
 assert(bridge.includes('CA612C488CBB19EE1601EAFFFE084ED6AC674AF264A861D9101CF1A3A191693E'));
});
console.log(passed+' Nav Mini protocol/lifecycle checks passed.');
