const {strict: assert} = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const {performance} = require('node:perf_hooks');
const {ScriptMatcher, normalize} = require('../App/matcher.js');
const results = [];
function test(name, fn) {
  const start = performance.now();
  try { fn(); results.push({name, passed: true, milliseconds: performance.now() - start}); }
  catch (error) { results.push({name, passed: false, message: error.message}); }
}
const script = '今天我们来测试中文语音提词。我读得快文字就跟得快。我停下来文字应该等我。窗外的阳光照在桌子上。小猫正在安静地睡觉。这一段可以跳过不需要每一句都读出来。我现在已经跳到这里提词器应该找到新的位置。如果我回头重读也应该跟着我回到对应的句子。最后检查录像里面的声音是否清楚测试结束。';
const norm = normalize(script);
const endOf = text => norm.indexOf(normalize(text)) + normalize(text).length;
test('中文没有空格也按字匹配', () => {
  const m = new ScriptMatcher(script);
  assert.equal(m.update('今天我们来测试').position, 7);
});
test('标点与全角数字规范化', () => {
  assert.equal(normalize('你好，１２３！ABC'), '你好123abc');
});
test('累计部分转写不重复前进', () => {
  const m = new ScriptMatcher(script);
  m.update('今天我们来');
  const position = m.update('今天我们来测试中文').position;
  for (let i = 0; i < 20; i++) assert.equal(m.update('今天我们来测试中文').position, position);
});
test('缓慢逐字增加', () => {
  const m = new ScriptMatcher(script);
  const text = '今天我们来测试中文语音提词';
  for (let i = 1; i <= text.length; i++) m.update(text.slice(0, i));
  assert.equal(m.position, text.length);
});
test('快速一次增加一整句', () => {
  const m = new ScriptMatcher(script);
  const text = '今天我们来测试中文语音提词';
  assert.equal(m.update(text).position, text.length);
});
test('漏一个字仍定位到句尾', () => {
  const m = new ScriptMatcher(script);
  assert.equal(m.update('今天我们测试中文语音提词').position, endOf('中文语音提词'));
});
test('句内口头语不使位置失控', () => {
  const m = new ScriptMatcher(script);
  assert.equal(m.update('今天我们来呃测试中文语音提词').position, endOf('中文语音提词'));
});
test('一个识别替换字', () => {
  const m = new ScriptMatcher(script);
  assert.equal(m.update('今天我们来测试中文语音题词').position, endOf('中文语音提词'));
});
test('跨多段向前跳读', () => {
  const m = new ScriptMatcher(script);
  m.update('今天我们来测试中文语音提词');
  m.newUtterance();
  const r = m.update('我现在已经跳到这里');
  assert.equal(r.position, endOf('我现在已经跳到这里'));
  assert.equal(r.reason, 'jump');
});
test('回头重读超过十个字', () => {
  const m = new ScriptMatcher(script);
  m.seek(endOf('新的位置'));
  assert.equal(m.update('窗外的阳光照在桌子上').position, endOf('窗外的阳光照在桌子上'));
});
test('结束后仍能重新回读', () => {
  const m = new ScriptMatcher(script);
  m.seek(norm.length);
  assert.equal(m.update('今天我们来测试中文语音提词').position, endOf('中文语音提词'));
});
test('离题讲话保持原位置', () => {
  const m = new ScriptMatcher(script);
  m.seek(20);
  assert.equal(m.update('明天去超市买水果和牛奶').position, 20);
});
test('只有常见短词不会远距离跳转', () => {
  const m = new ScriptMatcher(script);
  m.seek(20);
  for (const text of ['我', '这里', '测试']) assert.equal(m.update(text).position, 20);
});
test('重复句缺乏区分信息时保持位置', () => {
  const text = '红色气球慢慢升起。远处有许多观众正在等候。红色气球慢慢升起。';
  const m = new ScriptMatcher(text);
  m.seek(16);
  const r = m.update('红色气球慢慢升起');
  assert.equal(r.position, 16);
  assert.equal(r.reason, 'ambiguous');
});
test('重复句在从头顺读时可由位置消歧', () => {
  const m = new ScriptMatcher('红色气球慢慢升起。大家一起鼓掌。红色气球慢慢升起。');
  assert.equal(m.update('红色气球慢慢升起').position, 8);
});
test('识别器重启不清除稿件位置', () => {
  const m = new ScriptMatcher(script);
  m.update('今天我们来测试中文语音提词');
  m.newUtterance();
  assert.equal(m.update('我读得快文字就跟得快').position, endOf('我读得快文字就跟得快'));
});
test('相同长度的转写修订仍会重新对齐', () => {
  const m = new ScriptMatcher(script);
  m.update('xxxxxxxxx');
  assert.equal(m.update('今天我们来测试中文').position, 9);
});
test('手动定位后接受新的朗读位置', () => {
  const m = new ScriptMatcher(script);
  m.seek(endOf('小猫正在安静地睡觉'));
  assert.equal(m.update('我现在已经跳到这里').position, endOf('我现在已经跳到这里'));
});
test('空白及标点不移动', () => {
  const m = new ScriptMatcher(script);
  m.seek(17);
  assert.equal(m.update('，。！ ' ).position, 17);
});
test('边界定位被限制在稿件范围', () => {
  const m = new ScriptMatcher(script);
  assert.equal(m.seek(-100), 0);
  assert.equal(m.seek(99999), norm.length);
});
test('未知句子不被当成顺读成功', () => {
  const m = new ScriptMatcher(script);
  const r = m.update('海洋深处有一艘蓝色潜水艇');
  assert.equal(r.position, 0);
  assert.equal(r.reason, 'no-match');
});

// Benchmark only the text matcher. This is not ASR, acoustic latency, or a phone measurement.
const longScript = Array.from({length: 40}, (_, i) => `第${i}段今天记录春天的树木河流和远处的山峰`).join('');
const m = new ScriptMatcher(longScript);
const times = [];
for (let i = 0; i < 20; i++) {
  m.newUtterance();
  const start = performance.now(); m.update(`第${i}段今天记录`); times.push(performance.now() - start);
}
times.sort((a, b) => a - b);
const report = {
  stage: 'synthetic-text-fixtures-only',
  engine: process.version, platform: process.platform,
  passed: results.filter(x => x.passed).length, total: results.length,
  acousticRecognitionTested: false, iOSJavaScriptCoreTested: false, deviceTested: false,
  benchmark: {scriptCharacters: normalize(longScript).length, calls: times.length,
    medianMilliseconds: times[Math.floor(times.length / 2)], maxMilliseconds: times[times.length - 1]},
  results
};
fs.mkdirSync(path.join(__dirname, '../evidence'), {recursive: true});
fs.writeFileSync(path.join(__dirname, '../evidence/matcher-results.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify(report, null, 2));
if (report.passed !== report.total) process.exitCode = 1;
